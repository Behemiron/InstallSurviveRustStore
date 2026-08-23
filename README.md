# Survive Rust Store — Automated Server Deployment

Production-ready automated installation script for deploying the **SURVIVE RUST Store** web platform on **Ubuntu 20.04 / 22.04 / 24.04 LTS**.

Designed & Maintained by **PavelNetesov / Behemiron** (Discord: `behemiron_777777`).

---

## Architecture & Security Breakdown

This installer configures a hardened, non-root Linux environment following production security standards:

1. **System User Isolation**: Automatically creates a non-privileged system user `${project_name}_surviverust` (`/home/${project_name}_surviverust`) and runs all Node.js / PM2 / Next.js / Express application processes strictly under this unprivileged user.
2. **Automated UFW Firewall Security**:
   - **Allowed Public Ports**: `80` (HTTP), `443` (HTTPS), `22` (SSH).
   - **Blocked External Ports**: `3306` (MySQL), `6379` (Redis), `3000` (Next.js Direct), `5000` (Express API Direct).
   - Database and application services bind locally to `127.0.0.1` and are reverse-proxied exclusively through Nginx.
3. **Database Isolation**: Installs MySQL Server and creates a dedicated database `${project_name}_db` with auto-generated 32-character high-entropy credentials.
4. **Nginx Reverse Proxy & SSL**: Configures virtual host routing for API `/api`, WebSocket `/ws`, and frontend `/`, with automated Let's Encrypt TLS certificate issuance via Certbot.
5. **Zero-Downtime Process Management**: Integrates PM2 with systemd auto-restart policies upon VPS reboot.
6. **In-Game Rust Plugin Security**: Uses a secure shared secret and HMAC request validation for game server store delivery.

---

## Prerequisites

Before executing the installer:

1. A fresh **Ubuntu LTS (20.04 / 22.04 / 24.04)** server instance with SSH `root` access.
2. A valid domain name with its **DNS A Record** pointing to your VPS public IP (e.g., `store.yourrustserver.com`).
3. Your **Steam Web API Key** (obtainable from [Steam Developer Portal](https://steamcommunity.com/dev/apikey)).
4. Your **SteamID64** for initial Super Admin privileges.

---

## Quick One-Line Launch

Connect to your VPS via SSH as `root` and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Behemiron/InstallSurviveRustStore/main/install.sh)"
```

Alternatively:
```bash
curl -sSL https://raw.githubusercontent.com/Behemiron/InstallSurviveRustStore/main/install.sh | sudo bash
```

---

## Step-by-Step Installation Prompt Walkthrough

During installation, the script will prompt you for configuration parameters. Below is the complete step-by-step breakdown:

### Step 1: Unique Project & System User Name
- **Prompt**: `Enter a unique project / server identifier (e.g., survive, rust_pvp) [default: rust]:`
- **Action**: Enter your custom project identifier (e.g., `survive`).
- **Security Hardening**: The installer dynamically generates a unique isolated Linux system user `${name}_surviverust` (e.g., `survive_surviverust`), isolates its home directory `/home/survive_surviverust`, installs application code in `/var/www/survive_surviverust`, and provisions a dedicated database `${name}_db`. This completely eliminates predictable path vectors across target servers.

### Step 2: Domain Configuration
- **Prompt**: `Enter your domain name (e.g., surviverust.com) or leave blank for VPS IP:`
- **Action**: Type your domain name (e.g. `store.yourrustserver.com`) without `http://` or `https://`.
- **Note**: If you do not have a domain yet, press `ENTER`. The script will automatically detect your public VPS IP address and configure the web store to run directly on the IP.

### Step 3: Steam Web API Key
- **Prompt**: `Enter your Steam Web API Key (obtain from https://steamcommunity.com/dev/apikey):`
- **Action**: Paste your 32-character Steam Developer API Key. This key is required for Steam OpenID authentication and retrieving player avatars and names.

### Step 4: Admin SteamID64
- **Prompt**: `Enter Admin SteamID64 (e.g., 76561198000000000) for Super Admin privileges:`
- **Action**: Enter your SteamID64 to receive immediate Super Admin and Owner permissions in the store CMS dashboard.

### Step 5: Rust Server Plugin Secret Key
- **Prompt**: `Enter Rust Server In-Game Plugin Secret Key [default: auto-generated]:`
- **Action**: Press `ENTER` to generate a secure 32-character random key or specify your custom secret for the Rust in-game C# plugin.

### Step 6: Repository Selection
- **Prompt**: `Target GitHub Repository (default: Behemiron/survive-rust-store):`
- **Action**: Press `ENTER` to accept the official repository (`Behemiron/survive-rust-store`).

### Step 7: License Key Generation & Activation (Crucial)
- The installer displays your generated SSH Public Deploy Key on screen:
  ```text
  ==============================================================================
    YOUR LICENSE DEPLOY KEY (COPY THE PUBLIC KEY BELOW):                        
  ==============================================================================
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... rust@server
  ==============================================================================
  ```
- **Action Steps**:
  1. Copy the full `ssh-ed25519 ...` public key line printed in your console.
  2. Send this public key to **Behemiron** via Discord: `behemiron_777777`.
  3. Wait for **Behemiron** to confirm that your license key has been activated for repository access.
  4. Once confirmed by Behemiron, return to your server console and press `ENTER` to resume installation.

---

## Post-Installation Automated Sequence

After pressing `ENTER`, the installer autonomously handles the rest of the deployment:

1. Installs Node.js 20 LTS, MySQL, Redis, Nginx, Certbot, PM2, and UFW Firewall.
2. Clones the repository codebase into your custom isolated project directory `/var/www/${project_user}`.
3. Auto-generates production `.env` and `.env.local` configuration files with secure random database passwords and JWT secrets.
4. Generates Prisma database models and applies migrations (`npx prisma db push`).
5. Compiles the Next.js frontend web application (`npm run build`).
6. Configures Nginx virtual host proxying with WebSocket support and issues SSL certificates via Certbot.
7. Enables UFW Firewall rules blocking external access to database and internal backend ports (`3306`, `6379`, `3000`, `5000`).
8. Launches background services under PM2 and configures systemd startup policies.

---

## Server Management Commands

Replace `<project_user>` (e.g., `survive_surviverust`) and `<project_name>` (e.g., `survive`) with the custom project identifier chosen during setup:

```bash
# View active application process status
sudo -u <project_user> pm2 status

# View live application logs
sudo -u <project_user> pm2 logs <project_name>-backend
sudo -u <project_user> pm2 logs <project_name>-frontend

# Restart application services
sudo -u <project_user> pm2 restart <project_name>-backend
sudo -u <project_user> pm2 restart <project_name>-frontend

# Check active UFW firewall rules & blocked ports
sudo ufw status verbose
```

---

## Developer Support & Inquiries

For license activations, technical support, or custom Rust plugin integrations:

- **Lead Architect & Developer**: PavelNetesov / Behemiron
- **Discord**: `behemiron_777777`
