# KServe demonstration for Iris and text intent models

### Install Cert Manager

```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

### Install KServe CRDs

```
kubectl create namespace kserve

helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version v0.16.0 \
  -n kserve \
  --wait
```

### Install KServe controller

```
helm install kserve oci://ghcr.io/kserve/charts/kserve \
  --version v0.16.0 \
  -n kserve \
  --set kserve.controller.deploymentMode=RawDeployment \
  --wait
```

### Deploy the Intent Classifier model

```
kubectl create namespace intent

cat <<EOF | kubectl apply -n intent -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: intent-classifier
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "<downloadable location>"
      resources:
        requests:
          cpu: "100m"
          memory: "512Mi"
        limits:
          cpu: "1"
          memory: "1Gi"
EOF

kubectl get inferenceservice intent-classifier -n intent
```

### Deploy and check the text intent model (v2)

From the project directory, apply the v2 manifest:

```cmd
kubectl apply -n intent -f intent-classifier-v2.yaml
kubectl get isvc -n intent
kubectl get pods -n intent
kubectl get svc -n intent
```

Both inference services should show `READY=True`, and their predictor pods should be running. These models use the `intent` namespace; querying `ml` will not list them.

### Port-forward to access both models

Open two separate Command Prompt windows and leave each command running. Use a different local port for each model.

Window 1 — Iris model:

```cmd
kubectl port-forward -n intent svc/intent-classifier-predictor 8080:80
```

Window 2 — text intent model:

```cmd
kubectl port-forward -n intent svc/intent-classifier-v2-predictor 8081:80
```

| Model | Local port | Input |
| --- | --- | --- |
| `intent-classifier` | `8080` | Four Iris measurements |
| `intent-classifier-v2` | `8081` | Text |

### Run inference using Windows Command Prompt (cmd.exe)

Keep both port-forward windows open, then use a third Command Prompt window for the inference commands.

Iris model:

```cmd
curl -s -X POST http://localhost:8080/v1/models/intent-classifier:predict ^
  -H "Content-Type: application/json" ^
  -d "{\"instances\":[[6.8,2.8,4.8,1.4]]}"
```

In Command Prompt, `^` continues the command on the next line. It must be the last character on the line, with no trailing spaces. The `More?` prompt appears automatically; do not type it. Escape the double quotes inside the JSON with `\"`.

Alternatively, run the command on one line:

```cmd
curl -s -X POST http://localhost:8080/v1/models/intent-classifier:predict -H "Content-Type: application/json" -d "{\"instances\":[[6.8,2.8,4.8,1.4]]}"
```

Expected response for this example:

```json
{"predictions":[1]}
```

This Iris model accepts four numeric features per instance: sepal length, sepal width, petal length, and petal width. The returned value `1` is the predicted class index.

Text intent model (v2):

```cmd
curl -s http://localhost:8081/v1/models/intent-classifier-v2:predict ^
  -H "Content-Type: application/json" ^
  -d "{\"instances\":[\"I want to cancel my subscription\"]}"
```

Or on one line:

```cmd
curl -s http://localhost:8081/v1/models/intent-classifier-v2:predict -H "Content-Type: application/json" -d "{\"instances\":[\"I want to cancel my subscription\"]}"
```

Observed response for this example:

```json
{"predictions":["complaint"]}
```

With `-d`, curl automatically uses POST, so `-X POST` is optional. Replace `-s` with `-v` to inspect the HTTP request and response status.

Run each command separately. Do not append a `kubectl` command after the curl JSON payload.

### Troubleshooting port-forwarding

- **`unknown command "port-foward"`:** Use the spelling `port-forward` and include `-n intent`.
- **`Unable to listen on port 8080`:** Another process is using that local port. If the existing Iris port-forward works, keep using it. To restart it, press Ctrl+C in its original window before running it again. Alternatively, use `8082:80` and send Iris requests to `localhost:8082`.
- **`Model with name intent-classifier does not exist.`:** Check which service the requested local port forwards to. Use port `8080` with `intent-classifier` and port `8081` with `intent-classifier-v2` for the setup above. Switching port `8080` to the v2 service changes which model it reaches.
- **`Handling connection for 8080` or `8081`:** This is normal output when a request reaches the port-forward session.
