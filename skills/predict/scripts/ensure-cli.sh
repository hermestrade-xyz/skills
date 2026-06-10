#!/bin/sh
# Ensure predict-cli is available, installing the latest release if missing.
# Idempotent: exits 0 immediately when the binary is already on PATH.
set -e

if command -v predict-cli >/dev/null 2>&1; then
  echo "predict-cli already installed: $(command -v predict-cli)"
  predict-cli --version 2>/dev/null || true
  exit 0
fi

echo "predict-cli not found — installing latest release..."
# The installer honors INSTALL_DIR (default /usr/local/bin, sudo when needed);
# run as `INSTALL_DIR=~/.local/bin scripts/ensure-cli.sh` to avoid sudo.
curl -sSfL https://raw.githubusercontent.com/chainupcloud/predict-rs/main/install.sh \
  | INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}" sh

if ! command -v predict-cli >/dev/null 2>&1; then
  echo "Error: install finished but predict-cli is not on PATH" >&2
  echo "Check that ${INSTALL_DIR:-/usr/local/bin} is in PATH, or build from source: cargo build --release" >&2
  exit 1
fi

predict-cli --version 2>/dev/null || true
