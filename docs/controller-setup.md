# Raspberry Pi Controller Setup

This guide explains how to set up and use a Raspberry Pi as a controller for flashing Jetson devices.

## Overview

The controller setup allows you to:

- Flash Jetson devices remotely via USB using a Raspberry Pi
- Download tegraflash archives directly to the Raspberry Pi
- Manage all flashing operations from your laptop via NordVPN Meshnet
- Easily update controller software (Docker images and scripts)

## Architecture

```
┌─────────────┐      NordVPN Meshnet       ┌──────────────┐
│   Laptop    │ ◄─────────────────────────► │ Raspberry Pi │
│             │                              │  Controller  │
│  - Build    │                              │              │
│  - Deploy   │                              │  - Docker    │
│  - Control  │                              │  - Scripts   │
└─────────────┘                              └──────┬───────┘
                                                    │ USB
                                                    ▼
                                            ┌──────────────┐
                                            │  Jetson      │
                                            │  (Recovery)  │
                                            └──────────────┘
```

## Initial Setup

### 1. Install NordVPN on Raspberry Pi

```bash
# Install NordVPN
curl -fsSL https://downloads.nordcdn.com/apps/linux/install.sh | sh

# Login to your NordVPN account
nordvpn login

# Enable Meshnet
nordvpn set meshnet on

# Verify Meshnet is enabled
nordvpn meshnet peer list
```

Note your Meshnet hostname or IP from the peer list.

### 2. Install NordVPN on Your Laptop

Install NordVPN on your development laptop and enable Meshnet:

```bash
# Install NordVPN (if not already installed)
# macOS: brew install --cask nordvpn
# Linux: curl -fsSL https://downloads.nordcdn.com/apps/linux/install.sh | sh

# Login
nordvpn login

# Enable Meshnet
nordvpn set meshnet on

# Verify both devices can see each other
nordvpn meshnet peer list
```

### 3. Set Up SSH Over Meshnet

You need passwordless SSH access from your laptop to the Raspberry Pi. Choose one method:

#### Option A: SSH Key Authentication (Recommended)

**On your laptop**, generate an SSH key if you don't have one:

```bash
ssh-keygen -t ed25519 -C "laptop-to-controller"
```

**Copy your public key to the Raspberry Pi:**

```bash
# Test connection first
ping controller

# Copy SSH key (you'll be prompted for password once)
ssh-copy-id controller@controller

# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh controller@controller "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

**Test passwordless SSH:**

```bash
ssh controller@controller "echo 'SSH connection successful!'"
```

#### Option B: Use Password Authentication (Less Secure)

If you prefer to use passwords, the scripts will prompt you each time. This works but is less convenient.

### 4. Configure Controller Settings on Your Laptop

Edit `build/controller/config/controller-config.sh` on your laptop:

```bash
export CONTROLLER_HOSTNAME="controller"  # Your Meshnet hostname or IP
export CONTROLLER_USER="controller"  # Raspberry Pi username
```

**Finding your Meshnet hostname/IP:**

On your laptop, run:

```bash
nordvpn meshnet peer list
```

Look for your Raspberry Pi in the list. You can use either:

- The hostname (e.g., `controller`)
- The Meshnet IP address (e.g., `100.x.x.x`)

### 5. Set Up Raspberry Pi (Choose One Method)

#### Method 1: Automated Setup via SSH (Recommended)

**From your laptop**, use the remote setup script:

```bash
make controller-setup
```

This will:

- Copy the setup script to the Raspberry Pi
- Install Docker (if not present)
- Create necessary directories
- Set up user permissions

#### Method 2: Manual Setup on Raspberry Pi

**SSH into your Raspberry Pi** and run these commands:

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Add user to docker group
sudo usermod -aG docker controller

# Create directories
mkdir -p ~/edge-ai-controller/tegraflash

# Log out and back in for docker group to take effect
# Or run: newgrp docker
```

#### Method 3: Minimal Setup (Just Directories)

If Docker is already installed, just create the directories:

```bash
ssh controller@controller "mkdir -p ~/edge-ai-controller/tegraflash"
```

### 6. Deploy Controller Software from Laptop

**Note:** You don't need to clone the repository on the Raspberry Pi. All scripts run from your laptop and connect to the Pi via SSH.

From your laptop, run:

From your laptop, run:

```bash
make controller-update
```

This will:

- Build the Docker image on your laptop
- Transfer the Docker image to the Raspberry Pi
- Sync all controller scripts to the Raspberry Pi

**Note:** You don't need to clone the repository on the Raspberry Pi. All scripts run from your laptop and connect to the Pi via SSH.

## Usage

### Push Tegraflash Archive to Controller

After building an image on EC2, push the tegraflash archive directly to the controller:

```bash
make controller-push-tegraflash
```

This streams the archive from EC2 directly to the Raspberry Pi (via your laptop).

### Flash Device via USB

1. Put your Jetson device in forced recovery mode:
   - Power off the device
   - Short FC_REC to GND on the J14 header
   - Power on while keeping the jumper in place
   - Connect USB-C cable from Jetson to Raspberry Pi

2. Run the flash command from your laptop:

```bash
# Flash device
make controller-flash-usb
```

The script will:

- Check that the device is in recovery mode
- Extract the tegraflash archive on the controller
- Run the flash process in a Docker container on the Raspberry Pi
- Provide step-by-step instructions

### Update Controller Software

When you make changes to controller scripts or the Docker image, update the controller:

```bash
# Update everything (recommended)
make controller-update

# Or update individually:
make controller-deploy-docker    # Update Docker image only
make controller-deploy-scripts   # Update scripts only
```

## Directory Structure on Controller

```
/home/pi/edge-ai-controller/
├── config/
│   └── controller-config.sh    # Controller configuration
├── scripts/
│   ├── download-tegraflash.sh   # Download from EC2
│   ├── flash-usb.sh            # Flash via USB
│   └── lib/
│       └── controller-common.sh
├── tegraflash/                 # Tegraflash archives
│   └── *.tegraflash.tar.gz
└── tmp/                        # Temporary files
```

## Troubleshooting

### Cannot Connect to Controller

1. Verify NordVPN Meshnet is enabled on both devices:

   ```bash
   # On laptop
   nordvpn meshnet peer list

   # On Raspberry Pi (via SSH or direct access)
   nordvpn meshnet peer list
   ```

2. If Meshnet is not enabled:

   ```bash
   # Enable Meshnet
   nordvpn set meshnet on

   # Check status
   nordvpn meshnet peer list
   ```

3. Test connectivity:

   ```bash
   # Use the hostname or IP from meshnet peer list
   ping controller
   # Or ping the Meshnet IP directly
   ```

4. Check SSH access:

   ```bash
   ssh controller@controller
   ```

5. If SSH fails, verify:
   - SSH server is running on Pi: `sudo systemctl status ssh`
   - Firewall allows SSH: `sudo ufw status` (if using ufw)
   - Meshnet IP is correct: `nordvpn meshnet peer list` on Pi
   - Both devices are logged into the same NordVPN account

### Docker Image Not Found

If you get errors about the Docker image not being found:

```bash
make controller-deploy-docker
```

### Scripts Not Found on Controller

If scripts are missing or outdated:

```bash
make controller-deploy-scripts
```

### Device Not Detected

1. Verify the Jetson is in recovery mode:

   ```bash
   # On Raspberry Pi
   lsusb | grep -i nvidia
   ```

2. Check USB connection:
   - Ensure USB-C cable is properly connected
   - Try a different USB port on the Raspberry Pi
   - Verify the device appears in recovery mode

## Workflow Summary

1. **Build image on EC2**: `make build-image`
2. **Push tegraflash to controller**: `make controller-push-tegraflash`
3. **Put device in recovery mode** (physical steps)
4. **Flash device**: `make controller-flash-usb`
5. **Update controller when needed**: `make controller-update`

## Advanced Usage

### Manual Controller Commands

You can also run controller scripts directly:

```bash
# From your laptop
./build/controller/scripts/download-tegraflash.sh  # Pushes to controller
./build/controller/scripts/flash-usb.sh
```

### SSH into Controller

```bash
# Using the controller-common.sh functions
source build/controller/scripts/lib/controller-common.sh
controller_cmd "ls -la $CONTROLLER_BASE_DIR"
```
