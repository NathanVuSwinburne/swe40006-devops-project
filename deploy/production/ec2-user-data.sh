#!/bin/bash
# EC2 User Data for the production server (Ubuntu 24.04).
# Paste this whole file into "Advanced details -> User data" when launching the instance.
# It runs once as root on first boot. Output goes to /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Base packages (stress-ng is only used to spike CPU when testing the CloudWatch alarm)
apt-get update -y
apt-get install -y git curl ca-certificates logrotate stress-ng

# Docker Engine + Compose plugin
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable --now docker

# 1 GB swap so the t3.micro (1 GB RAM) doesn't run out of memory during image builds
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# CloudWatch agent (config is applied later, after the repo is cloned)
ARCH=$(dpkg --print-architecture)
curl -fsSL -o /tmp/cwagent.deb "https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/${ARCH}/latest/amazon-cloudwatch-agent.deb"
dpkg -i -E /tmp/cwagent.deb

# Folders for the app and its logs
mkdir -p /opt/swe40006 /var/log/swe40006/nginx
touch /var/log/swe40006/deploy.log
chown -R ubuntu:ubuntu /opt/swe40006 /var/log/swe40006

# Rotate logs daily so the disk doesn't fill up
cat > /etc/logrotate.d/swe40006 <<'EOF'
/var/log/swe40006/nginx/*.log /var/log/swe40006/deploy.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "SWE40006 BOOTSTRAP COMPLETE"
