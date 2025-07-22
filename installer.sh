#!/bin/bash
set -euo pipefail

log() {
    echo "[*] $1"
}
fail() {
    echo "[✗] $1"
    exit 1
}
warning() { echo -e "[⚠️] $*"; }
success() {
    echo "[✅] $1"
}

exec > >(tee -a gophish-install.log) 2>&1

__prerequisites_and_install() {
    local package="$1"
    log "Checking if $package is installed ..."

    if ! command -v "$package" 2>/dev/null; then
        log "'$package' not found. Attempting to install ..."
        if [ -f /etc/os-release ]; then
            # shellcheck disable=SC2002
            OS=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null)
        else
            fail "Unable to detect OS. Cannot install packages."
        fi
        case "$OS" in
        ubuntu | debian)
            sudo apt-get update
            sudo apt-get install -y "$package"
            ;;
        fedora)
            sudo dnf install -y "$package"
            ;;
        centos | rhel)
            sudo yum install -y "$package"
            ;;
        arch)
            sudo pacman -Sy --noconfirm "$package"
            ;;
        *)
            fail "Unsupported distribution: $OS"
            ;;
        esac

        if command -v "$package" 2>/dev/null; then
            success "$package successfully installed"
            echo "==============================================="
        else
            fail "Failed to install $package. Aborting ..."
        fi
    else
        success "$package already installed ..."
        echo "==============================================="
    fi
}

__INSTALLATION_FOLDER="/opt/gophish"

__getting_gophish() {
    __GIT_REPORT="gophish/gophish"

    log "Fetching latest Gophish version info..."
    __RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$__GIT_REPORT/releases/latest" 2>/dev/null) || fail "Failed to fetch release info."
    __DOWNLOAD_URL=$(
        echo "$__RELEASE_JSON" | grep -oP 'https://github\.com/gophish/gophish/releases/download/[^"]+linux-64bit\.zip' | head -n 1
    )

    if [[ -z "$__DOWNLOAD_URL" ]]; then
        fail "Could not find download URL for Linux 64-bit zip in latest release."
    fi

    __FILENAME=$(basename "$__DOWNLOAD_URL")
    log "Download URL found: $__DOWNLOAD_URL"

    log "Downloading $__FILENAME using curl ..."
    curl --retry 3 --retry-delay 5 --fail --location --output "$__FILENAME" "$__DOWNLOAD_URL" || fail "Failed to download $__FILENAME"

    log "Creating installation folder $__INSTALLATION_FOLDER ..."
    sudo mkdir -p "$__INSTALLATION_FOLDER" 2>/dev/null || fail "Cannot create install directory."

    log "Extracting $__FILENAME ..."
    (
        sudo unzip -oq "$__FILENAME" -d "$__INSTALLATION_FOLDER" 2>/dev/null && sudo rm -Rf "$__FILENAME" 2>/dev/null
    ) || fail "Failed to unzip package."

    success "Gophish Added to $__INSTALLATION_FOLDER"
    sleep 2s
    printf "Starting Configuration ...\n\n\n====================================== \n\n\n"
}

__generate_cert() {
    while true; do
        read -rp "Do you want to generate an SSL certificate now? (Y/N): " answer
        case "$answer" in
        [Yy])
            log "Let's generate an SSL/TLS certificate using Certbot."

            read -rp "Enter your domain name (e.g., hali.online): " __DOMAIN

            log "You’ll now complete a DNS-01 challenge manually."
            log "Certbot will prompt you to add a TXT record to your DNS settings."
            log "Make sure you have access to your DNS provider (e.g. Namecheap, Cloudflare)."

            read -rp "Press Enter to begin Certbot or Ctrl+C to cancel..."

            sudo certbot certonly \
                --manual \
                --preferred-challenges dns \
                --manual-public-ip-logging-ok \
                --register-unsafely-without-email \
                --agree-tos \
                -d "$__DOMAIN"

            local cert_path="/etc/letsencrypt/live/$__DOMAIN/fullchain.pem"
            local key_path="/etc/letsencrypt/live/$__DOMAIN/privkey.pem"

            if [[ -f "$cert_path" && -f "$key_path" ]]; then
                success "Certificate successfully created!"
                log "ert Path: $cert_path"
                log "Key Path:  $key_path"

                export __CERT_PATH="$cert_path"
                export __KEY_PATH="$key_path"
            else
                fail "❌ Failed to find certificates for domain $__DOMAIN."
            fi
            break
            ;;
        [Nn])
            log "Skipping certificate generation."
            break
            ;;
        *)
            log "Please enter Y or N."
            ;;
        esac
    done
}

__port_in_use() {
    local PORT=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -qw ":$PORT"
        return $?
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -qw ":$PORT"
        return $?
    else
        echo "Can not check Port"
        return 1
    fi
}

__generate_gophish_config() {
    log "Checking if default ports are available..."

    ADMIN_PORT=3333
    PHISH_PORT=80

    if __port_in_use "$ADMIN_PORT"; then
        warning "Port $ADMIN_PORT (Admin) is already in use!"
        while true; do
            read -rp "Enter a different Admin Server Port: " ADMIN_PORT
            if ! __port_in_use "$ADMIN_PORT"; then
                break
            fi
            echo "Port $ADMIN_PORT is also in use. Try another."
        done
    else
        log "Admin Server will use default port $ADMIN_PORT"
    fi

    if __port_in_use "$PHISH_PORT"; then
        warning "Port $PHISH_PORT (Phishing) is already in use!"
        while true; do
            read -rp "Enter a different Phishing Server Port: " PHISH_PORT
            if ! __port_in_use "$PHISH_PORT"; then
                break
            fi
            echo "Port $PHISH_PORT is also in use. Try another."
        done
    else
        log "Phish Server will use default port $PHISH_PORT"
    fi

    if [[ -n "${__CERT_PATH:-}" && -n "${__KEY_PATH:-}" ]]; then
        while true; do
            read -rp "Use previously generated certificate paths for both Admin & Phish servers? (Y/N): " cert_answer
            case "$cert_answer" in
            [Yy])
                log "Using previously generated certs"
                ADMIN_CERT="$__CERT_PATH"
                ADMIN_KEY="$__KEY_PATH"
                PHISH_CERT="$__CERT_PATH"
                PHISH_KEY="$__KEY_PATH"
                unset __CERT_PATH __KEY_PATH
                break
                ;;
            [Nn])
                log "Manual entry of cert/key paths..."
                break
                ;;
            *)
                log "Please enter Y or N."
                ;;
            esac
        done
    fi

    while [[ -z "${ADMIN_CERT+x}" ]]; do
        read -rp "Enter path to Admin TLS certificate (leave empty to disable TLS): " ADMIN_CERT
        if [[ -z "$ADMIN_CERT" || -f "$ADMIN_CERT" ]]; then
            break
        fi
        echo "File not found: $ADMIN_CERT"
    done

    while [[ -z "${ADMIN_KEY+x}" ]]; do
        read -rp "Enter path to Admin TLS key (leave empty to disable TLS): " ADMIN_KEY
        if [[ -z "$ADMIN_KEY" || -f "$ADMIN_KEY" ]]; then
            break
        fi
        echo "File not found: $ADMIN_KEY"
    done

    while [[ -z "${PHISH_CERT+x}" ]]; do
        read -rp "Enter path to Phish TLS certificate (leave empty to disable TLS): " PHISH_CERT
        if [[ -z "$PHISH_CERT" || -f "$PHISH_CERT" ]]; then
            break
        fi
        echo "File not found: $PHISH_CERT"
    done

    while [[ -z "${PHISH_KEY+x}" ]]; do
        read -rp "Enter path to Phish TLS key (leave empty to disable TLS): " PHISH_KEY
        if [[ -z "$PHISH_KEY" || -f "$PHISH_KEY" ]]; then
            break
        fi
        echo "File not found: $PHISH_KEY"
    done

    if [[ -n "$ADMIN_CERT" && -n "$ADMIN_KEY" ]]; then
        ADMIN_USE_TLS=true
    else
        ADMIN_USE_TLS=false
        ADMIN_CERT=""
        ADMIN_KEY=""
    fi

    if [[ -n "$PHISH_CERT" && -n "$PHISH_KEY" ]]; then
        PHISH_USE_TLS=true
    else
        PHISH_USE_TLS=false
        PHISH_CERT=""
        PHISH_KEY=""
    fi

    local config_path="/opt/gophish/config.json"

    log "Writing configuration to $config_path..."

    sudo bash -c "cat > '$config_path'" <<EOF
{
  "admin_server": {
    "listen_url": "0.0.0.0:$ADMIN_PORT",
    "use_tls": $ADMIN_USE_TLS,
    "cert_path": "$ADMIN_CERT",
    "key_path": "$ADMIN_KEY",
    "trusted_origins": []
  },
  "phish_server": {
    "listen_url": "0.0.0.0:$PHISH_PORT",
    "use_tls": $PHISH_USE_TLS,
    "cert_path": "$PHISH_CERT",
    "key_path": "$PHISH_KEY"
  },
  "db_name": "sqlite3",
  "db_path": "gophish.db",
  "migrations_prefix": "db/db_",
  "contact_address": "",
  "logging": {
    "filename": "gophish.log",
    "level": "debug"
  }
}
EOF

    success "Gophish config created at: $config_path"
}

__create_gophish_service() {

    log "Creating and starting GoPhish systemd service..."

    sudo chmod +x /opt/gophish/gophish

    sudo pkill -f "/opt/gophish/gophish" 2>/dev/null || true

    sudo tee /etc/systemd/system/gophish.service >/dev/null <<EOF
[Unit]
Description=GoPhish Phishing Framework
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gophish
ExecStart=/opt/gophish/gophish
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # Reload and start service
    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable gophish
    sudo systemctl restart gophish
    success "GoPhish systemd service created and started."
}

__display_gophish_credentials() {
    local log_file="/opt/gophish/gophish.log"
    local password=""
    sleep 5
    log "Everything Seems to be Okay ..."

    if [[ -f "$log_file" ]]; then
        password=$(grep -i "Please login with the username" "$log_file" |
            sed -n 's/.*password[[:space:]]\+\([^[:space:]]\+\).*/\1/p')

        if [[ -n "$password" ]]; then
            success "🔐 Admin credentials:"
            echo "   ➤ Username: admin"
            echo "   ➤ Password: $password"
        else
            warn "Credentials not found in the log. Please check manually: $log_file"
        fi
    else
        fail "❌ Log file not found: $log_file"
    fi

    echo
    success "You can access the GoPhish admin UI at: https://localhost:3333"
}

__root-check() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run as root or with sudo." >&2
        exit 1
    fi
}

__installer() {
    config_path="/opt/gophish/config.json"

    while true; do
        read -rp "Do you want to keep default configurations? [Y/N]: " __CHOICE
        case "$__CHOICE" in
        [Yy])
            echo "[*] Keeping default configurations."
            sudo tee "$config_path" >/dev/null <<EOF
{
  "admin_server": {
    "listen_url": "0.0.0.0:3333",
    "use_tls": false,
    "cert_path": "",
    "key_path": "",
    "trusted_origins": []
  },
  "phish_server": {
    "listen_url": "0.0.0.0:80",
    "use_tls": false,
    "cert_path": "",
    "key_path": ""
  },
  "db_name": "sqlite3",
  "db_path": "gophish.db",
  "migrations_prefix": "db/db_",
  "contact_address": "",
  "logging": {
    "filename": "gophish.log",
    "level": "debug"
  }
}
EOF
            __create_gophish_service
            __display_gophish_credentials
            break
            ;;
        [Nn])
            echo "[*] Proceeding with custom configuration ..."

            read -rp "Do you want to generate a new TLS certificate? [Y to generate / any other key to skip]: " cert_choice
            if [[ "$cert_choice" =~ ^[Yy]$ ]]; then
                __generate_cert
            else
                log "Skipping certificate generation."
                unset __CERT_PATH
                unset __KEY_PATH
            fi

            __generate_gophish_config
            __create_gophish_service
            __display_gophish_credentials
            break
            ;;
        *)
            echo "[!] Please enter Y if yes or N if No"
            ;;
        esac
    done
}

__main() {
    __root-check
    __prerequisites_and_install curl
    __prerequisites_and_install unzip
    __prerequisites_and_install certbot
    __getting_gophish
    __installer
}
__main
