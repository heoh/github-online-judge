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

PROBLEM="$(jq -r '.problem_id' "$RESULT_JSON")"
LANGUAGE="$(jq -r '.language' "$RESULT_JSON")"
CURRENT_RESULT_STATE="$(jq -r '.state' "$RESULT_JSON")"
LAST_STATE="$(jq -r '.detail' "$RESULT_JSON")"
LAST_SCORE="$(jq -r '.score' "$RESULT_JSON")"
LAST_TIME="$(jq -r '.time_ms' "$RESULT_JSON")"
LAST_MEMORY="$(jq -r '.memory_kb' "$RESULT_JSON")"



PR_NODE_ID="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq .node_id)"

PROJECT_QUERY='query($projectId: ID!) { node(id: $projectId) { ... on ProjectV2 { fields(first: 50) { nodes { ... on ProjectV2FieldCommon { id name dataType } ... on ProjectV2SingleSelectField { options { id name } } } } items(first: 100) { nodes { id content { ... on PullRequest { id number } } fieldValues(first: 30) { nodes { ... on ProjectV2ItemFieldNumberValue { field { ... on ProjectV2FieldCommon { id name } } number } ... on ProjectV2ItemFieldTextValue { field { ... on ProjectV2FieldCommon { id name } } text } ... on ProjectV2ItemFieldSingleSelectValue { field { ... on ProjectV2FieldCommon { id name } } name optionId } } } } } } } }'

PROJECT_DATA="$(gh api graphql -f query="$PROJECT_QUERY" -F projectId="$PROJECT_ID")"

field_id_by_name() {
  local field_name="$1"
  jq -r --arg n "$field_name" '
    .data.node.fields.nodes[]
    | select(.name == $n)
    | .id
  ' <<<"$PROJECT_DATA" | head -n1
}

field_type_by_name() {
  local field_name="$1"
  jq -r --arg n "$field_name" '
    .data.node.fields.nodes[]
    | select(.name == $n)
    | .dataType
  ' <<<"$PROJECT_DATA" | head -n1
}

single_select_option_id() {
  local field_name="$1"
  local option_name="$2"
  jq -r --arg f "$field_name" --arg o "$option_name" '
    .data.node.fields.nodes[]
    | select(.name == $f)
    | .options[]?
    | select(.name == $o)
    | .id
  ' <<<"$PROJECT_DATA" | head -n1
}

FIELD_PROBLEM_ID="$(field_id_by_name "problem")"
FIELD_LANGUAGE_ID="$(field_id_by_name "language")"
FIELD_STATE_ID="$(field_id_by_name "state")"
FIELD_LAST_STATE_ID="$(field_id_by_name "last-state")"
FIELD_MIN_SCORE_ID="$(field_id_by_name "min-score")"
FIELD_MAX_SCORE_ID="$(field_id_by_name "max-score")"
FIELD_LAST_SCORE_ID="$(field_id_by_name "last-score")"
FIELD_LAST_TIME_ID="$(field_id_by_name "last-time")"
FIELD_LAST_MEMORY_ID="$(field_id_by_name "last-memory")"

for f in \
  FIELD_PROBLEM_ID \
  FIELD_LANGUAGE_ID \
  FIELD_STATE_ID \
  FIELD_LAST_STATE_ID \
  FIELD_MIN_SCORE_ID \
  FIELD_MAX_SCORE_ID \
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

CURRENT_STATE="$(jq -r --arg pr "$PR_NODE_ID" '
  .data.node.items.nodes[]
  | select(.content.id == $pr)
  | (
      [.fieldValues.nodes[]
        | select(.field.name == "state")
        | (.text // .name)
      ][0] // "FAIL"
    )
' <<<"$PROJECT_DATA" | head -n1)"

CURRENT_MIN_SCORE="$(jq -r --arg pr "$PR_NODE_ID" '
  .data.node.items.nodes[]
  | select(.content.id == $pr)
  | (
      [.fieldValues.nodes[]
        | select(.field.name == "min-score")
        | .number
      ][0] // null
    )
' <<<"$PROJECT_DATA" | head -n1)"

CURRENT_MAX_SCORE="$(jq -r --arg pr "$PR_NODE_ID" '
  .data.node.items.nodes[]
  | select(.content.id == $pr)
  | (
      [.fieldValues.nodes[]
        | select(.field.name == "max-score")
        | .number
      ][0] // null
    )
' <<<"$PROJECT_DATA" | head -n1)"

[[ -z "$CURRENT_STATE" || "$CURRENT_STATE" == "null" ]] && CURRENT_STATE="FAIL"

if [[ -z "$ITEM_ID" ]]; then
  ADD_MUTATION='mutation($projectId: ID!, $contentId: ID!) { addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) { item { id } } }'
  ITEM_ID="$(gh api graphql -f query="$ADD_MUTATION" -F projectId="$PROJECT_ID" -F contentId="$PR_NODE_ID" --jq '.data.addProjectV2ItemById.item.id')"
  CURRENT_STATE="FAIL"
  CURRENT_MIN_SCORE="null"
  CURRENT_MAX_SCORE="null"
fi

if [[ "$CURRENT_STATE" == "PASS" || "$CURRENT_RESULT_STATE" == "PASS" ]]; then
  NEXT_STATE="PASS"
else
  NEXT_STATE="FAIL"
fi

if [[ -z "$CURRENT_MIN_SCORE" || "$CURRENT_MIN_SCORE" == "null" ]]; then
  MIN_SCORE="$LAST_SCORE"
else
  MIN_SCORE="$(awk -v a="$CURRENT_MIN_SCORE" -v b="$LAST_SCORE" 'BEGIN {print (a<b)?a:b}')"
fi

if [[ -z "$CURRENT_MAX_SCORE" || "$CURRENT_MAX_SCORE" == "null" ]]; then
  MAX_SCORE="$LAST_SCORE"
else
  MAX_SCORE="$(awk -v a="$CURRENT_MAX_SCORE" -v b="$LAST_SCORE" 'BEGIN {print (a>b)?a:b}')"
fi

TEXT_MUTATION='mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: String!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: { text: $value }}) { projectV2Item { id } } }'
SINGLE_SELECT_MUTATION='mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: { singleSelectOptionId: $optionId }}) { projectV2Item { id } } }'
NUMBER_MUTATION='mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: Float!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: { number: $value }}) { projectV2Item { id } } }'

update_text_or_single_select_field() {
  local field_name="$1"
  local field_id="$2"
  local field_value="$3"

  local field_type
  field_type="$(field_type_by_name "$field_name")"

  if [[ "$field_type" == "SINGLE_SELECT" ]]; then
    local option_id
    option_id="$(single_select_option_id "$field_name" "$field_value")"
    if [[ -z "$option_id" || "$option_id" == "null" ]]; then
      echo "[project] single_select option not found: field=$field_name option=$field_value" >&2
      exit 1
    fi
    gh api graphql -f query="$SINGLE_SELECT_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$field_id" -F optionId="$option_id" >/dev/null
  else
    gh api graphql -f query="$TEXT_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$field_id" -F value="$field_value" >/dev/null
  fi
}

update_text_or_single_select_field "problem" "$FIELD_PROBLEM_ID" "$PROBLEM"
update_text_or_single_select_field "language" "$FIELD_LANGUAGE_ID" "$LANGUAGE"
update_text_or_single_select_field "state" "$FIELD_STATE_ID" "$NEXT_STATE"
update_text_or_single_select_field "last-state" "$FIELD_LAST_STATE_ID" "$LAST_STATE"
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_MIN_SCORE_ID" -F value="$MIN_SCORE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_MAX_SCORE_ID" -F value="$MAX_SCORE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_SCORE_ID" -F value="$LAST_SCORE" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_TIME_ID" -F value="$LAST_TIME" >/dev/null
gh api graphql -f query="$NUMBER_MUTATION" -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_LAST_MEMORY_ID" -F value="$LAST_MEMORY" >/dev/null

echo "[project] updated project item for PR #${PR_NUMBER}"
