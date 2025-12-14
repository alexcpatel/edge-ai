# Edge AI Secure Image - Implementation Status

## ✅ Completed

### Yocto Layer (meta-edge-secure)

- [x] Layer structure and conf/layer.conf
- [x] Systemd generator for /data/services dynamic loading
- [x] First-boot bootstrap service (edge-bootstrap)
- [x] AWS IoT Fleet Provisioning (edge-provision.py)
- [x] NordVPN meshnet setup script (edge-nordvpn.sh)
- [x] Claim certificates recipe
- [x] Minimal edge-ai-image recipe
- [x] Read-only rootfs configuration
- [x] Volatile binds for /data partition
- [x] Realtek R8169 ethernet driver (kernel config)
- [x] Container policy enforcement (edge-docker wrapper)
- [x] Cosign for signature verification
- [x] NTP time sync (chrony)

### AWS Infrastructure (backend/iot/terraform)

- [x] Fleet provisioning template with pre-provisioning hook
- [x] Claim certificate + policy
- [x] Device IoT policy (with shadow permissions)
- [x] SSM parameters (claim certs, NordVPN token, container signing key, ECR URL)
- [x] ECR repository (edge-ai) with immutable tags
- [x] KMS key for container signing (ECC P-256)
- [x] CloudWatch logging for IoT lifecycle events
- [x] Pre-provisioning Lambda for device cleanup on re-provision

### Container Signing & Deployment

- [x] Container signing with KMS + cosign v2
- [x] Signature verification on device
- [x] edge-app.sh unified tool (build, push, sign, deploy, sandbox)
- [x] Sandbox mode for local development (unsigned containers)
- [x] ECR integration with signed pulls
- [x] Mount policy enforcement (signed → /data/apps/, sandbox → /data/sandbox/)

### Build Infrastructure

- [x] EC2 IAM permissions for SSM access
- [x] run-build.sh fetches claim certs + container signing key from SSM
- [x] Updated kas.yml for edge-ai-image target
- [x] Container builds with docker buildx (ARM64 cross-compile)

## 🔲 Remaining

### Device Verification

- [ ] Verify NordVPN meshnet connects
- [ ] Verify SSH via meshnet hostname works
- [ ] Test heartbeat service

### Future Enhancements

- [ ] Secure boot signing with NVIDIA PKC
- [ ] GPU container support (L4T/DeepStream base images)
- [ ] OTA container updates via AWS IoT Jobs
- [ ] Production hardening (remove debug-tweaks)
- [ ] MQTT broker setup for Home Assistant integration

## Architecture

```bash
┌─────────────────────────────────────────────────────────────┐
│                     ROOTFS (read-only)                       │
│  /etc/edge-ai/claim/           - Fleet provisioning certs   │
│  /etc/edge-ai/container-config - Container signing pubkey   │
│  /usr/bin/edge-*               - Bootstrap + policy scripts │
│  /lib/systemd/                 - Systemd generator          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    /data (read-write)                        │
│  /data/config/aws-iot/   - Device certs (post-provisioning) │
│  /data/config/pki/       - Container signing public key     │
│  /data/config/nordvpn/   - VPN config                       │
│  /data/apps/<app>/       - Signed container app data        │
│  /data/sandbox/<app>/    - Sandbox container app data       │
│  /data/services/         - Dynamic systemd services         │
│  /data/docker/           - Docker storage                   │
│  /data/log/              - System logs                      │
│  /data/.docker/          - Docker registry auth             │
└─────────────────────────────────────────────────────────────┘
```

## Container Workflow

```bash
# Development (unsigned, quick iteration)
make firmware-app-sandbox APP=animal-detector DEVICE=192.168.86.34
# Edit /data/sandbox/animal-detector/ on device for live changes

# Production (signed, verified)
make firmware-app-push APP=animal-detector VERSION=v1
make firmware-app-deploy APP=animal-detector DEVICE=192.168.86.34 VERSION=v1
```

## First Boot Flow

1. `edge-partition-setup.service` - Formats /data if needed
2. `data.mount` - Mounts /data partition
3. `edge-bootstrap.service` - Runs if not yet provisioned:
   - `edge-provision.py` - Generates device key, Fleet Provisioning via MQTT
   - `edge-nordvpn.sh` - Starts NordVPN, enables meshnet
   - Copies container signing public key to /data/config/pki/
4. Creates /data/.provisioned marker
5. Device ready for container deployments
