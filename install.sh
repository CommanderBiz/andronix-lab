#!/data/data/com.termux/files/usr/bin/bash

# --- CONFIGURATION ---
# PASTE YOUR RELEASE LINK HERE vvv
URL="https://github.com/CommanderBiz/andronix-lab/releases/download/v2.0/kali-fs.tar.xz"
# ---------------------

INSTALL_DIR="kali-fs"
TAR_FILE="kali-fs.tar.xz"

echo "=== CommanderBiz Kali Installer ==="

# 1. Dependency Check
echo "[*] Checking dependencies..."
pkg update -y > /dev/null 2>&1
for pkg in proot tar wget; do
    if ! command -v $pkg > /dev/null; then
        echo "Installing $pkg..."
        pkg install -y $pkg > /dev/null 2>&1
    fi
done

# 2. Download
if [ -d "$INSTALL_DIR" ]; then
    echo "[!] Existing installation found ($INSTALL_DIR). Please remove it first."
    exit 1
fi

echo "[*] Downloading Kali Image (This may take a while)..."
wget --show-progress -O $TAR_FILE "$URL"

if [ ! -f "$TAR_FILE" ]; then
    echo "[!] Download failed."
    exit 1
fi

# 3. Extract (The "Android Safe" Method)
echo "[*] Extracting RootFS..."
mkdir -p $INSTALL_DIR
proot --link2symlink tar -xJf $TAR_FILE -C $INSTALL_DIR --exclude='dev/*'
if [ $? -eq 0 ]; then
    echo "[+] Extraction complete."
    rm $TAR_FILE # Cleanup to save space
else
    echo "[!] Extraction failed."
    exit 1
fi

# 4. Create the Launcher
echo "[*] Creating Launcher..."
cat <<EOF > start-kali.sh
#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD

# Fix DNS
echo "nameserver 8.8.8.8" > $INSTALL_DIR/etc/resolv.conf

# Launch
proot --link2symlink -0 -r $INSTALL_DIR \\
    -b /dev \\
    -b \$PREFIX/tmp:/dev/shm \\
    -b /proc \\
    -b /sys \\
    -w /root \\
    /usr/bin/env -i HOME=/root TERM=xterm-256color PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin /bin/bash --login
EOF

chmod +x start-kali.sh

echo "========================================"
echo "INSTALLATION COMPLETE"
echo "To start: ./start-kali.sh"
echo "To use GUI: Run 'vncserver' inside Kali"
echo "========================================"
