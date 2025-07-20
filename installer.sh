#!/bin/bash
set -e
log() {
    echo "[*] $1"
}
fail() {
    echo "[✗] $1"
    exit 1
}

success() {
    echo "[✓] $1"
}

exec > >(tee -a gophish-install.log) 2>&1

#Checking for for prerequisites
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
    printf "Starting Configuration ...\n 📦 ====================================== \n"
}

__generate_cert() {
    while true; do
        read -rp "Do you want to generate an SSL certificate now? (Y/N): " answer
        case "$answer" in
        [Yy])
            log "Let's generate an SSL/TLS certificate using Certbot"

            read -rp "🌐 Enter your domain name (e.g., hali-cybers.online): " __DOMAIN

            log "You’ll now complete a DNS challenge manually."
            log "Certbot will prompt you to add a TXT record to your DNS settings."
            log "Make sure you can access your DNS provider's control panel."

            read -rp "⚠️  Press Enter to continue or Ctrl+C to cancel..."

            sudo certbot certonly \
                --manual \
                --preferred-challenges dns \
                --register-unsafely-without-email \
                -d "$__DOMAIN" || fail "Certbot failed to generate certificate."

            local cert_path="/etc/letsencrypt/live/$__DOMAIN/fullchain.pem"
            local key_path="/etc/letsencrypt/live/$__DOMAIN/privkey.pem"

            if [[ -f "$cert_path" && -f "$key_path" ]]; then
                success "Certificate successfully created!"
                log "Cert Path : $cert_path"
                log "Key Path  : $key_path"

                export __CERT_PATH="$cert_path"
                export __KEY_PATH="$key_path"
            else
                fail "Failed to find generated certificates for domain $__DOMAIN."
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

__generate_gophish_config() {
    log "Generating your custom Gophish configuration..."

    read -pr "🔧 Enter Admin Server Port (Recommended ==> 3333): " ADMIN_PORT
    read -pr "🎯 Enter Phishing Server Port (Recommended ==> 443): " PHISH_PORT

    if [[ -n "$__CERT_PATH" && -n "$__KEY_PATH" ]]; then
        while true; do
            read -rp "Use previously generated certificate paths for both Admin & Phish servers? (Y/N): " cert_answer
            case "$cert_answer" in
            [Yy])
                log "Using previously generated certs from __generate_cert"
                ADMIN_CERT="$__CERT_PATH"
                ADMIN_KEY="$__KEY_PATH"
                PHISH_CERT="$__CERT_PATH"
                PHISH_KEY="$__KEY_PATH"
                unset __CERT_PATH
                unset __KEY_PATH
                break
                ;;
            [Nn])
                log "Prompting for manual input of certificate and key paths..."

                while true; do
                    read -rp "🔑 Enter path to Admin TLS certificate (e.g., fullchain.pem): " ADMIN_CERT
                    [[ -f "$ADMIN_CERT" ]] && break
                    echo "[✗] File not found: $ADMIN_CERT"
                done

                while true; do
                    read -rp "🔐 Enter path to Admin TLS key (e.g., privkey.pem): " ADMIN_KEY
                    [[ -f "$ADMIN_KEY" ]] && break
                    echo "[✗] File not found: $ADMIN_KEY"
                done

                while true; do
                    read -rp "📜 Enter path to Phish TLS certificate (e.g., fullchain.pem): " PHISH_CERT
                    [[ -f "$PHISH_CERT" ]] && break
                    echo "[✗] File not found: $PHISH_CERT"
                done

                while true; do
                    read -rp "🔐 Enter path to Phish TLS key (e.g., privkey.pem): " PHISH_KEY
                    [[ -f "$PHISH_KEY" ]] && break
                    echo "[✗] File not found: $PHISH_KEY"
                done

                break
                ;;
            *)
                log "Please enter Y or N."
                ;;
            esac
        done
    else
        log "No exported certificate paths found. Prompting for manual input..."

        while true; do
            read -rp "🔑 Enter path to Admin TLS certificate (e.g., fullchain.pem): " ADMIN_CERT
            [[ -f "$ADMIN_CERT" ]] && break
            echo "[✗] File not found: $ADMIN_CERT"
        done

        while true; do
            read -rp "🔐 Enter path to Admin TLS key (e.g., privkey.pem): " ADMIN_KEY
            [[ -f "$ADMIN_KEY" ]] && break
            echo "[✗] File not found: $ADMIN_KEY"
        done

        while true; do
            read -rp "📜 Enter path to Phish TLS certificate (e.g., fullchain.pem): " PHISH_CERT
            [[ -f "$PHISH_CERT" ]] && break
            echo "[✗] File not found: $PHISH_CERT"
        done

        while true; do
            read -rp "🔐 Enter path to Phish TLS key (e.g., privkey.pem): " PHISH_KEY
            [[ -f "$PHISH_KEY" ]] && break
            echo "[✗] File not found: $PHISH_KEY"
        done
    fi

    local config_path="/opt/gophish/config.json"

    log "Writing configuration to $config_path..."

    cat <<EOF | sudo tee "$config_path" >/dev/null
{
    "admin_server": {
        "listen_url": "0.0.0.0:$ADMIN_PORT",
        "use_tls": true,
        "cert_path": "$ADMIN_CERT",
        "key_path": "$ADMIN_KEY",
        "trusted_origins": []
    },
    "phish_server": {
        "listen_url": "0.0.0.0:$PHISH_PORT",
        "use_tls": true,
        "cert_path": "$PHISH_CERT",
        "key_path": "$PHISH_KEY"
    },
    "db_name": "sqlite3",
    "db_path": "gophish.db",
    "migrations_prefix": "db/db_",
    "contact_address": "",
    "logging": {
        "filename": "__logs",
        "level": "error"
    }
}
EOF

    success "Gophish config created at $config_path"
}

__create_gophish_service() {
    log "Creating GoPhish systemd service ..."
    sudo tee /etc/systemd/system/gophish.service >/dev/null <<EOF
[Unit]
Description=GoPhish Phishing Framework
After=network.target

[Service]
Type=simple
ExecStart=/opt/gophish/gophish >> /opt/gophish/gophish.log 2>&1
WorkingDirectory=/opt/gophish
Restart=always
User=nobady

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable gophish
    sudo systemctl start gophish
    success "GoPhish service created and started."
}

__display_gophish_credentials() {
    sleep 5
    log "Attempting to extract admin credentials from logs..."
    local log_file="/opt/gophish/gophish.log"

    if [[ -f "$log_file" ]]; then
        grep "Generated Admin Server" "$log_file" ||
            grep "Please login" "$log_file" ||
            log "GoPhish log exists, but credentials not found. Check the log manually."
    else
        log "Log file not found. Please check manually: gophish/gophish.log"
    fi

    echo
    success "You can access GoPhish admin UI at: https://localhost:3333"
    echo "⚠️  Remember to check 'gophish.log' to retrieve your random admin password!"
}

__installer() {

    while true; do
        read -rp "📦 Do you want to keep default configurations? [Y/N]: " __CHOICE
        case "$__CHOICE" in
        [Yy])
            echo "[*] Keeping default configurations."
            __create_gophish_service
            __display_gophish_credentials
            break
            ;;
        [Nn])
            echo "[*] Proceeding with custom configuration ..."
            __generate_cert
            __generate_gophish_config
            __create_gophish_service
            __display_gophish_credentials
            break
            ;;
        *) echo "[!] Please enter Y if yes or N if No" ;;
        esac
    done

}

__main() {
    __prerequisites_and_install curl
    __prerequisites_and_install unzip
    __prerequisites_and_install certbot
    __installer
}
__main
