sudo apt-mark hold linux-image-raspi linux-headers-raspi linux-firmware

log_i "Installing updates (if any)"
DEBIAN_FRONTEND=noninteractive apt upgrade --yes

log_i "Autoremoving old packages (if any)"
DEBIAN_FRONTEND=noninteractive apt autoremove --yes

sudo apt-mark unhold linux-image-raspi linux-headers-raspi linux-firmware
