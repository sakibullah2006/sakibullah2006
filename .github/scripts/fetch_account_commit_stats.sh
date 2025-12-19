#!/usr/bin/env bash
set -euo pipefail

ACCOUNT="${1:-${ACCOUNT:-sakibullah2006}}"
TOKEN="${2:-${TOKEN:-${GITHUB_TOKEN:-}}}"

# helper to call GitHub API (with or without token)
gh_api() {
  url="$1"
  if [ -n "$TOKEN" ]; then
    curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -s -H "Accept: application/vnd.github+json" "$url"
  fi
}

# collect repos
page=1
repos=()
while true; do
  resp=$(gh_api "https://api.github.com/users/$ACCOUNT/repos?per_page=100&page=$page")
  names=$(echo "$resp" | jq -r '.[].name')
  if [ -z "$names" ]; then
    break
  fi
  while read -r n; do
    [ -z "$n" ] && continue
    repos+=("$n")
  done <<< "$names"
  page=$((page+1))
done

# if no repos found, exit
if [ ${#repos[@]} -eq 0 ]; then
  echo "TOTAL_COMMITS=0"
  echo "LAST_COMMIT_UTC=1970-01-01T00:00:00Z"
  exit 0
fi

# compute totals
total_commits=0
latest_commit="1970-01-01T00:00:00Z"
for repo in "${repos[@]}"; do
  # check if there are commits by the account in this repo
  # use per_page=1 and inspect Link header to get count
  if [ -n "$TOKEN" ]; then
    header=$(curl -s -I -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$ACCOUNT/$repo/commits?author=$ACCOUNT&per_page=1")
    body=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$ACCOUNT/$repo/commits?author=$ACCOUNT&per_page=1")
  else
    header=$(curl -s -I -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$ACCOUNT/$repo/commits?author=$ACCOUNT&per_page=1")
    body=$(curl -s -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$ACCOUNT/$repo/commits?author=$ACCOUNT&per_page=1")
  fi

  link=$(echo "$header" | awk '/^Link:/ {print substr($0,7)}' | tr -d '\r') || true
  if [ -n "$link" ]; then
    # extract last page number
    last=$(echo "$link" | sed -n 's/.*[?&]page=\([0-9]\+\)>; rel="last".*/\1/p') || true
    if [ -n "$last" ]; then
      count=$last
    else
      # ensure body is an array
      if echo "$body" | jq -e 'type=="array"' >/dev/null 2>&1; then
        count=$(echo "$body" | jq 'length')
      else
        count=0
      fi
    fi
  else
    if echo "$body" | jq -e 'type=="array"' >/dev/null 2>&1; then
      count=$(echo "$body" | jq 'length')
    else
      count=0
    fi
  fi

  if [ "$count" -gt 0 ]; then
    # get most recent commit date for this repo (safe-guard body may be object)
    if echo "$body" | jq -e 'type=="array"' >/dev/null 2>&1; then
      commit_date=$(echo "$body" | jq -r '.[0].commit.committer.date')
    else
      commit_date=""
      # try a direct GET to fetch commit info
      commit_json=$(gh_api "https://api.github.com/repos/$ACCOUNT/$repo/commits?author=$ACCOUNT&per_page=1")
      if echo "$commit_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
        commit_date=$(echo "$commit_json" | jq -r '.[0].commit.committer.date')
      fi
    fi

    if [ -n "$commit_date" ] && [ "$commit_date" != "null" ]; then
      # update latest_commit if this is newer
      if [ "$(date -d "$commit_date" +%s)" -gt "$(date -d "$latest_commit" +%s)" ]; then
        latest_commit="$commit_date"
      fi
    fi
  fi

  total_commits=$((total_commits + count))
done

# convert latest_commit to UTC Z format
if [ -z "$latest_commit" ] || [ "$latest_commit" = "1970-01-01T00:00:00Z" ]; then
  last_commit_utc="1970-01-01T00:00:00Z"
else
  last_commit_utc=$(date -u -d "$latest_commit" +%Y-%m-%dT%H:%M:%SZ)
fi

echo "TOTAL_COMMITS=$total_commits"
echo "LAST_COMMIT_UTC=$last_commit_utc"
