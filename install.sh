#!/bin/bash
# install.sh - Full Industrial IoT Provisioner Setup for Raspberry Pi 4 (64-bit Bookworm)

set -e

echo "[1/8] Updating system..."
sudo apt update && sudo apt upgrade -y


## DEPENDENCIES

echo "[2/8] Installing dependencies..."
sudo apt install -y hostapd dnsmasq python3-flask mosquitto mosquitto-clients python3-cryptography git ufw

sudo systemctl disable hostapd
sudo systemctl disable dnsmasq


## STATIC IP FOR AP MODE

echo "[3/8] Configuring AP mode static IP..."
cat <<EOF | sudo tee -a /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.4.1/24
EOF


## DNSMASQ CONFIG

echo "[4/8] Setting up dnsmasq..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
cat <<EOF | sudo tee /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF


## HOSTAPD CONFIG

echo "[5/8] Setting up hostapd..."
cat <<EOF | sudo tee /etc/hostapd/hostapd.conf
interface=wlan0
ssid=RPi-Setup
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

sudo sed -i 's|#DAEMON_CONF="|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd


## PROVISIONING PORTAL FILES

mkdir -p /home/pi/iot-provisioner/portal/templates
cd /home/pi/iot-provisioner

cat <<EOF > portal/templates/index.html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>WiFi Provisioning</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet">
  </head>
  <body class="container mt-5">
    <h2>Connect Raspberry Pi to WiFi</h2>
    <form method="POST">
      <div class="mb-3">
        <label>WiFi SSID</label>
        <input name="ssid" class="form-control" required>
      </div>
      <div class="mb-3">
        <label>Password</label>
        <input name="password" type="password" class="form-control" required>
      </div>
      <button type="submit" class="btn btn-primary">Connect</button>
    </form>
  </body>
</html>
EOF

cat <<EOF > portal/credentials.py
import os
import subprocess
from cryptography.fernet import Fernet

KEY_FILE = "/home/pi/iot-provisioner/portal/secret.key"
WPA_FILE = "/etc/wpa_supplicant/wpa_supplicant.conf"

def generate_key():
    key = Fernet.generate_key()
    with open(KEY_FILE, "wb") as keyfile:
        keyfile.write(key)

def load_key():
    if not os.path.exists(KEY_FILE):
        generate_key()
    return open(KEY_FILE, "rb").read()

def write_credentials(ssid, password):
    config = f"""
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=GB

network={{
    ssid=\"{ssid}\"
    psk=\"{password}\"
    key_mgmt=WPA-PSK
}}
"""
    with open(WPA_FILE, "w") as f:
        f.write(config)
    subprocess.run(["wpa_cli", "-i", "wlan0", "reconfigure"])
EOF

cat <<EOF > portal/app.py
from flask import Flask, request, render_template
import credentials

app = Flask(__name__)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        ssid = request.form['ssid']
        password = request.form['password']
        credentials.write_credentials(ssid, password)
        return "Connecting... Please wait 1 minute and reconnect."
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF


## SYSTEMD SERVICES

mkdir -p /home/pi/iot-provisioner/services

cat <<EOF > services/wifi-checker.sh
#!/bin/bash
sleep 10
ping -c 1 8.8.8.8 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "WiFi Connected"
    systemctl stop hostapd
    systemctl stop dnsmasq
    systemctl stop wifi-portal
    systemctl start mosquitto
else
    echo "WiFi NOT connected"
    systemctl stop mosquitto
    systemctl start hostapd
    systemctl start dnsmasq
    systemctl start wifi-portal
fi
EOF
chmod +x services/wifi-checker.sh

cat <<EOF | sudo tee /etc/systemd/system/wifi-checker.service
[Unit]
Description=WiFi Connectivity Checker
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/home/pi/iot-provisioner/services/wifi-checker.sh
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee /etc/systemd/system/wifi-portal.service
[Unit]
Description=Captive WiFi Portal
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/iot-provisioner/portal/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF


## ENABLE SERVICES

sudo systemctl enable wifi-checker.service
sudo systemctl enable wifi-portal.service
sudo systemctl enable mosquitto

sudo ufw allow 1883


## FINAL MESSAGE

echo "[8/8] Setup complete. Rebooting..."
sudo reboot

