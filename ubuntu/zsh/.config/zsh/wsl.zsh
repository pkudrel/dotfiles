# WSL only: Windows integration.

[[ -n "${WSL_DISTRO_NAME:-}" ]] || return 0

alias open='explorer.exe'   # open . / open file.pdf with the Windows default app
alias clip='clip.exe'       # echo text | clip

# SSH keys come from the Bitwarden desktop agent on Windows. It listens on the named pipe
# \\.\pipe\openssh-ssh-agent, which WSL cannot open, so socat serves a Unix socket and relays
# through npiperelay.exe (winget: albertony.npiperelay, found via the Windows PATH).
# Private keys never enter this distro; every use asks Bitwarden on the Windows side.
if (( $+commands[socat] && $+commands[npiperelay.exe] )); then
  export SSH_AUTH_SOCK="$HOME/.ssh/bitwarden-agent.sock"

  # The socket file survives wsl --shutdown while the relay does not, so ask who is listening.
  if ! ss -lx 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
    rm -f "$SSH_AUTH_SOCK"
    mkdir -p "${SSH_AUTH_SOCK:h}"
    setsid socat "UNIX-LISTEN:$SSH_AUTH_SOCK,fork" \
      "EXEC:npiperelay.exe -ei -s //./pipe/openssh-ssh-agent,nofork" >/dev/null 2>&1 &!
  fi
fi
