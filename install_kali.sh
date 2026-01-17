#!/bin/bash
echo "Building Base System (Version 2.0)..."

# 1. Clean Slate
sudo rm -rf kali-rootfs kali-fs.tar.xz
mkdir kali-rootfs 

# 2. Bootstrap
sudo debootstrap --arch=arm64 --no-check-gpg --include=nano,wget,dbus-x11 kali-rolling ./kali-rootfs https://kali.download/kali/ 

# 3. Create the Setup Script
cat <<EOF > ./kali-rootfs/setup.sh
#!/bin/bash

# Fix PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "Updating sources..."
apt update

# --- FUNCTION DEFINITIONS ---

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

patch_browsers() {
    echo "Patching Browser Shortcuts..."
    
    # 1. Patch Firefox
    # We use sed to find the 'Exec=' line and inject the flag
    if [ -f /usr/share/applications/firefox-esr.desktop ]; then
        sed -i 's|Exec=/usr/lib/firefox-esr/firefox-esr %u|Exec=env MOZ_FAKE_NO_SANDBOX=1 /usr/lib/firefox-esr/firefox-esr %u|g' /usr/share/applications/firefox-esr.desktop
        echo "Firefox patched."
    fi

    # 2. Patch Chromium
    # We replace the Exec line with our safe mode flags
    if [ -f /usr/share/applications/chromium.desktop ]; then
        sed -i 's|Exec=/usr/bin/chromium %U|Exec=/usr/bin/chromium --no-sandbox --test-type --disable-dev-shm-usage --user-data-dir=/root/.config/chromium %U|g' /usr/share/applications/chromium.desktop
        echo "Chromium patched."
    fi
}

cleanup_image() {
    rm -rf /var/lib/apt/lists/*
    rm -rf /var/cache/apt/*.bin
    rm -rf /tmp/*
}

# --- EXECUTION ---

nuke_systemd

echo "Installing Desktop & Browsers..."
# ADDED: firefox-esr and chromium to the install list
DEBIAN_FRONTEND=noninteractive apt install -y xfce4 tigervnc-standalone-server firefox-esr chromium || true

fix_broken_packages

# ADDED: Run the patcher
patch_browsers

cleanup_image
rm /setup.sh
EOF

sudo chmod +x ./kali-rootfs/setup.sh

# 4. Enter Build
echo "Entering Kali..."
folder="kali-rootfs"
sudo proot -q qemu-aarch64-static -0 -r $folder -b /dev -b /proc -b /sys -w /root /usr/bin/env -i /bin/bash /setup.sh

# 5. Package
echo "Packaging Release..."
tar -cJpf kali-fs.tar.xz -C ./kali-rootfs .

echo "Build Complete: kali-fs.tar.xz"