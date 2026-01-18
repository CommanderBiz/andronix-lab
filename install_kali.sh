#!/bin/bash
echo "Building Base System (Version 3.0 - The Dragon Edition)..."

# 1. Clean Slate
sudo rm -rf kali-rootfs kali-fs.tar.xz
mkdir kali-rootfs 

# 2. Bootstrap (Download the minimal OS)
sudo debootstrap --arch=arm64 --no-check-gpg --include=nano,wget,dbus-x11 kali-rolling ./kali-rootfs https://kali.download/kali/ 

# 3. Create the Setup Script
cat <<EOF > ./kali-rootfs/setup.sh
#!/bin/bash

# Fix PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

# --- CRITICAL FIX: ENABLE FULL REPOSITORIES ---
# This fixes the "Unable to locate package nmap" error for the user.
echo "Hydrating Repositories..."
echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list

echo "Updating sources..."
apt update

# --- FUNCTIONS ---

nuke_systemd() {
    echo "Neutralizing Systemd..."
    local offenders=("systemd" "udev" "systemd-resolved" "systemd-timesyncd")
    for pkg in "\${offenders[@]}"; do
        echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/\${pkg}.postinst"
    done
    dpkg --configure -a
}

fix_broken_packages() {
    echo "Fixing broken packages..."
    local broken=("fuse3" "ntfs-3g" "poppler-data" "kali-desktop-base" "desktop-base")
    for pkg in "\${broken[@]}"; do
        echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/\${pkg}.postinst"
        echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/\${pkg}.prerm"
    done
    dpkg --configure -a
}

wrap_browsers() {
    echo "Wrapping Browsers..."
    # Firefox Wrapper
    if [ -f /usr/bin/firefox-esr ]; then
        mv /usr/bin/firefox-esr /usr/bin/firefox-esr.real
        echo -e '#!/bin/bash\nexport MOZ_FAKE_NO_SANDBOX=1\nexec /usr/bin/firefox-esr.real "\$@"' > /usr/bin/firefox-esr
        chmod +x /usr/bin/firefox-esr
    fi
    # Chromium Wrapper
    if [ -f /usr/bin/chromium ]; then
        mv /usr/bin/chromium /usr/bin/chromium.real
        echo -e '#!/bin/bash\nexec /usr/bin/chromium.real --no-sandbox --test-type --disable-dev-shm-usage --user-data-dir=/root/.config/chromium "\$@"' > /usr/bin/chromium
        chmod +x /usr/bin/chromium
    fi
}

setup_vnc() {
    echo "Configuring VNC..."
    mkdir -p /root/.vnc
    echo "kali" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    
    # Force XFCE startup
    echo -e "#!/bin/sh\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nstartxfce4 &" > /root/.vnc/xstartup
    chmod +x /root/.vnc/xstartup
}

cleanup_image() {
    rm -rf /var/lib/apt/lists/*
    rm -rf /var/cache/apt/*.bin
    rm -rf /tmp/*
}

# --- EXECUTION ---

nuke_systemd

echo "Installing Desktop, Themes & Browsers..."
# ADDED: kali-themes and kali-defaults-desktop for the 'Dragon' look
# ADDED: nmap so the user has at least one tool to start with
apt install -y xfce4 tigervnc-standalone-server firefox-esr chromium kali-themes kali-defaults-desktop nmap || true

fix_broken_packages
wrap_browsers
setup_vnc
cleanup_image

rm /setup.sh
EOF

sudo chmod +x ./kali-rootfs/setup.sh

# 4. Enter Jail & Build
echo "Entering Jail to Compile..."
folder="kali-rootfs"
sudo proot -q qemu-aarch64-static -0 -r $folder -b /dev -b /proc -b /sys -w /root /usr/bin/env -i /bin/bash /setup.sh

# 5. Package
echo "Packaging Release..."
tar -cJpf kali-fs.tar.xz -C ./kali-rootfs .

echo "Build Complete: kali-fs.tar.xz"