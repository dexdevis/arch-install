#!/usr/bin/bash

################################################
##### Orologio
################################################

# Enable systemd-timesyncd
systemctl enable systemd-timesyncd.service

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

################################################
##### Impostazione della lingua
################################################

# Locale
echo "it_IT.UTF-8 UTF-8" > /etc/locale.gen
echo "LANG=\"it_IT.UTF-8\"" > /etc/locale.conf
locale-gen

# Keymap
echo "KEYMAP=it" > /etc/vconsole.conf

################################################
##### Hostname
################################################

# Set hostname
echo ${NEW_HOSTNAME} > /etc/hostname

# Set /etc/hosts
tee /etc/hosts << EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${NEW_HOSTNAME}.localdomain ${NEW_HOSTNAME}
EOF

################################################
##### Pacman
################################################

# Abilita repository multilib
sed -i '/#\[multilib\]/{N;s/#\[multilib\]\n#Include = \/etc\/pacman.d\/mirrorlist/\[multilib\]\nInclude = \/etc\/pacman.d\/mirrorlist/}' /etc/pacman.conf
pacman -Syy

# Inizializza il keyring di pacman
pacman-key --init
pacman-key --populate

# Configura Pacman
sed -i "s|^#Color|Color|g" /etc/pacman.conf
sed -i "s|^#VerbosePkgLists|VerbosePkgLists|g" /etc/pacman.conf
sed -i "s|^#ParallelDownloads.*|ParallelDownloads = 5|g" /etc/pacman.conf

# Aggiorna il sistema
pacman -Syu

################################################
##### Installa applicazioni di base
################################################

pacman -S --noconfirm base-devel nano btrfs-progs grub efibootmgr sudo bash-completion dialog wpa_supplicant mtools dosfstools coreutils util-linux inetutils xdg-utils xdg-user-dirs alsa-utils htop git p7zip unzip unrar which man-db man-pages rsync ufw zram-generator net-tools

################################################
##### zram (swap)
################################################

# Configura zram generator
tee /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
EOF

systemctl daemon-reload
systemctl start /dev/zram0
echo 'vm.page-cluster=0' > /etc/sysctl.d/99-page-cluster.conf
echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
echo 'vm.vfs_cache_pressure=50' > /etc/sysctl.d/99-vfs-cache-pressure.conf


################################################
##### Utenti
################################################

# Setta la password di root
echo -en "${NEW_USER_PASSWORD}\n${NEW_USER_PASSWORD}" | passwd

# Setup nuovo utente
useradd -m -G wheel ${NEW_USER}
echo -en "${NEW_USER_PASSWORD}\n${NEW_USER_PASSWORD}" | passwd ${NEW_USER}
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Crea le cartelle utente
sudo -u ${NEW_USER} LC_ALL=it_IT.UTF-8 xdg-user-dirs-update --force 

################################################
##### Firewall e rete                      
################################################

systemctl enable ufw.service
ufw default allow outgoing
ufw default deny incoming
ufw logging off
ufw enable

# Chiedo in input i nomi delle interfacce di rete e i dati della rete wifi
clear
ip link
read -p "Inserire il nome della scheda di rete Ethernet: " ETH
read -p "Inserire il nome della scheda di rete Wifi ([ n ] se non presente): " WIFI
clear

if [[ ${WIFI} != "n" ]]; then
    read -p "Inserire il nome della rete Wifi: " ESSID
    read -sp "Inserire la password: " PASS 

    # Creo il file di configurazione dell'interfaccia Wifi
    tee /etc/wpa_supplicant/wpa_supplicant-${WIFI}.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
eapol_version=1
ap_scan=1
fast_reauth=1

EOF

    # Creo la configurazione per la connessione Wireless
    tee /etc/systemd/network/25-wireless.network << EOF
[Match]
Name=${WIFI}

[Network]
DHCP=yes
IgnoreCarrierLoss=3s
DNS=1.1.1.1 1.0.0.1

[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600
EOF
fi

# Creo la configurazione per la connessione Ethernet
tee /etc/systemd/network/20-wired.network << EOF
[Match]
Name=${ETH}

[Network]
DHCP=yes
DNS=1.1.1.1 1.0.0.1

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100
EOF

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service

if [[ ${WIFI} != "n" ]]; then
    wpa_passphrase ${ESSID} ${PASS} >> /etc/wpa_supplicant/wpa_supplicant-${WIFI}.conf

    # Cancella la password in chiaro
    sed -i "/#psk=/d" /etc/wpa_supplicant/wpa_supplicant-${WIFI}.conf
    systemctl enable wpa_supplicant@${WIFI}.service
fi

################################################
##### Initramfs
################################################

# Configura mkinitcpio
sed -i "s|MODULES=()|MODULES=(btrfs${MKINITCPIO_MODULES})|" /etc/mkinitcpio.conf
mkinitcpio -P

################################################
##### GRUB
################################################

clear
grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=GRUB
sed -i "s|GRUB_TIMEOUT=5|GRUB_TIMEOUT=0|g" /etc/default/grub
if cat /proc/cpuinfo | grep "vendor" | grep "AuthenticAMD" > /dev/null; then
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 ${AMD_SCALING_DRIVER}\"|g" /etc/default/grub
else
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3\"|g" /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

################################################
##### GPU
################################################

# Installa i drivers della GPU
pacman -S --noconfirm mesa vulkan-icd-loader vulkan-mesa-layers ${GPU_PACKAGES}

# Sovrascrivi i driver VA-API tramite variable d'ambiente
tee -a /etc/environment << EOF

# VA-API
${LIBVA_ENV_VAR}
EOF

# Se la GPU è AMD, usa i driver Vulkan RADV
if lspci | grep "VGA" | grep "AMD" > /dev/null; then
tee -a /etc/environment << EOF

# Vulkan
AMD_VULKAN_ICD=RADV
EOF
fi

# Installa VA-API tools
pacman -S --noconfirm libva-utils

# Installa Vulkan tools
pacman -S --noconfirm vulkan-tools

################################################
##### Systemd
################################################

# Configura il timeout di default per le unità di sistema
mkdir -p /etc/systemd/system.conf.d
tee /etc/systemd/system.conf.d/default-timeout.conf << EOF
[Manager]
DefaultTimeoutStopSec=5s
EOF

# Configura il timeout di default per le unità utente
mkdir -p /etc/systemd/user.conf.d
tee /etc/systemd/user.conf.d/default-timeout.conf << EOF
[Manager]
DefaultTimeoutStopSec=5s
EOF

################################################
##### GStreamer
################################################

#pacman -S --noconfirm gstreamer gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi

################################################
##### Fonts
################################################

#pacman -S --noconfirm noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra ttf-liberation otf-cascadia-code otf-commit-mono-nerd ttf-firacode-nerd ttf-hack-nerd ttf-noto-nerd ttf-sourcecodepro-nerd ttf-ubuntu-nerd ttf-ubuntu-mono-nerd ttf-hack inter-font cantarell-fonts otf-font-awesome

################################################
##### Power Management
################################################

if [[ $(cat /sys/class/dmi/id/chassis_type) -eq 10 ]]; then
    # Attiva il risparmio energetico sull'audio
    echo 'options snd_hda_intel power_save=1' > /etc/modprobe.d/audio_powersave.conf

    # Attiva il risparmio energetico sul wifi
    echo 'options iwlwifi power_save=1' > /etc/modprobe.d/iwlwifi.conf

    mkinitcpio -P
else
    if lspci | grep "VGA" | grep "AMD" > /dev/null; then
        # Setta il livello di performance delle GPU AMD al livello minimo
        echo 'SUBSYSTEM=="pci", DRIVER=="amdgpu", ATTR{power_dpm_force_performance_level}="low"' > /etc/udev/rules.d/30-amdgpu-high-power.rules
    fi
fi

# Installa e abilita thermald per le CPU Intel
if [[ $(cat /proc/cpuinfo | grep vendor | uniq) =~ "GenuineIntel" ]]; then
    pacman -S --noconfirm thermald
    systemctl enable thermald.service
fi

# Intalla e abilita TLP
pacman -S --noconfirm tlp
systemctl enable tlp.service

################################################
##### Fine installazione
################################################

# Attribuisce correttamente i permessi alla home del nuovo utente
chown -R ${NEW_USER}:${NEW_USER} /home/${NEW_USER}

# Esce da chroot
exit
