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
    ssid=\\"{ssid}\\"
    psk=\\"{password}\\"
    key_mgmt=WPA-PSK
}}
"""
    with open(WPA_FILE, "w") as f:
        f.write(config)
    subprocess.run(["wpa_cli", "-i", "wlan0", "reconfigure"])
