#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_BACKUP="/etc/nginx/nginx.conf.bak"
SSL_DIR="/etc/letsencrypt/live"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit
fi

show_exit_msg() {
    echo ""
    echo ""
    echo -e "${WHITE}=======================================================${NC}"
    echo -e "${GREEN}Good luck...${NC} To Open this Menu again, just Type : ${YELLOW}n-cdn${NC}"
    echo -e "${WHITE}=======================================================${NC}"
    echo ""
}
trap show_exit_msg EXIT


draw_header() {
    clear
    echo ""
    echo -e "     ${CYAN}https://github.com/im-JvD/nginx-Reverce-CDN${NC}"
    echo ""
    echo -e "${WHITE}=======================================================${NC}"
    echo -e "${MAGENTA}  	    Install & Setup Nginx Configure        ${NC}"
    echo -e "${WHITE}=======================================================${NC}"
    echo -e "${YELLOW}          Configured for CloudFlare CDN + Worker       ${NC}"
    echo -e "${WHITE}=======================================================${NC}"
    echo ""
    echo ""
}

function install_core() {
	clear
	draw_header
    echo -e "${WHITE}===${NC} ${GREEN}Updating${NC} System & ${GREEN}Installing${NC} Nginx Core ${WHITE}===${NC}"
    echo ""
    apt update && apt upgrade -y
    apt install -y curl wget git socat cron htop vim ufw certbot python3-certbot-nginx nginx chrony
    timedatectl set-timezone Asia/Tehran
    systemctl enable chrony
    systemctl restart chrony
    echo ""
    echo -e "${GREEN}Core installation completed!${NC}"
    echo ""
    read -p "Press Enter..."
}

function setup_cdn_config() {
	clear
	draw_header
    echo -e "${WHITE}===${NC} Setup ${GREEN}CDN${NC} Configuration for ${YELLOW}Nginx${NC} ${WHITE}===${NC}"
    echo ""
    
    cp "$NGINX_CONF" "$NGINX_BACKUP"

    read -p "Enter your Domain (e.g., sub.example.com): " DOMAIN
    read -p "Enter Email for SSL: " EMAIL

    systemctl stop nginx
    
    if [ ! -d "$SSL_DIR/$DOMAIN" ]; then
        echo -e "${YELLOW}Obtaining SSL...${NC}"
        certbot certonly --standalone --preferred-challenges http --agree-tos --email "$EMAIL" -d "$DOMAIN"
        if [ $? -ne 0 ]; then
            echo -e "${RED}SSL Failed! Check DNS/IP.${NC}"
            return
        fi
    fi

    echo -e "${YELLOW}Building Nginx Config...${NC}"
    
    cat > "$NGINX_CONF" <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on;

    server {
        listen 443 ssl http2;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;
        ssl_session_tickets off;

        # -- CAMOUFLAGE START --
        location / {
            proxy_pass https://www.google.com;
            proxy_redirect off;
            proxy_ssl_server_name on;
            proxy_ssl_name "www.google.com";
            sub_filter_once off;
            proxy_set_header Host "www.google.com";
            proxy_set_header Referer \$http_referer;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header User-Agent \$http_user_agent;
        }
        # -- CAMOUFLAGE END --

        # -- INBOUNDS START --
EOF

    while true; do
        echo -e "${BLUE}--- Add Initial Inbound ---${NC}"
        read -p "WebSocket Path (e.g., /ws): " WSPATH
        read -p "Local Port (e.g., 10000): " LOCALPORT
        
        if [[ -z "$WSPATH" || -z "$LOCALPORT" ]]; then
            echo -e "${RED}Empty inputs!${NC}"
        else
            cat >> "$NGINX_CONF" <<EOF

        location $WSPATH {
            if (\$http_upgrade != "websocket") { return 404; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:$LOCALPORT;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
EOF
            echo -e "${GREEN}Added: $WSPATH -> $LOCALPORT${NC}"
        fi

        read -p "Add another? (y/n): " choice
        [[ "$choice" != "y" ]] && break
    done

    cat >> "$NGINX_CONF" <<EOF
        # -- INBOUNDS END --
    }

    server {
        listen 80;
        server_name $DOMAIN;
        if (\$host = $DOMAIN) {
            return 301 https://\$host\$request_uri;
        }
        return 404;
    }
}
EOF

    test_and_reload
}

function test_and_reload() {
    echo -e "${YELLOW}Verifying Configuration...${NC}"
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        echo -e "${GREEN}Success! Configuration Applied.${NC}"
    else
        echo -e "${RED}Config Error! Restoring backup...${NC}"
        cp "$NGINX_BACKUP" "$NGINX_CONF"
        systemctl restart nginx
        echo -e "${YELLOW}Backup restored. Please check your inputs.${NC}"
    fi
    read -p "Press Enter..."
}

function change_camouflage() {
	clear
	draw_header
    echo -e "${WHITE}===${NC} Change Reverce Proxy ${GREEN}Domain${NC} & ${GREEN}Website${NC} ${WHITE}===${NC}"
    echo ""
    echo -e "Current default is Google. Enter a new full URL."
    echo ""
    read -p "New URL (e.g., https://www.bing.com): " NEW_URL

    if [[ -z "$NEW_URL" ]]; then echo -e "${RED}Invalid Input${NC}"; return; fi

    NEW_DOMAIN=$(echo "$NEW_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')

    echo -e "${YELLOW}Updating to: $NEW_URL (Domain: $NEW_DOMAIN)${NC}"
    
    cp "$NGINX_CONF" "$NGINX_BACKUP"

    sed -i "s|proxy_pass https://.*;|proxy_pass $NEW_URL;|" "$NGINX_CONF"
    sed -i "s|proxy_ssl_name \".*\";|proxy_ssl_name \"$NEW_DOMAIN\";|" "$NGINX_CONF"
    sed -i "s|proxy_set_header Host \".*\";|proxy_set_header Host \"$NEW_DOMAIN\";|" "$NGINX_CONF"

    test_and_reload
}

function add_single_inbound() {
	clear
	draw_header
    echo -e "${WHITE}===${NC} Add New ${GREEN}Port${NC} & ${GREEN}Path${NC} (Safe Mode) ${WHITE}===${NC}"
    echo ""
    read -p "Enter New WebSocket Path (e.g., /NewWebSocketPath): " NEW_PATH
    echo ""
    read -p "Enter New Local Port (e.g., 54236): " NEW_PORT

    if [[ -z "$NEW_PATH" || -z "$NEW_PORT" ]]; then
        echo -e "${RED}Inputs cannot be empty!${NC}"; return;
    fi

    if grep -q "location $NEW_PATH " "$NGINX_CONF"; then
        echo -e "${RED}Error: Path '$NEW_PATH' already exists in Nginx config!${NC}"
        read -p "Press Enter..."
        return
    fi

    if grep -q "127.0.0.1:$NEW_PORT;" "$NGINX_CONF"; then
        echo -e "${RED}Error: Port '$NEW_PORT' is already assigned in Nginx config!${NC}"
        read -p "Press Enter..."
        return
    fi

    echo -e "${YELLOW}Adding new config block...${NC}"
    cp "$NGINX_CONF" "$NGINX_BACKUP"

    BLOCK="
        location $NEW_PATH {
            if (\$http_upgrade != \"websocket\") { return 404; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:$NEW_PORT;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \"upgrade\";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }"

    LINE_NUM=$(grep -n "# -- INBOUNDS END --" "$NGINX_CONF" | cut -d: -f1)
    
    if [[ -z "$LINE_NUM" ]]; then
        echo -e "${RED}Error: Config file structure is old. Run Option 2 (Setup CDN) once to fix structure.${NC}"
        return
    fi

    echo "$BLOCK" > /tmp/nginx_block_add

    sed -i "${LINE_NUM}r /tmp/nginx_block_add" "$NGINX_CONF"
        
    head -n $(($LINE_NUM - 1)) "$NGINX_BACKUP" > "$NGINX_CONF"
    echo "$BLOCK" >> "$NGINX_CONF"
    tail -n +$LINE_NUM "$NGINX_BACKUP" >> "$NGINX_CONF"

    rm /tmp/nginx_block_add 2>/dev/null

    test_and_reload
}

function manage_menu() {
    while true; do
        clear
		draw_header
        echo -e "	${CYAN}1.${NC} Change Reverse ${GREEN}Proxy${NC} URL & Domain "
        echo -e "	${CYAN}2.${NC} Add NEW ${YELLOW}WebSocketPath${NC} & ${YELLOW}Reverse Port${NC}"
		echo ""
        echo -e "	${CYAN}3.${NC} Back to Main Menu"
    echo ""
    echo -e "${WHITE}=======================================================${NC}"
    echo ""
        read -p "Select Option: : " mopt
        case $mopt in
            1) change_camouflage ;;
            2) add_single_inbound ;;
            3) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

while true; do
    clear
	draw_header
    echo -e "	${CYAN}1.${NC} Install ${GREEN}Nginx Core${NC} Requirements"
    echo -e "	${CYAN}2.${NC} Setup ${GREEN}CloudFlare CDN${NC} Configure"
    echo -e "	${CYAN}3.${NC} ${YELLOW}Manage${NC} Nginx Settings"
    echo -e "	${CYAN}4.${NC} ${RED}Uninstall${NC} - nginx + Configuration"
    echo ""
    echo -e "     ${CYAN}0.${NC} Exit"
    echo ""
    echo -e "${WHITE}=======================================================${NC}"
    echo ""
    read -p "Select Option: " choice

    case $choice in
        1) install_core ;;
        2) setup_cdn_config ;;
        3) manage_menu ;;
        4) 
		   
		   clear
		   draw_header
		   echo -e "${WHITE}===${NC} ${RED}Remove All Installing Package's & Nginx Configuration${NC} ${WHITE}===${NC}"
		   echo ""
           rm -f "$NGINX_CONF" && apt remove --purge -y nginx
           echo "Removed."; sleep 2 ;;
        0) exit 0 ;;
    esac
done
