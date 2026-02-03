#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sync_iterm2() {
  local src_dir dest_dir

  src_dir="$ROOT_DIR/iterm2"
  dest_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

  if [[ ! -d "$src_dir" ]]; then
    return 0
  fi

  mkdir -p "$dest_dir"

  local found=0
  local file
  for file in "$src_dir"/*.json; do
    if [[ ! -e "$file" ]]; then
      continue
    fi
    found=1
    cp -f "$file" "$dest_dir/"
    printf 'Synced iTerm2 profile: %s\n' "$(basename "$file")"
  done

  if [[ "$found" -eq 0 ]]; then
    printf 'No iTerm2 profiles found in %s\n' "$src_dir"
  fi
}

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

sync_iterm2
sync_home_configs
