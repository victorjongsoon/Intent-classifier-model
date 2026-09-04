# Intent Classifier Model

A small Flask API that trains and serves a text intent classifier. The model recognizes example intents such as `greeting`, `question`, `complaint`, and `praise`.

## Project flow

1. `model/train.py` trains the classifier.
2. The trained model is saved as `model/artifacts/intent_model.pkl`.
3. Flask exposes `/health` and `/predict` endpoints.
4. Gunicorn runs the Flask application through WSGI.

## Local quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python model/train.py
python app.py
```

The API will be available at `http://127.0.0.1:6000`.

## Deploy and test on an AWS EC2 instance

The following walkthrough uses an Ubuntu EC2 instance, a Windows computer, and the `virtual-machines` branch of this repository.

### 1. Launch an EC2 instance

1. Sign in to the AWS Console and open **EC2**.
2. Select **Instances**, then **Launch instances**.
3. Enter a name, for example `intent-classifier-test`.
4. Select an official **Ubuntu Server LTS** AMI with the `64-bit (x86)` architecture.
5. Select an instance type such as `t3.micro`.
6. Create or select an RSA key pair. Select the `.pem` private-key format and download the key. This guide uses `intent-classifier-key.pem`.
7. In the security group, allow inbound **SSH (TCP 22)** from **My IP** and **HTTP (TCP 80)** from your IP for private testing or `0.0.0.0/0` for an intentionally public API. Do not expose SSH to `0.0.0.0/0` unless it is temporarily required.
8. Keep the default storage or adjust it as needed, then select **Launch instance**.
9. Wait until the instance state is **Running** and its status checks pass.
10. Copy the instance's **Public IPv4 address**. It is referenced below as `<PUBLIC_IP>`.

The public IP can change after stopping and starting the instance unless an Elastic IP is assigned.

### 2. Secure the private key on Windows

Open PowerShell and move to the folder containing the downloaded key:

```powershell
cd "$HOME\Downloads"
```

Remove inherited permissions and give only the current Windows user read access:

```powershell
icacls .\intent-classifier-key.pem /inheritance:r
icacls .\intent-classifier-key.pem /grant:r "$($env:USERDOMAIN)\$($env:USERNAME):(R)"
icacls .\intent-classifier-key.pem
```

Never commit the `.pem` file or share its contents.

### 3. Connect to EC2 with SSH

Replace `<PUBLIC_IP>` with the public IPv4 address from the EC2 console:

```powershell
ssh -i .\intent-classifier-key.pem ubuntu@<PUBLIC_IP>
```

Enter `yes` if SSH asks whether to trust the host fingerprint. A successful connection displays an Ubuntu shell prompt similar to:

```text
ubuntu@ip-172-31-x-x:~$
```

### 4. Clone the virtual-machines branch

Run these commands on the EC2 instance:

```bash
mkdir -p ~/opt
cd ~/opt
git clone --branch virtual-machines --single-branch https://github.com/victorjongsoon/Intent-classifier-model.git
cd Intent-classifier-model
git branch --show-current
```

The last command should print `virtual-machines`.

If the instructor's repository was already cloned, point it to this fork and switch branches instead:

```bash
git remote set-url origin https://github.com/victorjongsoon/Intent-classifier-model.git
git fetch origin
git switch --track origin/virtual-machines
```

### 5. Run the deployment script

`userdata.sh` performs the production setup: it installs system packages, deploys the `virtual-machines` branch to `/opt/intent-app`, creates the Python virtual environment, installs dependencies, trains the model, and configures Gunicorn and Nginx as systemd services.

The APT commands use `Acquire::Retries=5`. This protects first-boot provisioning from temporary Ubuntu package-mirror errors such as `503 Service Unavailable`. If all attempts fail, `set -euo pipefail` stops the script instead of continuing with a partially configured server.

Make the script executable and run it as root:

```bash
chmod 700 userdata.sh
sudo ./userdata.sh
```

Do not run `sudo userdata.sh`; the current directory is not normally in root's command search path. Use `sudo ./userdata.sh` or `sudo bash userdata.sh`.

The script is safe to run again. If `/opt/intent-app` already contains the repository, it fetches and fast-forwards the `virtual-machines` branch before reinstalling and restarting the services.

### 6. Verify the systemd services

```bash
systemctl status intent_gunicorn --no-pager
systemctl status nginx --no-pager
```

Both services should show `active (running)`. The Gunicorn service is enabled at boot and runs three workers on the private loopback address `127.0.0.1:6000`.

Useful service commands:

```bash
sudo systemctl restart intent_gunicorn
sudo systemctl reload nginx
sudo journalctl -u intent_gunicorn -n 50 --no-pager
```

### 7. Verify the Nginx reverse proxy

Inspect and validate the active configuration:

```bash
cat /etc/nginx/conf.d/intent_app.conf
sudo nginx -t
```

The proxy target must not contain an endpoint path:

```nginx
proxy_pass http://127.0.0.1:6000;
```

This preserves `/health` and `/predict` when Nginx forwards requests to Gunicorn. Using `http://127.0.0.1:6000/predict` here causes `/predict` requests to be rewritten incorrectly and return `404 Not Found`.

### 8. Call the API through Nginx from EC2

Check the health endpoint on port 80:

```bash
curl http://127.0.0.1/health
```

Expected response:

```json
{"status":"ok"}
```

Classify a complaint:

```bash
curl -X POST http://127.0.0.1/predict -H "Content-Type: application/json" -d '{"text":"I want to cancel my subscription"}'
```

Expected response:

```json
{"intent":"complaint"}
```

Classify a greeting:

```bash
curl -X POST http://127.0.0.1/predict -H "Content-Type: application/json" -d '{"text":"Hi, Whats up"}'
```

Expected response:

```json
{"intent":"greeting"}
```

These requests exercise the complete internal path:

```text
Nginx :80 -> Gunicorn :6000 -> Flask -> trained model
```

The application does not define a `/` route, so requesting `http://127.0.0.1/` returns `404 Not Found`. Use `/health` or `/predict` explicitly.

### 9. Call the public API

Confirm that the EC2 security group permits inbound **HTTP (TCP 80)**. For private testing, restrict the source to your public IP. Use `0.0.0.0/0` only when the API is intentionally public.

From EC2 or another Linux client:

```bash
curl -X POST http://<PUBLIC_IP>/predict -H "Content-Type: application/json" -d '{"text":"I want to cancel my subscription"}'
```

PowerShell:

```powershell
Invoke-RestMethod -Uri "http://<PUBLIC_IP>/predict" -Method Post -ContentType "application/json" -Body '{"text":"I want to cancel my subscription"}'
```

Command Prompt:

```cmd
curl.exe -X POST http://<PUBLIC_IP>/predict -H "Content-Type: application/json" -d "{\"text\":\"I want to cancel my subscription\"}"
```

Port `80` is implied by `http://`. Do not expose Gunicorn's port `6000` in the security group; only Nginx needs to reach it locally.

## Troubleshooting

### `Permissions for private key are too open`

Repeat the `icacls` commands in step 2. The key must only be readable by your Windows account.

### `ensurepip is not available`

Install `python3-venv`, or the version-specific package suggested by Ubuntu, and recreate the virtual environment.

### `FileNotFoundError: model/artifacts/intent_model.pkl`

Train the model before starting Flask or Gunicorn:

```bash
python model/train.py
```

### Nginx returns `404 Not Found` for `/predict`

Confirm that `/etc/nginx/conf.d/intent_app.conf` uses `proxy_pass http://127.0.0.1:6000;` without `/predict` after the port. Validate the file with `sudo nginx -t`, then run `sudo systemctl reload nginx`.

### The root URL `/` returns `404 Not Found`

This is expected because Flask does not define a root endpoint. Send health checks to `GET /health` and classification requests to `POST /predict`.

## Auto Scaling and ALB deployment failure: root cause and fixes

The first Auto Scaling deployment failed because several independent problems occurred. The immediate cause of the original `502 Bad Gateway` was a temporary `503 Service Unavailable` response from the Ubuntu package mirror. The package installation failed, `set -e` stopped the user-data script, and neither Gunicorn nor Nginx was configured. The Application Load Balancer therefore had no working application server.

The complete set of problems and fixes was:

| Problem | Effect | Fix |
| --- | --- | --- |
| Ubuntu package mirror returned `503` | User data stopped during package installation | Add `Acquire::Retries=5` to both APT commands |
| Old user data cloned the instructor's default branch | The instance could receive an older deployment script | Clone this fork's `virtual-machines` branch explicitly |
| Launch template used `intent-classifier-key.pem` | Auto Scaling rejected the launch template because that key-pair name did not exist | Use the AWS key-pair name `intent-classifier-key`; `.pem` is only the local filename |
| Nginx used `proxy_pass http://127.0.0.1:6000/predict;` | Request paths were rewritten and `/health` could not be forwarded correctly | Use `proxy_pass http://127.0.0.1:6000;` |
| Target group checked the wrong URL | Target reported `Target.ResponseCodeMismatch` | Configure the health-check path as `/health` with expected code `200` |

The course script may work when the Ubuntu mirror responds normally. Adding retries makes it more resilient, while the other changes correct separate repository, AWS, and routing configuration issues.

### Diagnose a failed user-data launch

Get the instance ID from the Auto Scaling Group:

```bash
export INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text \
  --region "$AWS_REGION")
echo "$INSTANCE_ID"
```

Connect to the instance and inspect cloud-init. Replace `<PUBLIC_IP>` with the instance's public IP:

```bash
ssh -i ~/intent-classifier-key.pem ubuntu@<PUBLIC_IP>
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status intent_gunicorn nginx --no-pager
```

If cloud-init reports `scripts_user` failed and the log ends with an APT `503`, package installation stopped before the services were created. The committed `userdata.sh` now retries temporary APT failures.

### Create a corrected launch-template version

Run these commands from the repository in CloudShell. AWS uses the key-pair name without the `.pem` extension:

```bash
export AWS_REGION="ap-southeast-1"
export LAUNCH_TEMPLATE_NAME="mlops-template"
export ASG_NAME="mlops-autoscaling"
export KEY_NAME="intent-classifier-key"

aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION"
bash -n userdata.sh
USER_DATA=$(base64 -w0 userdata.sh)
```

Create a version based on the current default and override its user data and key-pair name:

```bash
export LT_VERSION=$(aws ec2 create-launch-template-version \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --source-version '$Default' \
  --version-description "reliable-userdata-and-correct-key" \
  --launch-template-data "{\"KeyName\":\"$KEY_NAME\",\"UserData\":\"$USER_DATA\"}" \
  --query 'LaunchTemplateVersion.VersionNumber' \
  --output text \
  --region "$AWS_REGION")
echo "$LT_VERSION"
```

Decode and inspect the stored user data before launching anything:

```bash
aws ec2 describe-launch-template-versions \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --versions "$LT_VERSION" \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text \
  --region "$AWS_REGION" | base64 -d | grep -E 'apt-get|git clone|proxy_pass'
```

The output should contain the APT retries, the `victorjongsoon` repository with the `virtual-machines` branch, and `proxy_pass http://127.0.0.1:6000;`.

Set the corrected version as the default and update the Auto Scaling Group. Do not start an instance refresh if the ASG update returns an error.

```bash
aws ec2 modify-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --default-version "$LT_VERSION" \
  --region "$AWS_REGION"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE_NAME,Version=$LT_VERSION" \
  --region "$AWS_REGION"
```

Verify that the ASG references the corrected version:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].LaunchTemplate' \
  --output table \
  --region "$AWS_REGION"
```

### Replace old instances safely

Start a rolling instance refresh only after the launch-template update succeeds:

```bash
export REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --strategy Rolling \
  --preferences '{"MinHealthyPercentage":0,"InstanceWarmup":300}' \
  --query 'InstanceRefreshId' \
  --output text \
  --region "$AWS_REGION")
echo "$REFRESH_ID"
```

Monitor it until the status is `Successful` and the percentage is `100`:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --instance-refresh-ids "$REFRESH_ID" \
  --query 'InstanceRefreshes[0].{Status:Status,Percentage:PercentageComplete,Reason:StatusReason}' \
  --output table \
  --region "$AWS_REGION"
```

### Correct and verify the target-group health check

Inspect the current health-check settings:

```bash
aws elbv2 describe-target-groups \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --query 'TargetGroups[0].{Path:HealthCheckPath,Port:HealthCheckPort,Protocol:HealthCheckProtocol,Expected:Matcher.HttpCode}' \
  --output table \
  --region "$AWS_REGION"
```

The path must be `/health`, the port should be `traffic-port`, and the expected HTTP code should be `200`. Correct it if necessary:

```bash
aws elbv2 modify-target-group \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --health-check-protocol HTTP \
  --health-check-port traffic-port \
  --health-check-path /health \
  --matcher HttpCode=200 \
  --region "$AWS_REGION"
```

Check target health until the new instance reports `healthy`:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --query 'TargetHealthDescriptions[].{Instance:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}' \
  --output table \
  --region "$AWS_REGION"
```

Finally, test through the ALB from Windows Command Prompt:

```cmd
curl.exe -X POST "http://<ALB_DNS>/predict" -H "Content-Type: application/json" -d "{\"text\":\"I want to cancel my subscription\"}"
```

Expected response:

```json
{"intent":"complaint"}
```
