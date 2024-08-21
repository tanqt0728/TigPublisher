#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Prompt for owner tag
read -p "Enter your owner tag: " owner_tag

# Install dependencies
apt-get update
apt-get install -y python3 python3-pip
pip3 install requests

# Create directories
mkdir -p /opt/tigpublisher
mkdir -p /etc/tigpublisher

# Download the main script
curl -o /opt/tigpublisher/tigpublisher.py https://raw.githubusercontent.com/tanqt0728/TigPublisher/main/tigpublisher.py

# Create the systemd service file
cat > /etc/systemd/system/tigpublisher.service <<EOL
[Unit]
Description=TigPublisher Mining Monitor Client
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/tigpublisher/tigpublisher.py
Environment="OWNER_TAG=${owner_tag}"
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable tigpublisher.service
systemctl start tigpublisher.service

echo "TigPublisher has been installed and started. It will automatically run on system startup."
echo "You can check its status with: systemctl status tigpublisher.service"