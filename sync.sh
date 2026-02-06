#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sync_home_file() {
  local src dest

  src="$1"
  dest="$HOME/$2"

  if [[ ! -f "$src" ]]; then
    return 0
  fi

  cp -f "$src" "$dest"
  printf 'Synced %s -> %s\n' "$(basename "$src")" "$dest"
}

sync_home_configs() {
  sync_home_file "$ROOT_DIR/.zshrc" ".zshrc"
  sync_home_file "$ROOT_DIR/.p10k.zsh" ".p10k.zsh"
  sync_home_file "$ROOT_DIR/.tmux.conf" ".tmux.conf"
}

sync_home_configs
