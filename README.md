# dotfiles

`ubuntu/` and `windows/` are independent: neither uses files from the other.

## Contents

- [New WSL (Ubuntu 26.04)](#new-wsl-ubuntu-2604)
- [New server (native Ubuntu 26.04, over SSH)](#new-server-native-ubuntu-2604-over-ssh)
- [New Windows machine (Windows 11)](#new-windows-machine-windows-11)
  - [Step 0: the account (before anything else)](#step-0-the-account-before-anything-else)
  - [Step 1: setup](#step-1-setup)
  - [Windows install steps (install.ps1)](#windows-install-steps-installps1)
  - [Windows admin steps (admin.ps1)](#windows-admin-steps-adminps1)
  - [Windows optional features](#windows-optional-features)
  - [Windows: PowerShell profile and commands](#windows-powershell-profile-and-commands)
- [What you get](#what-you-get)
- [SSH keys in WSL (Bitwarden)](#ssh-keys-in-wsl-bitwarden)
- [Private files (Bitwarden-store)](#private-files-bitwarden-store)
- [Everyday use](#everyday-use)
- [dlab commands](#dlab-commands)
- [Versions](#versions)
- [fzf shortcuts](#fzf-shortcuts)
- [Optional features](#optional-features)
- [Which files are linked, copied or not in the repo](#which-files-are-linked-copied-or-not-in-the-repo)
- [Adding a tool later](#adding-a-tool-later)

## New WSL (Ubuntu 26.04)

Prerequisites on Windows: **Git for Windows** (provides Git Credential Manager) and Windows Terminal.

```powershell
wsl --list --online            # exact distro name
wsl --install -d Ubuntu-26.04
```

In the new Ubuntu:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/pkudrel/dotfiles.git ~/.dotfiles
~/.dotfiles/ubuntu/install.sh
exec zsh
```

The repo is public, so the clone needs no sign-in. For pushing, `install.sh` stores Git Credential Manager (from
Git for Windows) as the credential helper in `~/.gitconfig.local`.

After that:

1. Nerd Font, once per Windows computer: see [`windows/fonts/README.md`](windows/fonts/README.md).
   `install.sh` asked for the Bitwarden master password for the [private files](#private-files-bitwarden-store);
   Enter skipped it: later `dlab-store-restore`.
2. SSH keys from Bitwarden, once per Windows computer: see [SSH keys in WSL](#ssh-keys-in-wsl-bitwarden).
3. Optional tools you want on this machine: `dlab-features-select` (Claude Code is one of them;
   after installing it, run `claude` once to log in).

## New server (native Ubuntu 26.04, over SSH)

GitHub access on the server uses **SSH agent forwarding**: your key stays on your computer, the server has no key or token.
Git on the server works only while you are connected.

Prerequisites on your computer: ssh-agent running with your GitHub key, and `ForwardAgent yes` for the server
(or connect with `ssh -A`). VS Code Remote-SSH forwards the agent automatically.
With Tailscale, connect with **regular OpenSSH** over the tailnet (`ssh <tailscale-host>`), not Tailscale SSH,
unless you have verified that Tailscale SSH forwards the agent.

```bash
ssh -A <server>
ssh-add -l                      # on the server: must list your key
sudo apt update && sudo apt install -y git
git clone git@github.com:pkudrel/dotfiles.git ~/.dotfiles
~/.dotfiles/ubuntu/install.sh
exit                            # reconnect to get zsh
```

No font on the server: set `Consolas NF` (or `MesloLGS NF`) in the terminal on your computer and in VS Code
(`terminal.integrated.fontFamily`), see [`windows/fonts/README.md`](windows/fonts/README.md).

## New Windows machine (Windows 11)

### Step 0: the account (before anything else)

The profile folder gets its name when the account is created and keeps it: with a Microsoft account Windows takes the
first five characters of the e-mail address (`C:\Users\piotr`). To get `C:\Users\pkudrel`, the account you work in
must be created as `pkudrel`:

- **Installing from USB**: make the stick with [Rufus](https://rufus.ie) from the Windows 11 ISO and, in its
  "Windows User Experience" dialog, tick *Remove requirement for an online Microsoft account* and
  *Create a local account using the username* `pkudrel`. Setup creates the account itself.
- **Pre-installed Windows** (no reinstall): finish the first setup with the Microsoft account, then in PowerShell as
  administrator create the real account, sign out and sign in as `pkudrel` (this creates `C:\Users\pkudrel`),
  and remove the first account in Settings → Accounts → Other users:

  ```powershell
  $pw = Read-Host 'Password for pkudrel' -AsSecureString
  New-LocalUser -Name pkudrel -Password $pw -FullName 'Piotr Kudrel'
  Add-LocalGroupMember -Group Administrators -Member pkudrel
  ```

Either way, link the Microsoft account afterwards if you want it (Settings → Accounts → Your info → Sign in with a
Microsoft account instead); the folder stays `pkudrel`. Skip the OOBE tricks (`Shift+F10`, `oobe\bypassnro`, ...):
Microsoft removes them from newer builds. Nothing in this repo depends on the user name.

### Step 1: setup

Windows 11 already has winget and Windows PowerShell; nothing else is needed up front. If `winget` is missing on a fresh
install: Microsoft Store → Library → Get updates (it updates "App Installer").

Signed in as `pkudrel`, in Windows Terminal, **Windows PowerShell, not as administrator**, paste:

```powershell
winget install -e --id Bitwarden.Bitwarden --source winget --accept-package-agreements --accept-source-agreements
winget install -e --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
winget install -e --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
git clone https://github.com/pkudrel/dotfiles.git "$HOME\.dotfiles"
pwsh -ExecutionPolicy Bypass -File "$HOME\.dotfiles\windows\setup.ps1"
```

Bitwarden, Git and PowerShell 7 come from winget; the `$env:Path` line lets this window see them.

The repo is public, so the clone needs no sign-in. The first push asks you to sign in to GitHub (Git Credential
Manager, part of Git): the GitHub login is in Bitwarden, or choose **Sign in with a code** and enter the code at
`github.com/login/device` on a phone that is already signed in to GitHub.

The repo lives in `C:\Users\<you>\.dotfiles`; nothing depends on the user name.
Then `windows\setup.ps1` (`-DryRun` to preview) runs:

1. a winget check;
2. `admin.ps1`: one UAC prompt, the [admin steps](#windows-admin-steps-adminps1), including the `W:` Dev Drive (it shows
   the plan and waits for `yes`);
3. `install.ps1`: the [install steps](#windows-install-steps-installps1). Some installers (Chrome, 7-Zip, ...) ask for
   UAC themselves;
4. the [optional features](#windows-optional-features) checklist;
5. a checklist of what is left to do by hand, and a restart when the admin steps need one.

Then, once per machine (`setup.ps1` prints the same list):

- Bitwarden: sign in, **Settings → enable SSH agent**. It holds all secrets, including the SSH keys; `ssh` on Windows
  and in WSL (see [SSH keys in WSL](#ssh-keys-in-wsl-bitwarden)) and git over SSH use it, no key on disk.
- Google Drive and Obsidian: sign in / open the vault.
- If you picked them: `sbx login`, `claude` (log in), QuickGestures in Brave (the feature prints the steps).

Update later: `dlab-dotfiles-update` (`git pull --ff-only` + `install.ps1`).

### Windows install steps (install.ps1)

`windows\install.ps1` runs `windows\scripts\NN-*.ps1` in order; `install.ps1 winget terminal` runs only matching steps.
Safe to re-run: done steps only print `ok`. Replaced files are copied to `~\.dotfiles-backup\<timestamp>\` first.
`install.ps1 -DryRun` lists what it would do (packages missing, files to write) without changing anything;
`features.ps1 --update --dry-run` does the same for features. Packages and features show progress as `[3/15]`.

| Step | What it does |
|------|--------------|
| `execution-policy` | RemoteSigned for the current user when scripts are blocked |
| `winget` | packages in [`windows/packages/winget.txt`](windows/packages/winget.txt) that are missing (upgrades: `dlab-winget-upgradeall`) |
| `modules` | posh-git, Terminal-Icons, DockerCompletion |
| `local-files` | `Documents\PowerShell\profile.local.ps1`, `~\.gitconfig.local` from `windows/templates/` (only when missing) |
| `profile` | `Documents\PowerShell\profile.ps1` becomes a loader for `windows\powershell\profile.ps1` |
| `git` | `~\.gitconfig` gets an `[include]` of `windows/git/.gitconfig` at the top (its other settings stay) |
| `font` | MesloLGS NF for the current user |
| `terminal` | Windows Terminal `settings.json` from `windows/terminal/settings.json`; when they differ it asks before replacing |
| `bitwarden-store` | [private files](#private-files-bitwarden-store) from the Bitwarden note `Bitwarden-store`; asks for the master password (Enter skips the step), UAC for folders like Program Files |
| `features` | installs/updates the remembered optional features |

Windows Terminal: the repo keeps the whole `settings.json`. Save this machine's version into the repo with
`dlab-terminal-save` and commit it. Profiles Windows Terminal adds by itself (WSL distros, Visual Studio shells) come back
on their own after a replace.

### Windows admin steps (admin.ps1)

`windows\admin.ps1` needs administrator rights and asks for them itself. `-DryRun` shows what would change.

| Step | What it does |
|------|--------------|
| `hypervisor-platform` | a hypervisor for `sbx`: skipped when Hyper-V or Virtual Machine Platform is on, else enables Windows Hypervisor Platform; restart |
| `dev-drive` | `W:` ReFS Dev Drive, label `Work`, 195 GB taken from `C:`, trusted. Skipped when `W:` already is one. Asks before shrinking `C:`. Other size/letter: `admin.ps1 -DevDriveSizeGB 250 -DevDriveLetter D` |
| `bitlocker` | checks that `C:` is protected; encrypts `W:` like `C:` with automatic unlock when it is not; asks whether to save the recovery keys of all drives to Bitwarden (bw CLI): a secure note "BitLocker recovery keys - <computer>", one hidden field per drive, never written to a file or shown |
| `drive-letters` | letters from [`windows/config/drive-letters.txt`](windows/config/drive-letters.txt) (`Q:` → `%USERPROFILE%\!others`); restart |
| `ssh-agent-service` | Windows "OpenSSH Authentication Agent" off, so Bitwarden's agent gets the pipe |
| `wsl` (only when named) | `admin.ps1 wsl`: WSL with Ubuntu-26.04, then [New WSL](#new-wsl-ubuntu-2604) from "In the new Ubuntu" |
| `remove-onedrive` (only when named) | `admin.ps1 onedrive`: uninstall OneDrive, block it by policy, hide it in Explorer |

Drive letters use `%USERPROFILE%` of the account that runs the elevated step: run `admin.ps1` from your own account.

### Windows optional features

```powershell
dlab-features-select            # checklist: arrows move, Space toggles, Enter installs
dlab-features-select dotnet sbx # the same without the checklist
dlab-features-list              # state of every feature
```

Before the first new tab (no `dlab-*` yet): `~\.dotfiles\windows\features.ps1` with the same arguments.
Features are installed from winget whenever possible ([`windows/features/winget.txt`](windows/features/winget.txt):
dotnet, node, uv, claude-code, docker-desktop, sbx, azure-cli, storage-explorer, helm, tailscale, sourcetree,
editplus, irfanview). Two are scripts because winget does not have them:

| Feature | What gets installed | After install |
|---------|---------------------|---------------|
| `sbxup` | [sbxup](https://github.com/deneblab/sbx-templates) (official installer, `--self-update` later) | needs the `sbx` feature; `sbx login` |
| `quickgestures` | [QuickGestures](https://github.com/deneblab/QuickGestures) release in `%LOCALAPPDATA%\dotfiles\QuickGestures` | Brave: `brave://extensions` → Developer mode → Load unpacked → that folder; after updates click reload |

The selection is remembered in `~\.config\dotfiles\features`; `install.ps1` updates those features on every run.
New winget feature: one line in `features/winget.txt`. Other: a script `features/NN-name.ps1` (line 1 = description,
actions `status` / `install`, like the two above).

### Windows: PowerShell profile and commands

- Edit the profile in the repo (`windows\powershell\profile.ps1`); changes apply in the next `pwsh` tab.
  Machine-only settings: `Documents\PowerShell\profile.local.ps1` (not in the repo, loaded last).
- Fast start: before the prompt the profile loads only PSReadLine, Oh My Posh, `dlab-*` and the local profile.
  Terminal-Icons loads right after the prompt shows (`$ProfileIdleTimings`); posh-git, DockerCompletion and Task
  completion load on the first `git`/`docker`/`task` Tab. The `Profile:` line shows the eager steps and the total in ms.
- `dlab-*` commands like on Ubuntu (`windows\powershell\dlab.ps1`, `dlab-help`): `dlab-dotfiles-update`, `-status`,
  `-version`, `-cd`, `-edit`, `dlab-features-select`, `-list`, `-update`, `dlab-store-restore` (and the other `dlab-store-*`), `dlab-terminal-save`,
  `dlab-winget-upgradeall`.
  Also `t` (Task).
- Git on Windows: shared settings in `windows/git/.gitconfig` (`autocrlf=true`, SSH through Windows OpenSSH → Bitwarden);
  machine settings in `~\.gitconfig.local` or below the include in `~\.gitconfig`.
- Only profile steps (the old way): `windows\powershell\install-profile.ps1` still works and runs those steps of `install.ps1`.
- From WSL both clones are visible: `~/.dotfiles` (WSL) and `/mnt/c/Users/<you>/.dotfiles` (Windows) are separate repos.

## What you get

- zsh + Oh My Zsh, Powerlevel10k (lean preset restyled like Oh My Posh "paradox": powerline segments, blue `❯`), zsh-autosuggestions, zsh-syntax-highlighting
  (long paths collapse like paradox: `~ > 📂 > src > Rules`; middle folders longer than `MY_DIR_MIXED_THRESHOLD` in `.p10k.zsh` become an icon)
- fzf (Ctrl+R history, **Alt+T** files, Alt+C cd), zoxide, eza, bat, fd, ripgrep
  (Ctrl+T is "new tab" in Windows Terminal, so files are on Alt+T; see [fzf shortcuts](#fzf-shortcuts))
- git config with aliases, `pull` = merge
- WSL: SSH keys served by the Bitwarden desktop agent on Windows (see [SSH keys in WSL](#ssh-keys-in-wsl-bitwarden))
- Private files from one Bitwarden secure note, on Windows and Ubuntu (see [Private files](#private-files-bitwarden-store))
- Optional features from a checklist: uv, node (fnm), .NET SDK 10, Docker Engine, Tailscale, Claude Code (see [Optional features](#optional-features))
- `EDITOR`: `code --wait` inside a VS Code terminal, otherwise `nano`

## SSH keys in WSL (Bitwarden)

In WSL, `ssh` gets its keys from the **Bitwarden desktop agent running on Windows**. No private key is
copied into the distro, and every use of a key asks Bitwarden on the Windows side.

Bitwarden serves the agent on the Windows named pipe `\\.\pipe\openssh-ssh-agent`, which WSL cannot open
directly. `~/.config/zsh/wsl.zsh` therefore points `SSH_AUTH_SOCK` at `~/.ssh/bitwarden-agent.sock` and, when
nothing is listening there yet, starts `socat` to relay that socket through `npiperelay.exe`. It starts once
per distro boot, from whichever shell comes first; further shells reuse it.

Three one-off steps on each Windows computer:

```powershell
winget install --id albertony.npiperelay -e
```

1. The command above (per user, no admin). `albertony.npiperelay` is the maintained fork;
   `jstarks.npiperelay` in winget is the abandoned original.
2. Bitwarden Desktop → **Settings** → enable the **SSH agent**.
3. **Services** → **OpenSSH Authentication Agent** → Startup type **Disabled**. It claims the same named
   pipe as Bitwarden, and whichever starts first wins. `windows\admin.ps1` does this (step `ssh-agent-service`), and
   `install.ps1` installs npiperelay (step 1) with the other winget packages.

Then, in a new WSL shell:

```bash
ssh-add -l                      # must list the keys held in Bitwarden
```

Empty or an error: unlock Bitwarden, check its SSH agent setting, and confirm `npiperelay.exe` is reachable
from WSL (`command -v npiperelay.exe`). `install.sh` installs `socat` and reports what is missing.

Git in WSL is unaffected: it uses HTTPS with Git Credential Manager, not the agent. The agent serves `ssh`
itself and any repository whose remote is SSH. On a native server none of this applies — there SSH keys come
from the agent you forward over the connection.

## Private files (Bitwarden-store)

Files that must not be in the repo are attachments of **one Bitwarden secure note named `Bitwarden-store`** (attachments
need Bitwarden Premium). The repo knows only what can be done with a file; the list of files and where they go is the
attachment **`_manifest.txt`** of the same note. The note's text stays empty.

The install step `bitwarden-store` (Windows `install.ps1`, Ubuntu `install.sh`; again later with `dlab-store-restore`)
asks for the master password once (Enter skips), reads `_manifest.txt`, and applies every line for this system and computer.
A file that differs is overwritten; an equal one is left alone (no write, no UAC). Downloads go to
`~/.dotfiles/local/tmp/` and are removed at the end, also after an error.

`_manifest.txt` (plain text; `#` starts a comment line):

```text
format: 1
# attachment        | system  | action | action params          | extra
example-license.key | windows | copy   | %ProgramFiles%\ExampleApp\license.key
ExampleFont.ttf     | windows | font
example.conf        | all     | copy   | ~/.config/example/example.conf | when=missing
example.zip         | all     | unzip  | ~/example
id_example          | linux   | copy   | ~/.ssh/id_example      | mode=600
```

| Column | Values |
|--------|--------|
| attachment | exact attachment name on `Bitwarden-store` (one attachment may be used by several lines) |
| system | `windows`, `linux` (Ubuntu and WSL) or `all` |
| action | `copy`: to the path in *action params* (`~` on both systems, `%VAR%` on Windows, `$VAR` on Linux; must be absolute; folders are created; UAC for folders like Program Files). `font`: install the `.ttf`/`.otf` for the current user (no params). `unzip`: unpack the `.zip` into the folder in *action params* (files that differ are overwritten, others are left alone) |
| extra | `host=PC1,PC2` only on these computers; `when=missing` only when the file does not exist yet (for files an app changes itself; default `always`); `mode=600` file permissions on Linux |

A line with a mistake (unknown action or option, relative path, missing attachment) is reported and skipped; the rest
still runs. The summary shows `ok / updated / skipped / errors`.

Change the store with the `dlab-store-*` commands (Windows `windows\store.ps1`, Ubuntu `ubuntu/store.sh`); no change in
the repo. Each asks for the master password once and, after a change, updates this machine in the same session:

| Command | What it does |
|---------|--------------|
| `dlab-store-list` | attachments, the manifest lines that use them, lines without an attachment, unused attachments |
| `dlab-store-add <file>` | opens `_manifest.txt` in the editor with a line for the file to complete (target path); after a valid save uploads the file and the manifest |
| `dlab-store-replace <file>` | new version of the attachment with that file name; the old one stays as `<name>.prev` |
| `dlab-store-remove <name>` | shows the manifest lines of the attachment, asks, removes both (the file stays as `<name>.prev`) |
| `dlab-store-manifest-edit` | edits `_manifest.txt` (a template when there is none); a manifest with mistakes is shown again, not saved |
| `dlab-store-restore` | the install step again: put every file in place |

Every save keeps one step back: `<name>.prev` (also `_manifest.txt.prev`). A replace deletes the old attachment before
the upload (Bitwarden cannot edit an attachment in place, and two with one name would block it); if the upload fails, the
old version is `<name>.prev` and running the same command again finishes it. Editor: `$EDITOR` (Windows: else VS Code,
else Notepad; Ubuntu: else `nano`). `add` and `manifest-edit` create the secure note when it does not exist yet (asks).

`~/.dotfiles/local/` is this machine's folder inside the repo, in `.gitignore`: never commit anything from it.

## Everyday use

| Task | Command |
|------|---------|
| Update this machine | `dlab-dotfiles-update` (= `git pull --ff-only` + `install.sh` + new shell) |
| Private files again (after a change in Bitwarden) | `dlab-store-restore` |
| Run selected steps only | `~/.dotfiles/ubuntu/install.sh stow cli` (matches step names) |
| Pick optional features | `dlab-features-select` |
| Machine-local git setting | `git config --file ~/.gitconfig.local <key> <value>` |

`install.sh` never overwrites your files silently: anything in the way of a link is moved to
`~/.dotfiles-backup/<timestamp>/`.

A plain `git pull` does not link new files (e.g. a new zsh module): run `dlab-dotfiles-stow` and `exec zsh` afterwards,
or update with `dlab-dotfiles-update`, which does both.

## dlab commands

Shell functions named `dlab-{area}-{action}` (`ubuntu/zsh/.config/zsh/dlab.zsh`). Type `dlab-<Tab>` or `dlab-help`.

| Command | What it does |
|---------|--------------|
| `dlab-dotfiles-update` | `git pull --ff-only`, then `install.sh`, then a new shell; stops at the first error (also when the history differs from GitHub instead of merging it) |
| `dlab-dotfiles-status` | compare with GitHub: this machine's version vs the latest, local changes, commits to pull / not pushed (fetches first) |
| `dlab-dotfiles-version` | version of this machine's dotfiles, e.g. `0.1.8` or `0.1.8 +2 commits` (local, no network) |
| `dlab-dotfiles-cd` | go to `~/.dotfiles` |
| `dlab-dotfiles-edit` | open `~/.dotfiles` in VS Code |
| `dlab-dotfiles-stow` | re-link config files (`install.sh stow`), e.g. after new zsh modules |
| `dlab-store-restore` | [private files](#private-files-bitwarden-store) from Bitwarden (`install.sh bitwarden-store`; asks for the master password) |
| `dlab-store-list`, `-add`, `-replace`, `-remove`, `-manifest-edit` | change what is in Bitwarden-store, see [Private files](#private-files-bitwarden-store) |
| `dlab-features-select` | optional features checklist; with names installs them directly |
| `dlab-features-list` | state of every optional feature |
| `dlab-features-update` | install/update the remembered features |
| `dlab-help` | list of these commands |

New command: add a function and a `DLAB_COMMANDS[name]` description to `dlab.zsh`.

## Versions

Every push to `main` gets a semantic version, e.g. `0.1.8`:

- GitHub Actions (`.github/workflows/version.yml`) computes it with [abcversion](https://github.com/deneblab/abcversion)
  and creates a GitHub Release for it, which also creates the tag `v<version>`.
- The Release notes and the Actions run summary list the commits since the previous version
  (subjects, with the full commit messages under "Details"). Re-running the workflow refreshes the notes.
- **Patch** = number of commits on `main` (first-parent), so it grows with every commit.
- **Minor / major**: change `BaseVersion` in `.abcversion.json` (the patch keeps counting all commits, e.g. `0.2.15`).
- On a machine: `dlab-dotfiles-version` shows the local version (no network);
  `dlab-dotfiles-status` fetches from GitHub and compares it with the latest version there.
- Tags and Releases come only from the workflow; don't create them by hand.

## fzf shortcuts

In the shell:

| Keys | What it does |
|------|--------------|
| `Ctrl+R` | Search command history, `Enter` puts the command on the prompt |
| `Alt+T` | Pick files and paste their paths at the cursor |
| `Alt+C` | Pick a directory and `cd` into it |
| `**` then `Tab` | Fuzzy completion for the current command, e.g. `nano **<Tab>`, `cd **<Tab>`, `kill **<Tab>`, `ssh **<Tab>` |

`Alt+T` and `Alt+C` list files with `fd`: hidden files included, `.git` excluded.
fzf's usual `Ctrl+T` is not used here: Windows Terminal takes it for "new tab", so the file picker is on `Alt+T`.

Inside the fzf list:

| Keys | What it does |
|------|--------------|
| `↑` / `↓` or `Ctrl+K` / `Ctrl+J` | Move |
| `Enter` | Accept |
| `Tab` / `Shift+Tab` | Mark / unmark several items (file picker and `**` completion) |
| `Ctrl+R` | In history search: toggle sorting by relevance / by time |
| `Esc` or `Ctrl+C` | Cancel |

Search syntax: `word` fuzzy, `'word` exact, `^word` starts with, `word$` ends with, `!word` exclude,
`a | b` either; separate terms with spaces to match all of them.

## Optional features

Extra tools that not every machine needs. Pick them once per machine:

```bash
dlab-features-select            # checklist: Space selects, Enter installs
dlab-features-select uv node    # the same without the checklist
dlab-features-list              # state of every feature
```

On a fresh machine before the first new shell (no `dlab-*` commands yet), use `~/.dotfiles/ubuntu/features.sh`
with the same arguments (`uv node`, `--list`, `--update`).

| Feature | What gets installed | After install |
|---------|---------------------|---------------|
| `uv` | uv in `~/.local/bin` (official installer) | `uv python install`, `uv init`, `uv run` |
| `node` | fnm in `~/.local/bin`, latest Node.js LTS as default | version follows `.nvmrc` / `.node-version` on `cd` |
| `dotnet` | .NET SDK 10 in `~/.dotnet` (`dotnet-install.sh`), native libraries from apt | new shell: `dotnet --version` |
| `docker` | Docker Engine, buildx and compose from Docker's apt repository; you join the `docker` group | log out and back in, then `docker run hello-world` |
| `tailscale` | Tailscale from its official install script, `tailscaled` enabled | `sudo tailscale up` once |
| `claude-code` | Claude Code CLI in `~/.local/bin` (official installer, self-updating) | `claude` once to log in |

- The selection is remembered in `~/.config/dotfiles/features`. `install.sh` updates the remembered features on every run.
  Unticking a feature stops the updates; it does not uninstall anything.
- `docker` and `tailscale` need systemd. On WSL: `systemd=true` under `[boot]` in `/etc/wsl.conf`, then `wsl --shutdown`.
- Membership in the `docker` group is effectively root access.
- WSL: turn off Docker Desktop's WSL integration for this distro, otherwise its CLI shadows Docker Engine.
  After joining the `docker` group, close all terminals of the distro or run `wsl --terminate <distro>`.
- WSL: Tailscale inside the distro is a separate device in your tailnet, next to the Windows client.

## Which files are linked, copied or not in the repo

| Group | Files | Behaviour |
|-------|-------|-----------|
| Linked (Stow) | `~/.zshrc`, `~/.config/zsh/*.zsh`, `~/.p10k.zsh`, `~/.gitconfig` | edit in place, changes show up in `git status` here |
| Copied once from `ubuntu/templates/` | `~/.zshrc.local`, `~/.gitconfig.local`, `~/.agents/config.md`, `~/.claude/settings.json` | created only when missing, never overwritten |
| From Bitwarden (`bitwarden-store`) | `~/.dotfiles/local/`, files placed by `_manifest.txt` | `local/` is in `.gitignore`; overwritten from Bitwarden when different |
| Not in the repo | shell history, zsh caches, Oh My Zsh and plugins, fonts, `~/.agents/issues/*`, the rest of `~/.claude`, optional features and their selection (`~/.config/dotfiles/features`) | installed or created by tools |

Rules:

- **Machine-specific settings** go to `~/.zshrc.local` / `~/.gitconfig.local`; **private files** to `Bitwarden-store`.
- **Never `git config --global`**: it writes into the shared `~/.gitconfig` in this repo. Use `--file ~/.gitconfig.local`.
- **Copied files do not sync back.** If you change `~/.claude/settings.json` or `~/.agents/config.md` and want the change on
  new machines, copy it into `ubuntu/templates/` and commit.
- **Installers that append to `~/.zshrc`** (nvm, rustup, …) will show up in `git status`; move those lines into a module
  in `ubuntu/zsh/.config/zsh/` or into `~/.zshrc.local`.
- After `p10k configure`, check that `~/.p10k.zsh` is still a link (`ls -l ~/.p10k.zsh`).

## Adding a tool later

Every machine needs it → base step. Only some machines → optional feature.

- Base step: `ubuntu/scripts/NN-<tool>.sh` (idempotent, `source lib.sh`), then `install.sh <tool>`.
- Optional feature: `ubuntu/features/NN-<tool>.sh` with a one-line description on line 2 and two commands:
  `status` (print the state; exit 0 installed, 1 not installed, 2 not available here) and `install`
  (install or update, idempotent). `features.sh` picks it up automatically.
- Shell setup for either: `ubuntu/zsh/.config/zsh/<tool>.zsh`, returning early when the tool is missing.
  Slow tab-completion generators: `cached_completion <command> <generator…>` from `env.zsh` (generated once,
  loaded on the first Tab; see `uv.zsh`).
