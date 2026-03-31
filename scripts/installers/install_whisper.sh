#!/usr/bin/env bash

ESCAPE=$(printf "\033")
RED="${ESCAPE}[91m"
GREEN="${ESCAPE}[92m"
YELLOW="${ESCAPE}[33m"
NOCOLOR="${ESCAPE}[0m"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
MODELS_DIR="$REPO_ROOT/whisper-models"
DEFAULT_MODEL="large-v3-turbo-q5_0"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

echo "=== Whisper.cpp Installer for Backup Brain ==="
echo ""

# -------------------------------------------------------
# Install whisper-cpp
# -------------------------------------------------------

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  echo "🍎 macOS detected — installing via Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "${RED}❌ Homebrew not found. Install it from https://brew.sh first.${NOCOLOR}"
    exit 1
  fi
  brew install whisper-cpp
  echo "✅ ${GREEN}whisper-cpp installed via Homebrew.${NOCOLOR}"

elif [ -f /etc/debian_version ]; then
  echo "🐧 Debian/Raspberry Pi OS detected — building whisper.cpp from source..."
  echo ""
  echo "We need to clone the whisper.cpp source code in order to compile it."
  printf "${YELLOW}Where should we clone it? ${NOCOLOR}[${HOME}/whisper.cpp]: "
  read -r whisper_src_input
  WHISPER_SRC="${whisper_src_input:-$HOME/whisper.cpp}"
  echo ""
  sudo apt-get update
  sudo apt-get install -y git build-essential cmake

  if [ -d "$WHISPER_SRC" ]; then
    echo "📁 Found existing clone at $WHISPER_SRC — pulling latest..."
    git -C "$WHISPER_SRC" pull
  else
    git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_SRC"
  fi

  cmake -S "$WHISPER_SRC" -B "$WHISPER_SRC/build"
  cmake --build "$WHISPER_SRC/build" --config Release -j"$(nproc 2>/dev/null || echo 4)"

  sudo ln -sf "$WHISPER_SRC/build/bin/whisper-cli" /usr/local/bin/whisper-cli
  echo "✅ ${GREEN}whisper-cli installed to /usr/local/bin/whisper-cli${NOCOLOR}"

else
  echo "${RED}❌ Unsupported OS: $OS${NOCOLOR}"
  echo "This script supports macOS and Debian-based Linux only."
  exit 1
fi

echo ""

# -------------------------------------------------------
# Model download
# -------------------------------------------------------

mkdir -p "$MODELS_DIR"
echo "✅ ${GREEN}Models directory ready: $MODELS_DIR${NOCOLOR}"
echo ""

echo "${YELLOW}Download the recommended model (ggml-${DEFAULT_MODEL}.bin)?${NOCOLOR} (Y/n)"
read -r use_default
use_default="${use_default:-Y}"

if [[ "$use_default" =~ ^[Yy]$ ]]; then
  MODEL_NAME="$DEFAULT_MODEL"
else
  echo ""
  echo "Common models (enter just the name, e.g. ${YELLOW}small.en${NOCOLOR}):"
  echo "  tiny  tiny.en  base  base.en  small  small.en"
  echo "  medium  medium.en  large-v3  large-v3-turbo  large-v3-turbo-q5_0"
  echo ""
  printf "${YELLOW}Model name: ${NOCOLOR}"
  read -r MODEL_NAME
fi

# Normalise: strip ggml- prefix and .bin suffix if the user included them
MODEL_NAME="${MODEL_NAME#ggml-}"
MODEL_NAME="${MODEL_NAME%.bin}"

MODEL_FILENAME="ggml-${MODEL_NAME}.bin"
MODEL_PATH="$MODELS_DIR/$MODEL_FILENAME"
MODEL_URL="$MODEL_BASE_URL/$MODEL_FILENAME"

echo ""
echo "Downloading ${YELLOW}$MODEL_FILENAME${NOCOLOR}…"
echo "(This may take a while — large models are several GB)"
echo ""

if curl -L --fail --show-error --progress-bar -o "$MODEL_PATH" "$MODEL_URL"; then
  echo ""
  echo "✅ ${GREEN}Model downloaded to: $MODEL_PATH${NOCOLOR}"
  echo ""
  echo "Add the following to your ${YELLOW}.env${NOCOLOR} file:"
  echo ""
  echo "  WHISPER_MODEL_PATH=$MODEL_PATH"
  echo "  ENABLE_AUDIO_TRANSCRIPTIONS=true"
else
  rm -f "$MODEL_PATH"
  echo ""
  echo "${RED}❌ Download failed for: $MODEL_FILENAME${NOCOLOR}"
  echo ""
  echo "Browse and download models manually from:"
  echo "  ${YELLOW}https://huggingface.co/ggerganov/whisper.cpp/tree/main${NOCOLOR}"
  echo "Place the downloaded .bin file in: $MODELS_DIR/"
  echo ""
  echo "Then add the following to your ${YELLOW}.env${NOCOLOR} file (adjusting the filename):"
  echo ""
  echo "  WHISPER_MODEL_PATH=$MODELS_DIR/ggml-small.en.bin"
  echo "  ENABLE_AUDIO_TRANSCRIPTIONS=true"
fi

echo ""
echo "⚠️  ${YELLOW}These settings won't take effect until you add them to your"
echo "   .env file and restart Backup Brain.${NOCOLOR}"
