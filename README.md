# Intent Classifier Model

This project trains a small text-classification model and serves predictions through a Flask API. It can run locally, in Docker, or on Amazon EKS behind Traefik Ingress.

## API endpoints

- `GET /health` returns `{"status":"ok"}`.
- `POST /predict` accepts JSON such as `{"text":"Hello, Hi"}`.

## Run locally with Python

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python model/train.py
python app.py
```

Test the API:

```bash
curl http://127.0.0.1:6000/health
curl -X POST http://127.0.0.1:6000/predict \
  -H "Content-Type: application/json" \
  -d '{"text":"I want to cancel my subscription"}'
```

Expected prediction:

```json
{"intent":"complaint"}
```

## Run locally with Docker

```bash
docker build -t intent-classifier .
docker run -d --name intent-classifier -p 6000:6000 intent-classifier
curl http://127.0.0.1:6000/health
```

On Windows Command Prompt, escape the JSON double quotes:

```cmd
curl.exe -X POST "http://127.0.0.1:6000/predict" -H "Content-Type: application/json" -d "{\"text\":\"Hello, Hi\"}"
```

## Deploy to Amazon EKS

The detailed deployment stages are:

1. [Deployment overview](01-overview.md)
2. [Build and push the container image](02-build-and-push-image.md)
3. [Create the EKS cluster](03-create-k8s-cluster.md)
4. [Deploy the model and test NodePort](04-k8s-manifests/README.md)
5. [Install Traefik](05-traefik-installation.md)
6. Apply [the Ingress resource](06-ingress.yaml)

Before creating a cluster, select a Kubernetes version that is currently under EKS standard support. Older versions can incur substantially higher extended-support charges.

### Deploy the model

```bash
kubectl apply -f 04-k8s-manifests/namespace.yml
kubectl apply -f 04-k8s-manifests/deployment.yaml
kubectl apply -f 04-k8s-manifests/service.yaml
kubectl rollout status deployment/intent-classifier -n intent-namespace
kubectl get all -n intent-namespace
```

The service should use `ClusterIP` when accessed through Traefik.

## Install Helm in AWS CloudShell

AWS CloudShell may include `aws` and `kubectl` without including Helm. Install Helm under the persistent home directory:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL -o "$HOME/get_helm.sh" \
  https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 "$HOME/get_helm.sh"
HELM_INSTALL_DIR="$HOME/.local/bin" "$HOME/get_helm.sh" --no-sudo
export PATH="$HOME/.local/bin:$PATH"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
helm version --short
```

## Install Traefik

Use the current Traefik chart repository:

```bash
helm repo add --force-update traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace
```

Verify the controller and its AWS load balancer:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
```

Wait until the `traefik` service has an external hostname. This `LoadBalancer` service creates a billable AWS load balancer.

## Configure Ingress

The example uses `example.com` as the host. Replace the placeholder in `06-ingress.yaml`, apply it, and confirm that Traefik publishes an address:

```bash
sed -i 's/<your-domain-or-elb-dns>/example.com/' 06-ingress.yaml
kubectl apply -f 06-ingress.yaml
kubectl get ingress -n intent-namespace
```

The request path is:

```text
Client -> AWS load balancer -> Traefik -> Ingress -> ClusterIP service -> model pod
```

### Test from CloudShell

Capture the load-balancer hostname rather than hard-coding one of its changing IP addresses:

```bash
export TRAEFIK_LB=$(kubectl get service traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$TRAEFIK_LB"

curl -X POST "http://$TRAEFIK_LB/predict" \
  -H "Host: example.com" \
  -H "Content-Type: application/json" \
  -d '{"text":"I want to cancel my subscription"}'
```

Expected response:

```json
{"intent":"complaint"}
```

The `Host: example.com` header is required because it matches the host in the Ingress rule.

### Test from Windows Command Prompt

Replace `<TRAEFIK_LB_HOSTNAME>` with the external hostname returned by `kubectl get svc -n traefik`:

```cmd
curl.exe -X POST "http://<TRAEFIK_LB_HOSTNAME>/predict" -H "Host: example.com" -H "Content-Type: application/json" -d "{\"text\":\"Hello, Hi\"}"
```

Expected response:

```json
{"intent":"greeting"}
```

For a temporary DNS override, resolve one of the load-balancer addresses and use:

```cmd
curl.exe -X POST --resolve example.com:80:<LOAD_BALANCER_IP> "http://example.com/predict" -H "Content-Type: application/json" -d "{\"text\":\"Hello, Hi\"}"
```

Do not permanently store the resolved IP because AWS can change load-balancer addresses. For a real domain, create a DNS CNAME or Route 53 alias pointing to the load-balancer hostname.

## Troubleshooting

- `helm: command not found`: install Helm using the CloudShell steps above.
- Traefik `404 page not found`: confirm the path is `/predict` and the request sends the host configured in the Ingress.
- Flask `400 Bad Request` from Windows Command Prompt: escape JSON double quotes as `\"`.
- `nslookup: command not found` in CloudShell: use `getent ahosts <hostname>`; installing `nslookup` is unnecessary.
- A direct request to the load-balancer hostname without `Host: example.com` does not match a host-specific Ingress rule.

Useful diagnostics:

```bash
kubectl describe ingress intent-classifier-ingress -n intent-namespace
kubectl get endpoints intent-classifier -n intent-namespace
kubectl logs -n traefik deployment/traefik
```

## Clean up AWS resources

Delete the Traefik release first so Kubernetes can remove its AWS load balancer, and then delete the EKS cluster:

```bash
helm uninstall traefik -n traefik
kubectl get svc -n traefik
eksctl delete cluster --name demo-cluster --region ap-southeast-1
```

Deleting only the pods does not stop charges for the EKS control plane, worker nodes, storage, public IPv4 addresses, NAT Gateway, or load balancer.
