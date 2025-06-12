#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with root privileges" 
   exit 1
fi

# Nhập domain từ người dùng
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

if ! command -v dig &> /dev/null; then
  apt update && apt install -y dnsutils
fi

if check_domain $DOMAIN; then
  echo "✅ Domain $DOMAIN đã trỏ đúng IP. Tiếp tục..."
else
  echo "❌ Domain $DOMAIN chưa trỏ đúng VPS. Hãy trỏ về IP: $(curl -s https://api.ipify.org)"
  exit 1
fi

# Cài Docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
mkdir -p /etc/apt/keyrings

echo \  
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Cấu hình thư mục
N8N_DIR="/home/n8n"
mkdir -p $N8N_DIR
cd $N8N_DIR || exit 1

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
      - $N8N_DIR:/home/node/.n8n
    networks:
      - n8n_network
    dns:
      - 8.8.8.8
      - 1.1.1.1

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile
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

# Cấp quyền & khởi động
chown -R 1000:1000 $N8N_DIR
docker-compose -f docker-compose.yml up -d

# Hoàn tất
echo ""
echo "🎉 N8n đã được cài đặt thành công!"
echo "🌐 Truy cập tại: https://$DOMAIN"
echo "📁 File cấu hình: $N8N_DIR/.env"
echo "📚 Tài liệu học: https://n8n-basic.mecode.pro"
echo ""
