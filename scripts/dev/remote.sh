#!/bin/bash
set -euo pipefail

# Usage:
#   just remote <user>@<host> [port]

HOST_ALIAS="runpod.io"
REMOTE_HOST="${1:?remote host required (e.g. root@ip)}"
REMOTE_PORT="${2:-22}"
SSH_CONFIG="$HOME/.ssh/config"

# ------------------------------------------------------------------------------
# Remove previous runpod.io entry from ~/.ssh/config

if grep -q "Host ${HOST_ALIAS}" "$SSH_CONFIG" 2>/dev/null; then
  echo "Removing old '${HOST_ALIAS}' entry from $SSH_CONFIG..."

  awk -v host="$HOST_ALIAS" '
    # If this line starts a Host block, decide whether to skip it
    $1 == "Host" {
      # does the alias appear among the host patterns?
      skip = 0
      for (i = 2; i <= NF; i++) if ($i == host) { skip = 1; break }
      if (skip) { next }       # start skipping (don’t print this Host line)
    }

    # If we are currently skipping, keep skipping until the next Host line
    skip { next }

    # Otherwise, print the line
    { print }
  ' "$SSH_CONFIG" > "$SSH_CONFIG.tmp" && mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
fi

# ------------------------------------------------------------------------------
# Add new runpod.io entry with agent forwarding

cat >> "$SSH_CONFIG" <<EOF


Host ${HOST_ALIAS}
    HostName $(echo "$REMOTE_HOST" | cut -d@ -f2)
    Port ${REMOTE_PORT}
    User $(echo "$REMOTE_HOST" | cut -d@ -f1)
    ForwardAgent yes
    IdentitiesOnly yes
EOF

# Squash consecutive blank lines
awk 'NF{blank=0} !NF{blank++} blank<2' "$SSH_CONFIG" > "${SSH_CONFIG}.tmp" \
  && mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"

echo "Added '${HOST_ALIAS}' entry to $SSH_CONFIG."

# ------------------------------------------------------------------------------
# Clone the current directory repository remotely into /workspace

REPO_NAME=$(basename "$PWD")
REPO_URL=$(git remote get-url origin)
TARGET_DIR="/workspace/$REPO_NAME"

echo "Cloning repo $REPO_URL to ${TARGET_DIR} on ${REMOTE_HOST}..."

ssh -A "${HOST_ALIAS}" bash -se <<EOF
set -euo pipefail

if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "==> Cloning fresh repo into $TARGET_DIR"
  git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "==> Repo already exists in $TARGET_DIR, skipping clone."
fi
EOF

echo "Done. You can now connect with:"
echo "  code --folder-uri 'vscode-remote://ssh-remote+${HOST_ALIAS}${TARGET_DIR}'"
