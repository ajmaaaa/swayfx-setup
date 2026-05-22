#!/bin/bash

# =============================================================================
# ARCH SETUP INSTALLER
# =============================================================================

set -e

# =============================================================================
# COLORS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info() {
  echo -e "${BLUE}[INFO]${RESET} $1"
}

success() {
  echo -e "${GREEN}[OK]${RESET} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${RESET} $1"
}

error() {
  echo -e "${RED}[ERROR]${RESET} $1"
  exit 1
}

# =============================================================================
# ROOT CHECK
# =============================================================================

if [[ "$EUID" -eq 0 ]]; then
  error "Do not run this script as root."
fi

# =============================================================================
# PATHS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACMAN_FILE="$SCRIPT_DIR/packages/pacman.txt"
AUR_FILE="$SCRIPT_DIR/packages/aur.txt"
NPM_FILE="$SCRIPT_DIR/packages/npm.txt"
SERVICES_FILE="$SCRIPT_DIR/packages/services.txt"

# =============================================================================
# CHECK REQUIRED FILES
# =============================================================================

for file in \
  "$PACMAN_FILE" \
  "$AUR_FILE" \
  "$NPM_FILE" \
  "$SERVICES_FILE"
do
  if [[ ! -f "$file" ]]; then
    error "Missing file: $file"
  fi
done

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
# INSTALL AUR PACKAGES
# =============================================================================

info "Installing AUR packages..."

AUR_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$AUR_FILE")

if [[ -n "$AUR_PACKAGES" ]]; then
  yay -S --needed --noconfirm $AUR_PACKAGES
fi
success "AUR packages installed."

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
# ENABLE SERVICES
# =============================================================================

info "Enabling system services..."

while read -r service; do
  [[ -z "$service" || "$service" =~ ^# ]] && continue
  sudo systemctl enable --now "$service"
  success "$service enabled."
done < "$SERVICES_FILE"

# =============================================================================
# COPY CONFIG FILES
# =============================================================================

info "Copying sway configuration..."
mkdir -p ~/.config/sway
cp -r "$SCRIPT_DIR/config/sway/." ~/.config/sway/
success "Sway configuration copied."

info "Copying swappy configuration..."
mkdir -p ~/.config/swappy
cp -r "$SCRIPT_DIR/config/swappy/." ~/.config/swappy/
success "Swappy configuration copied."

info "Copying alacritty configuration..."
mkdir -p ~/.config/alacritty
cp -r "$SCRIPT_DIR/config/alacritty/." ~/.config/alacritty/
success "Alacritty configuration copied."

# =============================================================================
# SET EXECUTABLE PERMISSIONS
# =============================================================================

if [[ -d ~/.config/sway/scripts ]]; then
  info "Setting executable permissions for sway scripts..."
  chmod +x ~/.config/sway/scripts/* 2>/dev/null || true
  success "Sway script permissions updated."
fi

# =============================================================================
# INSTALL CELESTIAL SDDM
# =============================================================================

info "Setting up celestial-sddm..."

mkdir -p ~/Projects/sddm
SDDM_SOURCE="$SCRIPT_DIR/sddm/celestial-sddm"
SDDM_TARGET="$HOME/Projects/sddm/celestial-sddm"

if [[ -d "$SDDM_SOURCE" ]]; then
  info "Copying celestial-sddm project..."
  rm -rf "$SDDM_TARGET"
  mkdir -p "$SDDM_TARGET"
  cp -r "$SDDM_SOURCE/." "$SDDM_TARGET/"
  success "celestial-sddm copied successfully."
  info "Setting executable permissions..."
  find "$SDDM_TARGET" -type f -name "*.sh" -exec chmod +x {} \;
  success "Executable permissions applied."
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
  warn "sddm/celestial-sddm directory not found."
fi

# =============================================================================
# FINISHED
# =============================================================================

echo ""
success "INSTALLATION COMPLETED SUCCESSFULLY!"
echo ""
