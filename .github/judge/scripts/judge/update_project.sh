#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash .github/judge/scripts/update_project.sh <result_json> <pr_number>

RESULT_JSON="${1:-}"
PR_NUMBER="${2:-}"

if [[ -z "$RESULT_JSON" || -z "$PR_NUMBER" ]]; then
  echo "[project] usage: update_project.sh <result_json> <pr_number>" >&2
  exit 2
fi

if [[ ! -f "$RESULT_JSON" ]]; then
  echo "[project] result json not found: $RESULT_JSON" >&2
  exit 2
fi

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
PROJECT_ID="${PROJECT_ID:?PROJECT_ID is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "[project] jq is required" >&2
  exit 1
fi

LANGUAGE="$(jq -r '.language' "$RESULT_JSON")"
STATE="$(jq -r '.detail' "$RESULT_JSON")"
LAST_SCORE="$(jq -r '.score' "$RESULT_JSON")"
LAST_TIME="$(jq -r '.time_ms' "$RESULT_JSON")"
LAST_MEMORY="$(jq -r '.memory_kb' "$RESULT_JSON")"



PR_NODE_ID="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq .node_id)"

PROJECT_QUERY='query($projectId: ID!) { node(id: $projectId) { ... on ProjectV2 { fields(first: 50) { nodes { ... on ProjectV2FieldCommon { id name } } } items(first: 100) { nodes { id content { ... on PullRequest { id number } } fieldValues(first: 30) { nodes { ... on ProjectV2ItemFieldNumberValue { field { ... on ProjectV2FieldCommon { id name } } number } ... on ProjectV2ItemFieldTextValue { field { ... on ProjectV2FieldCommon { id name } } text } } } } } } } }'

PROJECT_DATA="$(gh api graphql -f query="$PROJECT_QUERY" -F projectId="$PROJECT_ID")"

field_id_by_name() {
  local field_name="$1"
  jq -r --arg n "$field_name" '
    .data.node.fields.nodes[]
    | select(.name == $n)
    | .id
  ' <<<"$PROJECT_DATA" | head -n1
}

FIELD_LANGUAGE_ID="$(field_id_by_name "language")"
FIELD_STATE_ID="$(field_id_by_name "state")"
FIELD_BEST_SCORE_ID="$(field_id_by_name "best-score")"
FIELD_LAST_SCORE_ID="$(field_id_by_name "last-score")"
FIELD_LAST_TIME_ID="$(field_id_by_name "last-time")"
FIELD_LAST_MEMORY_ID="$(field_id_by_name "last-memory")"

for f in \
  FIELD_LANGUAGE_ID \
  FIELD_STATE_ID \
  FIELD_BEST_SCORE_ID \
  FIELD_LAST_SCORE_ID \
  FIELD_LAST_TIME_ID \
  FIELD_LAST_MEMORY_ID; do
  if [[ -z "${!f}" || "${!f}" == "null" ]]; then
    echo "[project] required project field not found: ${f}" >&2
    exit 1
  fi
done

ITEM_ID="$(jq -r --arg pr "$PR_NODE_ID" '
  .data.node.items.nodes[]
  | select(.content.id == $pr)
  | .id
' <<<"$PROJECT_DATA" | head -n1)"

CURRENT_BEST="$(jq -r --arg pr "$PR_NODE_ID" '
  .data.node.items.nodes[]
  | select(.content.id == $pr)
  | (
      [.fieldValues.nodes[]
        | select(.field.name == "best-score")
        | .number
      ][0] // 0
    )
' <<<"$PROJECT_DATA" | head -n1)"

[[ -z "$CURRENT_BEST" || "$CURRENT_BEST" == "null" ]] && CURRENT_BEST="0"

if [[ -z "$ITEM_ID" ]]; then
  ADD_MUTATION='mutation($projectId: ID!, $contentId: ID!) { addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) { item { id } } }'
  ITEM_ID="$(gh api graphql -f query="$ADD_MUTATION" -F projectId="$PROJECT_ID" -F contentId="$PR_NODE_ID" --jq '.data.addProjectV2ItemById.item.id')"
  CURRENT_BEST="0"
fi

BEST_SCORE="$(awk -v a="$CURRENT_BEST" -v b="$LAST_SCORE" 'BEGIN {print (a>b)?a:b}')"

TEXT_MUTATION='mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: String!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: { text: $value }}) { projectV2Item { id } } }'
NUMBER_MUTATION='mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: Float!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: { number: $value }}) { projectV2Item { id } } }'

gh api graphql -f query="$TEXT_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LANGUAGE_ID" -F value="$LANGUAGE" >/dev/null
gh api graphql -f query="$TEXT_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_STATE_ID" -F value="$STATE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_BEST_SCORE_ID" -F value="$BEST_SCORE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_SCORE_ID" -F value="$LAST_SCORE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_TIME_ID" -F value="$LAST_TIME" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_MEMORY_ID" -F value="$LAST_MEMORY" >/dev/null

echo "[project] updated project item for PR #${PR_NUMBER}"
