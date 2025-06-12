#!/bin/bash

# ====== KIỂM TRA QUYỀN ROOT ======
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# ====== HÀM KIỂM TRA DOMAIN ======
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

# ====== NHẬN DOMAIN ======
read -p "Enter your domain or subdomain (e.g. auto.example.com): " DOMAIN

if ! command -v dig &> /dev/null; then
  apt-get update && apt-get install -y dnsutils
fi

if check_domain $DOMAIN; then
    echo "\n✅ Domain trỏ đúng IP. Tiếp tục cài đặt..."
else
    echo "\n❌ Domain $DOMAIN chưa trỏ về VPS. Vui lòng trỏ về IP: $(curl -s https://api.ipify.org)"
    exit 1
fi

# ====== BIẾN MÔI TRƯỜNG ======
N8N_DIR="/opt/n8n"

# ====== CÀI DOCKER VÀ COMPOSE ======
apt-get update && \
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \  
  "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update && \
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# ====== TẠO THƯ MỤC & FILE CẤU HÌNH ======
mkdir -p $N8N_DIR

cat << EOF > $N8N_DIR/docker-compose.yml
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
      - N8N_DIAGNOSTICS_ENABLED=false
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

# ====== TẠO CADDYFILE ======
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# ====== CHOWN & START ======
cd $N8N_DIR
mkdir -p ./n8n_data && chown -R 1000:1000 ./n8n_data

docker compose up -d

echo ""
echo "🎉 N8n đã được cài đặt thành công!"
echo "🌐 Truy cập tại: https://${DOMAIN}"
echo ""
echo "📌 Nếu không truy cập được, kiểm tra DNS đã trỏ đúng hoặc chạy: docker logs n8n"
echo ""
