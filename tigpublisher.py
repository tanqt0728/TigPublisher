import os
import requests
import subprocess
import socket
import time
import logging
import uuid
import json

# Set up logging
logging.basicConfig(filename='/var/log/tigpublisher.log', level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')

# Default configuration
DEFAULT_CONFIG = {
    "SERVER_URL": "http://your_server_ip:5000/update",
    "UPDATE_INTERVAL": 1,
    "THREAD_COUNT_CMD": '''pgrep -f "tig-benchmarker 0xdbc262a7f3f03033da8c4addf9630fb6186718b3 83e5a8baad01ba664d65b0fddd8e7c1e" | xargs -I{} ps -o nlwp= -p {} | awk '{s+=$1} END {print s-1}' ''',
    "PUBLIC_IP_URL": "https://api.ipify.org",
    "MACHINE_ID": ""
}

CONFIG_FILE = '/etc/tigpublisher/config.json'

def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return DEFAULT_CONFIG

def save_config(config):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def get_machine_id():
    config = load_config()
    if not config['MACHINE_ID']:
        config['MACHINE_ID'] = str(uuid.uuid4())
        save_config(config)
    return config['MACHINE_ID']

MACHINE_ID = get_machine_id()

def get_thread_count(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        return int(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        logging.error(f"Error getting thread count: {e}")
        return 0

def get_ip_addresses(public_ip_url):
    hostname = socket.gethostname()
    try:
        internet_ip = requests.get(public_ip_url, timeout=5).text
    except requests.RequestException as e:
        logging.error(f"Error getting public IP: {e}")
        internet_ip = "Unknown"
    
    try:
        intranet_ip = socket.gethostbyname(hostname)
    except socket.gaierror as e:
        logging.error(f"Error getting local IP: {e}")
        intranet_ip = "Unknown"
    
    return internet_ip, intranet_ip, hostname

def send_update(config, owner_tag):
    thread_count = get_thread_count(config['THREAD_COUNT_CMD'])
    internet_ip, intranet_ip, hostname = get_ip_addresses(config['PUBLIC_IP_URL'])
    
    data = {
        "owner_tag": owner_tag,
        "machine_id": MACHINE_ID,
        "thread_count": thread_count,
        "internet_ip": internet_ip,
        "intranet_ip": intranet_ip,
        "hostname": hostname
    }
    
    try:
        response = requests.post(config['SERVER_URL'], json=data, timeout=10)
        response.raise_for_status()
        logging.info("Update sent successfully")
    except requests.RequestException as e:
        logging.error(f"Failed to send update: {e}")

def main():
    owner_tag = os.environ.get('OWNER_TAG')
    if not owner_tag:
        logging.error("OWNER_TAG environment variable is not set")
        print("Error: OWNER_TAG environment variable is not set")
        return

    config = load_config()

    logging.info(f"Starting TigPublisher for owner: {owner_tag}, Machine ID: {MACHINE_ID}")
    print(f"TigPublisher started for owner: {owner_tag}")
    print(f"Machine ID: {MACHINE_ID}")
    print("Sending updates every second. Press Ctrl+C to stop.")
    
    try:
        while True:
            send_update(config, owner_tag)
            time.sleep(config['UPDATE_INTERVAL'])
    except KeyboardInterrupt:
        print("\nTigPublisher stopped.")

if __name__ == "__main__":
    main()