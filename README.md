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

### 9. Call the public API from Windows

Confirm that the EC2 security group permits inbound **HTTP (TCP 80)**. For private testing, restrict the source to your public IP. Use `0.0.0.0/0` only when the API is intentionally public.

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
