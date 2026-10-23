# dotfiles

macOS dotfiles for zsh (oh-my-zsh + powerlevel10k), tmux, Neovim, and iTerm2.

## Setup

Run the setup script on macOS:

```bash
./setup.sh
```

It installs Homebrew when needed; installs the command-line tools, iTerm2, and
Meslo Nerd Font; configures zsh; links the tmux and Neovim configs; installs
their plugins; imports the tracked iTerm2 preferences; and enables the coding
agent status integrations. The script is safe to re-run. Config files it
replaces and the previous iTerm2 preferences are saved under
`~/.local/state/dotfiles/backups/`.

Open a new shell after setup. `.zsh_root` loads `.zsh_plugins` and `.zsh_p10k`
directly from this repository, so later changes take effect without another
setup run.

## Agent status in tmux

Shows every pane running Claude Code or opencode (1.x and 2.x) in the status bar, grouped by window (e.g. `local: fix-login-bug ● 2 ○`), using the session name the agent puts in the terminal title (the pane number until the session is named): `●` working, `✋` waiting for you (permission prompt, question, failed run), `✓` finished but not looked at yet, `○` idle.

- Click an agent to jump to its pane (needs `mouse on`); `agent-status.conf` binds `MouseDown1Status` for this and keeps tmux's default for other status clicks.
- State is a tmux pane option (`@agent_state`) set by `tmux/agent-status/agent-state.sh` from Claude Code hooks and an opencode plugin; rendering is a plain tmux format, no polling.
- `setup.sh` adds hooks to `~/.claude/settings.json` and links the plugin into `~/.config/opencode/plugins`. Set `CLAUDE_CONFIG_DIR` / `OPENCODE_CONFIG_DIR` to target other config dirs.
- Run `tmux/agent-status/test.sh` after changes.
- Claude Code runs no hook when you press Esc, so while it works a small background loop checks once a second for its "interrupted" transcript entry, or for a screen that stopped changing (its spinner stops when you cancel before it replies); the loop exits when the turn ends.
- Limitations: only the current tmux session's windows are listed; opencode 2.x tracks the session shown in that pane's TUI.
