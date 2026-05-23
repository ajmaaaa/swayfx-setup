# Arch Swayfx Setup

Simple automated Arch Linux setup using:

- SwayFX
- Alacritty
- Swappy
- Rofi
- Celestial SDDM
- Powerlevel10k

---

# Installation

```bash
git clone https://github.com/ajmaaaa/swayfx-setup.git
cd swayfx-stup
chmod +x install.sh
./install.sh
```

> Do not run the script as root.

---

# Repository Structure

```bash
swayfx-setup/
├── install.sh
├── packages/
│   ├── pacman.txt
│   ├── aur.txt
│   ├── npm.txt
│   └── services.txt
├── config/
│   ├── sway/
│   ├── swappy/
│   └── alacritty/
├── sddm/
│   └── celestial-sddm/
```

---

# Notes

- Arch Linux only
- Internet connection required
- Reboot recommended after installation
