# dotfiles

macOS dotfiles for zsh (oh-my-zsh + powerlevel10k), tmux, and iTerm2.

## Setup

1) Install dependencies with Homebrew:

```bash
./install_deps.sh
```

2) Sync configs into your home directory:

```bash
./sync.sh
```

3) Zsh config:

- Ensure your `~/.zshrc` sources `~/.zsh_root` if you want to use the split config in this repo.
- If you want `sync.sh` to copy `.zsh_root`, `.zsh_plugins`, and `.zsh_p10k`, add them to the script or copy them manually.

Example snippet for `~/.zshrc`:

```bash
source "$HOME/.zsh_root"
```

4) iTerm2 preferences (optional, overwrites existing iTerm2 defaults):

```bash
defaults import com.googlecode.iterm2 iterm2/com.googlecode.iterm2.plist
```

5) tmux plugins:

- Start tmux, then press `Ctrl-b` and `I` to install TPM plugins.

## Notes

- `install_deps.sh` installs Meslo Nerd Font; set it in iTerm2 profiles for the prompt glyphs.
