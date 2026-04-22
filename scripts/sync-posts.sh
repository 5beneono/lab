#!/usr/bin/env bash
# sync-posts.sh — heartbeat-lab/*.md → lab-site/posts/ with frontmatter
# Generates romaji slugs from Japanese titles for stable, number-independent URLs.
# Handles duplicate post numbers: renumbers to next available.
# Supports both 3-digit and 4-digit numbered files (001-999, 1000+).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_SITE_DIR="$(dirname "$SCRIPT_DIR")"
HEARTBEAT_DIR="${HEARTBEAT_DIR:-/mnt/ssd/openclaw-home/.openclaw/workspace/heartbeat-lab}"
POSTS_DIR="${LAB_SITE_DIR}/posts"
VENV_PYTHON="${LAB_SITE_DIR}/.venv/bin/python3"

mkdir -p "$POSTS_DIR"

# Remove old posts
rm -f "$POSTS_DIR"/*.md

count=0

# Track used numbers via a temp file
used_nums_file=$(mktemp)
trap 'rm -f "$used_nums_file" "$slugs_tmpfile"' EXIT

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

# Step 1: Extract all titles and generate slugs in batch (much faster than per-file Python)
slugs_tmpfile=$(mktemp)
if [ -x "$VENV_PYTHON" ]; then
  for src in "${sources[@]}"; do
    title=$(grep -m1 '^# ' "$src" | sed 's/^# //' | sed "s/^[0-9]*[: ]*//")
    if [ -z "$title" ]; then
      filename=$(basename "$src")
      title="${filename%.md}"
      title=$(echo "$title" | sed 's/^[0-9]*_//')
    fi
    echo "$title"
  done | "$VENV_PYTHON" "${SCRIPT_DIR}/batch_slug.py" > "$slugs_tmpfile"
else
  # Fallback: hash-based slugs
  for src in "${sources[@]}"; do
    title=$(grep -m1 '^# ' "$src" | sed 's/^# //' | sed "s/^[0-9]*[: ]*//")
    if [ -z "$title" ]; then
      filename=$(basename "$src")
      title="${filename%.md}"
      title=$(echo "$title" | sed 's/^[0-9]*_//')
    fi
    echo -n "$title" | sha256sum | cut -c1-12
  done > "$slugs_tmpfile"
fi

# Step 2: Read slugs into array (matching sources order)
mapfile -t slug_array < "$slugs_tmpfile"

# Step 3: Process each source file
idx=0
for src in "${sources[@]}"; do
  slug="${slug_array[$idx]}"
  idx=$((idx + 1))

  filename=$(basename "$src")
  orig_num="${filename%%_*}"

  # Extract number
  num="$orig_num"
  num_int=$((10#$num))

  # If this number is already used, assign the next available number
  if grep -qx "$num" "$used_nums_file" 2>/dev/null; then
    new_num=$next_num
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

  # Extract title from first H1 line
  title=$(grep -m1 '^# ' "$src" | sed 's/^# //' | sed "s/^[0-9]*[: ]*//")
  if [ -z "$title" ]; then
    title="${filename%.md}"
    title=$(echo "$title" | sed 's/^[0-9]*_//')
  fi

  # Extract date
  date_line=$(sed -n '2p' "$src" | grep -oP '^\d{4}-\d{2}-\d{2}' || echo "")
  if [ -z "$date_line" ]; then
    date_line=$(sed -n '3p' "$src" | grep -oP '\d{4}-\d{2}-\d{2}' || echo "")
  fi
  if [ -z "$date_line" ]; then
    date_line=$(date -r "$src" '+%Y-%m-%d')
  fi

  # Get content after the first heading line
  content=$(tail -n +2 "$src")
  content=$(echo "$content" | sed '/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/{ /^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\s*$/d; }' | sed '/^$/{ 1d; }')

  # Write post with frontmatter (slug for stable URLs)
  outfile="$POSTS_DIR/${filename}"
  cat > "$outfile" <<EOF
---
title: "${title//\"/\\\"}"
slug: ${slug}
date: ${date_line}
order: ${num_int}
tags: []
---

${content}
EOF

  count=$((count + 1))
done

echo "Synced ${count} posts to ${POSTS_DIR}"