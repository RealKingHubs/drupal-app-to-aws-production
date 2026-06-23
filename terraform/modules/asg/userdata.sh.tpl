#!/bin/bash
set -euo pipefail

# ============================================================
# Userdata Bootstrap Script
# Runs on first boot of every ASG instance.
# Installs SSM agent, node exporter, writes DB env vars
# for Ansible to use later in Phase 2.
# ============================================================

LOG_FILE="/var/log/drupal-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==== Bootstrap started at $(date) ===="

apt-get update -y
apt-get install -y \
  amazon-ssm-agent \
  awscli \
  curl \
  unzip \
  rsync

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# ============================================================
# Write DB connection details for Ansible to pick up later
# These come from Terraform template variables
# ============================================================
cat > /etc/drupal-env.sh <<EOF
export DRUPAL_DB_HOST="${db_host}"
export DRUPAL_DB_NAME="${db_name}"
export DRUPAL_DB_USER="${db_username}"
export DRUPAL_DB_PASS="${db_password}"
export DRUPAL_S3_BUCKET="${s3_bucket_name}"
export AWS_DEFAULT_REGION="${region}"
EOF

chmod 600 /etc/drupal-env.sh

# ============================================================
# Prometheus node exporter - for monitoring in Phase 5
# Using a plain bash variable, no curly braces, to avoid
# any conflict with Terraform's templatefile interpolation
# ============================================================
NODE_VERSION="1.7.0"
cd /tmp
curl -sL "https://github.com/prometheus/node_exporter/releases/download/v$NODE_VERSION/node_exporter-$NODE_VERSION.linux-amd64.tar.gz" -o node_exporter.tar.gz
tar xf node_exporter.tar.gz
mv "node_exporter-$NODE_VERSION.linux-amd64/node_exporter" /usr/local/bin/
chmod +x /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "==== Bootstrap completed at $(date) ===="