# Kserve Demonstration for Iris model

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

### Port-forward to access the model

```
kubectl -n intent port-forward svc/<svc-name> 8080:80
```

### Run inference using Windows Command Prompt (cmd.exe)

Keep the port-forward command running, then open another Windows Command Prompt window and run:

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

