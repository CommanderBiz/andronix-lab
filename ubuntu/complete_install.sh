#!/bin/bash
set -e

echo "--- Starting Desktop and Browser Installation ---"

# --- Environment Setup ---
export DEBIAN_FRONTEND=noninteractive

# --- Update APT and Install Desktop ---
echo "[*] Updating package lists and installing desktop environment..."
apt-get update
apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server nmap curl gpg

# --- Install Brave Browser ---
echo "[*] Installing Brave Browser..."
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update
apt-get install -y brave-browser

# --- Configure Desktop and Browser ---
echo "[*] Configuring desktop and browser..."
if dpkg -s brave-browser &> /dev/null; then
    find /usr/share/applications -name "brave-browser*.desktop" -print0 | while IFS= read -r -d $'
' desktop_file; do
        if [ -f "$desktop_file" ]; then
            echo "Patching $desktop_file..."
            if ! grep -q -- "--no-sandbox" "$desktop_file"; then
                sed -i 's|\(Exec=[^ ]*\)|\1 --no-sandbox --test-type --disable-dev-shm-usage|' "$desktop_file"
            fi
        fi
    done
    BRAVE_DESKTOP_FILE=$(find /usr/share/applications -name "brave-browser*.desktop" ! -name "*private*" ! -name "*incognito*" -print -quit)
    if [ -n "$BRAVE_DESKTOP_FILE" ]; then
        BRAVE_DESKTOP_BASENAME=$(basename "$BRAVE_DESKTOP_FILE")
        mkdir -p /root/.config/xfce4
        echo "Setting default browser to $BRAVE_DESKTOP_BASENAME..."
        echo -e "[Desktop Entry]\nWebBrowser=$BRAVE_DESKTOP_BASENAME" > /root/.config/xfce4/helpers.rc
    fi
fi

# --- Configure VNC ---
echo "[*] Configuring VNC..."
mkdir -p /root/.vnc
echo -e "#!/bin/sh\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\n/usr/bin/dbus-launch --exit-with-session /usr/bin/startxfce4" > /root/.vnc/xstartup
chmod +x /root/.vnc/xstartup
echo "Please set your VNC password now."
vncpasswd

# --- Final README ---
mkdir -p /root/Desktop
cat <<README > /root/Desktop/README.txt
Welcome to Ubuntu Noble on Termux!
Your desktop environment is now installed.
To start VNC server, run 'vncserver'.
The default password is the one you just set.
Enjoy your system!
README

echo "--- Installation Complete ---"
echo "You can now start a VNC server by running 'vncserver' and connect to it."
