#!/usr/bin/env bash
# Публикует research.md и spec.md из docs/llm/tasks/<TASK_ID>/ одним комментарием со спойлерами.
#
#   publish-artifacts.sh gitlab   <gl_profile> <gl_host> <gl_project_id> <TASK_ID>
#   publish-artifacts.sh youtrack <yt_profile> <yt_host> <TASK_ID>
#
# Профиль pcurl — с @ или без. Запускать из корня проекта. Нужны pcurl и jq 1.6+.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

target="${1:-}"
case "$target" in
  gitlab)
    [ $# -eq 5 ] || die "usage: $0 gitlab <gl_profile> <gl_host> <gl_project_id> <TASK_ID>"
    profile="${2#@}"; host="$3"; project="$4"; task="$5" ;;
  youtrack)
    [ $# -eq 4 ] || die "usage: $0 youtrack <yt_profile> <yt_host> <TASK_ID>"
    profile="${2#@}"; host="$3"; task="$4" ;;
  *)
    die "usage: $0 gitlab|youtrack ..." ;;
esac

command -v jq >/dev/null || die "jq не найден"
command -v pcurl >/dev/null || die "pcurl не найден"

dir="docs/llm/tasks/$task"
for f in research.md spec.md; do
  [ -s "$dir/$f" ] || die "нет $dir/$f"
done

if [ "$target" = gitlab ]; then
  mrs=$(pcurl "@$profile" "https://$host/api/v4/projects/$project/merge_requests?source_branch=$task&state=opened" -s)
  mr=$(jq -r 'if type == "array" then (.[0].iid // empty) else empty end' <<<"$mrs")
  [ -n "$mr" ] || die "открытый MR для ветки $task не найден: $mrs"

  body=$(jq -n --rawfile r "$dir/research.md" --rawfile s "$dir/spec.md" '{body: (
    "## Артефакты /solve\n\n"
    + "<details>\n<summary>Research — анализ задачи</summary>\n\n" + $r + "\n</details>\n\n"
    + "<details>\n<summary>Spec — план реализации</summary>\n\n" + $s + "\n</details>"
  )}')
  resp=$(pcurl "@$profile" "https://$host/api/v4/projects/$project/merge_requests/$mr/notes" -s -X POST \
    -H 'Content-Type: application/json' -d "$body")
  id=$(jq -r '.id // empty' <<<"$resp" 2>/dev/null || true)
  [ -n "$id" ] || die "GitLab не создал комментарий: $resp"
  echo "GitLab: комментарий $id в MR !$mr"
else
  body=$(jq -n --rawfile r "$dir/research.md" --rawfile s "$dir/spec.md" '{text: (
    "**Артефакты /solve**\n\n"
    + "{cut text=\"Research — анализ задачи\"}\n" + $r + "\n{cut}\n\n"
    + "{cut text=\"Spec — план реализации\"}\n" + $s + "\n{cut}"
  )}')
  resp=$(pcurl "@$profile" "https://$host/api/issues/$task/comments?fields=id" -s -X POST \
    -H 'Content-Type: application/json' -d "$body")
  id=$(jq -r '.id // empty' <<<"$resp" 2>/dev/null || true)
  [ -n "$id" ] || die "YouTrack не создал комментарий: $resp"
  echo "YouTrack: комментарий $id в $task"
fi
