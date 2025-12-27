# Edge AI

Secure edge computing platform for NVIDIA Jetson devices. Features read-only rootfs with signed container deployments via AWS IoT.

## Stack

- **Image**: Yocto/OE with L4T + CUDA + TensorRT
- **Infra**: AWS IoT Fleet Provisioning, ECR, KMS container signing
- **Build**: Automated remote EC2 builds with cost-minimizing idle management
- **Flash**: Automated flashing via optocoupler-controlled recovery mode (programmatically shorts pins to enter forced recovery)
- **Tooling**: VSCode extension for build/flash workflow orchestration
- **App**: Wildlife detection camera (YOLOv8 → TensorRT)

## Quick Start

```bash
# Build firmware image (auto-starts EC2, auto-stops on complete)
make firmware-build

# Deploy app to device (sandbox mode)
make firmware-app-sandbox APP=squirrel-cam DEVICE=192.168.86.34

# Production deploy (signed)
make firmware-app-push APP=squirrel-cam VERSION=v1
make firmware-app-deploy APP=squirrel-cam DEVICE=192.168.86.34 VERSION=v1
```

## Screenshots

<p align="center">
  <img src="photos/device-1.jpg" width="30%" />
  <img src="photos/device-2.jpg" width="30%" />
  <img src="photos/vscode-extension.png" width="30%" />
</p>

<p align="center">
  <img src="photos/vscode-extension-2.png" width="30%" />
  <img src="photos/flash-terminal.png" width="30%" />
</p>
