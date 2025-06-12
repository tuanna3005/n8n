#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run with root privileges"
   exit 1
fi

# Nhập domain
read -p "Enter your domain (e.g. auto.example.com): " DOMAIN

# Kiểm tra domain đã trỏ đúng chưa
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

# Cài dig nếu chưa có
if ! command -v dig &> /dev/null; then
  apt update && apt install -y dnsutils
fi

# Kiểm tra domain
if check_domain $DOMAIN; then
  echo "✅ Domain $DOMAIN đã trỏ đúng IP. Tiếp tục cài đặt..."
else
  echo "❌ Domain $DOMAIN chưa trỏ về VPS. Hãy trỏ về IP: $(curl -s https://api.ipify.org)"
  exit 1
fi

# Cài Docker
apt update
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
> /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose

# Tạo thư mục & cd vào
N8N_DIR="/home/n8n"
mkdir -p "$N8N_DIR"
cd "$N8N_DIR" || exit 1

# Tạo file .env
cat << EOF > .env
N8N_PROTOCOL=https
N8N_HOST=$DOMAIN
WEBHOOK_URL=https://$DOMAIN
WEBHOOK_TUNNEL_URL=https://$DOMAIN
N8N_DEFAULT_BINARY_DATA_MODE=filesystem
EOF

# Tạo docker-compose.yml
cat << EOF > docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    env_file:
      - .env
    ports:
      - "5678:5678"
    volumes:
      - ./files:/home/node/.n8n
    networks:
      - n8n_network

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
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

# Tạo Caddyfile
cat << EOF > Caddyfile
$DOMAIN {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# Cấp quyền & chạy
mkdir -p ./files
chown -R 1000:1000 ./files
docker-compose up -d

# Hoàn tất
echo ""
echo "🎉 N8n đã được cài đặt thành công!"
echo "🌐 Truy cập: https://$DOMAIN"
echo "🛠 Cấu hình nằm tại: /home/n8n"
echo "📁 File .env, docker-compose.yml và Caddyfile đã được tạo"
echo ""
