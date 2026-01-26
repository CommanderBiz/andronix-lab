#!/bin/bash
set -x
# This script automates the process of building a custom Ubuntu Noble (24.04 LTS) root filesystem
# specifically tailored for use within Termux on Android devices.
#
# The final output is a compressed tarball (ubuntu-fs.tar.xz) that can be
# downloaded and extracted by an end-user installer script.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Building Base System (Ubuntu Noble 24.04 LTS)..."

# --- PART 1: Build Environment Setup ---

ARCH="arm64"
echo "Target Architecture: $ARCH"

echo "Performing a clean slate by removing old 'ubuntu-rootfs' and '*.tar.xz'..."
sudo rm -rf ubuntu-rootfs ubuntu-fs.tar.xz
mkdir ubuntu-rootfs

echo "Bootstrapping Ubuntu Noble for $ARCH..."
#
# The --no-check-gpg flag is used here because this script is intended to be run
# on an amd64 host to build an arm64 root filesystem for Termux. In this cross-architecture
# debootstrap scenario, configuring apt/debootstrap on the host to properly verify
# GPG keys for a foreign architecture can be complex and may not be straightforward
# to automate reliably.
#
# For a more secure setup, it is recommended to ensure the amd64 host system has
# the Ubuntu GPG keys properly installed and configured for multi-arch support,
# and then remove the --no-check-gpg flag.
#
sudo debootstrap --arch=$ARCH --no-check-gpg --include=nano,wget,dbus-x11,ubuntu-keyring noble ./ubuntu-rootfs http://ports.ubuntu.com/ubuntu-ports/


# --- PART 2: The Internal Setup Script ---

echo "Generating the internal setup script (setup.sh)..."
cat <<'EOF' > ./ubuntu-rootfs/setup.sh
#!/bin/bash
set -e

# --- Environment Setup (inside the jail) ---
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

# --- Hydrate Repositories ---
echo "Hydrating Repositories..."
cat > /etc/apt/sources.list <<SOURCES
deb http://ports.ubuntu.com/ubuntu-ports/ noble main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
SOURCES

# --- APT Workarounds for QEMU ---
# Disable HTTP pipelining to work around a bug in apt's http method that
# can cause a "double free or corruption" error under qemu-static.
echo 'Acquire::http::Pipeline-Depth "0";' > /etc/apt/apt.conf.d/99-no-pipelining
# `apt-get update` frequently encounters a "double free or corruption" error
# when run under qemu-static emulation within proot. This issue is difficult
# to resolve directly at the script level.
# The `|| true` is used here to prevent the script from halting, but it means
# the apt package lists might not be fully updated, leading to an incomplete
# installation. Users may need to manually run `apt update` and `apt install`
# inside the Termux environment after the rootfs is extracted to complete the installation.
apt-get update || true

# --- Function: Neutralize Systemd ---
nuke_systemd() {
    echo "Neutralizing Systemd post-installation scripts..."
    # Systemd cannot function correctly within a proot environment.
    # This function prevents systemd-related packages from failing during
    # post-installation by patching their postinst scripts to simply exit 0.
    local offenders=("systemd" "udev")
    for pkg in "${offenders[@]}"; do
        if [ -f "/var/lib/dpkg/info/${pkg}.postinst" ]; then
            echo -e "#!/bin/sh\nexit 0" > "/var/lib/dpkg/info/${pkg}.postinst"
        fi
    done
    dpkg --configure -a
}

# --- Function: Fix Broken Packages ---
fix_broken_packages() {
    echo "Applying workarounds for known broken packages..."
    # Certain packages have post-installation or pre-removal scripts that
    # are incompatible with the proot environment.
    # This function patches their scripts to exit 0, disabling problematic
    # steps and allowing the packages to be installed/configured without errors.
    local broken=("fuse3" "ntfs-3g" "desktop-base")
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
    apt-get update || true
}

# --- Function: Configure Desktop and Browser ---
configure_desktop_and_browser() {
    echo "Configuring Brave Browser, setting defaults, and creating README..."

    # Patch all Brave Browser .desktop files to run without a sandbox.
    # The --no-sandbox flag is necessary in proot environments like Termux
    # due to kernel/filesystem limitations that prevent sandboxing.
    find /usr/share/applications -name "brave-browser*.desktop" -print0 | while IFS= read -r -d $'/0' desktop_file; do
        if [ -f "$desktop_file" ]; then
            echo "Patching $desktop_file..."
            if ! grep -q -- "--no-sandbox" "$desktop_file"; then
                sed -i 's|\(Exec=[^ ]*\)|\1 --no-sandbox --test-type --disable-dev-shm-usage|' "$desktop_file"
            fi
        fi
    done

    # Find the correct .desktop file to set as the default.
    BRAVE_DESKTOP_FILE=$(find /usr/share/applications -name "brave-browser*.desktop" ! -name "*private*" ! -name "*incognito*" -print -quit)

    if [ -n "$BRAVE_DESKTOP_FILE" ]; then
        BRAVE_DESKTOP_BASENAME=$(basename "$BRAVE_DESKTOP_FILE")
        mkdir -p /root/.config/xfce4
        echo "Setting default browser to $BRAVE_DESKTOP_BASENAME..."
        echo -e "[Desktop Entry]\nWebBrowser=$BRAVE_DESKTOP_BASENAME" > /root/.config/xfce4/helpers.rc
    else
        echo "WARNING: Could not find a suitable brave-browser.desktop file. Default browser may not be set."
    fi

    # Create a helpful README file on the root's desktop.
    mkdir -p /root/Desktop
    cat <<README > /root/Desktop/README.txt
Welcome to Ubuntu Noble on Termux!

Your default VNC password is: ubuntu

To change this password, open a terminal and run the command:
vncpasswd

Enjoy your system!
README
}

# --- Function: Setup TigerVNC ---
setup_vnc() {
    echo "Configuring VNC with robust startup script..."
    mkdir -p /root/.config/tigervnc
    echo "ubuntu" | vncpasswd -f > /root/.config/tigervnc/passwd
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
# Some packages may fail to install properly in a proot environment
# due to limited root access or kernel features. `|| true` is used here to
# prevent these expected failures from halting the entire installation process.
apt-get install -y xfce4 xfce4-goodies exo-utils tigervnc-standalone-server nmap || true

echo "Applying package fixes for desktop environment..."
fix_broken_packages

echo "Completing desktop installation..."
apt-get install -f -y

# --- Configure VNC ---
setup_vnc

# --- Install and Configure Brave Browser ---
echo "Installing Brave Browser..."
setup_brave_repo
for i in {1..3}; do
    apt-get install -y brave-browser && break
    echo "Brave installation failed. Retrying (attempt $i of 3)..."
    sleep 5
done

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

sudo chmod +x ./ubuntu-rootfs/setup.sh

echo "Entering proot jail to compile and configure the system..."
QEMU_STATIC_PATH="qemu-$(echo $ARCH | sed 's/arm64/aarch64/')"
if [ -f "/usr/bin/$QEMU_STATIC_PATH-static" ]; then
    sudo cp "/usr/bin/$QEMU_STATIC_PATH-static" "./ubuntu-rootfs/usr/bin/"
fi
# The `|| true` is critical here. The internal setup script may encounter non-fatal
# errors (like the apt-get update issue), and this ensures the main build
# script continues to the final packaging step regardless.
sudo proot -q "$QEMU_STATIC_PATH-static" -0 -r ./ubuntu-rootfs -b /dev -b /proc -b /sys -w /root /usr/bin/env -i /bin/bash /setup.sh || true

echo "Packaging the final root filesystem into 'ubuntu-fs.tar.xz'..."
sudo tar -cJpf ubuntu-fs.tar.xz -C ./ubuntu-rootfs .

echo "Build Complete: ubuntu-fs.tar.xz"

# --- End of Script ---
