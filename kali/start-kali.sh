#!/bin/bash

sudo proot -S ./kali-rootfs -b /dev -b /proc -b /sys /bin/bash
