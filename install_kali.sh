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

# Patching Browsers
wrap_browsers() {
    echo "Wrapping Browsers with Safety Flags..."

    # 1. Firefox Wrapper
    if [ -f /usr/bin/firefox-esr ]; then
        # Rename the real binary
        mv /usr/bin/firefox-esr /usr/bin/firefox-esr.real
        
        # Create a fake binary that calls the real one with our flag
        cat <<BASH > /usr/bin/firefox-esr

#!/bin/bash
export MOZ_FAKE_NO_SANDBOX=1
exec /usr/bin/firefox-esr.real "\$@"
BASH
        
        # Make it executable
        chmod +x /usr/bin/firefox-esr
        echo "Firefox wrapped."
    fi

    # 2. Chromium Wrapper
    if [ -f /usr/bin/chromium ]; then
        mv /usr/bin/chromium /usr/bin/chromium.real
        cat <<BASH > /usr/bin/chromium
#!/bin/bash
exec /usr/bin/chromium.real --no-sandbox --test-type --disable-dev-shm-usage --user-data-dir=/root/.config/chromium "\$@"
BASH
        chmod +x /usr/bin/chromium
        echo "Chromium wrapped."
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
wrap_browsers

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