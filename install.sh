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
  error "Jangan jalankan script sebagai root."
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
# CHECK FILES
# =============================================================================

for file in \
  "$PACMAN_FILE" \
  "$AUR_FILE" \
  "$NPM_FILE" \
  "$SERVICES_FILE"
do
  if [[ ! -f "$file" ]]; then
    error "File tidak ditemukan: $file"
  fi
done

# =============================================================================
# UPDATE SYSTEM
# =============================================================================

info "Update system..."

sudo pacman -Syu --noconfirm

# =============================================================================
# INSTALL PACMAN PACKAGES
# =============================================================================

info "Install pacman packages..."

PACMAN_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$PACMAN_FILE")

if [[ -n "$PACMAN_PACKAGES" ]]; then
  sudo pacman -S --needed --noconfirm $PACMAN_PACKAGES
fi

success "Pacman packages selesai."

# =============================================================================
# INSTALL YAY
# =============================================================================

if ! command -v yay &>/dev/null; then

  info "Installing yay..."

  TMPDIR=$(mktemp -d)

  git clone --depth=1 https://aur.archlinux.org/yay.git "$TMPDIR/yay"

  cd "$TMPDIR/yay"

  makepkg -si --noconfirm

  cd "$SCRIPT_DIR"

  rm -rf "$TMPDIR"

  success "yay berhasil diinstall."

else

  info "yay sudah terinstall."

fi

# =============================================================================
# INSTALL AUR PACKAGES
# =============================================================================

info "Install AUR packages..."

AUR_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$AUR_FILE")

if [[ -n "$AUR_PACKAGES" ]]; then
  yay -S --needed --noconfirm $AUR_PACKAGES
fi

success "AUR packages selesai."

# =============================================================================
# INSTALL NPM PACKAGES
# =============================================================================

info "Install npm global packages..."

NPM_PACKAGES=$(grep -vE '^\s*#|^\s*$' "$NPM_FILE")

if [[ -n "$NPM_PACKAGES" ]]; then
  sudo npm install -g $NPM_PACKAGES
fi

success "NPM packages selesai."

# =============================================================================
# ENABLE SERVICES
# =============================================================================

info "Enable services..."

while read -r service; do

  [[ -z "$service" || "$service" =~ ^# ]] && continue

  sudo systemctl enable --now "$service"

  success "$service enabled."

done < "$SERVICES_FILE"

# =============================================================================
# INSTALL CELESTIAL SDDM
# =============================================================================

info "Setup celestial-sddm..."

mkdir -p ~/Projects/sddm

SDDM_SOURCE="$SCRIPT_DIR/sddm/celestial-sddm"
SDDM_TARGET="$HOME/Projects/sddm/celestial-sddm"

if [[ -d "$SDDM_SOURCE" ]]; then

  info "Menyalin celestial-sddm ke ~/Projects/sddm..."

  rm -rf "$SDDM_TARGET"

  mkdir -p "$SDDM_TARGET"

  cp -r "$SDDM_SOURCE/." "$SDDM_TARGET/"

  success "celestial-sddm berhasil disalin."

  info "Memberikan permission executable..."

  find "$SDDM_TARGET" -type f -name "*.sh" -exec chmod +x {} \;

  success "Permission berhasil diberikan."

  if [[ -f "$SDDM_TARGET/install.sh" ]]; then

    info "Menjalankan installer celestial-sddm..."

    cd "$SDDM_TARGET"

    bash install.sh

    cd "$SCRIPT_DIR"

    success "celestial-sddm berhasil diinstall."

  else

    warn "install.sh celestial-sddm tidak ditemukan."

  fi

else

  warn "Folder sddm/celestial-sddm tidak ditemukan."

fi

# =============================================================================
# DONE
# =============================================================================

echo ""
success "INSTALLATION COMPLETED!"
echo ""
