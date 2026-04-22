#!/usr/bin/env bash
# sync-posts.sh — heartbeat-lab/*.md → lab-site/posts/ with frontmatter
# Run from lab-site directory or set LAB_SITE_DIR
#
# Handles duplicate post numbers: if two files share the same number prefix,
# the second one is automatically renumbered to the next available number.
# Supports both 3-digit and 4-digit numbered files (001-999, 1000+).

set -euo pipefail

HEARTBEAT_DIR="${HEARTBEAT_DIR:-/mnt/ssd/openclaw-home/.openclaw/workspace/heartbeat-lab}"
POSTS_DIR="${LAB_SITE_DIR:-/mnt/ssd/openclaw-home/lab-site}/posts"

mkdir -p "$POSTS_DIR"

# Remove old posts
rm -f "$POSTS_DIR"/*.md

count=0

# Track used numbers via a temp file (compatible with bash 3.x)
used_nums_file=$(mktemp)
trap 'rm -f "$used_nums_file"' EXIT

# Collect all numbered source files (3-digit and 4-digit)
declare -a sources=()
for f in "$HEARTBEAT_DIR"/[0-9][0-9][0-9]_*.md "$HEARTBEAT_DIR"/[0-9][0-9][0-9][0-9]_*.md; do
  [ -f "$f" ] || continue
  sources+=("$f")
done

# Find the current max number for renumbering duplicates
max_num=0
for src in "${sources[@]}"; do
  bname=$(basename "$src")
  num="${bname%%_*}"
  num_int=$((10#$num))
  if [ "$num_int" -gt "$max_num" ]; then
    max_num=$num_int
  fi
done
next_num=$((max_num + 1))

for src in "${sources[@]}"; do
  filename=$(basename "$src")
  orig_num="${filename%%_*}"

  # Extract number (e.g., 001, 052, 357, 1000)
  num="$orig_num"
  num_int=$((10#$num))

  # Determine zero-padding width for output filename
  pad_width=3
  if [ "$num_int" -ge 1000 ]; then
    pad_width=4
  fi

  # If this number is already used, assign the next available number
  if grep -qx "$num" "$used_nums_file" 2>/dev/null; then
    new_num=$next_num
    # Determine padding for renumbered file
    new_pad=3
    if [ "$new_num" -ge 1000 ]; then
      new_pad=4
    fi
    new_num_padded=$(printf "%0${new_pad}d" $new_num)
    rest="${filename#${orig_num}_}"
    filename="${new_num_padded}_${rest}"
    num="$new_num_padded"
    num_int=$next_num
    next_num=$((next_num + 1))
    echo "WARNING: Duplicate number detected, renumbered to ${num}: ${rest}" >&2
  fi
  echo "$num" >> "$used_nums_file"

  # Extract title from first H1 line, stripping markdown heading and number prefix
  title=$(grep -m1 '^# ' "$src" | sed 's/^# //' | sed "s/^[0-9]*[: ]*//")

  # If title is empty, use filename
  if [ -z "$title" ]; then
    slug="${filename%.md}"
    # Remove number prefix (3 or 4 digits + underscore)
    slug=$(echo "$slug" | sed 's/^[0-9]*_//')
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