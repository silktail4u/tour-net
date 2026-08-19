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
    echo "ERROR: Wi-Fi and upstream interfaces are the same"
    exit 1
fi

echo "Wi-Fi interface : $IFACE"
echo "Upstream        : $UPSTREAM"

echo
echo "=== Checking IP forwarding ==="

FORWARDING=$(cat /proc/sys/net/ipv4/ip_forward)

if [ "$FORWARDING" != "1" ]; then
    echo "ERROR: IPv4 forwarding is disabled."
    echo "Docker must have enabled forwarding on the host."
    exit 1
fi

echo "IPv4 forwarding : enabled"

echo
echo "=== Preparing Wi-Fi ==="

rfkill unblock wifi || true
ip link set "$IFACE" down || true
ip addr flush dev "$IFACE"
ip link set "$IFACE" up

echo
echo "=== Configuring hostapd ==="

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
echo "=== Configuring DHCP ==="

cat > /etc/dnsmasq.conf <<EOF
interface=$IFACE
bind-interfaces

dhcp-range=10.42.0.10,10.42.0.100,255.255.255.0,12h

dhcp-option=3,10.42.0.1
dhcp-option=6,10.42.0.1

address=/app.stationcheckin.com/192.168.1.66

domain-needed
bogus-priv
EOF

ip addr add 10.42.0.1/24 dev "$IFACE"

echo
echo "=== Configuring NAT ==="

iptables -t nat -F
iptables -F FORWARD

iptables -t nat -A POSTROUTING \
    -s 10.42.0.0/24 \
    -o "$UPSTREAM" \
    -j MASQUERADE

iptables -A FORWARD \
    -i "$IFACE" \
    -o "$UPSTREAM" \
    -j ACCEPT

iptables -A FORWARD \
    -i "$UPSTREAM" \
    -o "$IFACE" \
    -m conntrack \
    --ctstate ESTABLISHED,RELATED \
    -j ACCEPT

echo
echo "================================"
echo " Hotspot configuration"
echo "================================"
echo "SSID       : Konga-Line"
echo "Password   : Tare-Land"
echo "Wi-Fi      : $IFACE"
echo "Internet   : $UPSTREAM"
echo "Gateway    : 10.42.0.1"
echo "DHCP range : 10.42.0.10-10.42.0.100"
echo "================================"
echo

dnsmasq --keep-in-foreground &
DNSMASQ_PID=$!

hostapd /etc/hostapd/hostapd.conf &
HOSTAPD_PID=$!

cleanup() {
    echo "Stopping hotspot..."
    kill "$HOSTAPD_PID" "$DNSMASQ_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

wait "$HOSTAPD_PID"
