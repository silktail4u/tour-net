FROM alpine:latest
RUN apk add --no-cache dnsmasq
# Keep the container running in the foreground by default
ENTRYPOINT [dnsmasq, --keep-in-foreground]

