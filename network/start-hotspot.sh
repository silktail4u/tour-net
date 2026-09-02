#!/bin/bash

set -e

echo "=== Detecting interfaces ==="

IFACE=$(iw dev | awk '$1=="Interface"{print $2; exit}')

if [ -z "$IFACE" ]; then
    echo "ERROR: No Wi-Fi interface found"
    iw dev
    exit 1
fi

UPSTREAM=$(ip route show default | awk '{print $5; exit}')

if [ -z "$UPSTREAM" ]; then
    echo "ERROR: No default route found"
    ip route
    exit 1
fi

if [ "$IFACE" = "$UPSTREAM" ]; then
    echo "ERROR: Wi-Fi interface and upstream interface are the same"
    exit 1
fi

# Dynamically determine the machine's IPv4 address on the upstream
# interface. This replaces the previous hard-coded 192.168.1.66.
HOST_IP=$(
    ip -4 addr show "$UPSTREAM" |
    awk '/inet / {print $2}' |
    cut -d/ -f1 |
    head -n1
)

if [ -z "$HOST_IP" ]; then
    echo "ERROR: Could not determine IPv4 address for $UPSTREAM"
    ip -4 addr show "$UPSTREAM"
    exit 1
fi

echo "Wi-Fi interface : $IFACE"
echo "Upstream        : $UPSTREAM"
echo "Host IP         : $HOST_IP"

echo
echo "=== Checking IPv4 forwarding ==="

if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "Enabling IPv4 forwarding"
    sysctl -w net.ipv4.ip_forward=1
fi

echo
echo "=== Preparing Wi-Fi interface ==="

rfkill unblock wifi || true

ip link set "$IFACE" down || true
ip addr flush dev "$IFACE"
ip link set "$IFACE" up

# Hotspot gateway address
ip addr add 10.42.0.1/24 dev "$IFACE"

echo
echo "=== Configuring hostapd ==="

mkdir -p /etc/hostapd

cat > /etc/hostapd/hostapd.conf <<EOF
interface=$IFACE
driver=nl80211

ssid=Konga-Line
hw_mode=g
channel=6

wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_passphrase=Tare-Land

auth_algs=1
wmm_enabled=0
ieee80211w=0
EOF

echo
echo "=== Configuring dnsmasq ==="

cat > /etc/dnsmasq.conf <<EOF
interface=$IFACE
bind-interfaces

# DHCP
dhcp-range=10.42.0.10,10.42.0.100,255.255.255.0,12h
dhcp-option=3,10.42.0.1
dhcp-option=6,10.42.0.1

# Hosted services.
#
# DNS only maps hostnames to the dynamically detected host IP.
# Ports are handled by the services themselves.
#
# meleenium.slippi  -> HOST_IP:5002
# ftp.slippi        -> HOST_IP:<requested port>
# checkin.slippi    -> HOST_IP:5003

address=/meleenium.slippi/$HOST_IP
address=/ftp.slippi/$HOST_IP
address=/checkin.slippi/$HOST_IP

domain-needed
bogus-priv
EOF

echo
echo "=== Configuring NAT ==="

# Allow hotspot clients to access the Internet through the upstream
# interface.
iptables -t nat -C POSTROUTING \
    -s 10.42.0.0/24 \
    -o "$UPSTREAM" \
    -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING \
    -s 10.42.0.0/24 \
    -o "$UPSTREAM" \
    -j MASQUERADE

# Allow hotspot -> Internet.
iptables -C FORWARD \
    -i "$IFACE" \
    -o "$UPSTREAM" \
    -j ACCEPT 2>/dev/null || \
iptables -A FORWARD \
    -i "$IFACE" \
    -o "$UPSTREAM" \
    -j ACCEPT

# Allow established Internet -> hotspot traffic.
iptables -C FORWARD \
    -i "$UPSTREAM" \
    -o "$IFACE" \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null || \
iptables -A FORWARD \
    -i "$UPSTREAM" \
    -o "$IFACE" \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

echo
echo "=== Allowing hosted services from hotspot ==="

# The hosted applications are on the machine itself.
#
# meleenium = 5002
# checkin   = 5003
#
# FTP is intentionally not restricted to a particular port here.

for PORT in 5002 5003; do
    iptables -C INPUT \
        -i "$IFACE" \
        -p tcp \
        --dport "$PORT" \
        -j ACCEPT 2>/dev/null || \
    iptables -A INPUT \
        -i "$IFACE" \
        -p tcp \
        --dport "$PORT" \
        -j ACCEPT
done

echo
echo "=== Hotspot configuration ==="
echo
echo "SSID:"
echo "  Konga-Line"
echo
echo "Password:"
echo "  Tare-Land"
echo
echo "Wi-Fi interface:"
echo "  $IFACE"
echo
echo "Upstream interface:"
echo "  $UPSTREAM"
echo
echo "Dynamic host IP:"
echo "  $HOST_IP"
echo
echo "Hotspot gateway:"
echo "  10.42.0.1"
echo
echo "DHCP range:"
echo "  10.42.0.10 - 10.42.0.100"
echo
echo "DNS:"
echo "  meleenium.slippi  -> $HOST_IP:5002"
echo "  ftp.slippi        -> $HOST_IP:<requested port>"
echo "  checkin.slippi    -> $HOST_IP:5003"
echo

echo "=== Starting dnsmasq ==="

# Kill an existing dnsmasq instance if one is running.
pkill dnsmasq 2>/dev/null || true
sleep 1

dnsmasq \
    --interface="$IFACE" \
    --address="/meleenium.slippi/$HOST_IP" \
    --address="/ftp.slippi/$HOST_IP" \
    --address="/checkin.slippi/$HOST_IP" \
    --keep-in-foreground &

DNSMASQ_PID=$!

echo "dnsmasq started: PID $DNSMASQ_PID"

echo
echo "=== Starting hostapd ==="

pkill hostapd 2>/dev/null || true
sleep 1

hostapd /etc/hostapd/hostapd.conf &

HOSTAPD_PID=$!

echo "hostapd started: PID $HOSTAPD_PID"

cleanup() {
    echo
    echo "=== Stopping hotspot ==="

    kill "$HOSTAPD_PID" 2>/dev/null || true
    kill "$DNSMASQ_PID" 2>/dev/null || true

    wait "$HOSTAPD_PID" 2>/dev/null || true
    wait "$DNSMASQ_PID" 2>/dev/null || true

    echo "Hotspot stopped"
}

trap cleanup EXIT INT TERM

echo
echo "=== Hotspot is running ==="
echo
echo "Clients should receive:"
echo "  Gateway : 10.42.0.1"
echo "  DNS     : 10.42.0.1"
echo
echo "Service endpoints:"
echo "  meleenium.slippi:5002"
echo "  ftp.slippi:<any requested port>"
echo "  checkin.slippi:5003"
echo

wait "$HOSTAPD_PID"
