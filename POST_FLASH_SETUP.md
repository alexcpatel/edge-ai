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

### Prerequisites (Dev Machine)

```bash
# Install provisioning tools
cd iot/provision
pip install -e .

# Deploy shared infrastructure (once)
cd ../terraform
terraform init
terraform apply
```

### Provision Device (From Dev Machine)

```bash
# Provision device at IP address
edge-ai-iot provision <DEVICE_IP>

# With options
edge-ai-iot provision 192.168.1.100 --user root --port 22
```

This SSHs into the device and:

1. Installs Python packages (awscli, awsiotsdk, numpy, paho-mqtt, boto3, requests)
2. Generates ECDSA P-256 key pair on device
3. Creates IoT Thing and certificate via CSR
4. Downloads Amazon Root CA
5. Saves credentials to `/etc/aws-iot/`
6. Verifies IoT connection

### Re-provision After Reflash

```bash
# Idempotent - cleans up old resources first
edge-ai-iot provision <DEVICE_IP>
```

### Skip Steps

```bash
# Skip dependency installation (faster re-provision)
edge-ai-iot provision <DEVICE_IP> --skip-deps

# Skip connection verification
edge-ai-iot provision <DEVICE_IP> --skip-verify
```

### Cleanup Orphaned Resources

```bash
# Remove things/certs not attached to anything
edge-ai-iot cleanup --dry-run  # preview
edge-ai-iot cleanup            # execute
```

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

## Systemd Services

### Create a service for your application

```bash
cat > /etc/systemd/system/edge-ai-app.service << 'EOF'
[Unit]
Description=Edge AI Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/edge-ai/app.py
Restart=always
RestartSec=10
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable edge-ai-app
systemctl start edge-ai-app
```

### View logs

```bash
journalctl -u edge-ai-app -f
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
- [ ] Weston display running

**NVIDIA SDK:**

- [ ] cuDNN installed
- [ ] TensorRT installed
- [ ] DeepStream installed
- [ ] Test CUDA sample
- [ ] Test DeepStream pipeline

**AWS IoT (run from dev machine):**

- [ ] Terraform infrastructure deployed (`iot/terraform`)
- [ ] Device provisioned (`edge-ai-iot provision <IP>`)

**Application:**

- [ ] Application deployed to `/opt/edge-ai/`
- [ ] Systemd service created and enabled
- [ ] Telemetry agent running

**Optional:**

- [ ] ROS2 packages installed
- [ ] Static IP configured
- [ ] WiFi configured
