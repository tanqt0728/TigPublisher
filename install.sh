#!/bin/bash

# Force root user
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Prompt for owner tag
read -p "Enter your owner tag: " owner_tag

# Install Python and pip if not already installed
apt-get update
apt-get install -y python3 python3-pip

# Install required Python packages
pip3 install requests

# Create directory for TigPublisher
mkdir -p /opt/tigpublisher

# Create TigPublisher script
cat > /opt/tigpublisher/tigpublisher.py << EOL
import requests
import subprocess
import socket
import time
import logging
import uuid
import argparse

# Set up logging
logging.basicConfig(filename='/root/tigpublisher.log', level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')

# Parse command-line arguments
parser = argparse.ArgumentParser(description="TigPublisher Mining Monitor Client")
parser.add_argument("--ownertag", required=True, help="Set the owner tag")
args = parser.parse_args()

# Configuration
SERVER_URL = "http://192.99.13.55:5000/update"
UPDATE_INTERVAL = 1
THREAD_COUNT_CMD = '''pgrep -f "tig-benchmarker 0xdbc262a7f3f03033da8c4addf9630fb6186718b3 83e5a8baad01ba664d65b0fddd8e7c1e" | xargs -I{} ps -o nlwp= -p {} 2>/dev/null | awk '{s+=$1} END {print s ? s-1 : 0}' '''
IP_SERVICES = [
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com"
]

# Generate a unique identifier for this machine
MACHINE_ID = str(uuid.uuid4())

# Cache for public IP
cached_ip = None
last_ip_check = 0
IP_CACHE_DURATION = 300  # 5 minutes

def get_thread_count():
    try:
        result = subprocess.run(THREAD_COUNT_CMD, shell=True, capture_output=True, text=True, check=True)
        return int(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        logging.error(f"Error getting thread count: {e}")
        return 0

def get_public_ip():
    global cached_ip, last_ip_check
    current_time = time.time()
    
    if cached_ip and (current_time - last_ip_check) < IP_CACHE_DURATION:
        return cached_ip

    for service in IP_SERVICES:
        try:
            response = requests.get(service, timeout=10)
            if response.status_code == 200:
                cached_ip = response.text.strip()
                last_ip_check = current_time
                return cached_ip
        except requests.RequestException as e:
            logging.warning(f"Failed to get IP from {service}: {e}")
    
    logging.error("Failed to get public IP from all services")
    return "Unknown"

def get_ip_addresses():
    hostname = socket.gethostname()
    internet_ip = get_public_ip()
    
    try:
        intranet_ip = socket.gethostbyname(hostname)
    except socket.gaierror as e:
        logging.error(f"Error getting local IP: {e}")
        intranet_ip = "Unknown"
    
    return internet_ip, intranet_ip, hostname

def send_update():
    thread_count = get_thread_count()
    internet_ip, intranet_ip, hostname = get_ip_addresses()
    
    data = {
        "owner_tag": args.ownertag,
        "machine_id": MACHINE_ID,
        "thread_count": thread_count,
        "internet_ip": internet_ip,
        "intranet_ip": intranet_ip,
        "hostname": hostname
    }
    
    try:
        response = requests.post(SERVER_URL, json=data, timeout=10)
        response.raise_for_status()
        logging.info("Update sent successfully")
    except requests.RequestException as e:
        logging.error(f"Failed to send update: {e}")

def main():
    logging.info(f"Starting TigPublisher for owner: {args.ownertag}, Machine ID: {MACHINE_ID}")
    print(f"TigPublisher started for owner: {args.ownertag}")
    print(f"Machine ID: {MACHINE_ID}")
    print("Logs are being written to: /root/tigpublisher.log")
    print("Sending updates every second. Press Ctrl+C to stop.")
    
    try:
        while True:
            send_update()
            time.sleep(UPDATE_INTERVAL)
    except KeyboardInterrupt:
        print("\nTigPublisher stopped.")

if __name__ == "__main__":
    main()
EOL

# Set permissions
chmod 755 /opt/tigpublisher/tigpublisher.py

# Create the systemd service file
cat > /etc/systemd/system/tigpublisher.service << EOL
[Unit]
Description=TigPublisher Mining Monitor Client
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/tigpublisher/tigpublisher.py --ownertag ${owner_tag}
Restart=always
User=root
StandardOutput=append:/root/tigpublisher.log
StandardError=append:/root/tigpublisher.log

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable tigpublisher.service
systemctl start tigpublisher.service

echo "TigPublisher has been installed and started. It will automatically run on system startup."
echo "You can check its status with: systemctl status tigpublisher.service"
echo "Logs are available at: /root/tigpublisher.log"
echo "Logs are available at: /root/tigpublisher.log"