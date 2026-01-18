#!/bin/bash
set -e

echo "Building Base System (Version 3.7 - Commander Dragon Brave Edition)..."

# --- TARGET ARCHITECTURE (for Android/Termux) ---
ARCH="arm64"
echo "Target Architecture: $ARCH"

# 1. Clean Slate
echo "Performing a clean slate..."
sudo rm -rf kali-rootfs kali-fs.tar.xz
mkdir kali-rootfs

# 2. Bootstrap (Download the minimal OS)
echo "Bootstrapping the Kali Rolling release for $ARCH..."
sudo debootstrap --arch=$ARCH --no-check-gpg --include=nano,wget,dbus-x11 kali-rolling ./kali-rootfs https://kali.download/kali/

# 3. Create the Setup Script
echo "Generating the internal setup script..."
cat <<EOF > ./kali-rootfs/setup.sh
#!/bin/bash
set -e

# --- ENVIRONMENT SETUP ---
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

# --- CRITICAL FIX: ENABLE FULL REPOSITORIES ---
echo "Hydrating Repositories..."
echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list

echo "Updating sources..."
apt-get update

# --- FUNCTIONS ---
nuke_systemd() {
    echo "Neutralizing Systemd..."
    local offenders=("systemd" "udev" "systemd-resolved" "systemd-timesyncd")
    for pkg in "\${offenders[@]}"; do
        if [ -f "/var/lib/dpkg/info/\${pkg}.postinst" ]; then
            echo -e "#!/bin/sh\\nexit 0" > "/var/lib/dpkg/info/\${pkg}.postinst"
        fi
    done
    dpkg --configure -a
}

fix_broken_packages() {
    echo "Fixing broken packages..."
    local broken=("fuse3" "ntfs-3g" "poppler-data" "kali-desktop-base" "desktop-base")
    for pkg in "\${broken[@]}"; do
        if [ -f "/var/lib/dpkg/info/\${pkg}.postinst" ]; then
            echo -e "#!/bin/sh\\nexit 0" > "/var/lib/dpkg/info/\${pkg}.postinst"
        fi
        if [ -f "/var/lib/dpkg/info/\${pkg}.prerm" ]; then
            echo -e "#!/bin/sh\\nexit 0" > "/var/lib/dpkg/info/\${pkg}.prerm"
        fi
    done
    dpkg --configure -a
}

setup_brave_repo() {
    echo "Setting up Brave Browser repository..."
    apt-get install -y curl gpg
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list
    apt-get update
}

wrap_browsers() {
    echo "Wrapping Brave Browser..."
    if [ -f /usr/bin/brave-browser ]; then
        mv /usr/bin/brave-browser /usr/bin/brave-browser.real
        echo -e '#!/bin/bash\\nexec /usr/bin/brave-browser.real --no-sandbox --test-type --disable-dev-shm-usage --user-data-dir=/root/.config/BraveSoftware/Brave-Browser "\$@"' > /usr/bin/brave-browser
        chmod +x /usr/bin/brave-browser
    fi
}

setup_vnc() {
    echo "Configuring VNC..."
    mkdir -p /root/.vnc
    echo "kali" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    
    echo -e "#!/bin/sh\\nunset SESSION_MANAGER\\nunset DBUS_SESSION_BUS_ADDRESS\\nstartxfce4 &" > /root/.vnc/xstartup
    chmod +x /root/.vnc/xstartup
}

cleanup_image() {
    echo "Cleaning up the image..."
    rm -rf /var/lib/apt/lists/*
    rm -rf /var/cache/apt/*.bin
    rm -rf /tmp/*
}

# --- EXECUTION ---
nuke_systemd
setup_brave_repo

echo "Installing Desktop, Themes, Browsers & Goodies (Attempt 1)..."
apt-get install -y --allow-unauthenticated xfce4 xfce4-goodies tigervnc-standalone-server brave-browser kali-themes kali-defaults-desktop nmap || true

echo "Applying package fixes..."
fix_broken_packages

echo "Completing installation (Attempt 2)..."
apt-get install -f -y --allow-unauthenticated

wrap_browsers
setup_vnc
cleanup_image
rm /setup.sh
EOF

sudo chmod +x ./kali-rootfs/setup.sh

# 4. Enter Jail & Build
echo "Entering Jail to Compile..."
QEMU_STATIC_PATH="qemu-$(echo $ARCH | sed 's/arm64/aarch64/' | sed 's/amd64/x86_64/')-static"
if [ -f "/usr/bin/$QEMU_STATIC_PATH" ]; then
    sudo cp "/usr/bin/$QEMU_STATIC_PATH" "./kali-rootfs/usr/bin/"
fi
sudo proot -q $QEMU_STATIC_PATH -0 -r ./kali-rootfs -b /dev -b /proc -b /sys -w /root /usr/bin/env -i /bin/bash /setup.sh

# 5. Package
echo "Packaging Release..."
tar -cJpf kali-fs.tar.xz -C ./kali-rootfs .

echo "Build Complete: kali-fs.tar.xz"
