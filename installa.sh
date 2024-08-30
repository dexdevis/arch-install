#!/usr/bin/bash

clear

read -p "Inserire un nuovo utente: " NEW_USER
export NEW_USER

read -sp "Password del nuovo utente: " NEW_USER_PASSWORD
export NEW_USER_PASSWORD
echo -e "\n"

read -p "Abilitare l'autologin per il nuovo utente [ s|n ]: " AUTOLOGIN
export AUTOLOGIN

read -p "Nome Host del computer: " NEW_HOSTNAME
export NEW_HOSTNAME

# Determina la CPU
if cat /proc/cpuinfo | grep "vendor" | grep "GenuineIntel" > /dev/null; then
    export CPU_MICROCODE="intel-ucode"
elif cat /proc/cpuinfo | grep "vendor" | grep "AuthenticAMD" > /dev/null; then
    export CPU_MICROCODE="amd-ucode"
    export AMD_SCALING_DRIVER="amd_pstate=active"
fi

# Determina la GPU
if lspci | grep "VGA" | grep "Intel" > /dev/null; then
    export GPU_PACKAGES="vulkan-intel intel-media-driver intel-gpu-tools"
    export MKINITCPIO_MODULES=" i915"
    export LIBVA_ENV_VAR="LIBVA_DRIVER_NAME=iHD"
elif lspci | grep "VGA" | grep "AMD" > /dev/null; then
    export GPU_PACKAGES="vulkan-radeon libva-mesa-driver radeontop"
    export MKINITCPIO_MODULES=" amdgpu"
    export LIBVA_ENV_VAR="LIBVA_DRIVER_NAME=radeonsi"
fi

################################################
##### Partiziona il disco 
################################################

# Legge la tabella partizioni
partprobe /dev/nvme0n1 # <----------------------------------

# Cancella il disco
wipefs -af /dev/nvme0n1 # <-------------------------------
sgdisk --zap-all --clear /dev/nvme0n1 # <----------------------------------
partprobe /dev/nvme0n1 # <----------------------------------

# Partiziona il disco
sgdisk -n 1:0:+300M -t 1:ef00 /dev/nvme0n1 # <----------------------------------
sgdisk -n 2:0:0 -t 2:8300 /dev/nvme0n1 # <----------------------------------
partprobe /dev/nvme0n1 # <----------------------------------

# Formatta le partizioni
mkfs.btrfs /dev/nvme0n1p2 # <----------------------------------
mkfs.fat -F32 /dev/nvme0n1p1 # <----------------------------------

# Crea i sottovolumi
mount /dev/nvme0n1p2 /mnt # <----------------------------------
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
umount /mnt

# Monta i sottovolumi
mount -o noatime,compress=zstd,subvol=@ /dev/nvme0n1p2 /mnt # <----------------------------------
mkdir -p /mnt/home
mkdir -p /mnt/boot/efi
mount -o noatime,compress=zstd,subvol=@home /dev/nvme0n1p2 /mnt/home # <----------------------------------
mount /dev/nvme0n1p1 /mnt/boot/efi # <----------------------------------


################################################
##### Installa il sistema base
################################################

# Importa la mirrorlist
tee /etc/pacman.d/mirrorlist << 'EOF'
Server = https://europe.mirror.pkgbuild.com/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://it.mirrors.cicku.me/archlinux/$repo/os/$arch
EOF

# Sincronizza i pacchetti
pacman -Syy

# Installa i pacchetti base
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware nano btrfs-progs ${CPU_MICROCODE}

# Genera fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configura il sistema
mkdir -p /mnt/installa-arch
cp ./configura.sh /mnt/installa-arch/configura.sh
arch-chroot /mnt /bin/bash /installa-arch/configura.sh
rm -rf /mnt/installa-arch
umount -R /mnt
