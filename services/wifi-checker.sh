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
