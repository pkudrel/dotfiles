#!/usr/bin/env bash
# Link Stow packages into $HOME. Conflicting files are moved to $BACKUP_DIR first.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command_exists stow || die "stow is not installed (run the apt step first)"

# Linked file by file: directories such as ~/.config/zsh stay real directories.
file_packages=(zsh git)

for pkg in "${file_packages[@]}"; do
  while IFS= read -r -d '' src; do
    backup_file "$HOME/${src#"$UBUNTU_DIR/$pkg/"}"
  done < <(find "$UBUNTU_DIR/$pkg" \( -type f -o -type l \) -print0)
done

# Claude Code skills are no longer in the repo (they come from Bitwarden-store): drop the old link into it.
if [[ -L "$HOME/.claude/skills" && "$(readlink "$HOME/.claude/skills")" == *"ubuntu/claude/.claude/skills"* ]]; then
  rm "$HOME/.claude/skills"
  ok "removed the old link ~/.claude/skills (skills now come from Bitwarden-store)"
fi

stow --dir "$UBUNTU_DIR" --target "$HOME" --no-folding --restow "${file_packages[@]}"
ok "stowed: ${file_packages[*]}"
