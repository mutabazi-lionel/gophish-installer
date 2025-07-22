# Gophish Auto Installer Script

A bash script to automatically download, configure, and install [Gophish](https://getgophish.com/) phishing framework on Linux systems.  
The script handles prerequisite installation, downloads the latest Gophish release, sets up TLS certificates (via Certbot or manual input), creates a systemd service, and displays admin credentials.

---

## Features

- Supports Debian/Ubuntu, Fedora, CentOS/RHEL, Arch Linux
- Checks and installs required dependencies (`curl`, `unzip`, `certbot`)
- Fetches latest Gophish release automatically from GitHub
- Optional SSL/TLS certificate generation with Certbot (DNS challenge)
- Custom or default Gophish configuration (ports, certificates)
- Creates and enables systemd service for Gophish
- Logs installation steps and outputs for troubleshooting

---

## Prerequisites

- Linux system with `bash` shell
- `sudo` privileges for package installation and service setup
- Internet connection to download dependencies and Gophish

---

## Usage

1. Clone or download this repository:

   ```bash
   git clone https://github.com/mutabazi-lionel/gophish-installer.git
   cd gophish-installer
   chmod +x install.sh
   sudo ./install.sh

   #Troubleshooting
   Ensure your system's package manager is supported (Ubuntu, Debian, Fedora, CentOS, Arch)
   ```

Verify that snap is installed for Certbot on Debian/Ubuntu

Check firewall rules allow traffic on chosen ports

Review ~/gophish-install.log and /opt/gophish/gophish.log for error details

# Disclaimer

Use this tool responsibly and only on systems you own or have explicit permission to test.
