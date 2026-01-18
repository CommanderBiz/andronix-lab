#!/bin/bash
# This script automates the process of building a custom Kali Linux root filesystem
# specifically tailored for use within Termux on Android devices.
#
# Version: 4.2 - The Commander Edition (Robust Install Order)
#
# The final output is a compressed tarball (kali-fs.tar.xz) that can be
# downloaded and extracted by an end-user installer script.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Building Base System (Version 4.2 - The Commander Edition)..."

# --- PART 1: Build Environment Setup ---

# --- Target Architecture ---
# We hardcode the architecture to 'arm64' (also known as aarch64) because
# the target platform is modern Android devices running Termux.
ARCH="arm64"
echo "Target Architecture: $ARCH"

# --- Clean Slate ---
# To ensure a fresh build every time, we remove any artifacts from previous runs.
echo "Performing a clean slate by removing old 'kali-rootfs' and '*.tar.xz'..."
sudo rm -rf kali-rootfs kali-fs.tar.xz
mkdir kali-rootfs

# --- Bootstrap ---
# 'debootstrap' is a tool to create a basic Debian-based system from scratch.
echo "Bootstrapping the Kali Rolling release for $ARCH..."
sudo debootstrap --arch=$ARCH --no-check-gpg --include=nano,wget,dbus-x11 kali-rolling ./kali-rootfs https://kali.download/kali/


# --- PART 2: The Internal Setup Script ---

# --- Generate Internal Script ---
# This 'heredoc' creates a shell script INSIDE the new filesystem.
# This script will be executed within the 'proot' jail to perform the setup.
echo "Generating the internal setup script (setup.sh)..."
cat <<'EOF' > ./kali-rootfs/setup.sh
#!/bin/bash
set -e

# --- Environment Setup (inside the jail) ---
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

# --- Hydrate Repositories ---
echo "Hydrating Repositories..."
echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list
apt-get update

# --- Function: Neutralize Systemd ---
# Overwrites problematic systemd-related scripts that fail in a proot environment.
nuke_systemd() {
    echo "Neutralizing Systemd post-installation scripts..."
    local offenders=("systemd" "udev" "systemd-resolved" "systemd-timesyncd")
    for pkg in "${offenders[@]}"; do
        if [ -f "/var/lib/dpkg/info/${pkg}.postinst" ]; then
            echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/${pkg}.postinst"
        fi
    done
    dpkg --configure -a
}

# --- Function: Fix Broken Packages ---
# Applies workarounds for other known fragile package installation scripts.
fix_broken_packages() {
    echo "Applying workarounds for known broken packages..."
    local broken=("fuse3" "ntfs-3g" "poppler-data" "kali-desktop-base" "desktop-base")
    for pkg in "${broken[@]}"; do
        if [ -f "/var/lib/dpkg/info/${pkg}.postinst" ]; then
            echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/${pkg}.postinst"
        fi
        if [ -f "/var/lib/dpkg/info/${pkg}.prerm" ]; then
            echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/${pkg}.prerm"
        fi
    done
    dpkg --configure -a
}

# --- Function: Add Brave Browser Repository ---
setup_brave_repo() {
    echo "Setting up Brave Browser repository..."
    apt-get install -y curl gpg
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list
    apt-get update
}

# --- Function: Configure Desktop and Browser ---
configure_desktop_and_browser() {
    echo "Configuring Brave Browser, setting defaults, and creating README..."

    # Patch Brave Browser's .desktop files to run without a sandbox.
    find /usr/share/applications -name "brave-browser*.desktop" -print0 | while IFS= read -r -d $'\0' desktop_file; do
        if [ -f "$desktop_file" ]; then
            echo "Patching $desktop_file..."
            if ! grep -q -- "--no-sandbox" "$desktop_file"; then
                sed -i 's|\(Exec=[^ ]*\)|\1 --no-sandbox --test-type --disable-dev-shm-usage|' "$desktop_file"
            fi
        fi
    done

    # Set Brave as the default web browser for XFCE.
    mkdir -p /root/.config/xfce4
    echo "[Desktop Entry]\nWebBrowser=brave-browser.desktop" > /root/.config/xfce4/helpers.rc

    # Create a helpful README file on the root's desktop.
    mkdir -p /root/Desktop
    cat <<README > /root/Desktop/README.txt
Welcome to The Commander Edition!

Your default VNC password is: kali

To change this password, open a terminal and run the command:
vncpasswd

Enjoy your system!
README
}

# --- Function: Setup TigerVNC ---
setup_vnc() {
    echo "Configuring VNC with robust startup script..."
    mkdir -p /root/.config/tigervnc
    echo "kali" | vncpasswd -f > /root/.config/tigervnc/passwd
    chmod 600 /root/.config/tigervnc/passwd
    echo -e "#!/bin/sh\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\n/usr/bin/dbus-launch --exit-with-session /usr/bin/startxfce4" > /root/.config/tigervnc/xstartup
    chmod +x /root/.config/tigervnc/xstartup
}

# --- Function: Cleanup ---
cleanup_image() {
    echo "Cleaning up the image to reduce size..."
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/*
}

# --- EXECUTION (inside the jail) ---

nuke_systemd

# --- Install Desktop and VNC ---
echo "Installing Desktop, VNC & Core Tools..."
# We use a two-step installation process to handle expected dpkg errors gracefully.
apt-get install -y --allow-unauthenticated xfce4 xfce4-goodies tigervnc-standalone-server kali-themes kali-defaults-desktop nmap || true

echo "Applying package fixes for desktop environment..."
fix_broken_packages

echo "Completing desktop installation..."
apt-get install -f -y --allow-unauthenticated

# --- Configure VNC ---
# Now that the VNC server is guaranteed to be installed, we can configure it.
setup_vnc

# --- Install and Configure Brave Browser ---
echo "Installing Brave Browser..."
setup_brave_repo
# We add a retry loop here to guard against transient network errors during the download.
for i in {1..3}; do
    apt-get install -y --allow-unauthenticated brave-browser && break
    echo "Brave installation failed. Retrying (attempt $i of 3)..."
    sleep 5
done

# Check if brave-browser is installed before trying to configure it
if dpkg -s brave-browser &> /dev/null; then
    configure_desktop_and_browser
else
    echo "WARNING: Brave Browser installation failed after 3 attempts. Skipping browser configuration."
fi

# --- Final Cleanup ---
cleanup_image

# Self-destruct the setup script.
rm /setup.sh

EOF
# --- End of Internal Script Generation ---


# --- PART 3: Execution and Packaging ---

# Make the internal script executable.
sudo chmod +x ./kali-rootfs/setup.sh

# --- Enter Jail & Build ---
echo "Entering proot jail to compile and configure the system..."
QEMU_STATIC_PATH="qemu-$(echo $ARCH | sed 's/arm64/aarch64/')"
if [ -f "/usr/bin/$QEMU_STATIC_PATH-static" ]; then
    sudo cp "/usr/bin/$QEMU_STATIC_PATH-static" "./kali-rootfs/usr/bin/"
fi
sudo proot -q "$QEMU_STATIC_PATH-static" -0 -r ./kali-rootfs -b /dev -b /proc -b /sys -w /root /usr/bin/env -i /bin/bash /setup.sh

# --- Package ---
echo "Packaging the final root filesystem into 'kali-fs.tar.xz'..."
sudo tar -cJpf kali-fs.tar.xz -C ./kali-rootfs .

echo "Build Complete: kali-fs.tar.xz"
echo "You can now use this tarball with the Termux Kali installer script."
# --- End of Script ---