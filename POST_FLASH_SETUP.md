# Post-Flash Setup

Packages and configuration needed after flashing the Yocto image.
This will inform the setup script.

---

## Pre-configured in Image

The following are already set up in the Yocto image:

- **Hostname:** `edge-ai`
- **SSH:** Enabled (via debug-tweaks, root login allowed)
- **Network:** Ethernet (DHCP)
- **Weston:** Auto-starts for display output

---

## NVIDIA SDK Packages (Required for AI)

The following require NVIDIA Developer account and SDK Manager download:

- **cuDNN** - Deep learning primitives
- **TensorRT** - Inference optimization
- **DeepStream** - AI video analytics

### Install via JetPack / SDK Manager

1. Download packages from [NVIDIA Developer](https://developer.nvidia.com/embedded/jetpack)
2. Transfer .deb packages to device
3. Install:

```bash
dpkg -i cudnn*.deb
dpkg -i tensorrt*.deb
dpkg -i deepstream*.deb
```

### Test DeepStream

```bash
export DISPLAY=:0
deepstream-app -c /opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app/<CONFIG_FILE>
```

---

## AWS IoT

### Install AWS CLI and IoT SDK

```bash
pip3 install awscli awsiotsdk
```

### Configure AWS credentials

```bash
aws configure
```

### AWS IoT Device Setup (Automated)

Use the provisioning script from `iot/`:

```bash
# First, deploy shared resources via Terraform (run once from dev machine)
cd iot/terraform
terraform init
terraform apply

# Then on each device, run provisioning
cd iot/python
pip3 install -e .
edge-ai-iot provision
```

This will:

- Generate ECDSA P-256 key pair on device
- Create IoT Thing and certificate via CSR
- Save credentials to `/etc/aws-iot/`

Credentials are stored in `/etc/aws-iot/config.json`

---

## Telemetry (Free Options)

### Option A: Prometheus + Node Exporter

```bash
# Install node_exporter for system metrics
pip3 install prometheus-client

# Or download binary from prometheus.io
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz
tar xzf node_exporter-*.tar.gz
./node_exporter &
```

Metrics available at `http://localhost:9100/metrics`

### Option B: Collectd (lightweight)

```bash
# If available via opkg/package manager
opkg install collectd
```

### Option C: Telegraf

```bash
# Download from InfluxData
# Supports output to AWS CloudWatch, InfluxDB, Prometheus, etc.
```

---

## ROS2 (Jazzy)

ROS2 is not pre-installed but meta-ros layers are included in the build.

### Option A: Install via package manager (if available)

```bash
# Check available ROS2 packages
opkg list | grep ros
```

### Option B: Build with colcon (using SDK)

Cross-compile ROS2 packages on dev machine using the SDK, then deploy via rsync.

### Environment setup

```bash
source /opt/ros/jazzy/setup.bash  # if installed
```

---

## Python Packages

Common packages to install:

```bash
pip3 install \
    numpy \
    opencv-python \
    paho-mqtt \
    boto3 \
    requests
```

---

## Network Configuration

Ethernet with DHCP is configured by default.

### Static IP (if needed)

```bash
# Edit /etc/systemd/network/eth.network or use connmanctl
```

### Configure WiFi (if applicable)

```bash
connmanctl
> enable wifi
> scan wifi
> agent on
> connect wifi_<SSID>
```

---

## Checklist

**Pre-configured (verify working):**

- [ ] SSH accessible via ethernet
- [ ] Hostname is `edge-ai`

**Post-flash setup:**

- [ ] NVIDIA SDK packages (cuDNN, TensorRT, DeepStream)
- [ ] AWS IoT certificates deployed
- [ ] AWS CLI configured
- [ ] Telemetry agent running
- [ ] Test CUDA: run a CUDA sample
- [ ] Test DeepStream pipeline
