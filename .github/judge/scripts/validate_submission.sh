#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash .github/judge/scripts/validate_submission.sh <base_sha> <head_sha> <output_env_file>

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
OUT_FILE="${3:-judge-meta.env}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  echo "[validate] base/head sha are required" >&2
  exit 2
fi

mapfile -t CHANGES < <(git diff --name-status "$BASE_SHA" "$HEAD_SHA")

if [[ "${#CHANGES[@]}" -eq 0 ]]; then
  echo "[validate] no changed files" >&2
  exit 1
fi

SUBMISSION_COUNT=0
SUBMISSION_PATH=""
PROBLEM_ID=""
LANGUAGE=""

declare -a BLOCKED_PATHS=()

for row in "${CHANGES[@]}"; do
  status="${row%%$'\t'*}"
  path="${row#*$'\t'}"

  if [[ "$status" == "A" && "$path" =~ ^problems/([^/]+)/user-[^/]+\.(cpp|py)$ ]]; then
    SUBMISSION_COUNT=$((SUBMISSION_COUNT + 1))
    SUBMISSION_PATH="$path"
    PROBLEM_ID="${BASH_REMATCH[1]}"
    LANGUAGE="${BASH_REMATCH[2]}"
  fi
done

if [[ "$SUBMISSION_COUNT" -ne 1 ]]; then
  echo "[validate] exactly one added submission file user-<name>.<ext> is required" >&2
  exit 1
fi

PROBLEM_DIR="problems/${PROBLEM_ID}"
CONFIG_PATH="${PROBLEM_DIR}/config.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[validate] config not found: $CONFIG_PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[validate] jq is required" >&2
  exit 1
fi

while IFS= read -r blocked; do
  [[ -n "$blocked" ]] && BLOCKED_PATHS+=("$blocked")
done < <(
  jq -r '
    .languages
    | to_entries[]
    | .value
    | [.template, .judge]
    | .[]
    | select(. != null and . != "")
  ' "$CONFIG_PATH" | while IFS= read -r file; do
    echo "$PROBLEM_DIR/$file"
  done
  echo "$CONFIG_PATH"
)

for row in "${CHANGES[@]}"; do
  status="${row%%$'\t'*}"
  path="${row#*$'\t'}"

  for blocked in "${BLOCKED_PATHS[@]}"; do
    if [[ "$path" == "$blocked" ]]; then
      echo "[validate] protected file modified: $path" >&2
      exit 1
    fi
  done
done

if [[ "$SUBMISSION_PATH" == "" ]]; then
  echo "[validate] submission path is empty" >&2
  exit 1
fi

if ! jq -e --arg lang "$LANGUAGE" '.languages | has($lang)' "$CONFIG_PATH" >/dev/null; then
  echo "[validate] language '$LANGUAGE' is not supported by ${CONFIG_PATH}" >&2
  exit 1
fi

cat > "$OUT_FILE" <<EOF_META
PROBLEM_ID=$PROBLEM_ID
PROBLEM_DIR=$PROBLEM_DIR
LANGUAGE=$LANGUAGE
SUBMISSION_PATH=$SUBMISSION_PATH
CONFIG_PATH=$CONFIG_PATH
EOF_META

echo "[validate] ok"
echo "[validate] submission=$SUBMISSION_PATH"
