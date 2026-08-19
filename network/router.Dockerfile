FROM alpine:latest

RUN apk add --no-cache \
    iproute2 \
    iptables \
    ip6tables

COPY router-entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
