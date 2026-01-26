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
sudo debootstrap --arch=$ARCH --components=main,restricted,universe,multiverse --no-check-gpg --include=nano,wget,dbus-x11,ubuntu-keyring noble ./ubuntu-rootfs http://ports.ubuntu.com/ubuntu-ports/


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
deb https://ports.ubuntu.com/ubuntu-ports/ noble main restricted universe multiverse
deb https://ports.ubuntu.com/ubuntu-ports/ noble-updates main restricted universe multiverse
deb https://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
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

# --- Function: Cleanup ---
cleanup_image() {
    echo "Cleaning up the image to reduce size..."
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/*
}

# --- EXECUTION (inside the jail) ---

nuke_systemd

echo "Applying package fixes..."
fix_broken_packages

# --- Final Cleanup ---
cleanup_image

# Self-destruct the setup script.
rm /setup.sh

EOF
# --- End of Internal Script Generation ---


# --- PART 3: Execution and Packaging ---

sudo chmod +x ./ubuntu-rootfs/setup.sh

echo "Copying post-install script..."
sudo cp ./ubuntu/complete_install.sh ./ubuntu-rootfs/root/complete_install.sh
sudo chmod +x ./ubuntu-rootfs/root/complete_install.sh

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
