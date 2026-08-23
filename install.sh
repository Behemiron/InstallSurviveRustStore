#!/bin/bash
# ==============================================================================
#                 SURVIVE RUST STORE - Ubuntu Auto-Installer Script
# ==============================================================================
# OS Support: Ubuntu 20.04 / 22.04 / 24.04 (LTS)
# Runs as: root (will configure and run applications under surviverust system user)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                SURVIVE RUST STORE AUTO-INSTALLER SCRIPT                      ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# 1. Root & OS check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Этот скрипт должен быть запущен от имени суперпользователя (root).${NC}"
  echo -e "Используйте: sudo $0"
  exit 1
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" != "ubuntu" ]; then
    echo -e "${YELLOW}Предупреждение: Этот скрипт официально поддерживает только Ubuntu.${NC}"
    read -p "Вы действительно хотите продолжить? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
else
  echo -e "${RED}Ошибка: Не удалось определить операционную систему.${NC}"
  exit 1
fi

# 2. Interactive user inputs
echo -e "\n${YELLOW}>>> Настройка конфигурации проекта SURVIVE RUST...${NC}"
read -p "Введите имя домена (например, surviverust.ru) или оставьте пустым для IP: " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r')

if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}Домен не указан. Автоматическое определение внешнего IP-адреса сервера...${NC}"
  DOMAIN=$(curl -s --max-time 5 https://api.ipify.org || echo "")
  DOMAIN=$(echo "$DOMAIN" | tr -d '\r')
  if [ -z "$DOMAIN" ]; then
    DOMAIN="localhost"
  fi
  echo -e "${GREEN}Используется IP-адрес: $DOMAIN${NC}"
fi

read -p "Введите ваш Steam Web API Key (получить на https://steamcommunity.com/dev/apikey): " STEAM_KEY
STEAM_KEY=$(echo "$STEAM_KEY" | tr -d '\r')

read -p "Репозиторий GitHub (по умолчанию Behemiron/survive-rust-store): " GIT_REPO
GIT_REPO=$(echo "$GIT_REPO" | tr -d '\r')
GIT_REPO=${GIT_REPO:-Behemiron/survive-rust-store}

USE_SSH="true"
GIT_TOKEN=""

# 3. Create non-privileged system user "surviverust"
if ! id "surviverust" &>/dev/null; then
  echo -e "${YELLOW}>>> Создание системного пользователя surviverust...${NC}"
  useradd -r -m -U -d /home/surviverust -s /bin/bash surviverust
fi

if [ -n "$GIT_REPO" ]; then
  read -p "Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n): " auth_choice
  if [[ "$auth_choice" =~ ^[Nn]$ ]]; then
    USE_SSH="false"
    read -p "Введите ваш GitHub Personal Access Token (PAT): " GIT_TOKEN
  else
    USE_SSH="true"
    # Ensure surviverust SSH directory exists
    mkdir -p /home/surviverust/.ssh
    chmod 700 /home/surviverust/.ssh
    
    # Generate SSH Key if it does not exist
    SSH_KEY_FILE="/home/surviverust/.ssh/id_ed25519_surviverust"
    if [ ! -f "$SSH_KEY_FILE" ]; then
      echo -e "${YELLOW}>>> Генерация SSH Deploy Key...${NC}"
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
      chmod 600 "$SSH_KEY_FILE"
      chmod 644 "${SSH_KEY_FILE}.pub"
    fi
    chown -R surviverust:surviverust /home/surviverust/.ssh
    
    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}  ВАШ SSH DEPLOY KEY (СКОПИРУЙТЕ СТРОКУ НИЖЕ И ДОБАВЬТЕ В НАСТРОЙКИ GITHUB):     ${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    cat "${SSH_KEY_FILE}.pub"
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "  Инструкция:"
    echo -e "  1. Откройте ваш GitHub-репозиторий -> Settings -> Deploy keys -> Add deploy key"
    echo -e "  2. Вставьте скопированный ключ в поле Key"
    echo -e "  3. Назовите ключ (например, VPS Deploy Key)"
    echo -e "  4. Нажмите Add key"
    echo -e "${GREEN}==============================================================================${NC}"
    
    read -p "После того как добавите ключ на GitHub, нажмите ENTER для продолжения установки..." dummy
  fi
fi

# Generate random secure passwords for DB and JWT
DB_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)

echo -e "\n${YELLOW}>>> Установка необходимых системных пакетов...${NC}"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git build-essential openssl nginx certbot python3-certbot-nginx sudo redis-server

# Configure sudoers for passwordless Nginx/Certbot reload by surviverust user
echo -e "${YELLOW}>>> Настройка прав sudo для пользователя surviverust...${NC}"
echo "surviverust ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /usr/bin/systemctl reload nginx, /usr/bin/certbot" > /etc/sudoers.d/surviverust
chmod 440 /etc/sudoers.d/surviverust

# 4. Install Node.js 20 LTS
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}>>> Установка Node.js 20...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo -e "${GREEN}Node.js версия: $(node -v)${NC}"
echo -e "${GREEN}npm версия: $(npm -v)${NC}"

# 5. Install PM2
if ! command -v pm2 &> /dev/null; then
  echo -e "${YELLOW}>>> Установка PM2...${NC}"
  npm install -y -g pm2
fi

# Enable and start Redis
echo -e "${YELLOW}>>> Настройка Redis Server...${NC}"
systemctl start redis-server
systemctl enable redis-server

# 6. Install MySQL Server
if ! command -v mysql &> /dev/null; then
  echo -e "${YELLOW}>>> Установка MySQL Server...${NC}"
  apt-get install -y mysql-server
  systemctl start mysql
  systemctl enable mysql
fi

# Configure MySQL Database & User
echo -e "${YELLOW}>>> Настройка базы данных MySQL...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS survive_rust CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'surviverust'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON survive_rust.* TO 'surviverust'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 7. Setup Directory Structure
APP_DIR="/var/www/survive-rust"
echo -e "${YELLOW}>>> Подготовка директорий в $APP_DIR...${NC}"

# Fresh installation - clone from GitHub repo
echo -e "Клонирование репозитория с GitHub..."
rm -rf $APP_DIR
mkdir -p $APP_DIR
chown surviverust:surviverust $APP_DIR

if [ "$USE_SSH" = "true" ]; then
  sudo -u surviverust GIT_SSH_COMMAND="ssh -i /home/surviverust/.ssh/id_ed25519_surviverust -o StrictHostKeyChecking=no" git clone git@github.com:${GIT_REPO}.git $APP_DIR
  cd $APP_DIR
  sudo -u surviverust git config core.sshCommand "ssh -i /home/surviverust/.ssh/id_ed25519_surviverust -o StrictHostKeyChecking=no"
else
  sudo -u surviverust git clone https://${GIT_TOKEN}@github.com/${GIT_REPO}.git $APP_DIR
fi

# 8. Generate Configuration files
echo -e "${YELLOW}>>> Генерация конфигурационных файлов .env...${NC}"

# Backend config
cat > $APP_DIR/backend/.env << ENVEOF
NODE_ENV=production
PORT=5000
FRONTEND_URL=http://${DOMAIN:-localhost}
DATABASE_URL=mysql://surviverust:${DB_PASS}@localhost:3306/survive_rust
REDIS_URL=redis://localhost:6379
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=7d
STEAM_API_KEY=${STEAM_KEY}
UPDATE_LOG_PATH=/var/www/survive-rust/update.log
APP_DIR=/var/www/survive-rust
ENVEOF

# Frontend config
cat > $APP_DIR/frontend/.env.local << ENVEOF
NEXT_PUBLIC_BACKEND_URL=http://${DOMAIN:-localhost}/api
NEXT_PUBLIC_API_URL=http://${DOMAIN:-localhost}/api
ENVEOF

# Write DB credentials
cat > $APP_DIR/.db_creds << CREDSEOF
DB_USER=surviverust
DB_PASS=${DB_PASS}
DB_NAME=survive_rust
CREDSEOF

# Set ownership of all files to surviverust user
chown -R surviverust:surviverust $APP_DIR

# 9. Build Backend
echo -e "${YELLOW}>>> Сборка бэкенда...${NC}"
cd $APP_DIR/backend
sudo -u surviverust npm install --production=false
sudo -u surviverust npx prisma generate
sudo -u surviverust npx prisma db push --accept-data-loss

# 10. Build Frontend
echo -e "${YELLOW}>>> Сборка фронтенда...${NC}"
cd $APP_DIR/frontend
sudo -u surviverust npm install --production=false
sudo -u surviverust NEXT_PUBLIC_BACKEND_URL="http://${DOMAIN:-localhost}/api" npm run build

# 11. Configure Nginx Virtual Host
echo -e "${YELLOW}>>> Настройка веб-сервера Nginx...${NC}"
cat > /etc/nginx/sites-available/survive-rust << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN:-_};

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

    location /_next/static/ {
        proxy_pass http://localhost:3000/_next/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINXEOF

# Enable Nginx configs
ln -sf /etc/nginx/sites-available/survive-rust /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

# 12. Run Services with PM2 under surviverust user
echo -e "${YELLOW}>>> Запуск приложений под PM2...${NC}"
sudo -u surviverust pm2 delete backend 2>/dev/null || true
sudo -u surviverust pm2 delete frontend 2>/dev/null || true

cd $APP_DIR/backend
sudo -u surviverust pm2 start npm --name backend -- run dev

cd $APP_DIR/frontend
sudo -u surviverust pm2 start npm --name frontend -- start -- -p 3000

sudo -u surviverust pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u surviverust --hp /home/surviverust || true

# 13. Let's Encrypt SSL automation
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
  echo -e "${YELLOW}>>> Запрос SSL сертификата Let's Encrypt для $DOMAIN...${NC}"
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || echo -e "${RED}Предупреждение: Не удалось выпустить SSL. Возможно, домен не направлен на этот IP.${NC}"
fi

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}             УСТАНОВКА SURVIVE RUST STORE УСПЕШНО ЗАВЕРШЕНА!                 ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "  Сайт доступен по адресу: http://${DOMAIN:-Ваш_IP_Сервера}"
echo -e "  Бэкенд API:              http://${DOMAIN:-Ваш_IP_Сервера}/api"
echo -e "  Пароль к базе данных:    ${DB_PASS} (Сохранен в $APP_DIR/.db_creds)"
echo -e "${GREEN}==============================================================================${NC}"

# Self cleanup
rm -- "$0" 2>/dev/null || true
