# Nerd Fonts (MesloLGS NF, Consolas NF)

Powerlevel10k needs a Nerd Font on the machine that **displays** the terminal:
your Windows computer, also when you work on a server over SSH.

## Install (once per Windows computer)

From a WSL terminal:

```bash
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.dotfiles/windows/fonts/install-nerd-font.ps1)"
```

or from PowerShell in a Windows clone of this repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\fonts\install-nerd-font.ps1
```

The script installs MesloLGS NF for the current user only (no admin needed). Re-running is safe.

## Consolas NF

`ConsolasNF.ttf` (Microsoft's Consolas with Nerd Font glyphs, a single regular weight) is **not in the repo**:
Consolas is licensed with Windows and Office and may not be redistributed. It is an attachment of the Bitwarden note
`bitwarden-store`, installed by the Windows install step `bitwarden-store` (`_manifest.txt` line with the action `font`),
see [Private files](../../README.md#private-files-bitwarden-store). Until then Windows Terminal, which defaults to
`Consolas NF`, shows its own font; `MesloLGS NF` from the script above works everywhere.

## Use it

The default is `Consolas NF`; `MesloLGS NF` (four weights, the Powerlevel10k recommendation) is the alternative.

**Windows Terminal:** the repo's `windows/terminal/settings.json` (install step `terminal`)
already sets `Consolas NF` in *Defaults*. By hand: Settings → *Defaults* → Appearance → Font face: `Consolas NF`.
Set it in *Defaults* instead of a single profile: every new WSL distro gets its own profile.

Same in `settings.json`:

```json
"profiles": { "defaults": { "font": { "face": "Consolas NF" } } }
```

**VS Code** (local, WSL and Remote-SSH terminals):

```json
"terminal.integrated.fontFamily": "Consolas NF"
```

Restart Windows Terminal / VS Code after installing the font.
