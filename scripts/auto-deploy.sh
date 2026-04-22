#!/usr/bin/env bash
# auto-deploy.sh — sync heartbeat-lab → posts, commit & push if changed
# Intended to run via cron every 30 min or so

set -euo pipefail

LAB_SITE_DIR="/mnt/ssd/openclaw-home/lab-site"
SCRIPT_DIR="${LAB_SITE_DIR}/scripts"

cd "$LAB_SITE_DIR"

# Step 1: sync posts from heartbeat-lab
bash "${SCRIPT_DIR}/sync-posts.sh"

# Step 2: stage all posts
git add posts/

# Step 3: check for changes (after staging, so new files are caught)
if git diff --cached --quiet; then
  # No changes
  exit 0
fi
git commit -m "auto: sync $(date '+%Y-%m-%d %H:%M') — $(git diff --cached --stat | tail -1)"
git push origin main
