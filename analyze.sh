#!/bin/bash
set -eo pipefail

echo "::add-mask::$SCHEMASYNC_TOKEN"

if [ -z "$GITHUB_BASE_REF" ] || [ -z "$GITHUB_HEAD_REF" ]; then
    echo "Error: This action must be run in a pull_request event context."
    exit 1
fi

echo "Identifying modified .sql files..."
git fetch origin "$GITHUB_BASE_REF" --depth=1 || true
FILES=$(git diff --name-only "origin/$GITHUB_BASE_REF...$GITHUB_HEAD_REF" | grep '\.sql$' || true)

if [ -z "$FILES" ]; then
    echo "No .sql files modified. Exiting cleanly."
    exit 0
fi

MARKDOWN_BODY="## 🛡️ SchemaSync Report\n\n| Arquivo | Violação | Severidade | Lock Time (ms) |\n|---|---|---|---|\n"
RESULTS_JSON="["

SEVERITY_WEIGHT_BREAKING=3
SEVERITY_WEIGHT_WARNING=2
SEVERITY_WEIGHT_INFO=1

get_severity_weight() {
    case "$1" in
        "BREAKING") echo 3 ;;
        "WARNING") echo 2 ;;
        "INFO") echo 1 ;;
        *) echo 0 ;;
    esac
}

FAIL_ON_WEIGHT=$(get_severity_weight "$FAIL_ON")
MAX_FOUND_WEIGHT=0

for file in $FILES; do
    echo "Analyzing file: $file"
    if [ ! -f "$file" ]; then
        echo "File $file not found locally, skipping..."
        continue
    fi

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      -H "Authorization: Bearer $SCHEMASYNC_TOKEN" \
      -F "file=@$file" \
      "$SCHEMASYNC_URL/api/projects/$PROJECT_ID/migrations/analyze")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Failed to analyze $file. HTTP status: $HTTP_CODE"
        echo "Response: $BODY"
        exit 1
    fi

    OVERALL_SEV=$(echo "$BODY" | jq -r '.overallSeverity')
    VIOLATIONS_LEN=$(echo "$BODY" | jq '.violations | length')

    CURRENT_WEIGHT=$(get_severity_weight "$OVERALL_SEV")
    if [ "$CURRENT_WEIGHT" -gt "$MAX_FOUND_WEIGHT" ]; then
        MAX_FOUND_WEIGHT=$CURRENT_WEIGHT
    fi

    if [ "$VIOLATIONS_LEN" -gt 0 ]; then
        while read -r violation; do
            if [ -z "$violation" ]; then continue; fi
            SEV=$(echo "$violation" | jq -r '.severity')
            DESC=$(echo "$violation" | jq -r '.description')
            LOCK=$(echo "$violation" | jq -r '.estimatedLockTimeMs')
            
            ICON="ℹ️"
            if [ "$SEV" == "BREAKING" ]; then ICON="🔴"; fi
            if [ "$SEV" == "WARNING" ]; then ICON="⚠️"; fi
            
            MARKDOWN_BODY+="| \`$file\` | $DESC | $ICON $SEV | $LOCK |\n"
        done <<< "$(echo "$BODY" | jq -c '.violations[]')"
    else
         MARKDOWN_BODY+="| \`$file\` | Sem violações | ✅ SEGURO | 0 |\n"
    fi

    RESULTS_JSON+="$BODY,"
done

RESULTS_JSON="${RESULTS_JSON%,}]"
echo "result=$RESULTS_JSON" >> "$GITHUB_OUTPUT"

PR_NUMBER=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH" || echo "null")
if [ "$PR_NUMBER" != "null" ] && [ -n "$PR_NUMBER" ]; then
    COMMENT_URL="https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments"
    
    EXISTING_COMMENT_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$COMMENT_URL" | jq '.[] | select(.body | contains("## 🛡️ SchemaSync Report")) | .id' | head -n 1)

    PAYLOAD=$(jq -n --arg body "$(echo -e "$MARKDOWN_BODY")" '{body: $body}')

    if [ -n "$EXISTING_COMMENT_ID" ] && [ "$EXISTING_COMMENT_ID" != "null" ]; then
        echo "Updating existing comment ($EXISTING_COMMENT_ID)..."
        curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$PAYLOAD" "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/comments/$EXISTING_COMMENT_ID"
    else
        echo "Creating new comment..."
        curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$PAYLOAD" "$COMMENT_URL"
    fi
fi

if [ "$MAX_FOUND_WEIGHT" -ge "$FAIL_ON_WEIGHT" ]; then
    echo "Failing pipeline due to violations meeting or exceeding the fail-on threshold."
    exit 1
fi

exit 0
