#!/usr/bin/env bash
set -euo pipefail

ACCOUNT="${1:-${ACCOUNT:-sakibullah2006}}"
TOKEN="${2:-${TOKEN:-${GH_PAT:-${GITHUB_TOKEN:-}}}}"

if [ -z "$TOKEN" ]; then
  cat <<EOF
# No token provided. GitHub GraphQL requires authentication and has strict rate limits for unauthenticated requests.
# Falling back to zeroed values. To get accurate "contributions (last year)" values, set a PAT in the repository secrets as GH_PAT.
TOTAL_CONTRIBUTIONS_LAST_YEAR=0
TOTAL_COMMIT_CONTRIBUTIONS_LAST_YEAR=0
LAST_CONTRIBUTION_DATE_UTC=1970-01-01T00:00:00Z
EOF
  exit 0
fi

FROM=$(date -u -d '365 days ago' +%Y-%m-%dT%H:%M:%SZ)
TO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

read -r -d '' QUERY <<'GRAPHQL'
query($login:String!, $from:DateTime!, $to:DateTime!) {
  user(login:$login) {
    contributionsCollection(from:$from, to:$to) {
      contributionCalendar {
        totalContributions
        weeks {
          contributionDays {
            date
            contributionCount
          }
        }
      }
      totalCommitContributions
      totalPullRequestContributions
      totalIssueContributions
      totalRepositoryContributions
      restrictedContributionCount
    }
  }
}
GRAPHQL

payload=$(jq -n --arg q "$QUERY" --arg login "$ACCOUNT" --arg from "$FROM" --arg to "$TO" '{query:$q, variables:{login:$login, from:$from, to:$to}}')

resp=$(curl -s -H "Authorization: bearer $TOKEN" -H "Content-Type: application/json" -d "$payload" https://api.github.com/graphql)

# check for errors
err=$(echo "$resp" | jq -r '.errors[0].message // empty') || true
if [ -n "$err" ]; then
  echo "# GraphQL error: $err" >&2
  echo "TOTAL_CONTRIBUTIONS_LAST_YEAR=0"
  echo "TOTAL_COMMIT_CONTRIBUTIONS_LAST_YEAR=0"
  echo "LAST_CONTRIBUTION_DATE_UTC=1970-01-01T00:00:00Z"
  exit 0
fi

total_contrib=$(echo "$resp" | jq -r '.data.user.contributionsCollection.contributionCalendar.totalContributions')
commit_contrib=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalCommitContributions')

# find latest day with contributionCount > 0
last_day=$(echo "$resp" | jq -r '.data.user.contributionsCollection.contributionCalendar.weeks[].contributionDays[] | select(.contributionCount>0) | .date' | tail -n1 || true)
if [ -z "$last_day" ] || [ "$last_day" = "null" ]; then
  last_day="1970-01-01"
fi
# convert to UTC full timestamp
last_day_utc=$(date -u -d "$last_day" +%Y-%m-%dT%H:%M:%SZ)

echo "TOTAL_CONTRIBUTIONS_LAST_YEAR=$total_contrib"
echo "TOTAL_COMMIT_CONTRIBUTIONS_LAST_YEAR=$commit_contrib"
echo "LAST_CONTRIBUTION_DATE_UTC=$last_day_utc"