#!/usr/bin/env bash
set -euo pipefail

DOMAIN="gbwvpn.anyidphoto.com"
XRAY_PORT=443
XRAY_USER="vless-http2"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_CONFIG_DIR}/config.json"
UUID_FILE="${XRAY_CONFIG_DIR}/${XRAY_USER}.uuid"
CERT_DIR="/www/server/panel/vhost/cert/${DOMAIN}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"
FALLBACK_DEST="127.0.0.1:80"
HTTP2_PATH="/subh"

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script requires root. Please run as root or with sudo." >&2
    exit 1
  fi
}

install_dependencies() {
  apt-get update
  apt-get install -y --no-install-recommends curl unzip uuid-runtime
}

install_xray() {
  if ! command -v xray >/dev/null 2>&1; then
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
  else
    echo "Xray already present, skipping installation."
  fi
}

ensure_certificates() {
  if [[ ! -f "${CERT_FILE}" || ! -f "${KEY_FILE}" ]]; then
    cat >&2 <<EOF
Missing certificate files:
- cert: ${CERT_FILE}
- key : ${KEY_FILE}

Please issue a TLS certificate for ${DOMAIN} in BT Panel and rerun this script once the files exist.
EOF
    exit 1
  fi
}

generate_uuid() {
  if [[ -f "${UUID_FILE}" ]]; then
    UUID=$(cat "${UUID_FILE}")
  else
    UUID=$(uuidgen)
    mkdir -p "$(dirname "${UUID_FILE}")"
    echo "${UUID}" > "${UUID_FILE}"
  fi
}

write_config() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  cat > "${XRAY_CONFIG}" <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "${XRAY_USER}",
      "port": ${XRAY_PORT},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "",
            "email": "${XRAY_USER}@${DOMAIN}"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "${FALLBACK_DEST}",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "h2"
          ],
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        },
        "xhttpSettings": {
          "path": "${HTTP2_PATH}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "blocked",
        "ip": [
          "geoip:private"
        ]
      }
    ]
  }
}
EOF
}

ensure_log_dir() {
  mkdir -p /var/log/xray
  chown root:root /var/log/xray || true
  chmod 755 /var/log/xray || true
  touch /var/log/xray/access.log /var/log/xray/error.log
  chmod 644 /var/log/xray/access.log /var/log/xray/error.log
}

restart_service() {
  systemctl enable xray
  systemctl restart xray
}

print_summary() {
  cat <<EOF
Xray VLESS + HTTP/2 deployment completed.

- Domain: ${DOMAIN}
- Listen port: ${XRAY_PORT}
- HTTP/2 path: ${HTTP2_PATH}
- Client UUID: ${UUID}
- Fallback target: ${FALLBACK_DEST}
- Certificate: ${CERT_FILE}

Configure the client with protocol VLESS, transport http, TLS enabled, and the above domain/path.

To inspect logs:
  journalctl -u xray -e
  tail -f /var/log/xray/access.log
EOF
}

main() {
  ensure_root
  install_dependencies
  install_xray
  ensure_certificates
  generate_uuid
  write_config
  ensure_log_dir
  restart_service
  print_summary
}

main "$@"
