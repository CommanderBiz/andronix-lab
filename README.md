# CommanderBiz Linux on Android (ARM64)

This project provides highly optimized, crash-proof builds of popular Linux distributions for Android using Termux and PRoot. These builds are created from source to bypass common PRoot errors and come with pre-patched components for a smoother experience.

## Available Distributions

*   [Kali Linux](#kali-linux)
*   [Ubuntu](#ubuntu)

---

## Kali Linux

A full-featured Kali Linux environment with a pre-configured VNC server for GUI access.

### 🚀 Quick Install (The One-Liner)

Copy and paste this into Termux:

```bash
pkg install wget -y && pkg rm -rf install.sh kali-fs && wget https://raw.githubusercontent.com/commanderbiz/andronix-lab/main/install.sh && bash install.sh
```

---

## Ubuntu

A minimal Ubuntu server environment. It includes a script to install a full XFCE desktop environment.

### 🚀 Quick Install (The One-Liner)

Copy and paste this into Termux:

```bash
pkg install wget -y && wget -O install_ubuntu.sh https://raw.githubusercontent.com/commanderbiz/andronix-lab/main/ubuntu/install.sh && bash install_ubuntu.sh
```

After the minimal installation is complete, you can start the Ubuntu environment with `./start-ubuntu.sh`.

Inside the Ubuntu environment, you can install the XFCE desktop and Brave browser by running:
```bash
/root/complete_install.sh
```
