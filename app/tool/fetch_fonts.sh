#!/usr/bin/env bash
# Télécharge les polices (Bricolage Grotesque, Atkinson Hyperlegible) depuis Google Fonts.
set -euo pipefail
mkdir -p "$(dirname "$0")/../assets/fonts"
cd "$(dirname "$0")/../assets/fonts"
base=https://raw.githubusercontent.com/google/fonts/main/ofl
curl -fsSL "$base/bricolagegrotesque/BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf" -o BricolageGrotesque.ttf
for f in Regular Bold Italic; do
  curl -fsSL "$base/atkinsonhyperlegible/AtkinsonHyperlegible-$f.ttf" -o "AtkinsonHyperlegible-$f.ttf"
done
ls -la
