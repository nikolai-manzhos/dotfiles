#!/usr/bin/env bash

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  printf 'Homebrew is required. Install it from https://brew.sh and re-run this script.\n' >&2
  exit 1
fi

install_formula() {
  local name="$1"

  if brew list --formula "$name" >/dev/null 2>&1; then
    printf 'Already installed: %s\n' "$name"
    return 0
  fi

  brew install "$name"
}

install_cask() {
  local name="$1"

  if brew list --cask "$name" >/dev/null 2>&1; then
    printf 'Already installed: %s\n' "$name"
    return 0
  fi

  brew install --cask "$name"
}

brew update
brew tap homebrew/cask-fonts >/dev/null 2>&1 || true

install_formula git
install_formula zsh
install_formula tmux
install_formula zsh-autosuggestions
install_formula powerlevel10k
install_formula ripgrep
install_formula fd

install_cask iterm2
install_cask font-meslo-lg-nerd-font

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  if brew info oh-my-zsh >/dev/null 2>&1; then
    install_formula oh-my-zsh
  else
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  fi
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/themes" "$ZSH_CUSTOM/plugins"

p10k_prefix="$(brew --prefix powerlevel10k 2>/dev/null || true)"
if [[ -n "$p10k_prefix" && -d "$p10k_prefix/share/powerlevel10k" ]]; then
  ln -sfn "$p10k_prefix/share/powerlevel10k" "$ZSH_CUSTOM/themes/powerlevel10k"
fi

autosuggestions_prefix="$(brew --prefix zsh-autosuggestions 2>/dev/null || true)"
if [[ -n "$autosuggestions_prefix" && -d "$autosuggestions_prefix/share/zsh-autosuggestions" ]]; then
  ln -sfn "$autosuggestions_prefix/share/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

tpm_dir="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$tpm_dir" ]]; then
  git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir"
fi

printf 'Dependencies installed. Source .zsh_root from this repo (see README.md), then start tmux to install plugins.\n'
