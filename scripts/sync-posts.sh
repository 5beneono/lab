#!/usr/bin/env bash
# sync-posts.sh — heartbeat-lab/*.md → lab-site/posts/ with frontmatter
# Run from lab-site directory or set LAB_SITE_DIR

set -euo pipefail

HEARTBEAT_DIR="${HEARTBEAT_DIR:-/mnt/ssd/openclaw-home/.openclaw/workspace/heartbeat-lab}"
POSTS_DIR="${LAB_SITE_DIR:-/mnt/ssd/openclaw-home/lab-site}/posts"

mkdir -p "$POSTS_DIR"

# Remove old posts
rm -f "$POSTS_DIR"/*.md

count=0

for src in "$HEARTBEAT_DIR"/[0-9][0-9][0-9]_*.md; do
  [ -f "$src" ] || continue
  
  filename=$(basename "$src")
  
  # Extract number (e.g., 001, 052, 357)
  num="${filename%%_*}"
  # Remove leading zeros for ordering
  num_int=$((10#$num))
  
  # Extract title from first H1 line, stripping markdown heading and number prefix
  title=$(grep -m1 '^# ' "$src" | sed 's/^# //' | sed "s/^${num}[: ]*//")
  
  # If title is empty, use filename
  if [ -z "$title" ]; then
    slug="${filename%.md}"
    slug="${slug#[0-9][0-9][0-9]_}"
    title="$slug"
  fi
  
  # Extract date from second line if it looks like YYYY-MM-DD
  date_line=$(sed -n '2p' "$src" | grep -oP '^\d{4}-\d{2}-\d{2}' || echo "")
  # Also try third line
  if [ -z "$date_line" ]; then
    date_line=$(sed -n '3p' "$src" | grep -oP '\d{4}-\d{2}-\d{2}' || echo "")
  fi
  # Fallback: file modification time
  if [ -z "$date_line" ]; then
    date_line=$(date -r "$src" '+%Y-%m-%d')
  fi
  
  # Get content after the first heading line (skip H1 and optional date line)
  # We'll include everything starting from the first ## or paragraph
  content=$(tail -n +2 "$src")
  # Strip leading date-only line if present
  content=$(echo "$content" | sed '/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/{ /^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\s*$/d; }' | sed '/^$/{ 1d; }')
  
  # Write post with frontmatter
  outfile="$POSTS_DIR/${filename}"
  cat > "$outfile" <<EOF
---
title: "${title//\"/\\\"}"
date: ${date_line}
order: ${num_int}
tags: []
---

${content}
EOF
  
  count=$((count + 1))
done

echo "Synced ${count} posts to ${POSTS_DIR}"
