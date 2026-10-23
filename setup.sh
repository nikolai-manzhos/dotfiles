#!/usr/bin/env bash

set -euo pipefail

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.local/state/dotfiles/backups/$(date +%Y%m%d-%H%M%S)-$$}"

info() {
  printf '\n==> %s\n' "$1"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die 'this setup currently supports macOS only'
fi

ensure_homebrew() {
  local brew_path

  if ! command -v brew >/dev/null 2>&1; then
    info 'Installing Homebrew'
    NONINTERACTIVE=1 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_path" ]]; then
      eval "$("$brew_path" shellenv)"
      return 0
    fi
  done

  die 'Homebrew was installed but could not be found'
}

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

install_git_repo() {
  local url="$1"
  local destination="$2"
  local expected_file="$3"

  if [[ -f "$destination/$expected_file" ]]; then
    printf 'Already installed: %s\n' "$(basename "$destination")"
    return 0
  fi

  if [[ -L "$destination" ]]; then
    backup_path "$destination" "$(basename "$destination").link"
  elif [[ -e "$destination" ]]; then
    die "$destination exists but does not look like the expected installation"
  fi

  mkdir -p "$(dirname "$destination")"
  git clone --depth=1 "$url" "$destination"
}

backup_path() {
  local path="$1"
  local name="$2"

  mkdir -p "$BACKUP_DIR"
  mv "$path" "$BACKUP_DIR/$name"
  printf 'Backed up %s to %s\n' "$path" "$BACKUP_DIR/$name"
}

link_config() {
  local source="$1"
  local destination="$2"
  local backup_name="$3"

  mkdir -p "$(dirname "$destination")"

  if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
    printf 'Already linked: %s\n' "$destination"
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_path "$destination" "$backup_name"
  fi

  ln -s "$source" "$destination"
  printf 'Linked %s -> %s\n' "$destination" "$source"
}

configure_zshrc() {
  local zshrc="$HOME/.zshrc"
  local begin_marker='# >>> dotfiles setup >>>'
  local end_marker='# <<< dotfiles setup <<<'
  local quoted_root
  local tmp

  printf -v quoted_root '%q' "$ROOT_DIR/.zsh_root"
  touch "$zshrc"

  if grep -Fq "$ROOT_DIR/.zsh_root" "$zshrc"; then
    printf 'Already configured: %s\n' "$zshrc"
    return 0
  fi

  if grep -Fq "$begin_marker" "$zshrc"; then
    mkdir -p "$BACKUP_DIR"
    cp -p "$zshrc" "$BACKUP_DIR/zshrc"
    tmp="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" -v root="$quoted_root" '
      $0 == begin {
        print begin
        print "source " root
        print end
        replacing = 1
        next
      }
      replacing && $0 == end { replacing = 0; next }
      !replacing { print }
    ' "$zshrc" >"$tmp"
    cat "$tmp" >"$zshrc"
    rm -f "$tmp"
    printf 'Updated dotfiles source in %s\n' "$zshrc"
    return 0
  fi

  if grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*\.zsh_root([[:space:]]|$)' "$zshrc"; then
    printf 'Existing .zsh_root source left unchanged in %s\n' "$zshrc"
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  cp -p "$zshrc" "$BACKUP_DIR/zshrc"
  {
    printf '\n%s\n' "$begin_marker"
    printf 'source %s\n' "$quoted_root"
    printf '%s\n' "$end_marker"
  } >>"$zshrc"
  printf 'Configured %s\n' "$zshrc"
}

import_iterm_preferences() {
  local preferences="$ROOT_DIR/iterm2/com.googlecode.iterm2.plist"

  if [[ ! -f "$preferences" ]]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  if defaults export com.googlecode.iterm2 "$BACKUP_DIR/com.googlecode.iterm2.plist" >/dev/null 2>&1; then
    printf 'Backed up iTerm2 preferences to %s\n' "$BACKUP_DIR/com.googlecode.iterm2.plist"
  fi
  defaults import com.googlecode.iterm2 "$preferences"
  printf 'Imported iTerm2 preferences\n'
}

ensure_homebrew

info 'Installing Homebrew packages'
brew update
for formula in git zsh tmux neovim ripgrep fd fzf jq; do
  install_formula "$formula"
done

if [[ -d /Applications/iTerm.app || -d "$HOME/Applications/iTerm.app" ]]; then
  printf 'Already installed: iTerm2\n'
else
  install_cask iterm2
fi
if [[ -f "$HOME/Library/Fonts/MesloLGS NF Regular.ttf" || -f '/Library/Fonts/MesloLGS NF Regular.ttf' ]]; then
  printf 'Already installed: Meslo Nerd Font\n'
else
  install_cask font-meslo-lg-nerd-font
fi

info 'Installing zsh framework and plugins'
install_git_repo https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" oh-my-zsh.sh
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
install_git_repo https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" powerlevel10k.zsh-theme
install_git_repo https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions" zsh-autosuggestions.plugin.zsh
install_git_repo https://github.com/unixorn/fzf-zsh-plugin.git "$ZSH_CUSTOM/plugins/fzf-zsh-plugin" fzf-zsh-plugin.plugin.zsh
install_git_repo https://github.com/Aloxaf/fzf-tab.git "$ZSH_CUSTOM/plugins/fzf-tab" fzf-tab.plugin.zsh

info 'Linking dotfiles'
configure_zshrc
link_config "$ROOT_DIR/.tmux.conf" "$HOME/.tmux.conf" tmux.conf
link_config "$ROOT_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua" nvim-init.lua

info 'Installing tmux plugins'
install_git_repo https://github.com/tmux-plugins/tpm.git "$HOME/.tmux/plugins/tpm" bin/install_plugins
"$HOME/.tmux/plugins/tpm/bin/install_plugins"

info 'Installing Neovim plugins'
nvim --headless '+Lazy! sync' +qa

info 'Configuring coding-agent status'
mkdir -p "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
"$ROOT_DIR/tmux/agent-status/install.sh"

info 'Importing iTerm2 preferences'
import_iterm_preferences

if tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
fi

printf '\nSetup complete. Restart iTerm2 or open a new shell to load the configuration.\n'
if [[ -d "$BACKUP_DIR" ]]; then
  printf 'Backups from this run are in %s\n' "$BACKUP_DIR"
fi
