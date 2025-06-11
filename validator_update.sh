#!/bin/bash

set -e

echo ">>> [1/6] Detecting public IP..."
SERVER_IP=$(curl -s -4 ifconfig.me)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Failed to detect public IP. Please check your internet connection."
    exit 1
fi
echo "✔ Public IP detected: $SERVER_IP"

echo ">>> [2/6] Stopping and removing old service if exists..."
sudo systemctl stop 0gchaind || true
sudo rm -f /etc/systemd/system/0gchaind.service
sudo systemctl daemon-reload

echo ">>> [3/6] Downloading and extracting latest 0gchaind release..."
cd $HOME
rm -rf galileo
wget -q https://github.com/0glabs/0gchain-NG/releases/download/v1.2.0/galileo-v1.2.0.tar.gz
tar -xzf galileo-v1.2.0.tar.gz
mv galileo-v1.2.0 galileo
rm galileo-v1.2.0.tar.gz
chmod +x galileo/bin/0gchaind
chmod +x galileo/bin/geth

echo ">>> [4/6] Creating systemd service with IP $SERVER_IP..."
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
[Unit]
Description=0GChainD Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/galileo
ExecStart=$HOME/galileo/bin/0gchaind start \\
    --rpc.laddr tcp://0.0.0.0:26657 \\
    --kzg.trusted-setup-path=$HOME/galileo/kzg-trusted-setup.json \\
    --engine.jwt-secret-path=$HOME/galileo/jwt-secret.hex \\
    --kzg.implementation=crate-crypto/go-kzg-4844 \\
    --block-store-service.enabled \\
    --node-api.enabled \\
    --node-api.logging \\
    --node-api.address 0.0.0.0:3500 \\
    --pruning=nothing \\
    --home=$HOME/.0gchaind/0g-home/0gchaind-home \\
    --p2p.seeds=85a9b9a1b7fa0969704db2bc37f7c100855a75d9@8.218.88.60:26656 \\
    --p2p.external_address=$SERVER_IP:26656
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [5/6] Enabling and starting systemd service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable 0gchaind
sudo systemctl restart 0gchaind

echo "✅ [6/6] 0gchaind service successfully updated and restarted!"
