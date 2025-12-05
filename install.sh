#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;94m'
YELLOW='\033[0;33m'
NC='\033[0m'

CHECK_MARK="[✓]"
CROSS_MARK="[✗]"
INFO_MARK="[i]"
WARNING_MARK="[!]"

IP=$(curl -fsSL https://ipinfo.io/ip)

log_info()    { echo -e "${BLUE}${INFO_MARK} ${1}${NC}"; }
log_success() { echo -e "${GREEN}${CHECK_MARK} ${1}${NC}"; }
log_error()   { echo -e "${RED}${CROSS_MARK} ${1}${NC}" >&2; }
log_warning() { echo -e "${YELLOW}${WARNING_MARK} ${1}${NC}"; }

check_root() {
    [[ "$(id -u)" -ne 0 ]] && log_error "Run as root." && exit 1
}

check_os() {
    [[ ! -f /etc/os-release ]] && log_error "Unsupported OS." && exit 1

    os=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    ver=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

    if ! command -v bc >/dev/null 2>&1; then
        apt update -qq && apt install -y -qq bc || exit 1
    fi

    if ! { [[ "$os" == "ubuntu" ]] && [[ $(echo "$ver >= 22" | bc) -eq 1 ]]; } &&
       ! { [[ "$os" == "debian" ]] && [[ $(echo "$ver >= 12" | bc) -eq 1 ]]; }; then
        log_error "Requires Ubuntu 22+ or Debian 12+."
        exit 1
    fi
}

install_packages() {
    local REQUIRED_PACKAGES=("curl" "wget" "tar" "openssl")
    local MISSING_PACKAGES=()

    log_info "Checking required packages..."

    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$package" &> /dev/null; then
            MISSING_PACKAGES+=("$package")
        else
            log_success "Package $package is already installed"
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
        apt update -qq || { log_error "Failed to update apt repositories"; exit 1; }
        apt upgrade -y -qq || log_warning "Failed to upgrade packages, continuing..."

        for package in "${MISSING_PACKAGES[@]}"; do
            log_info "Installing $package..."
            if apt install -y -qq "$package"; then
                log_success "Installed $package"
            else
                log_error "Failed to install $package"
                exit 1
            fi
        done
    else
        log_success "All required packages are already installed."
    fi

    if ! command -v go &> /dev/null; then
        GO_VERSION="1.25.4"
        log_info "Installing Go $GO_VERSION..."
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz || { log_error "Failed to download Go"; exit 1; }
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz || { log_error "Failed to extract Go"; exit 1; }
        rm /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        log_success "Go $GO_VERSION installed successfully"
    else
        log_success "Go is already installed: $(go version)"
    fi
}

install_hysteria() {
    log_info "Installing Hysteria 2..."

    if [ -d "/etc/hysteria" ]; then
        log_warning "Directory /etc/hysteria already exists."
        read -p "Do you want to remove it and install again? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /etc/hysteria
            curl -fsSL https://get.hy2.sh/ | bash || exit 1
            log_success "Hysteria 2 installed."
        else
            log_info "Skipping download. Using existing directory."
            return 0
        fi
    fi
}

setup_hysteria() {
    mkdir -p /etc/hysteria

    log_info "Generating TLS certificate..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout /etc/hysteria/ca.key \
        -out /etc/hysteria/ca.crt \
        -days 3650 -nodes -subj "/CN=$IP"

    log_info "Calculating SHA256 fingerprint..."
    sha256=$(openssl x509 -in /etc/hysteria/ca.crt -noout -sha256 -fingerprint)

    read -rp "Enter port for Hysteria [443]: " port
    port=${port:-443}
    if ! [[ $port =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_error "Invalid port number. Must be 1-65535."
        exit 1
    fi
    if ss -tuln | grep -q ":$port\b"; then
        log_error "Port $port is already in use."
        exit 1
    fi

    password=$(openssl rand -base64 16)

    cat >/etc/hysteria/config.yaml <<EOF
listen: :$port

tls:
  cert: /etc/hysteria/ca.crt
  key: /etc/hysteria/ca.key
  insecure: true
  pinSHA256: $sha256

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
EOF
    log_success "Config created: /etc/hysteria/config.yaml"

    log_info "Creating systemd service..."
    cat >/etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Hysteria Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
User=root
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now hysteria-server
    log_success "Hysteria service installed and started!"

    generate_name() {
        tr -dc 'A-Za-z1-9' </dev/urandom | head -c 8
    }

    echo ""
    echo "======================================="
    echo ""
    echo "Connection URI for Hiddify:"
    echo ""
    for i in 1 2 3; do
        NAME=$(generate_name)
        URI="hy2://$password@$IP:$port?sni=$IP&insecure=1#$NAME"
        echo "  $URI"
    done
    echo ""
    echo "======================================="
    echo ""
}

main() {
    check_root
    check_os
    install_packages
    install_hysteria
    setup_hysteria
}

main
