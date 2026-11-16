#!/usr/bin/env bash
# Télécharge le modèle de langage local embarqué dans l'APK.
# Qwen2.5-0.5B-Instruct (Alibaba, licence Apache 2.0), quantifié Q4_K_M.
set -euo pipefail

URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
DIR="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/assets/models"
FILE="$DIR/qwen2.5-0.5b-instruct-q4_k_m.gguf"

mkdir -p "$DIR"
if [ -s "$FILE" ]; then
  echo "Modèle déjà présent : $FILE"
  exit 0
fi

echo "Téléchargement du modèle…"
curl --fail --location --retry 3 --output "$FILE.part" "$URL"

# Un fichier GGUF commence par les 4 octets « GGUF ».
if [ "$(head -c 4 "$FILE.part")" != "GGUF" ]; then
  rm -f "$FILE.part"
  echo "Le fichier téléchargé n'est pas un modèle GGUF." >&2
  exit 1
fi
mv "$FILE.part" "$FILE"
ls -l "$FILE"
