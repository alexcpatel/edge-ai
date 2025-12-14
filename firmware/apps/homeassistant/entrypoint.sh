#!/bin/bash
# Copy default config if /config is empty (first run)
if [ ! -f /config/configuration.yaml ]; then
    echo "[homeassistant] First run - copying default configuration..."
    cp -r /default-config/* /config/
fi

# Start Home Assistant
exec /init
