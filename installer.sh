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
    printf "Starting Configuration ...\n ====================================== \n"
}

__gophish_config() {
    read -pr "Do you what to keep default configulations? [Y/N]" __CHOICE
    if condition; then
        command ...
    else
        command ...
    fi
}
__prerequisites_and_install curl
__prerequisites_and_install unzip
__getting_gophish
