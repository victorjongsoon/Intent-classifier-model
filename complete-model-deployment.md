# Deploy Intent Classifier on VMs (AWS VPC + ASG + ALB) — CLI Steps

This simple step-by-step guide shows how to deploy your Intent Classifier model on AWS using EC2 instances in an Auto Scaling Group (ASG) behind an Application Load Balancer (ALB).

### 1. Configure deployment variables

First, make sure the CloudShell checkout uses the latest `virtual-machines` branch from this fork:

```bash
git remote set-url origin https://github.com/victorjongsoon/Intent-classifier-model.git
git fetch origin
git switch virtual-machines
git pull --ff-only origin virtual-machines
```

Set these values once in the CloudShell session before running the remaining commands:

```bash
export AWS_REGION="ap-southeast-1"
export INSTANCE_TYPE="t2.medium"
export KEY_NAME="intent-classifier-key"
export LAUNCH_TEMPLATE_NAME="mlops-template"
export TARGET_GROUP_NAME="mlops-target-group"
export ALB_NAME="model-deployment"
export ASG_NAME="mlops-autoscaling"
```

`KEY_NAME` must be the AWS EC2 key-pair name, not the downloaded `.pem` filename. Verify that the key pair exists:

```bash
aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION"
```

The environment variables only last for the current CloudShell session. Display one with `echo`, for example `echo "$LAUNCH_TEMPLATE_NAME"`.

### 2. Find a recent Ubuntu AMI for your region

A quick way to locate an official Ubuntu AMI (example uses AWS CLI):

```bash
export AMI_ID=$(aws ec2 describe-images \
--owners 099720109477 \
--filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" \
--query 'Images | sort_by(@, &CreationDate)[-1].ImageId' --output text --region "$AWS_REGION")

echo "$AMI_ID"
```

This prints the latest Ubuntu 20.04 AMI ID for the region. Adjust the name filter to whichever you need.

### 3. Create a VPC, public subnets (multi-AZ), and Internet Gateway

For an ALB you must provide at least two subnets in different Availability Zones. We'll create two public subnets (one per AZ).

- Create VPC

```bash
export VPC_ID=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --query 'Vpc.VpcId' --output text --region "$AWS_REGION")
echo "$VPC_ID"
```

The returned VPC ID is saved in `VPC_ID`.

- Create two public subnets in different AZs (replace ${AWS_REGION}a/b if needed):

```bash
export SUBNET_ID1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.10.1.0/24 --availability-zone "${AWS_REGION}a" --query 'Subnet.SubnetId' --output text --region "$AWS_REGION")
echo "$SUBNET_ID1"
```

```bash
export SUBNET_ID2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.10.2.0/24 --availability-zone "${AWS_REGION}b" --query 'Subnet.SubnetId' --output text --region "$AWS_REGION")
echo "$SUBNET_ID2"
```

- Create and attach an Internet Gateway

```bash
export IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region "$AWS_REGION")
echo "$IGW_ID"
```

```bash
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
```

- Create a route table and route 0.0.0.0/0 to IGW and associate with both subnets

```bash
export RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text --region "$AWS_REGION")
echo "$RTB_ID"
```

```bash
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$AWS_REGION"
```

```bash
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID1" --region "$AWS_REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID2" --region "$AWS_REGION"
```

Optional: enable auto-assign public IP for the subnets so instances get public addresses (helpful for debugging):

```bash
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID1" --map-public-ip-on-launch --region "$AWS_REGION"
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID2" --map-public-ip-on-launch --region "$AWS_REGION"
```

### 4. Create Security Group for instances

Create a security group that allows traffic from the ALB (on port 80) and SSH from your IP (or nothing for production):

```bash
export SG_ID=$(aws ec2 create-security-group --group-name intent-sg --description "Allow app and ssh" --vpc-id "$VPC_ID" --query 'GroupId' --output text --region "$AWS_REGION")
echo "$SG_ID"
```

Add rules:

```bash
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$AWS_REGION"
```

Open SSH 

```bash
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$AWS_REGION"
```

Note: allowing 0.0.0.0/0 to port 80 is simple for beginners but not ideal for production. The more secure pattern is:
Create an ALB security group that allows inbound HTTP/HTTPS from the internet. Configure the instance security group to only allow inbound traffic from the ALB security group's ID.

### 5. Create Launch Template (includes user-data)

A Launch Template defines how EC2 instances are launched (AMI, instance type, key pair, security groups, IAM instance profile, and user-data). Below are two straightforward ways to create a launch template from the CLI.

Prepare your user data.

Create a user-data.sh file with your startup script (refer userdata.sh). Make sure it is executable text.

Confirm that every value required by the launch template is set. None of these lines should end after the `=` sign:

```bash
echo "AWS_REGION=$AWS_REGION"
echo "AMI_ID=$AMI_ID"
echo "INSTANCE_TYPE=$INSTANCE_TYPE"
echo "KEY_NAME=$KEY_NAME"
echo "SG_ID=$SG_ID"
echo "LAUNCH_TEMPLATE_NAME=$LAUNCH_TEMPLATE_NAME"
echo "TARGET_GROUP_NAME=$TARGET_GROUP_NAME"
echo "ALB_NAME=$ALB_NAME"
echo "ASG_NAME=$ASG_NAME"
```

Update the repository before encoding `userdata.sh`, then generate the base64 value:

```bash
git pull --ff-only origin virtual-machines
USER_DATA=$(base64 -w0 userdata.sh)
printf '%s' "$USER_DATA" | base64 -d | grep -E 'set -|git clone|proxy_pass'
```

The decoded check should show the `victorjongsoon` repository and `proxy_pass http://127.0.0.1:6000;`. Do not continue if it shows the instructor's repository or `/predict` after port 6000.

Create the launch template:

```bash
export LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
--launch-template-name "$LAUNCH_TEMPLATE_NAME" \
--version-description "v1" \
--launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"$INSTANCE_TYPE\",\"KeyName\":\"$KEY_NAME\",\"SecurityGroupIds\":[\"$SG_ID\"],\"UserData\":\"$USER_DATA\"}" \
--query 'LaunchTemplate.LaunchTemplateId' --output text \
--region "$AWS_REGION")

echo "$LAUNCH_TEMPLATE_ID"
```

### 6. Create Target Group and Application Load Balancer (ALB)

- Create target group (instances will be registered automatically by ASG)

```bash
export TARGET_GROUP_ARN=$(aws elbv2 create-target-group --name "$TARGET_GROUP_NAME" --protocol HTTP --port 80 --target-type instance --vpc-id "$VPC_ID" --health-check-protocol HTTP --health-check-path /health --matcher HttpCode=200 --query 'TargetGroups[0].TargetGroupArn' --output text --region "$AWS_REGION")
echo "$TARGET_GROUP_ARN"
```

- Create an ALB (public) in the two subnets you created. The --subnets parameter must include at least two subnets in different AZs

```bash
export ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" --subnets "$SUBNET_ID1" "$SUBNET_ID2" --security-groups "$SG_ID" --scheme internet-facing --type application --query 'LoadBalancers[0].LoadBalancerArn' --output text --region "$AWS_REGION")
echo "$ALB_ARN"

aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION"
```

- Create a listener to forward traffic from port 80 to the target group

```bash
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN" --region "$AWS_REGION"
```

### 7. Create Auto Scaling Group that uses the Launch Template

Create the autoscaling group in both subnets and attach it to the target group so that instances are automatically registered.

```bash
aws autoscaling create-auto-scaling-group \
--auto-scaling-group-name "$ASG_NAME" \
--launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE_NAME,Version=1" \
--min-size 1 --max-size 3 --desired-capacity 1 \
--vpc-zone-identifier "$SUBNET_ID1,$SUBNET_ID2" \
--health-check-type ELB --health-check-grace-period 300 \
--region "$AWS_REGION"
```

### 8. Attach the Target Group to ASG 

This ensures instances are automatically registered with the ALB target group:

```bash
aws autoscaling attach-load-balancer-target-groups \
--auto-scaling-group-name "$ASG_NAME" \
--target-group-arns "$TARGET_GROUP_ARN" \
--region "$AWS_REGION"
```

### 9. Verify targets and call the API

Check whether the ASG instances have registered and passed the `/health` check:

```bash
aws elbv2 describe-target-health \
--target-group-arn "$TARGET_GROUP_ARN" \
--query 'TargetHealthDescriptions[].{Instance:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
--output table --region "$AWS_REGION"
```

Wait until at least one target reports `healthy`, then capture the ALB DNS name:

```bash
export ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text --region "$AWS_REGION")
echo "$ALB_DNS"
```

Test from CloudShell:

```bash
curl "http://$ALB_DNS/health"
curl -X POST "http://$ALB_DNS/predict" -H "Content-Type: application/json" -d '{"text":"I want to cancel my subscription"}'
```

Test from local Windows PowerShell. PowerShell maps `curl` to `Invoke-WebRequest`, so use `Invoke-RestMethod`:

```powershell
Invoke-RestMethod -Uri "http://<ALB_DNS>/predict" -Method Post -ContentType "application/json" -Body '{"text":"I want to cancel my subscription"}'
```

Command Prompt or the real curl executable:

```cmd
curl.exe -X POST http://<ALB_DNS>/predict -H "Content-Type: application/json" -d "{\"text\":\"I want to cancel my subscription\"}"
```

Expected response:

```json
{"intent":"complaint"}
```

If the ALB returns `502 Bad Gateway`, Nginx is reachable but cannot connect to Gunicorn. Inspect the launched instance:

```bash
sudo systemctl status intent_gunicorn nginx --no-pager
sudo journalctl -u intent_gunicorn -n 100 --no-pager
sudo tail -n 100 /var/log/cloud-init-output.log
curl http://127.0.0.1:6000/health
curl http://127.0.0.1/health
```
