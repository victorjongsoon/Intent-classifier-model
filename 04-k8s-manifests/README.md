# Deploy and test the model with NodePort

This step deploys two model API pods and temporarily exposes them through a Kubernetes `NodePort`. It matches the development demonstration in which a public EKS worker-node IP is used to call the model directly.

For a production-style deployment, do not expose worker nodes directly. Change the service back to `ClusterIP` and follow `05-traefik-installation.md` and `06-ingress.yaml` instead.

## 1. Apply the namespace and deployment

Run these commands from the repository root:

```bash
kubectl apply -f 04-k8s-manifests/namespace.yml
kubectl apply -f 04-k8s-manifests/deployment.yaml
```

Wait until both replicas are ready:

```bash
kubectl rollout status deployment/intent-classifier -n intent-namespace
kubectl get pods -n intent-namespace -o wide
```

## 2. Use NodePort for the course demonstration

For this demonstration, change the last line of `service.yaml` from:

```yaml
type: ClusterIP
```

to:

```yaml
type: NodePort
```

Apply and inspect the service:

```bash
kubectl apply -f 04-k8s-manifests/service.yaml
kubectl get service intent-classifier -n intent-namespace
```

The `PORT(S)` column will look similar to `80:32609/TCP`. Port `80` is the service port and `32609` is the dynamically assigned NodePort. Your value can be different from the one shown in the course.

Capture the assigned NodePort and a worker's public IP:

```bash
export NODE_PORT=$(kubectl get service intent-classifier -n intent-namespace -o jsonpath='{.spec.ports[0].nodePort}')
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "NODE_IP=$NODE_IP NODE_PORT=$NODE_PORT"
```

## 3. Allow the NodePort in the AWS security group

Creating a Kubernetes NodePort does not automatically permit public traffic through the EC2 security group. Without this rule, requests to the worker IP will time out.

Get a worker EC2 instance ID and display its attached security groups:

```bash
export INSTANCE_ID=$(kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | awk -F/ '{print $NF}')
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups' \
  --output table \
  --region ap-southeast-1
```

Copy the worker or cluster security-group ID from the output:

```bash
export NODE_SG_ID="<SECURITY_GROUP_ID>"
```

Restrict the temporary rule to the current CloudShell public IP:

```bash
export CLIENT_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')
aws ec2 authorize-security-group-ingress \
  --group-id "$NODE_SG_ID" \
  --protocol tcp \
  --port "$NODE_PORT" \
  --cidr "$CLIENT_IP/32" \
  --region ap-southeast-1
```

The course may use `0.0.0.0/0` for a short demonstration, but that exposes the model to the entire internet. A `/32` rule permits only the client IP used for testing.

## 4. Call the model

Check the health endpoint:

```bash
curl --connect-timeout 10 "http://$NODE_IP:$NODE_PORT/health"
```

Run model inference:

```bash
curl --connect-timeout 10 -X POST "http://$NODE_IP:$NODE_PORT/predict" -H "Content-Type: application/json" -d '{"text":"I want to cancel my subscription"}'
```

Expected response:

```json
{"intent":"complaint"}
```

If the request hangs, confirm that the security-group rule uses the current value of `$NODE_PORT` and the public IP of the machine making the request. Selecting **My IP** in the AWS browser console uses the computer browser's public IP, which can differ from CloudShell's public IP.

## 5. Remove temporary public access

Remove the inbound rule immediately after the NodePort demonstration:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$NODE_SG_ID" \
  --protocol tcp \
  --port "$NODE_PORT" \
  --cidr "$CLIENT_IP/32" \
  --region ap-southeast-1
```

## 6. Continue to ingress-based model serving

Change `service.yaml` back to `ClusterIP` and apply it:

```bash
kubectl apply -f 04-k8s-manifests/service.yaml
```

Then install Traefik and configure ingress using the next two project steps. The resulting request path is:

```text
Client -> AWS load balancer -> Traefik ingress -> ClusterIP service -> model pod
```

This avoids giving end users direct access to Kubernetes worker-node IP addresses.
