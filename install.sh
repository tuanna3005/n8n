#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges"
   exit 1
fi

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận input domain từ người dùng
read -p "Enter your domain or subdomain: " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Sử dụng thư mục /home trực tiếp
N8N_DIR="/home/n8n"

# Cài đặt Docker và Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR

# Tạo file .env
cat << 'EOF' > $N8N_DIR/.env
N8N_HOST=$DOMAIN
WEBHOOK_URL=https://$DOMAIN/
WEBHOOK_TUNNEL_URL=https://$DOMAIN/
N8N_DEFAULT_BINARY_DATA_MODE=filesystem
EOF

# Tạo file docker-compose.yml
cat << 'EOF' > $N8N_DIR/docker-compose.yml
version: "3.6"
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

# Tạo file Caddyfile
cat << 'EOF' > $N8N_DIR/Caddyfile
$DOMAIN {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động các container
cd $N8N_DIR
docker-compose up -d

echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             ║"
echo "║  ✅ N8n đã được cài đặt thành công!                         ║"
echo "║                                                             ║"
echo "║  🌐 Truy cập: https://$DOMAIN                              ║"
echo "║                                                             ║"
echo "║  📚 Học n8n cơ bản: https://n8n-basic.mecode.pro            ║"
echo "║                                                             ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""
