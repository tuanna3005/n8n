#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  This script must be run as root!"
  exit 1
fi

# Yêu cầu nhập domain
read -p "Enter your domain (e.g. auto.example.com): " DOMAIN

# Kiểm tra domain đã trỏ đúng IP chưa
check_domain() {
  local domain=$1
  local server_ip=$(curl -s https://api.ipify.org)
  local domain_ip=$(dig +short $domain | tail -n1)

  if [ "$domain_ip" = "$server_ip" ]; then
    return 0
  else
    return 1
  fi
}

# Cài dnsutils nếu thiếu
if ! command -v dig &> /dev/null; then
  apt update && apt install -y dnsutils
fi

# Kiểm tra domain
if check_domain $DOMAIN; then
  echo -e "\n✅ Domain $DOMAIN đã trỏ đúng IP. Tiếp tục cài đặt..."
else
  echo -e "\n❌ Domain $DOMAIN chưa trỏ về VPS. Vui lòng trỏ về IP: $(curl -s https://api.ipify.org)"
  exit 1
fi

# Cài Docker & Docker Compose
apt update
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Khởi tạo thư mục
N8N_DIR="/opt/n8n"
mkdir -p $N8N_DIR
cd $N8N_DIR

# Tạo docker-compose.yml
cat <<EOF > docker-compose.yml
version: "3.8"

services:
  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - n8n_net
    dns:
      - 1.1.1.1

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
    networks:
      - n8n_net

networks:
  n8n_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

# Tạo Caddyfile
cat <<EOF > Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# Cấp quyền và khởi động
mkdir -p ./n8n_data
chown -R 1000:1000 ./n8n_data
docker compose up -d

echo ""
echo "🎉 N8n đã được cài đặt thành công!"
echo "🌐 Truy cập tại: https://${DOMAIN}"
echo ""
