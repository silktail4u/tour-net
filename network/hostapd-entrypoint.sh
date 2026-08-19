#!/bin/sh
set -eu

LAN_IF="${LAN_IF:-wlp2s0}"
EVENT_SSID="${EVENT_SSID:-Event-WiFi}"
EVENT_PASSWORD="${EVENT_PASSWORD:-ChangeMe123!}"

echo "[hostapd] starting AP on $LAN_IF"
echo "[hostapd] SSID: $EVENT_SSID"

cat > /tmp/hostapd.conf <<EOF
interface=$LAN_IF
driver=nl80211

ssid=$EVENT_SSID

hw_mode=g
channel=6
country_code=US

ieee80211n=1
wmm_enabled=1

auth_algs=1
ignore_broadcast_ssid=0

wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$EVENT_PASSWORD

# Useful for event/public networks
ap_isolate=0

logger_syslog=-1
logger_syslog_level=2
EOF

# Make sure NetworkManager/systemd isn't keeping control of the interface.
ip link set "$LAN_IF" up

exec hostapd -dd /tmp/hostapd.conf
