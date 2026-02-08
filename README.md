# dotfiles

macOS dotfiles for zsh (oh-my-zsh + powerlevel10k), tmux, and iTerm2.

## Setup

1) Install dependencies with Homebrew:

```bash
./install_deps.sh
```

2) Zsh config (source directly from this repo):

Add this to your `~/.zshrc` (set `DOTFILES_DIR` to your repo path):

```bash
DOTFILES_DIR="$HOME/Projects/dotfiles"
source "$DOTFILES_DIR/.zsh_root"
```

Notes:

- `.zsh_root` loads `.zsh_plugins` and `.zsh_p10k` from this repo.
- `.zsh_root` will symlink `.tmux.conf` into `~/.tmux.conf` if it does not already exist.
- `install_deps.sh` installs Meslo Nerd Font; set it in iTerm2 profiles for the prompt glyphs.

3) iTerm2 preferences (optional, overwrites existing iTerm2 defaults):

```bash
defaults import com.googlecode.iterm2 iterm2/com.googlecode.iterm2.plist
```

4) tmux plugins:

- Start tmux, then press `Ctrl-b` and `I` to install TPM plugins.
