#!/usr/bin/env bash
# Silent Low-RAM Pleroma Installer (<512MB RAM, 2 CPU)
# Fully automated, no user input

set -e

# --- Variables ---
PLEROMA_USER=pleroma
PLEROMA_HOME=/home/$PLEROMA_USER
PLEROMA_REPO=https://git.pleroma.social/pleroma/pleroma.git
POSTGRES_PASSWORD=$(openssl rand -base64 12)
BANNED_WORDS=("nsfw" "porn" "hentai" "18+" "lewd" "nude" "erotic")

echo "=== Installing system packages ==="
sudo apt update -qq
sudo apt install -yqq git libmagic-dev build-essential cmake erlang-dev libssl-dev \
libncurses5-dev libcurl4-openssl-dev libexpat1-dev libxml2-dev \
postgresql postgresql-contrib redis-server wget curl

echo "=== Creating pleroma user ==="
id -u $PLEROMA_USER &>/dev/null || sudo useradd -m -d $PLEROMA_HOME -s /bin/bash $PLEROMA_USER

echo "=== Setting up PostgreSQL ==="
sudo -u postgres psql -c "CREATE USER $PLEROMA_USER WITH PASSWORD '$POSTGRES_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE pleroma OWNER $PLEROMA_USER;" || true

echo "=== Cloning Pleroma repo ==="
sudo -u $PLEROMA_USER git clone $PLEROMA_REPO $PLEROMA_HOME/pleroma || true

cd $PLEROMA_HOME/pleroma

echo "=== Installing Hex & Rebar ==="
sudo -u $PLEROMA_USER mix local.hex --force
sudo -u $PLEROMA_USER mix local.rebar --force

echo "=== Fetching and compiling dependencies ==="
sudo -u $PLEROMA_USER MIX_ENV=prod mix deps.get --only prod --force
sudo -u $PLEROMA_USER MIX_ENV=prod mix deps.compile
sudo -u $PLEROMA_USER MIX_ENV=prod mix compile
sudo -u $PLEROMA_USER MIX_ENV=prod mix release

echo "=== Creating production config ==="
sudo -u $PLEROMA_USER mkdir -p $PLEROMA_HOME/pleroma/config
CONFIG_FILE=$PLEROMA_HOME/pleroma/config/prod.secret.exs

sudo -u $PLEROMA_USER tee $CONFIG_FILE > /dev/null <<EOL
use Mix.Config

config :pleroma, Pleroma.Repo,
  database: "pleroma",
  username: "$PLEROMA_USER",
  password: "$POSTGRES_PASSWORD",
  hostname: "localhost",
  pool_size: 5  # Low RAM optimization

config :pleroma, :instance,
  host: "$(hostname -I | awk '{print \$1}')",
  prohibited_words: ${BANNED_WORDS[@]}
EOL

echo "=== Applying database migrations ==="
sudo -u $PLEROMA_USER MIX_ENV=prod mix ecto.migrate

echo "=== Deploying assets ==="
sudo -u $PLEROMA_USER MIX_ENV=prod mix assets.deploy

echo "=== Creating systemd service ==="
sudo tee /etc/systemd/system/pleroma.service > /dev/null <<EOL
[Unit]
Description=Pleroma social server
After=network.target

[Service]
Type=simple
User=$PLEROMA_USER
WorkingDirectory=$PLEROMA_HOME/pleroma
ExecStart=$PLEROMA_HOME/pleroma/_build/prod/rel/pleroma/bin/pleroma start
ExecStop=$PLEROMA_HOME/pleroma/_build/prod/rel/pleroma/bin/pleroma stop
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable --now pleroma

echo "=== Installation complete! ==="
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "Pleroma is running on http://$(hostname -I | awk '{print $1}'):4000"
echo "PostgreSQL user: $PLEROMA_USER"
echo "PostgreSQL password: $POSTGRES_PASSWORD"
echo "View logs: sudo journalctl -u pleroma -f"
