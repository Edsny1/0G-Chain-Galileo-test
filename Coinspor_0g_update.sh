#!/bin/bash
set -e

echo -e "\n---"
echo -e "\e[1;96m0G Galileo Düğüm Güncellemesi Başlatılıyor\e[0m"
echo -e "---"

# Kullanıcı tarafından tanımlanmış MONIKER ve PORT ön ekini mevcut yapılandırmadan algıla
echo "🔍 Mevcut MONIKER ve PORT ayarları algılanıyor..."
# 0gchaind config.toml dosyasından MONIKER'ı okumaya çalış
OG_MONIKER=$(grep -E '^moniker\s*=' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml" | awk -F'=' '{print $2}' | tr -d '[:space:]"' || true)

# config.toml'dan bağlantı noktası ön ekini okumaya çalış (örneğin: 26656 -> 26)
# Bu, bağlantı noktası ön ekinin p2p.laddr bağlantı noktasının ilk iki hanesi olduğunu varsayar.
OG_PORT_FULL=$(grep -E '^laddr\s*=\s*"tcp://0.0.0.0:' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml" | awk -F':' '{print $3}' | awk -F'"' '{print $1}' || true)
if [[ -n "$OG_PORT_FULL" ]]; then
    OG_PORT="${OG_PORT_FULL:0:2}"
else
    # Algılama başarısız olursa yedek olarak manuel giriş iste
    echo "⚠️ Mevcut bağlantı noktası ön eki algılanamadı. Doğru güncelleme için lütfen manuel olarak girin."
    read -p "🔢 Orijinal özel PORT ön ekinizi girin (Örnek: 14): " OG_PORT
fi

if [[ -z "$OG_MONIKER" ]]; then
    echo "⚠️ Mevcut MONIKER algılanamadı. Doğru güncelleme için lütfen manuel olarak girin."
    read -p "📝 Orijinal MONIKER'ınızı (Doğrulayıcı adı) girin: " OG_MONIKER
fi


echo -e "Algılanan MONIKER: \e[1;92m$OG_MONIKER\e[0m"
echo -e "Algılanan PORT Ön Eki: \e[1;93m$OG_PORT\e[0m"
echo -e "---"

read -p "🚀 Bu ayarlarla devam etmek istiyor musunuz? (e/h): " confirm_settings
[[ "$confirm_settings" != "e" ]] && echo "❌ Güncelleme iptal edildi. Lütfen betiği yeniden çalıştırın veya ayarlarınızı manuel olarak doğrulayın." && exit 1


echo ">>> [1/7] Genel IP algılanıyor..."
SERVER_IP=$(curl -s -4 ifconfig.me)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Genel IP algılanamadı. Lütfen internet bağlantınızı kontrol edin."
    exit 1
fi
echo "✔ Genel IP algılandı: \e[1;96m$SERVER_IP\e[0m"

echo ">>> [2/7] Eski 0gchaind servisi durduruluyor ve kaldırılıyor..."
sudo systemctl stop 0gchaind 2>/dev/null || true
sudo rm -f /etc/systemd/system/0gchaind.service
sudo systemctl daemon-reload

echo ">>> [3/7] En son 0gchaind sürümü (v1.2.0) indiriliyor ve çıkarılıyor..."
cd "$HOME"
rm -rf galileo
wget -q https://github.com/0glabs/0gchain-NG/releases/download/v1.2.0/galileo-v1.2.0.tar.gz
tar -xzf galileo-v1.2.0.tar.gz
mv galileo-v1.2.0 galileo
rm galileo-v1.2.0.tar.gz
chmod +x galileo/bin/0gchaind
chmod +x galileo/bin/geth # Geth'in de çalıştırılabilir olduğundan emin ol

echo ">>> [4/7] Yeni galileo dizininde güvenilir kurulum dosyalarının bulunduğundan emin olunuyor..."
# Bu dosyalar 0gchaind tarafından kullanılır ve yeni ikili için doğru yolda olmaları gerekir
[ ! -f "$HOME/galileo/jwt-secret.hex" ] && openssl rand -hex 32 > "$HOME/galileo/jwt-secret.hex"
[ ! -f "$HOME/galileo/kzg-trusted-setup.json" ] && curl -L -o "$HOME/galileo/kzg-trusted-setup.json" https://danksharding.io/trusted-setup/kzg-trusted-setup.json

echo ">>> [5/7] Özel ayarlarla 0gchaind için yeni systemd servisi oluşturuluyor..."
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
[Unit]
Description=0GChainD Service
After=network.target geth.service # Geth'den sonra başladığından emin olun

[Service]
User=$USER
WorkingDirectory=$HOME/galileo
ExecStart=$HOME/galileo/bin/0gchaind start \\
    --rpc.laddr tcp://0.0.0.0:${OG_PORT}657 \\
    --chaincfg.chain-spec devnet \\
    --chaincfg.kzg.trusted-setup-path=$HOME/galileo/kzg-trusted-setup.json \\
    --chaincfg.engine.jwt-secret-path=$HOME/galileo/jwt-secret.hex \\
    --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \\
    --chaincfg.block-store-service.enabled \\
    --chaincfg.node-api.enabled \\
    --chaincfg.node-api.logging \\
    --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \\
    --pruning=nothing \\
    --home=$HOME/.0gchaind/0g-home/0gchaind-home \\
    --p2p.seeds=85a9b9a1b7fa0969704db2bc37f7c100855a75d9@8.218.88.60:26656 \\
    --p2p.external_address=$SERVER_IP:${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [6/7] Yeni sürüm için 0gchaind yapılandırma dosyaları güncelleniyor..."
# Moniker'ı güncelle (algılamadan ayarlanmış olsa da, v1.2.0 için doğru şekilde yazıldığından emin olun)
sed -i "s|^moniker *=.*|moniker = \"${OG_MONIKER}\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# client.toml'u özel bağlantı noktasını kullanacak şekilde güncelle
sed -i "s|node = .*|node = \"tcp://localhost:${OG_PORT}657\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/client.toml"

# p2p dinleme adresini özel bağlantı noktasını kullanacak şekilde güncelle
sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${OG_PORT}656\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"
sed -i "s|laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# abci bağlantısı için proxy_app'i güncelle
sed -i "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:${OG_PORT}658\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# pprof_laddr'ı güncelle
sed -i "s|^pprof_laddr = .*|pprof_laddr = \"0.0.0.0:${OG_PORT}060\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# prometheus_listen_addr'ı güncelle
sed -i "s|prometheus_listen_addr = \".*\"|prometheus_listen_addr = \"0.0.0.0:${OG_PORT}660\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# app.toml'u node-api adresi ve rpc-dial-url için güncelle
sed -i "s|address = \".*:3500\"|address = \"127.0.0.1:${OG_PORT}500\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml"
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" "$HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml"

# Budama (pruning) ayarları (v1.2.0 için tutarlı veya güncel olduğundan emin olun)
sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" \
       -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" \
       -e "s/^pruning-interval *=.*/pruning-interval = \"19\"/" \
       "$HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml"
sed -i "s/^indexer *=.*/indexer = \"null\"/" "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml"

# Yeni ikili konum için bash profil yolunun doğru olduğundan emin olun
sed -i '/galileo\/bin/d' $HOME/.bash_profile || true
echo 'export PATH=$PATH:$HOME/galileo/bin' >> $HOME/.bash_profile
source $HOME/.bash_profile

echo ">>> [7/7] systemd servisi etkinleştiriliyor ve başlatılıyor..."
sudo systemctl daemon-reexec # Tüm değişikliklerin algılandığından emin olmak için daemon'ı yeniden çalıştır
sudo systemctl daemon-reload
sudo systemctl enable 0gchaind
sudo systemctl restart 0gchaind

echo -e "\n✅ \e[1;92m0Gchaind servisi başarıyla güncellendi ve yeniden başlatıldı!\e[0m"
echo -e "Durumu ve günlükleri şu komutla kontrol edebilirsiniz: \e[1;97mjournalctl -u 0gchaind -u geth -f\e[0m"
echo -e "---"
