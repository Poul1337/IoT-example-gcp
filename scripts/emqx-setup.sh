#!/bin/bash
set -e

# Variables from Terraform templatefile
EMQX_VERSION="${emqx_version}"
MQTTS_PROD_PORT="${mqtts_prod_port}"
MQTTS_DEV_PORT="${mqtts_dev_port}"
DASHBOARD_PORT="${dashboard_port}"
CERT_BUCKET="${certificate_bucket}"

# Update system
apt-get update
apt-get install -y wget curl gnupg

# Install EMQX using package repository (more reliable than direct download)
echo "Installing EMQX from package repository..."
curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | bash -s -- --version ${emqx_version} || {
    echo "Package repository installation failed, trying direct download..."
    # Fallback: try direct download
    DOWNLOAD_URL="https://www.emqx.com/en/downloads/broker/${emqx_version}/emqx-${emqx_version}-ubuntu22.04-amd64.deb"
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if wget --timeout=30 --tries=3 "$DOWNLOAD_URL" 2>&1; then
            echo "Download successful"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "Download failed, retrying ($RETRY_COUNT/$MAX_RETRIES)..."
            sleep 5
        fi
    done
    
    if [ -f "emqx-${emqx_version}-ubuntu22.04-amd64.deb" ]; then
        dpkg -i emqx-${emqx_version}-ubuntu22.04-amd64.deb || apt-get install -f -y
    else
        echo "ERROR: All installation methods failed. Please check network connectivity."
        echo "Continuing anyway to allow manual installation..."
    fi
}

# Install Google Cloud SDK for gsutil
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update && apt-get install -y google-cloud-sdk

# Download certificates from GCS bucket
mkdir -p /etc/emqx/certs
if gsutil cp gs://${certificate_bucket}/emqx-server.key gs://${certificate_bucket}/emqx-server.crt gs://${certificate_bucket}/ca.pem /etc/emqx/certs/ 2>/dev/null; then
    echo "Certificates downloaded successfully"
else
    echo "WARNING: Certificates not found in bucket. Will need to upload manually and restart EMQX."
fi

# Copy ca.pem to ca.crt if needed
if [ -f /etc/emqx/certs/ca.pem ] && [ ! -f /etc/emqx/certs/ca.crt ]; then
    cp /etc/emqx/certs/ca.pem /etc/emqx/certs/ca.crt
fi

# Set proper permissions
chown -R emqx:emqx /etc/emqx/certs 2>/dev/null || true
chmod 600 /etc/emqx/certs/*.key 2>/dev/null || true
chmod 644 /etc/emqx/certs/*.crt 2>/dev/null || true
chmod 644 /etc/emqx/certs/*.pem 2>/dev/null || true

# Create EMQX config directory if it doesn't exist
mkdir -p /etc/emqx/conf.d

# Configure EMQX (HOCON format for EMQX 5.x)
cat > /etc/emqx/conf.d/listeners.conf <<EOF
# Production MQTTS listener (port ${mqtts_prod_port})
listeners.ssl.prod {
  bind = ${mqtts_prod_port}
  ssl_options {
    keyfile = "/etc/emqx/certs/emqx-server.key"
    certfile = "/etc/emqx/certs/emqx-server.crt"
    cacertfile = "/etc/emqx/certs/ca.crt"
    verify = verify_peer
    fail_if_no_peer_cert = true
    versions = ["tlsv1.2", "tlsv1.3"]
  }
  max_connections = 1024000
}

# Development MQTTS listener (port ${mqtts_dev_port})
listeners.ssl.dev {
  bind = ${mqtts_dev_port}
  ssl_options {
    keyfile = "/etc/emqx/certs/emqx-server.key"
    certfile = "/etc/emqx/certs/emqx-server.crt"
    cacertfile = "/etc/emqx/certs/ca.crt"
    verify = verify_peer
    fail_if_no_peer_cert = true
    versions = ["tlsv1.2", "tlsv1.3"]
  }
  max_connections = 1024000
}
EOF

# Configure Dashboard (ensure directory exists)
mkdir -p /etc/emqx/conf.d
cat > /etc/emqx/conf.d/dashboard.conf <<EOF
dashboard.listeners.http.bind = 0.0.0.0:${dashboard_port}
dashboard.default_user.login = admin
dashboard.default_user.password = public
EOF

# Note: Clustering can be configured later via dashboard or API
# For manual clustering, edit /etc/emqx/conf.d/cluster.conf

# Enable and start EMQX (ignore errors if not installed yet)
systemctl enable emqx 2>/dev/null || true
systemctl start emqx 2>/dev/null || {
    echo "WARNING: EMQX service not found. May need manual installation."
    echo "Trying to start manually..."
    /usr/bin/emqx start 2>/dev/null || echo "EMQX may not be installed correctly"
}

# Wait for EMQX to start
sleep 15

# Check EMQX status
systemctl status emqx 2>/dev/null || {
    echo "EMQX service status unknown"
    echo "Checking if EMQX process is running..."
    ps aux | grep -i emqx | grep -v grep || echo "EMQX process not found"
}

echo "EMQX setup completed. Remember to upload certificates to gs://${certificate_bucket}/"

