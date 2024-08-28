# Script di installazione di arch linux con filesystem Btrfs

ATTENZIONE: l'esecuzione dello script installa.sh cancellerà l'intero disco senza richiedere conferma.

## Requisiti

- UEFI
- NVMe SSD
- GPU singola (Intel o AMD)

## Guida all'installazione 

1. Aggiornare i repositories e installare git: `pacman -Sy git`
2. Se il primo comando fallisce rinizializzare il keyring: `pacman-key --init && pacman-key --populate`
3. Clona il repository: `git clone https://github.com/dexdevis/arch-install.git`
5. L'SSD di default dello script è nvme0n1. Per verificare gli hard disk installati sul proprio pc lanciare il comando: `lsblk`
5. Se il nome dell'SSD differisce da nvme0n1, modificare manualmente lo script installa.sh
6. Eseguire lo script: `cd arch-linux && ./installa.sh`
