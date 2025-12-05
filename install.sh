#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;94m'
NC='\033[0m'

CHECK_MARK="[✓]"
CROSS_MARK="[✗]"
INFO_MARK="[i]"

IP=$(curl -fsSL https://ipinfo.io/ip)

log_info()    { echo -e "${BLUE}${INFO_MARK} ${1}${NC}"; }
log_success() { echo -e "${GREEN}${CHECK_MARK} ${1}${NC}"; }
log_error()   { echo -e "${RED}${CROSS_MARK} ${1}${NC}" >&2; }

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
    hysteria server -c /etc/hysteria/config.yaml &
    log_success "Hysteria is running!"

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
    install_hysteria
    setup_hysteria
}

main
