#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash .github/judge/scripts/local_judge.sh <submission_path> [result_json_path]
#
# Example:
#   bash .github/judge/scripts/local_judge.sh problems/w00-add/user-heoh.cpp

SUBMISSION_PATH="${1:-}"
RESULT_JSON="${2:-local-judge-result.json}"

if [[ -z "$SUBMISSION_PATH" ]]; then
  echo "[local-judge] usage: local_judge.sh <submission_path> [result_json_path]" >&2
  exit 2
fi

if [[ ! -f "$SUBMISSION_PATH" ]]; then
  echo "[local-judge] submission file not found: $SUBMISSION_PATH" >&2
  exit 1
fi

if [[ ! "$SUBMISSION_PATH" =~ ^problems/([^/]+)/user-[^/]+\.(cpp|py)$ ]]; then
  echo "[local-judge] submission path must match problems/<id>/user-<name>.<ext> (.cpp/.py)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[local-judge] jq is required" >&2
  exit 1
fi

PROBLEM_ID="${BASH_REMATCH[1]}"
LANGUAGE="${BASH_REMATCH[2]}"
PROBLEM_DIR="problems/${PROBLEM_ID}"
CONFIG_PATH="${PROBLEM_DIR}/config.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[local-judge] config not found: $CONFIG_PATH" >&2
  exit 1
fi

if ! jq -e --arg lang "$LANGUAGE" '.languages | has($lang)' "$CONFIG_PATH" >/dev/null; then
  echo "[local-judge] language '$LANGUAGE' is not supported by $CONFIG_PATH" >&2
  exit 1
fi

REPO_ROOT="$(pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp -R "$REPO_ROOT"/. "$TMP_DIR/repo"

META_FILE="$TMP_DIR/judge-meta.env"
cat > "$META_FILE" <<EOF_META
PROBLEM_ID=$PROBLEM_ID
PROBLEM_DIR=problems/$PROBLEM_ID
LANGUAGE=$LANGUAGE
SUBMISSION_PATH=$SUBMISSION_PATH
CONFIG_PATH=problems/$PROBLEM_ID/config.json
EOF_META

echo "[local-judge] start"
echo "[local-judge] submission=$SUBMISSION_PATH"
echo "[local-judge] temp=$TMP_DIR/repo"

(
  cd "$TMP_DIR/repo"
  JUDGE_IMAGE_NAME="${JUDGE_IMAGE_NAME:-local/judge-base:latest}" \
    bash .github/judge/scripts/judge_submission.sh "$META_FILE" "result.json"
)

cp "$TMP_DIR/repo/result.json" "$RESULT_JSON"

echo "[local-judge] done"
echo "[local-judge] result=$RESULT_JSON"
cat "$RESULT_JSON"
