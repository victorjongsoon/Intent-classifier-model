#!/bin/bash

# Directory
# update packages
# Git clone - Download
# Python Virtual Env
# Install the Python Dependencies
# Run Model
# WSGI -> Linux systemd service
# Nginx -> Linux systemd service
# Enable services

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root: sudo ./userdata.sh"
  exit 1
fi

export APP_DIR=/opt/intent-app

apt update -y
apt install -y git python3 python3-venv python3-pip nginx

if [ -d "$APP_DIR/.git" ]; then
  git -c safe.directory="$APP_DIR" -C "$APP_DIR" remote set-url origin https://github.com/victorjongsoon/Intent-classifier-model.git
  git -c safe.directory="$APP_DIR" -C "$APP_DIR" fetch origin virtual-machines
  git -c safe.directory="$APP_DIR" -C "$APP_DIR" switch virtual-machines
  git -c safe.directory="$APP_DIR" -C "$APP_DIR" pull --ff-only origin virtual-machines
else
  mkdir -p "$APP_DIR"
  git clone --branch virtual-machines --single-branch https://github.com/victorjongsoon/Intent-classifier-model.git "$APP_DIR"
fi

cd "$APP_DIR"

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

python model/train.py
chown -R ubuntu:ubuntu "$APP_DIR"

# Configure Gunicorn systemd service
cat >/etc/systemd/system/intent_gunicorn.service <<'EOF'
[Unit]
Description=Gunicorn instance for Intent Classifier
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/intent-app
Environment="PATH=/opt/intent-app/.venv/bin"
ExecStart=/opt/intent-app/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:6000 wsgi:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# configure nginx reverse proxy (default config will be overwritten)
cat >/etc/nginx/conf.d/intent_app.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:6000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
    }
}
EOF

# Remove default site if present to avoid duplicate default_server collision
if [ -L /etc/nginx/sites-enabled/default ] || [ -f /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default || true
fi

# start & enable services
systemctl daemon-reload
systemctl enable intent_gunicorn
systemctl restart intent_gunicorn
nginx -t
systemctl enable nginx
systemctl restart nginx
