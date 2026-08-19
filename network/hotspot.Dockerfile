FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        hostapd \
        dnsmasq \
        iw \
        iproute2 \
        iptables \
        ethtool \
        procps \
        wireless-regdb && \
    rm -rf /var/lib/apt/lists/*

COPY start-hotspot.sh /usr/local/bin/start-hotspot.sh

RUN chmod +x /usr/local/bin/start-hotspot.sh

CMD ["/usr/local/bin/start-hotspot.sh"]
