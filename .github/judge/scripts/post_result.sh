#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash .github/judge/scripts/post_result.sh <result_json> <pr_number>

RESULT_JSON="${1:-}"
PR_NUMBER="${2:-}"

if [[ -z "$RESULT_JSON" || -z "$PR_NUMBER" ]]; then
  echo "[post] usage: post_result.sh <result_json> <pr_number>" >&2
  exit 2
fi

if [[ ! -f "$RESULT_JSON" ]]; then
  echo "[post] result json not found: $RESULT_JSON" >&2
  exit 2
fi

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "[post] jq is required" >&2
  exit 1
fi

PROBLEM_ID="$(jq -r '.problem_id' "$RESULT_JSON")"
LANGUAGE="$(jq -r '.language' "$RESULT_JSON")"
SUBMISSION_PATH="$(jq -r '.submission_path' "$RESULT_JSON")"
DETAIL="$(jq -r '.detail' "$RESULT_JSON")"
SCORE="$(jq -r '.score' "$RESULT_JSON")"
TIME_MS="$(jq -r '.time_ms' "$RESULT_JSON")"
MEMORY_KB="$(jq -r '.memory_kb' "$RESULT_JSON")"

BODY=$(cat <<EOF_BODY
## Judge Result

- problem: `$PROBLEM_ID`
- language: `$LANGUAGE`
- submission: `$SUBMISSION_PATH`
- state: `$DETAIL`
- score: `$SCORE`
- time: `$TIME_MS ms`
- memory: `$MEMORY_KB KB`
EOF_BODY
)

gh api \
  -X POST \
  "repos/${REPO}/issues/${PR_NUMBER}/comments" \
  -f body="$BODY" >/dev/null

echo "[post] commented on PR #${PR_NUMBER}"
