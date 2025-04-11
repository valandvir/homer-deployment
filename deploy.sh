#!/bin/bash

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run the script with root privileges (sudo)."
    exit 1
fi

# === 1. Install Docker ===
if ! command -v docker &> /dev/null; then
    echo "🔹 Installing Docker..."
    apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Check and start Docker
echo "🔹 Checking and starting Docker..."
systemctl enable --now docker
systemctl restart docker

# Check Docker group for the real user and apply changes
if [ -n "$SUDO_USER" ] && ! groups "$SUDO_USER" | grep -q '\bdocker\b'; then
    echo "🔹 Adding user $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
    echo "🔹 Group changes applied. Please log out and log back in to apply them to your session."
    echo "🔹 Alternatively, run 'newgrp docker' in your current session to continue without relogging."
    exit 0
fi

# Verify docker compose plugin
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose plugin is not installed. Ensure the installation completed successfully."
    exit 1
fi

# === 2. Create directory structure ===
echo "🔹 Creating directory structure..."
mkdir -p /opt/homer/nginx/certs /opt/homer/nginx/conf

# === 3. Generate self-signed certificates ===
echo "🔹 Generating self-signed certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/homer/nginx/certs/nginx.key \
    -out /opt/homer/nginx/certs/nginx.crt \
    -subj "/C=RU/ST=State/L=City/O=Organization/OU=Unit/CN=$(hostname -f)"

# === 4. Download homer7-docker ===
cd /opt/homer
if [ ! -d "homer7-docker" ]; then
    echo "🔹 Downloading homer7-docker..."
    git clone https://github.com/sipcapture/homer7-docker.git
fi
cd homer7-docker/heplify-server/hom7-prom-all

# Copy modified files from your repository
echo "🔹 Copying modified files..."
git clone https://github.com/valandvir/homer-deployment.git /tmp/repo
cp /tmp/repo/docker-compose.yml .
cp /tmp/repo/default.conf.template /opt/homer/nginx/conf/
rm -rf /tmp/repo

# === 5. Generate .env with manual interface input ===
echo "🔹 Setting up environment variables..."
read -p "Enter the CAPTURE interface name (default: ens192): " CAPTURE_INTERFACE
CAPTURE_INTERFACE=${CAPTURE_INTERFACE:-ens192}  # Default to ens192 if empty
if [ -z "$CAPTURE_INTERFACE" ]; then
    echo "❌ Interface cannot be empty. Using ens192."
    CAPTURE_INTERFACE="ens192"
fi

echo "CAPTURE_INTERFACE=$CAPTURE_INTERFACE" > .env
echo "SERVER_HOSTNAME=$(hostname -f)" >> .env
echo "HOMER_DST=127.0.0.1" >> .env

# === 6. Start services ===
echo "🔹 Starting services..."
docker compose up -d

# === 7. Clean up: Remove homer-deployment directory ===
echo "🔹 Cleaning up: Removing homer-deployment directory..."
cd /opt/homer/homer7-docker/heplify-server/hom7-prom-all
rm -rf /home/$(whoami)/homer-deployment

echo "✅ Deployment completed! Check status with: docker compose ps"

