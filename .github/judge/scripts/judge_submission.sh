#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash .github/judge/scripts/judge_submission.sh <meta_env_file> <result_json_file>

META_FILE="${1:-judge-meta.env}"
RESULT_JSON="${2:-judge-result.json}"
IMAGE_NAME="${JUDGE_IMAGE_NAME:-local/judge-base:latest}"

if [[ ! -f "$META_FILE" ]]; then
  echo "[judge] meta file not found: $META_FILE" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$META_FILE"

if ! command -v jq >/dev/null 2>&1; then
  echo "[judge] jq is required" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
WORK_DIR="$TMP_ROOT/work"
RESULT_DIR="$TMP_ROOT/result"
mkdir -p "$WORK_DIR" "$RESULT_DIR"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cp -R "$PROBLEM_DIR"/. "$WORK_DIR"/

TEMPLATE_FILE="$(jq -r --arg l "$LANGUAGE" '.languages[$l].template' "$CONFIG_PATH")"
COMPILE_CMD="$(jq -r --arg l "$LANGUAGE" '.languages[$l].compile // ""' "$CONFIG_PATH")"
EXECUTE_CMD="$(jq -r --arg l "$LANGUAGE" '.languages[$l].execute' "$CONFIG_PATH")"
TIME_LIMIT_MS="$(jq -r '.time_limit_ms' "$CONFIG_PATH")"
MEMORY_LIMIT_KB="$(jq -r '.memory_limit_kb' "$CONFIG_PATH")"

if [[ -z "$TEMPLATE_FILE" || "$TEMPLATE_FILE" == "null" ]]; then
  echo "[judge] template is missing in config" >&2
  exit 1
fi
if [[ -z "$EXECUTE_CMD" || "$EXECUTE_CMD" == "null" ]]; then
  echo "[judge] execute command is missing in config" >&2
  exit 1
fi

cp "$SUBMISSION_PATH" "$WORK_DIR/$TEMPLATE_FILE"

cat > "$WORK_DIR/.judge_run.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

cd /box/work

STATE="PASS"
DETAIL="PASS"

# Backward compatibility for problem configs using /box/* paths.
# - compile runs on host container filesystem (/box/work)
# - execute runs inside isolate sandbox where /work is bind-mounted
HOST_COMPILE_CMD="${COMPILE_CMD//\/box\//\/box\/work\/}"
SANDBOX_EXECUTE_CMD="${EXECUTE_CMD//\/box\//\/work\/}"

if [[ -n "${COMPILE_CMD:-}" ]]; then
  set +e
  /bin/bash -lc "$HOST_COMPILE_CMD" > /box/result/compile.out 2> /box/result/compile.err
  C_EXIT=$?
  set -e
  if [[ $C_EXIT -ne 0 ]]; then
    STATE="FAIL"
    DETAIL="FAIL: COMPILE_ERROR"
    echo "$STATE" > /box/result/state.txt
    echo "$DETAIL" > /box/result/detail.txt
    echo "-1" > /box/result/exit_code.txt
    echo "0" > /box/result/time_ms.txt
    echo "0" > /box/result/memory_kb.txt
    exit 0
  fi
fi

set +e
isolate --init >/box/result/isolate_init.log 2>&1
isolate \
  --meta=/box/result/isolate.meta \
  --dir=/work=/box/work:rw \
  --chdir=/work \
  --time="$TIME_LIMIT_SEC" \
  --mem="$MEMORY_LIMIT_KB" \
  --run -- \
  /bin/bash -lc "$SANDBOX_EXECUTE_CMD" \
  > /box/result/stdout.txt 2> /box/result/stderr.txt
RUN_EXIT=$?
isolate --cleanup >/box/result/isolate_cleanup.log 2>&1 || true
set -e

EXIT_CODE="$(awk -F: '/^exitcode:/{gsub(/^[ \t]+/,"",$2); print $2}' /box/result/isolate.meta | tail -n1)"
META_STATUS="$(awk -F: '/^status:/{gsub(/^[ \t]+/,"",$2); print $2}' /box/result/isolate.meta | tail -n1)"
TIME_WALL="$(awk -F: '/^time-wall:/{gsub(/^[ \t]+/,"",$2); print $2}' /box/result/isolate.meta | tail -n1)"
MAX_RSS="$(awk -F: '/^cg-mem:/{gsub(/^[ \t]+/,"",$2); print $2}' /box/result/isolate.meta | tail -n1)"
if [[ -z "$MAX_RSS" ]]; then
  MAX_RSS="$(awk -F: '/^max-rss:/{gsub(/^[ \t]+/,"",$2); print $2}' /box/result/isolate.meta | tail -n1)"
fi

[[ -z "$EXIT_CODE" ]] && EXIT_CODE="$RUN_EXIT"
[[ -z "$TIME_WALL" ]] && TIME_WALL="0"
[[ -z "$MAX_RSS" ]] && MAX_RSS="0"

TIME_MS="$(awk -v t="$TIME_WALL" 'BEGIN { printf "%d", (t * 1000) }')"

if [[ "$EXIT_CODE" != "0" ]]; then
  STATE="FAIL"
  DETAIL="FAIL"
fi

if [[ "$META_STATUS" == "TO" ]]; then
  STATE="FAIL"
  DETAIL="FAIL: TIME_LIMIT_EXCEEDED"
elif [[ "$META_STATUS" == "RE" || "$META_STATUS" == "SG" ]]; then
  STATE="FAIL"
  DETAIL="FAIL: RUNTIME_ERROR"
elif [[ "$META_STATUS" == "XX" ]]; then
  STATE="FAIL"
  if [[ "$MAX_RSS" =~ ^[0-9]+$ ]] && [[ "$MAX_RSS" -gt 0 ]]; then
    DETAIL="FAIL: MEMORY_LIMIT_EXCEEDED"
  else
    DETAIL="FAIL: RUNTIME_ERROR"
  fi
fi

echo "$STATE" > /box/result/state.txt
echo "$DETAIL" > /box/result/detail.txt
echo "$EXIT_CODE" > /box/result/exit_code.txt
echo "$TIME_MS" > /box/result/time_ms.txt
echo "$MAX_RSS" > /box/result/memory_kb.txt
EOS

chmod +x "$WORK_DIR/.judge_run.sh"

TIME_LIMIT_SEC="$(awk -v ms="$TIME_LIMIT_MS" 'BEGIN { sec = ms / 1000; if (sec < 0.001) sec = 0.001; printf "%.3f", sec }')"

docker run --rm --privileged \
  -e COMPILE_CMD="$COMPILE_CMD" \
  -e EXECUTE_CMD="$EXECUTE_CMD" \
  -e TIME_LIMIT_SEC="$TIME_LIMIT_SEC" \
  -e MEMORY_LIMIT_KB="$MEMORY_LIMIT_KB" \
  -v "$WORK_DIR:/box/work" \
  -v "$RESULT_DIR:/box/result" \
  "$IMAGE_NAME" \
  bash /box/work/.judge_run.sh

STATE="$(cat "$RESULT_DIR/state.txt" 2>/dev/null || echo FAIL)"
DETAIL="$(cat "$RESULT_DIR/detail.txt" 2>/dev/null || echo FAIL)"
EXIT_CODE="$(cat "$RESULT_DIR/exit_code.txt" 2>/dev/null || echo 1)"
TIME_MS="$(cat "$RESULT_DIR/time_ms.txt" 2>/dev/null || echo 0)"
MEMORY_KB="$(cat "$RESULT_DIR/memory_kb.txt" 2>/dev/null || echo 0)"

SCORE="$(sed -n 's/.*SCORE:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$RESULT_DIR/stdout.txt" 2>/dev/null | head -n1)"
[[ -z "$SCORE" ]] && SCORE=0

META_STATUS="$(awk -F: '/^status:/{gsub(/^[ \t]+/,"",$2); print $2}' "$RESULT_DIR/isolate.meta" 2>/dev/null | tail -n1)"
META_MESSAGE="$(awk -F: '/^message:/{sub(/^message:[ \t]*/,""); print}' "$RESULT_DIR/isolate.meta" 2>/dev/null | tail -n1)"
[[ -z "$META_STATUS" ]] && META_STATUS=""
[[ -z "$META_MESSAGE" ]] && META_MESSAGE=""

jq -n \
  --arg problem_id "$PROBLEM_ID" \
  --arg language "$LANGUAGE" \
  --arg submission_path "$SUBMISSION_PATH" \
  --arg state "$STATE" \
  --arg detail "$DETAIL" \
  --arg isolate_status "$META_STATUS" \
  --arg isolate_message "$META_MESSAGE" \
  --argjson score "$SCORE" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson time_ms "$TIME_MS" \
  --argjson memory_kb "$MEMORY_KB" \
  '{
    problem_id: $problem_id,
    language: $language,
    submission_path: $submission_path,
    state: $state,
    detail: $detail,
    isolate_status: $isolate_status,
    isolate_message: $isolate_message,
    score: $score,
    exit_code: $exit_code,
    time_ms: $time_ms,
    memory_kb: $memory_kb
  }' > "$RESULT_JSON"

if [[ "$DETAIL" != "PASS" ]]; then
  echo "[judge][debug] detail=$DETAIL"
  echo "[judge][debug] isolate.meta"
  cat "$RESULT_DIR/isolate.meta" 2>/dev/null || true
  echo "[judge][debug] stderr"
  cat "$RESULT_DIR/stderr.txt" 2>/dev/null || true
  echo "[judge][debug] isolate_init.log"
  cat "$RESULT_DIR/isolate_init.log" 2>/dev/null || true
fi

cat "$RESULT_JSON"
