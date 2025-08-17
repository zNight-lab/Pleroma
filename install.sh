#!/usr/bin/env bash
# Fully automated Pleroma installer for Debian/Ubuntu
# Production-ready, low-RAM optimized
# No Docker, no YunoHost required

set -e

echo "🚀 Starting Pleroma installation..."

# --- Detect VPS IP ---
INSTANCE_DOMAIN=$(curl -s http://ipinfo.io/ip)
INSTANCE_NAME="Pleroma Auto"
PLEROMA_USER="pleroma"
PLEROMA_HOME="/home/$PLEROMA_USER"
PG_PASSWORD=$(openssl rand -hex 12)

# --- Ask user for optional banned words ---
read -p "Do you want to add banned words filter? (y/N): " USE_BANNED
if [[ "$USE_BANNED" =~ ^[Yy]$ ]]; then
    read -p "Enter banned words as comma-separated list (example: nsfw,porn,hentai): " BANNED_INPUT
    IFS=',' read -ra WORDS <<< "$BANNED_INPUT"
    BANNED_WORDS="["
    for w in "${WORDS[@]}"; do
        BANNED_WORDS="$BANNED_WORDS\"$w\","
    done
    BANNED_WORDS="${BANNED_WORDS%,}]"
else
    BANNED_WORDS="[]"
fi

echo "Detected VPS IP: $INSTANCE_DOMAIN"

# --- Install dependencies ---
sudo apt update
sudo apt install -y git build-essential postgresql postgresql-contrib \
    redis-server elixir erlang libssl-dev libncurses5-dev libcurl4-openssl-dev \
    libpq-dev nodejs npm curl

# --- Create Pleroma system user ---
sudo adduser --disabled-login --gecos "Pleroma User" $PLEROMA_USER || true

# --- Setup PostgreSQL ---
sudo -u postgres psql -c "CREATE USER $PLEROMA_USER WITH PASSWORD '$PG_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE pleroma OWNER $PLEROMA_USER;" || true

# --- Clone Pleroma repo ---
sudo -u $PLEROMA_USER git clone https://git.pleroma.social/pleroma/pleroma.git $PLEROMA_HOME/pleroma

# --- Configure production settings ---
sudo -u $PLEROMA_USER bash <<EOF
cd $PLEROMA_HOME/pleroma
cp config/dev.secret.exs config/prod.secret.exs

cat > config/prod.secret.exs <<EOC
use Mix.Config

config :pleroma, Pleroma.Web.Endpoint,
  http: [ip: {0,0,0,0}, port: 4000],
  url: [host: "$INSTANCE_DOMAIN", scheme: "http"],
  secret_key_base: "$(openssl rand -hex 64)"

config :pleroma, :instance,
  name: "$INSTANCE_NAME",
  description: "Automated low-RAM Pleroma instance",
  limit: 50_000

config :pleroma, Pleroma.Repo,
  username: "$PLEROMA_USER",
  password: "$PG_PASSWORD",
  database: "pleroma",
  hostname: "localhost"

config :pleroma, Pleroma.Moderation,
  banned_words: $BANNED_WORDS
EOC
EOF

# --- Build Pleroma ---
sudo -u $PLEROMA_USER bash <<EOF
cd $PLEROMA_HOME/pleroma
mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release
EOF

# --- Setup systemd service ---
sudo tee /etc/systemd/system/pleroma.service > /dev/null <<EOC
[Unit]
Description=Pleroma
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=$PLEROMA_USER
WorkingDirectory=$PLEROMA_HOME/pleroma
ExecStart=$PLEROMA_HOME/pleroma/_build/prod/rel/pleroma/bin/pleroma start
Restart=always
Environment=MIX_ENV=prod

[Install]
WantedBy=multi-user.target
EOC

sudo systemctl daemon-reload
sudo systemctl enable --now pleroma

echo "✅ Pleroma installed successfully!"
echo "Instance URL: http://$INSTANCE_DOMAIN:4000"
echo "PostgreSQL user: $PLEROMA_USER"
echo "PostgreSQL password: $PG_PASSWORD"
if [[ "$USE_BANNED" =~ ^[Yy]$ ]]; then
    echo "Banned words filter active: $BANNED_INPUT"
else
    echo "No banned words filter applied"
fi
echo "Use 'journalctl -u pleroma -f' to view server logs"
