# Home Assistant - Smart home hub
#
# Uses the official Home Assistant image with ARM64 support.
# Runs on the device with host networking for mDNS/device discovery.

FROM ghcr.io/home-assistant/home-assistant:stable

# Copy default configuration
COPY config/ /default-config/

# Startup script that copies defaults if config is empty
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
