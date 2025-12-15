# go2rtc - Lightweight RTSP proxy for Blink cameras
# Exposes Blink live view as RTSP streams for DeepStream consumption

FROM alexxit/go2rtc:latest

COPY config.yaml /config/go2rtc.yaml

EXPOSE 8554/tcp
EXPOSE 1984/tcp

CMD ["go2rtc", "-config", "/config/go2rtc.yaml"]
