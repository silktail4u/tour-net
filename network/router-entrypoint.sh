#!/bin/sh
set -eu

WAN_IF="${WAN_IF:-eth0}"
LAN_IF="${LAN_IF:-wlp2s0}"
LAN_IP="${LAN_IP:-10.50.0.1}"
LAN_NET="${LAN_NET:-10.50.0.0/24}"

echo "[router] WAN: $WAN_IF"
echo "[router] LAN: $LAN_IF"
echo "[router] LAN IP: $LAN_IP"
echo "[router] LAN network: $LAN_NET"

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# Disable reverse-path filtering. This can otherwise interfere
# with routing/NAT on a multi-interface host.
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w "net.ipv4.conf.${WAN_IF}.rp_filter=0"
sysctl -w "net.ipv4.conf.${LAN_IF}.rp_filter=0"

# Configure the Wi-Fi interface
ip link set "$LAN_IF" up
ip addr replace "${LAN_IP}/24" dev "$LAN_IF"

# Clear old NAT/routing rules created by this router.
iptables -t nat -F
iptables -t nat -X
iptables -F FORWARD

# Permit LAN -> WAN
iptables -A FORWARD \
    -i "$LAN_IF" \
    -o "$WAN_IF" \
    -s "$LAN_NET" \
    -j ACCEPT

# Permit return traffic
iptables -A FORWARD \
    -i "$WAN_IF" \
    -o "$LAN_IF" \
    -d "$LAN_NET" \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

# NAT Wi-Fi clients onto the WAN
iptables -t nat -A POSTROUTING \
    -s "$LAN_NET" \
    -o "$WAN_IF" \
    -j MASQUERADE

echo "[router] forwarding and NAT configured"

# Keep container alive.
while :; do
    sleep 3600
done
