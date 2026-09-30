# herdr-nvim

[![CI](https://github.com/ChmaraX/herdr-nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChmaraX/herdr-nvim/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ChmaraX/herdr-nvim)](https://github.com/ChmaraX/herdr-nvim/releases)
[![License](https://img.shields.io/github/license/ChmaraX/herdr-nvim)](LICENSE)

Neovim, built into your [herdr](https://herdr.dev) workspace: a persistent
nvim sidebar one key away, with quick access to the files your agent works on.

https://github.com/user-attachments/assets/9a6092b4-6851-4e47-a4b7-d09fda1f5121

## Features

- **Full-height nvim sidebar, one key to toggle.** Your panes move into the
  left half, and nvim takes the right. Toggle it off, and herdr restores the
  original layout. Each tab keeps its own persistent nvim, so buffers, cursor,
  and pending annotations survive the toggle.
- **Fuzzy file picker.** It opens on the files your agent touched recently
  (newest first, with diff stats). Type to fuzzy-search the whole repo. `⏎`
  opens the file in the sidebar at the right line.
- **Code annotations you send to the agent.** Comment lines or a selection
  like a code review. Then send them all to any agent in the workspace (pi,
  claude, codex), with file:line and git context.
- **Inline file:line references.** Drop `path:12-20` into the agent's input
  mid-sentence.

## Requirements

nvim ≥ 0.10 · herdr ≥ 0.7.5 · runs inside a herdr session

## Install

Both halves come from this repo:

**1. The herdr plugin** (sidebar + picker):

```sh
herdr plugin install ChmaraX/herdr-nvim
# or, for a local checkout: herdr plugin link /path/to/herdr-nvim
```

Bind keys to the two actions in `~/.config/herdr/config.toml` (herdr binds
none by default):

```toml
[[keys.command]]
key = "prefix+e"
type = "plugin_action"
command = "chmarax.herdr-nvim.toggle"
description = "nvim sidebar"

[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "chmarax.herdr-nvim.pick-file"
description = "open file from agent output"
```

**2. The nvim plugin** (annotations), with your plugin manager (e.g. lazy.nvim):

```lua
{ "ChmaraX/herdr-nvim", opts = {} }
```

### Nix

This repo is a flake input; no `flake = false` is needed:

```nix
inputs.herdr-nvim = {
  url = "github:curtbushko/herdr-nvim";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

In a Home Manager module with `inputs` passed through `extraSpecialArgs`:

```nix
{ inputs, pkgs, ... }:
{
  programs.neovim.plugins = [
    inputs.herdr-nvim.packages.${pkgs.stdenv.hostPlatform.system}.nvim-plugin
  ];
  # Optional: the Rust sidebar/picker CLI.
  home.packages = [
    inputs.herdr-nvim.packages.${pkgs.stdenv.hostPlatform.system}.herdr-nvim
  ];
}
```

`packages.<system>.default` is the Neovim plugin. An optional
`overlays.default` exposes `pkgs.vimPlugins.herdr-nvim` and `pkgs.herdr-nvim`.
The CLI package includes the Lua runtime for its sidebar daemon. It does not
register herdr actions automatically; install/link the herdr plugin and bind
its actions as above.

## The sidebar

`prefix+e` toggles it. Each tab gets its own nvim, backed by a headless
daemon that survives the toggle. Two tabs can show two different files in two
sidebars. When you close and reopen a sidebar, it loses nothing.

A daemon lives as long as its tab. Closing the tab (or its whole workspace)
stops that nvim right away, along with its LSP servers; unsaved buffers in it
are discarded. Daemons survive a herdr restart, so restored tabs reattach to
their nvim; any whose tab did not come back are reaped when herdr starts.

To see which tab each hidden nvim belongs to and how much memory it (with its
LSP servers) holds, run `herdr-nvim daemons` (`--json` for machine-readable
output). The listing ends with the commands to free them:

```text
TAB       WORKSPACE / TAB   RAM      UP       STATE
w26:t2    novu / api        1.4 GB   3h 31m   alive · 2 unsaved
w26:t5    novu / web        612 MB   12m      alive
w9:t1     —                 180 MB   2d 4h    orphaned

3 daemons · 2.2 GB total
stop one: herdr-nvim daemons stop w26:t2   (--force discards unsaved work)
stop all: herdr-nvim daemons stop --all
orphans:  herdr-nvim daemons stop --orphans   (safe: their tabs are gone)
```

`daemons stop <tab>` refuses a daemon with unsaved buffers or pending comments
unless given `--force`; `--orphans` stops the daemons whose tab is gone.

The next toggle in that tab starts a fresh nvim.

## The file picker

`prefix+o` pops a fuzzy file picker. It has two modes:

- **Default view (no query):** the files touched this session, newest first.
  It mines edits from the agent's session log and adds uncommitted git
  changes. For agents that herdr does not track, it scrapes recent pane
  output instead. The cursor starts on the newest file, so `⏎` opens it with
  no typing.
- **Typing:** fuzzy matches across the **whole repo**, ranked best first.
  This includes every file that `git ls-files` reports, and it honors
  `.gitignore`. The match is on the path and filename, not the file contents.

The repo-wide tier is served by [fff-search](https://crates.io/crates/fff-search)
(fff.nvim's core matcher): multi-term queries (`cargo toml`), typo
tolerance, and frecency ranking. If a fff.nvim frecency database exists at
`~/.cache/nvim/fff_nvim`, the picker reuses it read-only (it copies the DB
to a temp dir and opens the copy; your database is never opened, locked, or
written) so files you actually open often rank higher. Set `frecency =
false` to skip the DB reuse. The agent-touched session tier always ranks
first and uses its own matcher regardless.

Each row shows:

- the path, relative to the agent's cwd
- a `new` badge for files created this session
- green/red `+N -M` diff stats for uncommitted edits
- a relative touched-age (`2m`, `3h`)

If you start the picker from a non-agent pane (for example, the sidebar
itself), it reads the agent in the same tab. So it searches the repo that
you see.

The default view shows the latest `max_files` entries (20). A typed query is
uncapped.

## Annotations

Each action has a default keymap and a `:Herdr` subcommand (subcommands
tab-complete):

| Keymap | Command | Action |
| --- | --- | --- |
| `<leader>ac` | `:Herdr comment` | comment the current line / selection (the command also takes a range: `:5,10Herdr comment`) |
| `<leader>al` | `:Herdr list` | list comments (float): hover to jump, `⏎` edit, `d` delete |
| `<leader>as` | `:Herdr send` | paste all comments into the agent's input |
| `<leader>aS` | `:Herdr submit` | send all comments to the agent (auto-submits) |
| `<leader>ai` | `:Herdr ref` | reference the current line / selection at the agent's cursor (also takes a range: `:5,10Herdr ref`) |

Keymaps are on by default (prefix `<leader>a`) and never override a map you
already set. To bind your own, set `keymaps = false` and map the command:

```lua
require("herdr-nvim").setup({ keymaps = false })
vim.keymap.set("n", "<leader>ac", "<CMD>Herdr comment<CR>", { desc = "Comment" })
vim.keymap.set("x", "<leader>ac", ":Herdr comment<CR>", { desc = "Comment" }) -- `:` passes the selection
```

Or call the Lua API directly (`comment_line`, `comment_selection`,
`comment_range(s, e)`, `list_comments`, `send_all{ submit = false|true }`,
`ref_line`, `ref_selection`, `ref_range(s, e)`).
See `:help herdr-nvim` for the full reference.

Sending skips the picker when the target is obvious: the lone agent in the
workspace, or the single agent sharing this tab (the sibling pane). The picker
only appears when two or more agents could plausibly be meant.

## References

`<leader>ai` (or `:Herdr ref`) drops just `path:12-20` into the agent's input,
so you can mention code mid-sentence. It never submits.

Comments are ephemeral by design: in-memory only, extmark-tracked (they follow
your edits), cleared after a successful send. The sent prompt includes each
comment's file:line plus the repo and branch, so the agent has context.

For a pending-comment indicator (`● 3`) in your statusline:
`require("herdr-nvim").statusline()`.

## Config

Two small config surfaces, one per half:

**nvim side** — `setup{}` opts:

```lua
require("herdr-nvim").setup({
  prefix = "<leader>a",     -- keymap prefix
  keymaps = true,           -- set false to define your own
  clear_after_send = true,  -- comments are ephemeral by design
  icons = {
    comment = " ",        -- callout and comment-list title (Nerd Font)
    sign = "▌",            -- sign-column rail (at most two display cells)
    statusline = "●",      -- pending-comment indicator
  },
})
```

The default comment icon requires a Nerd Font. Override any icon with a
string; a trailing space is preserved without adding another. Omitted keys
use the defaults; `""` hides an individual icon. Set `icons = false` to hide
all three, or `icons = true` to restore defaults. Disabling icons keeps the
callout text, line tint, and statusline count. New decorations use the updated
icons; existing decorations retain theirs until edited or recreated.

### Custom icon example

For Nerd Font icons (requires a Nerd Font in your terminal):

```lua
require("herdr-nvim").setup({
  icons = {
    comment = "󰅺",    -- comment callout and list title
    sign = "▎",       -- rail beside annotated lines
    statusline = "󰅺", -- e.g. "󰅺 3" for three pending comments
  },
})
```

For plain-text markers instead:

```lua
require("herdr-nvim").setup({
  icons = { comment = "#", sign = "|", statusline = "*" },
})
```

**herdr side** — `~/.config/herdr-nvim/config.toml` (optional; missing or
malformed files fall back to these defaults):

```toml
[sidebar]
nvim_bin = "nvim"     # binary used to spawn the per-tab nvim daemon
nvim_env = []         # env overrides for that nvim, applied to the daemon,
                      # the sidebar window, and open-file clients. For
                      # example, nvim_env = ["NVIM_APPNAME=myapp"] runs the
                      # sidebar under the config in ~/.config/myapp instead
                      # of vanilla nvim (replace myapp with your app name).
position = "right"    # right (default), left, top, or bottom

[picker]
scan_lines = 300    # pane lines scanned by the fallback text-scrape
max_files = 20      # session entries shown before you type a query
                    # (a typed query fuzzy-searches the whole repo, uncapped)
frecency = true     # let fff reuse ~/.cache/nvim/fff_nvim (read-only copy)
```

If your normal nvim config lives under a custom `NVIM_APPNAME` (any name you
launch `nvim` with — e.g. a distro or your own config directory), set
`sidebar.nvim_env = ["NVIM_APPNAME=myapp"]` so the sidebar's daemon and window
run that configuration too. Without it the sidebar is vanilla nvim. The daemon
still injects this plugin's lua over runtimepath after your config loads
(VimEnter fallback), so annotations work under any appname.

## Troubleshooting

```sh
herdr-nvim doctor                     # live checks: splits, toggle, daemon, remote-ui
herdr-nvim doctor --with-agent claude # also verify agent registration
```

Doctor runs labeled checks in a scratch workspace and always removes them
afterward. The most common failure is `daemon-healthy` FAIL: the nvim daemon
did not start. Make sure that `sidebar.nvim_bin` points at a working nvim ≥
0.10.

## Tests

```sh
nix develop       # Rust, Neovim, just, and native build dependencies
just ci           # cargo fmt + cargo test + headless Lua suite
nix flake check   # builds both packages and runs Rust/Lua tests
```

The development shell and packages support Linux on x86_64/AArch64 and
macOS on AArch64 (the pinned nixpkgs no longer supports Intel macOS). Dependencies are pinned in `flake.lock`.
