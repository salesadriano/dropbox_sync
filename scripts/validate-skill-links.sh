#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
skills_root="$repo_root/.github/skills"
failures_file=$(mktemp)

cleanup() {
  rm -f "$failures_file"
}

trap cleanup EXIT INT TERM

if [ ! -d "$skills_root" ]; then
  echo "Skills directory not found: $skills_root" >&2
  exit 1
fi

find "$skills_root" -name SKILL.md | sort | while IFS= read -r skill_file; do
  skill_dir=$(dirname "$skill_file")

  awk '
    {
      line = $0
      while (match(line, /(references\/[^] )`>"[:space:]]+|assets\/templates\/[^] )`>"[:space:]]+|assets\/template\/[^] )`>"[:space:]]+)/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$skill_file" | sort -u | while IFS= read -r relative_path; do
    [ -z "$relative_path" ] && continue
    normalized_path=${relative_path%%#*}
    case "$normalized_path" in
      *'*'* | *'?'*)
        continue
        ;;
    esac
    if [ ! -e "$skill_dir/$normalized_path" ]; then
      printf 'Broken local reference: %s -> %s\n' "$skill_file" "$relative_path" >> "$failures_file"
    fi
  done
done

if [ -s "$failures_file" ]; then
  cat "$failures_file" >&2
  exit 1
fi

echo "All local skill references are valid."