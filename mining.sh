#!/bin/bash

echo "=========================================="
echo "  MONERO MINING - UNINSTALL & REINSTALL"
echo "  (Support Non-Root & Root)"
echo "  ALL THREADS MODE (100% CPU)"
echo "=========================================="

# ============================================
# DETEKSI USER (ROOT atau NON-ROOT)
# ============================================
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
    echo "✅ Mode: ROOT"
    MINING_DIR="/root/moneroocean"
    LOG_FILE="/root/moneroocean/mining.log"
else
    IS_ROOT=false
    echo "✅ Mode: NON-ROOT"
    MINING_DIR="$HOME/moneroocean"
    LOG_FILE="$HOME/moneroocean/mining.log"
fi

# ============================================
# UNINSTALL LAMA (BERSIHKAN SEMUA)
# ============================================
echo ""
echo "=========================================="
echo "  🗑️ UNINSTALL MINING LAMA"
echo "=========================================="

echo "⏹️ Menghentikan semua service..."
systemctl stop monero-miner.service 2>/dev/null
systemctl stop moneroocean_miner.service 2>/dev/null
systemctl stop supportxmr.service 2>/dev/null
systemctl stop moneroocean.service 2>/dev/null

echo "🗑️ Menghapus service files..."
systemctl disable monero-miner.service 2>/dev/null
systemctl disable moneroocean_miner.service 2>/dev/null
rm -f /etc/systemd/system/monero-miner.service
rm -f /etc/systemd/system/moneroocean_miner.service
rm -f /etc/systemd/system/supportxmr.service
rm -f /etc/systemd/system/moneroocean.service
systemctl daemon-reload

echo "🔪 Menghentikan proses xmrig..."
pkill -f xmrig 2>/dev/null
killall xmrig 2>/dev/null

echo "📁 Menghapus direktori mining..."
rm -rf /root/moneroocean 2>/dev/null
rm -rf ~/moneroocean 2>/dev/null
for dir in /home/*/moneroocean; do
    rm -rf "$dir" 2>/dev/null
done

echo "🧹 Membersihkan file temporary..."
rm -f /tmp/xmrig.tar.gz /tmp/xmrig-*.tar.gz /root/xmrig-*.tar.gz 2>/dev/null

echo "📊 Mereset huge pages..."
sysctl -w vm.nr_hugepages=0 2>/dev/null
sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf 2>/dev/null

echo "⚙️ Menghapus alias lama..."
sed -i '/alias mine-/d' ~/.bashrc 2>/dev/null
sed -i '/alias cek-/d' ~/.bashrc 2>/dev/null
sed -i '/alias mo-/d' ~/.bashrc 2>/dev/null
sed -i '/# ========== MONERO MINING ALIAS/d' ~/.bashrc 2>/dev/null

echo "✅ UNINSTALL SELESAI!"

# ============================================
# CEK KONEKSI KE POOL
# ============================================
cek_koneksi() {
    timeout 3 nc -zv "$1" "$2" 2>&1 | grep -q "Connected\|succeeded"
}

echo ""
echo "=========================================="
echo "  🔍 CEK KONEKSI KE POOL"
echo "=========================================="

if cek_koneksi "gulf.moneroocean.stream" 10128; then
    POOL_URL="gulf.moneroocean.stream:10128"
    POOL_NAME="MoneroOcean"
    USE_TLS="false"
    echo "✅ MoneroOcean: BISA connect"
elif cek_koneksi "pool.supportxmr.com" 443; then
    POOL_URL="pool.supportxmr.com:443"
    POOL_NAME="SupportXMR"
    USE_TLS="true"
    echo "✅ SupportXMR: BISA connect"
else
    echo "❌ SEMUA POOL DIBLOKIR! Tidak bisa mining."
    exit 1
fi

echo "📌 Menggunakan Pool: $POOL_NAME"

# ============================================
# DETEKSI CPU
# ============================================
CPU_THREADS=$(nproc)
echo ""
echo "📊 CPU Threads: $CPU_THREADS"
echo "🔥 Mode: ALL THREADS (100% CPU)"

# ============================================
# INSTALL XMRIG
# ============================================
echo ""
echo "=========================================="
echo "  📥 INSTALL XMRIG"
echo "=========================================="

mkdir -p "$MINING_DIR"
cd "$MINING_DIR"

echo "Download XMRig..."
wget -q https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz
tar -xzf xmrig-6.25.0-linux-static-x64.tar.gz 2>/dev/null
cp xmrig-6.25.0/xmrig . 2>/dev/null
chmod +x xmrig
rm -rf xmrig-6.25.0 xmrig-6.25.0-linux-static-x64.tar.gz

if [ ! -f "xmrig" ]; then
    echo "❌ Gagal install XMRig!"
    exit 1
fi

echo "✅ XMRig terinstall"

# ============================================
# WALLET
# ============================================
WALLET="454rxijwzidbyHRALEqaiWbLeEcLXKNaNWZ5YusaMDeweD1bbwP7WkMYqRp4SGNv5jih8rRGK7aW4butACPM2BvLGwGHtC7"

# ============================================
# BUAT KONFIGURASI (FORCE ALL THREADS)
# ============================================
echo ""
echo "📝 Membuat konfigurasi (force all threads)..."

cat > "$MINING_DIR/config.json" << EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "threads": $CPU_THREADS,
        "max-threads-hint": 100,
        "priority": 5,
        "yield": false,
        "asm": true,
        "argon2-impl": "AVX2"
    },
    "pools": [
        {
            "url": "${POOL_URL}",
            "user": "${WALLET}",
            "pass": "x",
            "rig-id": "rig-${CPU_THREADS}t",
            "tls": ${USE_TLS},
            "keepalive": true
        }
    ],
    "print-time": 60,
    "randomx": {
        "mode": "fast",
        "init": -1
    }
}
EOF

echo "✅ Konfigurasi selesai (${CPU_THREADS} threads dipaksa)"

# ============================================
# JALANKAN MINING
# ============================================
echo ""
echo "=========================================="
echo "  🚀 MENJALANKAN MINER"
echo "=========================================="

cd "$MINING_DIR"

if [ "$IS_ROOT" = true ]; then
    # ROOT: pakai systemd service
    echo "Mode Root: Menggunakan systemd service"
    
    # Aktifkan huge pages
    echo "Aktifkan huge pages..."
    sysctl -w vm.nr_hugepages=1280 2>/dev/null
    grep -q "vm.nr_hugepages" /etc/sysctl.conf || echo "vm.nr_hugepages=1280" >> /etc/sysctl.conf
    
    cat > /etc/systemd/system/monero-miner.service << EOF
[Unit]
Description=Monero Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${MINING_DIR}
ExecStart=${MINING_DIR}/xmrig --config=${MINING_DIR}/config.json
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable monero-miner.service
    systemctl start monero-miner.service
    
    echo "✅ Mining berjalan sebagai service"
    
    # Buat alias untuk root
    echo ""
    echo "📝 Membuat alias command (Root)..."
    
    cat >> ~/.bashrc << 'EOF'

# ========== MONERO MINING ALIAS (ROOT) ==========
alias mine-status='systemctl status monero-miner.service --no-pager'
alias mine-log='journalctl -u monero-miner.service -f --output=cat'
alias mine-start='systemctl start monero-miner.service'
alias mine-stop='systemctl stop monero-miner.service'
alias mine-restart='systemctl restart monero-miner.service'
alias cek-hash='journalctl -u monero-miner.service --since="10 minutes ago" | grep "speed" | tail -10'
alias cek-thread='journalctl -u monero-miner.service --since="5 minutes ago" | grep "READY threads" | tail -1'
# ================================================
EOF
    
    source ~/.bashrc 2>/dev/null
    
    echo ""
    echo "📋 PERINTAH:"
    echo "  mine-status   - Cek status mining"
    echo "  mine-log      - Lihat log realtime"
    echo "  mine-stop     - Hentikan mining"
    echo "  mine-start    - Mulai mining"
    echo "  cek-hash      - Lihat hashrate"
    echo "  cek-thread    - Cek jumlah thread aktif"
    
else
    # NON-ROOT: pakai nohup
    echo "Mode Non-Root: Menggunakan nohup"
    
    pkill -f xmrig 2>/dev/null
    sleep 2
    
    nohup ./xmrig --config=config.json > mining.log 2>&1 &
    PID=$!
    
    echo "✅ Mining berjalan di background (PID: $PID)"
    
    # Buat alias untuk non-root
    echo ""
    echo "📝 Membuat alias command (Non-Root)..."
    
    cat >> ~/.bashrc << 'EOF'

# ========== MONERO MINING ALIAS (NON-ROOT) ==========
alias mine-start='cd ~/moneroocean && nohup ./xmrig --config=config.json > mining.log 2>&1 & echo "Started (PID: \$!)"'
alias mine-stop='pkill -f xmrig'
alias mine-restart='mine-stop && sleep 2 && mine-start'
alias mine-status='ps aux | grep xmrig | grep -v grep'
alias mine-log='tail -f ~/moneroocean/mining.log'
alias mine-log-tail='tail -n 50 ~/moneroocean/mining.log'
alias cek-hash='grep "speed" ~/moneroocean/mining.log 2>/dev/null | tail -10'
alias cek-thread='grep "READY threads" ~/moneroocean/mining.log 2>/dev/null | tail -1'
alias cek-cpu='top -bn1 | grep "Cpu(s)"'
# =====================================================
EOF
    
    source ~/.bashrc 2>/dev/null
    
    echo ""
    echo "📋 PERINTAH:"
    echo "  mine-status   - Cek status mining"
    echo "  mine-log      - Lihat log realtime"
    echo "  mine-stop     - Hentikan mining"
    echo "  mine-start    - Mulai mining"
    echo "  cek-hash      - Lihat hashrate"
    echo "  cek-thread    - Cek jumlah thread aktif"
    echo "  cek-cpu       - Lihat CPU usage"
fi

# ============================================
# TAMPILKAN HASIL
# ============================================
echo ""
echo "=========================================="
echo "  ✅ INSTALLASI SELESAI!"
echo "=========================================="
echo ""
echo "📋 KONFIGURASI:"
echo "  Mode    : $( [ "$IS_ROOT" = true ] && echo "ROOT" || echo "NON-ROOT" )"
echo "  Pool    : $POOL_NAME"
echo "  Threads : $CPU_THREADS thread (100% CPU)"
echo "  Dir     : $MINING_DIR"
echo ""

# Cek thread setelah 5 detik
sleep 5
if [ "$IS_ROOT" = true ]; then
    echo "📊 CEK THREAD AKTIF:"
    journalctl -u monero-miner.service --since="5 seconds ago" 2>/dev/null | grep "READY threads" | tail -1 || echo "  Masih inisialisasi, tunggu sebentar..."
else
    if [ -f "$LOG_FILE" ]; then
        echo "📊 CEK THREAD AKTIF:"
        grep "READY threads" "$LOG_FILE" 2>/dev/null | tail -1 || echo "  Masih inisialisasi, tunggu sebentar..."
    fi
fi

echo ""
echo "=========================================="
echo "⏳ Tunggu 10-15 menit, lalu jalankan: cek-hash"
echo "🔥 Mining berjalan dengan ALL $CPU_THREADS threads!"
echo "=========================================="