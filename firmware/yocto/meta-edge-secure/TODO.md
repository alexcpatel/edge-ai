# Edge AI Secure Image - Implementation Status

## ✅ Completed

### Yocto Layer (meta-edge-secure)

- [x] Layer structure and conf/layer.conf
- [x] Systemd generator for /data/services dynamic loading
- [x] First-boot bootstrap service (edge-bootstrap)
- [x] AWS IoT Fleet Provisioning script (edge-provision.sh)
- [x] NordVPN meshnet setup script (edge-nordvpn.sh)
- [x] Claim certificates recipe
- [x] Minimal edge-ai-image recipe
- [x] Read-only rootfs configuration
- [x] Volatile binds for /data partition

### AWS Infrastructure (iot/terraform)

- [x] Fleet provisioning template
- [x] Claim certificate + policy
- [x] SSM parameters (claim certs, NordVPN token)
- [x] Device IoT policy

### Build Infrastructure

- [x] EC2 IAM permissions for SSM access
- [x] run-build.sh fetches claim certs from SSM
- [x] Updated kas.yml for edge-ai-image target

## 🔲 Not Yet Done

### Pre-Build Setup

- [x] Apply IoT terraform (`cd iot/terraform && terraform apply`)
- [x] Set NordVPN token in SSM Parameter Store

### Build & Flash

- [x] Test build on EC2
- [ ] Verify tegraflash output includes correct partitions
- [ ] Create /data partition during flash (may need flash script update)

### Post-Flash Verification

- [ ] Verify first-boot provisioning runs
- [ ] Verify device registers with AWS IoT
- [ ] Verify NordVPN meshnet connects
- [ ] Verify SSH via meshnet hostname works

### Deferred (Implement Later)

- [ ] Secure boot signing with NVIDIA PKC
- [ ] AWS KMS integration for signing keys
- [ ] Production hardening (remove debug-tweaks)
- [ ] OTA container updates via AWS IoT Jobs

## Architecture Notes

```bash
┌─────────────────────────────────────────────────────────────┐
│                     ROOTFS (read-only)                       │
│  /etc/edge-ai/claim/  - Fleet provisioning claim certs      │
│  /usr/bin/edge-*      - Bootstrap scripts                   │
│  /lib/systemd/        - Systemd generator                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    /data (read-write)                        │
│  /data/config/aws-iot/  - Device certs (after provisioning) │
│  /data/config/nordvpn/  - VPN config                        │
│  /data/apps/            - Container app data                │
│  /data/services/        - Dynamic systemd services          │
│  /data/docker/          - Docker storage                    │
│  /data/log/             - System logs                       │
└─────────────────────────────────────────────────────────────┘
```

## First Boot Flow

1. `edge-bootstrap.service` starts (triggered by /data/.need_provisioning)
2. `edge-provision.sh` - Generates device key, calls Fleet Provisioning API
3. `edge-nordvpn.sh` - Starts NordVPN container, enables meshnet
4. Removes provision marker, device is ready
5. Meshnet hostname reported to IoT shadow for SSH access
