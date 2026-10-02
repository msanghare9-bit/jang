#!/usr/bin/env bash
# Télécharge les polices (Baloo 2 pour les titres, Nunito pour le texte) depuis Google Fonts.
set -euo pipefail
mkdir -p "$(dirname "$0")/../assets/fonts"
cd "$(dirname "$0")/../assets/fonts"
gh=https://raw.githubusercontent.com/google/fonts/main/ofl
get() { # $1 = famille et graisse pour l'API Google Fonts, $2 = fichier
  url=$(curl -fsSL "https://fonts.googleapis.com/css2?family=$1" | grep -o 'https://[^)]*\.ttf' | head -1 || true)
  if [ -n "$url" ] && curl -fsSL "$url" -o "$2"; then return 0; fi
  echo "Secours pour $2"
  case "$2" in
    Baloo*) curl -fsSL "$gh/baloo2/Baloo2%5Bwght%5D.ttf" -o "$2" ;;
    *Italic*) curl -fsSL "$gh/nunito/Nunito-Italic%5Bwght%5D.ttf" -o "$2" ;;
    *) curl -fsSL "$gh/nunito/Nunito%5Bwght%5D.ttf" -o "$2" ;;
  esac
}
get "Baloo+2:wght@600" Baloo2-SemiBold.ttf
get "Baloo+2:wght@700" Baloo2-Bold.ttf
get "Baloo+2:wght@800" Baloo2-ExtraBold.ttf
get "Nunito:wght@400" Nunito-Regular.ttf
get "Nunito:wght@600" Nunito-SemiBold.ttf
get "Nunito:wght@700" Nunito-Bold.ttf
get "Nunito:wght@800" Nunito-ExtraBold.ttf
get "Nunito:ital,wght@1,600" Nunito-SemiBoldItalic.ttf
ls -la
