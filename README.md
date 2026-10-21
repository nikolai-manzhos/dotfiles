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

5) Agent status in tmux (optional):

```bash
./tmux/agent-status/install.sh
tmux source ~/.tmux.conf
```

Shows `window:pane` (e.g. `android:1`) in the status bar for every pane running Claude Code or opencode (1.x and 2.x): `●` working, `✋` waiting for you (permission prompt, question, failed run), `✓` finished but not looked at yet, `○` idle.

- State is a tmux pane option (`@agent_state`) set by `tmux/agent-status/agent-state.sh` from Claude Code hooks and an opencode plugin; rendering is a plain tmux format, no polling.
- `install.sh` adds hooks to `~/.claude/settings.json` and links the plugin into `~/.config/opencode/plugins`. Safe to re-run; set `CLAUDE_CONFIG_DIR` / `OPENCODE_CONFIG_DIR` to target other config dirs.
- Run `tmux/agent-status/test.sh` after changes.
- Limitations: after pressing Esc in Claude Code, `●` stays until its 60s idle notification; only the current tmux session's windows are listed; opencode 2.x tracks the session shown in that pane's TUI.
