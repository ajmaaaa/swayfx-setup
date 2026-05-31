#!/bin/bash

# =============================================================================
# ARCH SETUP INSTALLER
# Automated Arch Linux post-install setup script
# =============================================================================

set -e

# =============================================================================
# COLORS & HELPERS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

# =============================================================================
# ROOT CHECK
# =============================================================================

if [[ "$EUID" -eq 0 ]]; then
  error "Do not run this script as root. Run as a standard user."
fi

# =============================================================================
# PATHS & REQUIREMENT CHECK
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACMAN_FILE="$SCRIPT_DIR/packages/pacman.txt"
AUR_FILE="$SCRIPT_DIR/packages/aur.txt"
NPM_FILE="$SCRIPT_DIR/packages/npm.txt"
SERVICES_FILE="$SCRIPT_DIR/packages/services.txt"

for file in "$PACMAN_FILE" "$AUR_FILE" "$NPM_FILE" "$SERVICES_FILE"; do
  if [[ ! -f "$file" ]]; then
    error "Missing file: $file"
  fi
done

# =============================================================================
# PRE-CHECK: INTERNET & DNS
# =============================================================================

info "Checking internet connection..."
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
  warn "Connection issues detected. Setting DNS to Google & Cloudflare..."
  sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
  sudo chattr +i /etc/resolv.conf 2>/dev/null || true
  sleep 2
fi

MAX_RETRY=5
ATTEMPT=0
CONNECTED=false

while [[ $ATTEMPT -lt $MAX_RETRY ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  if ping -c 1 -W 3 github.com &>/dev/null; then
    CONNECTED=true
    break
  fi
  warn "Waiting for network... ($ATTEMPT/$MAX_RETRY)"
  sleep 5
done

if [[ "$CONNECTED" == false ]]; then
  error "No internet connection after $MAX_RETRY attempts. Please check your network."
fi
success "Internet connection is stable."

# =============================================================================
# SYSTEM UPDATE
# =============================================================================

info "Updating system packages..."
sudo pacman -Syu --noconfirm

# =============================================================================
# INSTALL PACMAN PACKAGES
# =============================================================================

info "Installing pacman packages..."
PACMAN_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$PACMAN_FILE")

if [[ -n "$PACMAN_PACKAGES" ]]; then
  sudo pacman -S --needed --noconfirm $PACMAN_PACKAGES
fi
success "Pacman packages installed."

# =============================================================================
# INSTALL YAY
# =============================================================================

if ! command -v yay &>/dev/null; then
  info "Installing yay AUR helper..."
  if ! grep -q "--retry 5" /etc/makepkg.conf; then
    sudo sed -i '/curl/s/-o %o %u/--retry 5 --retry-delay 5 -o %o %u/' /etc/makepkg.conf
  fi
  
  TMPDIR=$(mktemp -d)
  git clone --depth=1 https://aur.archlinux.org/yay.git "$TMPDIR/yay"
  cd "$TMPDIR/yay"
  makepkg -si --noconfirm
  cd "$SCRIPT_DIR"
  rm -rf "$TMPDIR"
  success "yay installed successfully."
else
  info "yay is already installed."
fi

# =============================================================================
# INSTALL AUR PACKAGES (WITH PGP ERROR HANDLING)
# =============================================================================

import_missing_pgp_key() {
  local output="$1"
  local key_id
  key_id=$(echo "$output" | grep -oP '(?<=key |NO_PUBKEY )[0-9A-Fa-f]{8,}' | tail -n1)
  if [[ -n "$key_id" ]]; then
    warn "PGP key not found: $key_id - attempting automatic import..."
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key_id" 2>/dev/null || \
    gpg --keyserver hkps://keys.openpgp.org --recv-keys "$key_id" 2>/dev/null || \
    gpg --keyserver hkps://pgp.mit.edu --recv-keys "$key_id" 2>/dev/null
    return 0
  fi
  return 1
}

info "Installing AUR packages..."
mapfile -t AUR_PACKAGES < <(grep -vE '^\s*#|^\s*$' "$AUR_FILE")

if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  set +e # Temporarily disable exit on error to handle PGP issues manually
  for pkg in "${AUR_PACKAGES[@]}"; do
    info "Installing: $pkg"
    install_output=$(yay -S --noconfirm --needed --answerdiff None --answerclean None "$pkg" 2>&1)
    install_status=$?

    if [[ $install_status -ne 0 ]]; then
      if echo "$install_output" | grep -qiE "pgp|gpg|signature|key"; then
        import_missing_pgp_key "$install_output"
        info "Retrying $pkg after PGP key import..."
        if yay -S --noconfirm --needed --answerdiff None --answerclean None "$pkg"; then
          success "$pkg installed after PGP import."
        else
          warn "Failed to install $pkg even after PGP import."
        fi
      else
        warn "Failed to install $pkg (Not a PGP issue)."
      fi
    else
      success "$pkg installed successfully."
    fi
  done
  set -e # Re-enable exit on error
fi

# =============================================================================
# INSTALL NPM PACKAGES
# =============================================================================

info "Installing global npm packages..."
NPM_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$NPM_FILE")

if [[ -n "$NPM_PACKAGES" ]]; then
  sudo npm install -g $NPM_PACKAGES
fi
success "Global npm packages installed."

# =============================================================================
# ENABLE SERVICES & QEMU GROUP
# =============================================================================

info "Enabling system services..."
while read -r service; do
  [[ -z "$service" || "$service" =~ ^# ]] && continue
  sudo systemctl enable --now "$service"
  success "$service enabled."
done < "$SERVICES_FILE"

if grep -q "libvirtd.service" "$SERVICES_FILE"; then
  info "Adding user to libvirt and kvm groups..."
  sudo usermod -aG libvirt,kvm "$USER"
  sudo virsh net-autostart default 2>/dev/null || true
  sudo virsh net-start default 2>/dev/null || true
  success "User added to QEMU/KVM groups."
fi

# =============================================================================
# COPY CONFIG FILES & CHMOD
# =============================================================================

info "Copying configuration files..."

for app in sway swappy alacritty; do
  mkdir -p "$HOME/.config/$app"
  if [[ -d "$SCRIPT_DIR/config/$app" ]]; then
    cp -r "$SCRIPT_DIR/config/$app/." "$HOME/.config/$app/"
    success "$app configuration copied."
  fi
done

if [[ -d "$HOME/.config/sway/scripts" ]]; then
  info "Setting executable permissions for sway scripts..."
  chmod +x "$HOME"/.config/sway/scripts/* 2>/dev/null || true
  success "Sway script permissions updated."
fi

# =============================================================================
# SNAPPER CONFIGURATION
# =============================================================================

info "Configuring Snapper for root..."
sudo mkdir -p /etc/snapper/configs
sudo tee /etc/snapper/configs/root > /dev/null << 'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="3600"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="no"
TIMELINE_CLEANUP="yes"
TIMELINE_LIMIT_HOURLY="3"
TIMELINE_LIMIT_DAILY="5"
TIMELINE_LIMIT_WEEKLY="2"
TIMELINE_LIMIT_MONTHLY="1"
TIMELINE_LIMIT_QUARTERLY="0"
TIMELINE_LIMIT_YEARLY="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="3600"
EOF
success "Snapper root configuration updated."

# =============================================================================
# NVCHAD SETUP
# =============================================================================

info "Setting up NvChad..."
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.cache/nvim
git clone --depth=1 https://github.com/NvChad/starter ~/.config/nvim

mkdir -p ~/.config/nvim/lua
cat > ~/.config/nvim/lua/chadrc.lua << 'LUAEOF'
---@type ChadrcConfig
local M = {}
M.ui = { theme = "horizon" }
return M
LUAEOF
success "NvChad cloned and horizon theme applied."

# =============================================================================
# ROFI THEMES
# =============================================================================

info "Installing Rofi themes..."
TMPDIR=$(mktemp -d)
git clone --depth=1 https://github.com/adi1090x/rofi.git "$TMPDIR/rofi"
cd "$TMPDIR/rofi"
chmod +x setup.sh
./setup.sh
cd "$SCRIPT_DIR"
rm -rf "$TMPDIR"

ln -sf ~/.config/rofi/launchers/type-1/launcher.sh ~/.config/rofi/launcher_active.sh
ln -sf ~/.config/rofi/powermenu/type-1/powermenu.sh ~/.config/rofi/powermenu_active.sh
success "Rofi themes installed and symlinked."

# =============================================================================
# POWERLEVEL10K & ZSHRC
# =============================================================================

info "Setting up Powerlevel10k and ZSH..."
if [[ -d "$SCRIPT_DIR/powerlevel10k" && "$(ls -A "$SCRIPT_DIR/powerlevel10k" 2>/dev/null | grep -v '.gitkeep')" ]]; then
  cp -r "$SCRIPT_DIR/powerlevel10k/." ~/powerlevel10k/
else
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
fi
success "Powerlevel10k configured."

if [[ -f "$SCRIPT_DIR/dotfiles/.zshrc" ]]; then
  cp "$SCRIPT_DIR/dotfiles/.zshrc" ~/.zshrc
fi
if [[ -f "$SCRIPT_DIR/dotfiles/.p10k.zsh" ]]; then
  cp "$SCRIPT_DIR/dotfiles/.p10k.zsh" ~/.p10k.zsh
fi

if [[ "$SHELL" != "$(which zsh)" ]]; then
  info "Changing default shell to ZSH..."
  chsh -s "$(which zsh)"
  success "Default shell changed to ZSH. Will take effect upon next login."
fi

# =============================================================================
# INSTALL CELESTIAL SDDM
# =============================================================================

info "Setting up celestial-sddm..."
mkdir -p ~/Projects/sddm
SDDM_SOURCE="$SCRIPT_DIR/sddm/celestial-sddm"
SDDM_TARGET="$HOME/Projects/sddm/celestial-sddm"

if [[ -d "$SDDM_SOURCE" ]]; then
  rm -rf "$SDDM_TARGET"
  mkdir -p "$SDDM_TARGET"
  cp -r "$SDDM_SOURCE/." "$SDDM_TARGET/"
  
  info "Applying executable permissions for SDDM scripts..."
  find "$SDDM_TARGET" -type f -name "*.sh" -exec chmod +x {} \;
  
  if [[ -f "$SDDM_TARGET/install.sh" ]]; then
    info "Running celestial-sddm installer..."
    cd "$SDDM_TARGET"
    bash install.sh
    cd "$SCRIPT_DIR"
    success "celestial-sddm installed successfully."
  else
    warn "install.sh not found inside celestial-sddm."
  fi
else
  warn "sddm/celestial-sddm directory not found. Skipping SDDM setup."
fi

# =============================================================================
# FINISHED
# =============================================================================

echo ""
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo -e "${GREEN}${BOLD}           INSTALLATION COMPLETED SUCCESSFULLY!       ${RESET}"
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo ""
echo -e "  ${YELLOW}The system will reboot in 5 seconds...${RESET}"
echo -e "  ${YELLOW}Press Ctrl+C to cancel the reboot.${RESET}"
echo ""
sleep 5
sudo reboot
