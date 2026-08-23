#!/bin/bash
# ==============================================================================
#                 SURVIVE RUST STORE - Ubuntu Auto-Installer Script
# ==============================================================================
# Supported Operating Systems: Ubuntu 20.04 / 22.04 / 24.04 (LTS)
# Lead Architect & Developer: PavelNetesov / Behemiron (Discord: behemiron_777777)
# Execution: Run as root (the installer sets up an isolated non-root system user)
# ==============================================================================

set -e

# ANSI Color Codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                 SURVIVE RUST STORE AUTO-INSTALLER SCRIPT                     ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# 1. Verify Superuser Privileges & Operating System Compatibility
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This installation script must be executed as root.${NC}"
  echo -e "Please run using: sudo bash $0"
  exit 1
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" != "ubuntu" ]; then
    echo -e "${YELLOW}Warning: This script is officially tested and optimized for Ubuntu LTS only.${NC}"
    read -p "Do you want to continue anyway? (y/N): " confirm < /dev/tty || true
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
else
  echo -e "${RED}Error: Could not detect the operating system distribution.${NC}"
  exit 1
fi

# 2. Interactive Project & User Configuration
echo -e "\n${YELLOW}>>> Configuring Project Parameters & System Environment...${NC}"

read -p "Enter a unique project / server identifier (e.g., survive, rust_pvp) [default: rust]: " INPUT_PROJECT_NAME < /dev/tty || true
INPUT_PROJECT_NAME=$(echo "$INPUT_PROJECT_NAME" | tr -cd 'a-zA-Z0-9_' | tr '[:upper:]' '[:lower:]')
INPUT_PROJECT_NAME=${INPUT_PROJECT_NAME:-rust}

# Dynamically derive isolated names to ensure clean directory and process separation
SYS_USER="${INPUT_PROJECT_NAME}_surviverust"
SYS_HOME="/home/${SYS_USER}"
APP_DIR="/var/www/${SYS_USER}"
DB_NAME="${INPUT_PROJECT_NAME}_db"
DB_USER="${SYS_USER}"
PM2_BACKEND="${INPUT_PROJECT_NAME}-backend"
PM2_FRONTEND="${INPUT_PROJECT_NAME}-frontend"
NGINX_CONF="${SYS_USER}"

echo -e "${GREEN}✓ Isolated System User:     ${SYS_USER}${NC}"
echo -e "${GREEN}✓ Project Installation Path: ${APP_DIR}${NC}"
echo -e "${GREEN}✓ Dedicated MySQL Database:  ${DB_NAME}${NC}"

read -p "Enter your domain name (e.g., surviverust.com) or leave blank for VPS IP: " DOMAIN < /dev/tty || true
DOMAIN=$(echo "$DOMAIN" | tr -d '\r')

if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}No domain specified. Automatically detecting your server's public IP address...${NC}"
  DOMAIN=$(curl -s --max-time 5 https://api.ipify.org || echo "")
  DOMAIN=$(echo "$DOMAIN" | tr -d '\r')
  if [ -z "$DOMAIN" ]; then
    DOMAIN="localhost"
  fi
  echo -e "${GREEN}✓ Operating with server IP: ${DOMAIN}${NC}"
fi

read -p "Enter your Steam Web API Key (obtain from https://steamcommunity.com/dev/apikey): " STEAM_KEY < /dev/tty || true
STEAM_KEY=$(echo "$STEAM_KEY" | tr -d '\r')

read -p "Enter Admin SteamID64 (e.g., 76561198000000000) for Super Admin privileges: " ADMIN_STEAM_ID < /dev/tty || true
ADMIN_STEAM_ID=$(echo "$ADMIN_STEAM_ID" | tr -d '\r')

read -p "Enter Rust Server In-Game Plugin Secret Key [default: auto-generated]: " RUST_SECRET < /dev/tty || true
RUST_SECRET=$(echo "$RUST_SECRET" | tr -d '\r')
if [ -z "$RUST_SECRET" ]; then
  RUST_SECRET=$(openssl rand -hex 16)
fi

read -p "Target GitHub Repository (default: Behemiron/survive-rust-store): " GIT_REPO < /dev/tty || true
GIT_REPO=$(echo "$GIT_REPO" | tr -d '\r')
GIT_REPO=${GIT_REPO:-Behemiron/survive-rust-store}

USE_SSH="true"
GIT_TOKEN=""

# 3. Create Dedicated Non-Privileged System User
if ! id "$SYS_USER" &>/dev/null; then
  echo -e "\n${YELLOW}>>> Creating non-root system user '${SYS_USER}'...${NC}"
  useradd -r -m -U -d "$SYS_HOME" -s /bin/bash "$SYS_USER"
  echo -e "${GREEN}✓ System user created successfully.${NC}"
fi

# Configure SSH Deployment Keys for Git Synchronization
if [ -n "$GIT_REPO" ]; then
  read -p "Use SSH Deploy Key for GitHub repository authentication? (Recommended) (Y/n): " auth_choice < /dev/tty || true
  if [[ "$auth_choice" =~ ^[Nn]$ ]]; then
    USE_SSH="false"
    read -p "Enter your GitHub Personal Access Token (PAT): " GIT_TOKEN < /dev/tty || true
  else
    USE_SSH="true"
    # Ensure project user's .ssh directory exists with restricted permissions
    mkdir -p "${SYS_HOME}/.ssh"
    chmod 700 "${SYS_HOME}/.ssh"
    
    # Generate Ed25519 SSH keypair if one does not already exist
    SSH_KEY_FILE="${SYS_HOME}/.ssh/id_ed25519_${INPUT_PROJECT_NAME}"
    if [ ! -f "$SSH_KEY_FILE" ]; then
      echo -e "${YELLOW}>>> Generating unique Ed25519 SSH Deploy Key (${SSH_KEY_FILE})...${NC}"
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
      chmod 600 "$SSH_KEY_FILE"
      chmod 644 "${SSH_KEY_FILE}.pub"
    fi
    chown -R "${SYS_USER}:${SYS_USER}" "${SYS_HOME}/.ssh"
    
    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}  YOUR SSH DEPLOY KEY (COPY THE ENTIRE LINE BELOW):                           ${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    cat "${SSH_KEY_FILE}.pub"
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "  DEPLOY KEY ACTIVATION INSTRUCTIONS:"
    echo -e "  1. Copy the full public key string starting with 'ssh-ed25519 ...'"
    echo -e "  2. Go to your GitHub repository -> Settings -> Deploy keys -> Add deploy key"
    echo -e "  3. Paste the key, give it a title (e.g. VPS Deploy Key), and click Add key."
    echo -e "     (If you are using the official private repo, send it to Behemiron on Discord: behemiron_777777)"
    echo -e "  4. Once added/confirmed, press ENTER to resume installation."
    echo -e "${GREEN}==============================================================================${NC}"
    
    read -p "Press ENTER to continue installation..." dummy < /dev/tty || true
  fi
fi

# Generate cryptographically secure passwords for Database and JWT Authentication
DB_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)

echo -e "\n${YELLOW}>>> Installing system packages and dependencies...${NC}"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git build-essential openssl nginx certbot python3-certbot-nginx sudo redis-server ufw

# Configure sudoers to allow the isolated user to safely reload Nginx without root login
echo -e "${YELLOW}>>> Granting scoped sudo permissions for ${SYS_USER}...${NC}"
echo "${SYS_USER} ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /usr/bin/systemctl reload nginx, /usr/bin/certbot" > "/etc/sudoers.d/${SYS_USER}"
chmod 440 "/etc/sudoers.d/${SYS_USER}"

# 4. Install Node.js 20 LTS Runtime
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}>>> Installing Node.js 20 LTS...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo -e "${GREEN}✓ Node.js version: $(node -v)${NC}"
echo -e "${GREEN}✓ npm version:     $(npm -v)${NC}"

# 5. Install PM2 Process Manager globally
if ! command -v pm2 &> /dev/null; then
  echo -e "${YELLOW}>>> Installing PM2 Process Manager...${NC}"
  npm install -y -g pm2
fi

# Enable and start Redis caching service
echo -e "${YELLOW}>>> Starting Redis Server...${NC}"
systemctl start redis-server
systemctl enable redis-server

# 6. Install and Configure MySQL Server
if ! command -v mysql &> /dev/null; then
  echo -e "${YELLOW}>>> Installing MySQL Server...${NC}"
  apt-get install -y mysql-server
  systemctl start mysql
  systemctl enable mysql
fi

# Provision isolated MySQL database and dedicated user
echo -e "${YELLOW}>>> Provisioning MySQL Database (${DB_NAME})...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 7. Clone Repository into Application Directory
echo -e "${YELLOW}>>> Setting up application directory in ${APP_DIR}...${NC}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
chown "${SYS_USER}:${SYS_USER}" "$APP_DIR"

git config --system --add safe.directory "$APP_DIR" || true
git config --global --add safe.directory "$APP_DIR" || true

if [ "$USE_SSH" = "true" ]; then
  sudo -u "$SYS_USER" git config --global --add safe.directory "$APP_DIR" || true
  sudo -u "$SYS_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no" git clone "git@github.com:${GIT_REPO}.git" "$APP_DIR"
  cd "$APP_DIR"
  sudo -u "$SYS_USER" git config core.sshCommand "ssh -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no"
else
  sudo -u "$SYS_USER" git clone "https://${GIT_TOKEN}@github.com/${GIT_REPO}.git" "$APP_DIR"
fi

# 8. Generate Production Environment Configuration Files (.env)
echo -e "${YELLOW}>>> Generating production environment configurations...${NC}"

# Backend environment configuration
cat > "$APP_DIR/backend/.env" << ENVEOF
# Server Configuration
PORT=5000
NODE_ENV=production
APP_DIR=${APP_DIR}
SYSTEM_USER=${SYS_USER}
UPDATE_LOG_PATH=${APP_DIR}/update.log
PM2_BACKEND_NAME=${PM2_BACKEND}
PM2_FRONTEND_NAME=${PM2_FRONTEND}

# Database Connection
DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}"
REDIS_URL="redis://localhost:6379"

# Security & Secrets
JWT_SECRET="${JWT_SECRET}"
JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET}"
JWT_ACCESS_EXPIRY="30d"
JWT_REFRESH_EXPIRY="90d"
SERVER_SECRET_KEY="${RUST_SECRET}"
ADMIN_STEAM_IDS="${ADMIN_STEAM_ID}"

# Steam Authentication
STEAM_API_KEY="${STEAM_KEY}"

# Web App URLs
FRONTEND_URL="http://${DOMAIN:-localhost}"
BACKEND_URL="http://${DOMAIN:-localhost}"
ENVEOF

# Frontend environment configuration
cat > "$APP_DIR/frontend/.env.local" << ENVEOF
NEXT_PUBLIC_API_URL=http://${DOMAIN:-localhost}
NEXT_PUBLIC_WS_URL=ws://${DOMAIN:-localhost}
ENVEOF

# Store database credentials backup for automated updater access
cat > "$APP_DIR/.db_creds" << CREDSEOF
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_NAME=${DB_NAME}
CREDSEOF

# Ensure all files belong strictly to the project system user
chown -R "${SYS_USER}:${SYS_USER}" "$APP_DIR"

# 9. Build and Synchronize Backend Database
echo -e "${YELLOW}>>> Installing dependencies and compiling Backend...${NC}"
cd "$APP_DIR/backend"
sudo -u "$SYS_USER" npm install --production=false
sudo -u "$SYS_USER" npx prisma generate
sudo -u "$SYS_USER" npx prisma db push --accept-data-loss

# 10. Build Frontend Web Application
echo -e "${YELLOW}>>> Installing dependencies and compiling Frontend Next.js app...${NC}"
cd "$APP_DIR/frontend"
sudo -u "$SYS_USER" npm install --production=false
sudo -u "$SYS_USER" NEXT_PUBLIC_API_URL="http://${DOMAIN:-localhost}" NEXT_PUBLIC_WS_URL="ws://${DOMAIN:-localhost}" npm run build

# 11. Configure Nginx Reverse Proxy with WebSocket Support
echo -e "${YELLOW}>>> Configuring Nginx Virtual Host...${NC}"
cat > "/etc/nginx/sites-available/${NGINX_CONF}" << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN:-_};

    # Frontend Next.js reverse proxy
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }

    # Backend Express API reverse proxy
    location /api/ {
        proxy_pass http://localhost:5000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    # WebSocket stream endpoint for live player counts and live updates
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Optimized caching for static Next.js build assets
    location /_next/static/ {
        proxy_pass http://localhost:3000/_next/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINXEOF

# Enable Nginx configuration and set permissions
touch "/etc/nginx/sites-available/${NGINX_CONF}"
chown "${SYS_USER}:${SYS_USER}" "/etc/nginx/sites-available/${NGINX_CONF}"
mkdir -p /etc/nginx/ssl
chown -R "${SYS_USER}:${SYS_USER}" /etc/nginx/ssl

ln -sf "/etc/nginx/sites-available/${NGINX_CONF}" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

# 12. Start Application Services under PM2 using the Isolated System User
echo -e "${YELLOW}>>> Starting PM2 processes under user '${SYS_USER}'...${NC}"
sudo -u "$SYS_USER" pm2 delete "$PM2_BACKEND" 2>/dev/null || true
sudo -u "$SYS_USER" pm2 delete "$PM2_FRONTEND" 2>/dev/null || true

cd "$APP_DIR/backend"
sudo -u "$SYS_USER" pm2 start npm --name "$PM2_BACKEND" -- run dev

cd "$APP_DIR/frontend"
sudo -u "$SYS_USER" pm2 start npm --name "$PM2_FRONTEND" -- start -- -p 3000

sudo -u "$SYS_USER" pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u "$SYS_USER" --hp "$SYS_HOME" || true

# 13. Automated Let's Encrypt SSL Certificate Issuance
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
  echo -e "${YELLOW}>>> Requesting Let's Encrypt SSL certificate for ${DOMAIN}...${NC}"
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@${DOMAIN}" --redirect || echo -e "${RED}Warning: Could not automatically issue SSL certificate. Ensure your domain's DNS A Record points to this server IP.${NC}"
fi

# 14. Configure Hardened UFW Firewall Rules
echo -e "${YELLOW}>>> Configuring UFW Firewall security rules...${NC}"
if command -v ufw &> /dev/null || apt-get install -y ufw; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp      # SSH Administrative Access
  ufw allow 80/tcp      # HTTP Web Access
  ufw allow 443/tcp     # HTTPS Web Access (SSL)
  ufw deny 3306/tcp     # Block external MySQL access
  ufw deny 6379/tcp     # Block external Redis access
  ufw deny 3000/tcp     # Block direct Next.js port access (bypass Nginx)
  ufw deny 5000/tcp     # Block direct Express API port access (bypass Nginx)
  ufw --force enable
  echo -e "${GREEN}✓ UFW Firewall enabled. Database (3306), Redis (6379) and internal API ports are secured.${NC}"
fi

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}             SURVIVE RUST STORE INSTALLATION COMPLETED!                       ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "  Project / System User:   ${SYS_USER}"
echo -e "  Installation Directory:  ${APP_DIR}"
echo -e "  Website URL:             http://${DOMAIN:-Your_Server_IP}"
echo -e "  Backend API URL:         http://${DOMAIN:-Your_Server_IP}/api"
echo -e "  Database Password:       ${DB_PASS} (Saved in ${APP_DIR}/.db_creds)"
echo -e "  In-Game Plugin Secret:   ${RUST_SECRET}"
echo -e "${GREEN}==============================================================================${NC}"

# Clean up installer script file
rm -- "$0" 2>/dev/null || true
