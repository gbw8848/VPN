#!/bin/bash

# Install V2Ray
sudo apt update
sudo apt install -y curl unzip
curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
sudo bash install-release.sh

# Configure V2Ray (VLESS + HTTP/SOCKS5)
sudo cat > /usr/local/etc/v2ray/config.json <<EOL
{
  "inbounds": [
    {
      "port": 40000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(uuidgen)",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/vpn.anyidphoto.com/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/vpn.anyidphoto.com/privkey.pem"
            }
          ]
        }
      }
    },
    {
      "port": 40001,
      "protocol": "http",
      "settings": {
        "timeout": 0
      }
    },
    {
      "port": 40002,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOL

# Start V2Ray
sudo systemctl enable v2ray
sudo systemctl start v2ray

# Open firewall ports
sudo ufw allow 40000/tcp
sudo ufw allow 40001/tcp
sudo ufw allow 40002/tcp
sudo ufw enable
