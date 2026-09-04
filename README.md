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
7. In the security group, allow inbound **SSH (TCP 22)** from **My IP**. Do not expose SSH to `0.0.0.0/0` unless it is temporarily required.
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

### 5. Install Python and create a virtual environment

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

The prompt should now start with `(.venv)`. If Ubuntu requests a version-specific package, install the package named in the error—for example:

```bash
sudo apt install -y python3.14-venv
python3 -m venv --clear .venv
source .venv/bin/activate
```

### 6. Train the model

```bash
python model/train.py
```

The command should print `trained`. Confirm that the generated artifact exists:

```bash
ls -l model/artifacts/intent_model.pkl
```

The model artifact is generated locally and intentionally excluded from Git.

### 7. Start Gunicorn

```bash
gunicorn --workers 3 --bind 127.0.0.1:6000 wsgi:app
```

Gunicorn should report that it is listening at `http://127.0.0.1:6000` and that three workers have booted. Keep this SSH window open while testing. Press `Ctrl+C` when you want to stop Gunicorn.

`wsgi:app` tells Gunicorn to load the `app` object from `wsgi.py`. Binding to `127.0.0.1` keeps port 6000 private to the EC2 instance.

### 8. Call the API from the EC2 instance

Open a second PowerShell window, connect to the instance again using SSH, and run the following commands inside the EC2 session.

Check the health endpoint:

```bash
curl http://127.0.0.1:6000/health
```

Expected response:

```json
{"status":"ok"}
```

Classify a complaint:

```bash
curl -X POST http://127.0.0.1:6000/predict -H "Content-Type: application/json" -d '{"text":"I want to cancel my subscription"}'
```

Expected response:

```json
{"intent":"complaint"}
```

Classify a greeting:

```bash
curl -X POST http://127.0.0.1:6000/predict -H "Content-Type: application/json" -d '{"text":"Hi, Whats up"}'
```

Expected response:

```json
{"intent":"greeting"}
```

### 9. Optional: call the private API from Windows through SSH

An SSH tunnel lets Windows reach Gunicorn without opening port 6000 in the EC2 security group. Keep Gunicorn running, then open another PowerShell window in the key directory:

```powershell
ssh -i .\intent-classifier-key.pem -L 6000:127.0.0.1:6000 ubuntu@<PUBLIC_IP>
```

While that SSH connection remains open, use another PowerShell window to call the API:

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:6000/predict" -Method Post -ContentType "application/json" -Body '{"text":"I want to cancel my subscription"}'
```

Command Prompt equivalent:

```cmd
curl.exe -X POST http://127.0.0.1:6000/predict -H "Content-Type: application/json" -d "{\"text\":\"I want to cancel my subscription\"}"
```

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

### Gunicorn works only while SSH is open

This walkthrough runs Gunicorn in the foreground for verification. The next production step is to configure Gunicorn as a `systemd` service and place Nginx in front of it on port 80 or 443.
