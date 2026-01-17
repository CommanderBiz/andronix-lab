#!/bin/bash

rm -rf kali-fs
mkdir kali-fs

proot --link2symlink tar -xJf kali-fs.tar.xz -C kali-fs --exclude='dev*'
