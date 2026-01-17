#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD

# Force DNS to Google
echo "nameserver 8.8.8.8" > kali-fs/etc/resolv.conf

# The Magic Line: Binding Android's real hardware to your OS
proot --link2symlink -0 -r kali-fs \
    -b /dev \
    -b $PREFIX/tmp:/dev/shm \
    -b /proc \
    -b /sys \
    -w /root \
    /usr/bin/env -i HOME=/root TERM=xterm-256color PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin /bin/bash --login
