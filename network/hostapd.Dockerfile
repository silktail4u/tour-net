FROM alpine:latest

RUN apk add --no-cache \
    hostapd \
    iw \
    wireless-tools \
    bash

COPY hostapd-entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
