#!/usr/bin/env bash
# Smoke-проверка интеграций для /skills-check.
#
#   probe.sh [--verbose] < probes.tsv
#
# Строка stdin: name<TAB>profile<TAB>url[<TAB>header[<TAB>check]]
#   profile — имя pcurl-профиля (с @ или без) или "-" для запроса без профиля;
#   header  — дополнительный заголовок запроса или "-";
#   check   — jq-выражение для проверки формы ответа в --verbose (например `.status == "success"`) или "-".
# Делает GET через pcurl (до 6 запросов параллельно) и печатает таблицу. Тело ответа не выводится:
# в --verbose оно только проверяется выражением check. Строки, начинающиеся с #, пропускаются.
set -u

verbose=0
[ "${1:-}" = "--verbose" ] && verbose=1

max=6
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
profiles=$(pcurl show 2>/dev/null | awk 'NR > 1 { print $1 }')

probe() { # idx name profile url header check
  local i="$1" name="$2" profile="${3#@}" url="$4" header="${5:--}" check="${6:--}"
  local body=/dev/null out code t ms status note=""

  if [ "$profile" != "-" ] && ! grep -qxF "$profile" <<<"$profiles"; then
    printf '%s\tNO-PROFILE\t-\t-\tpcurl-профиля @%s нет в pcurl show\n' "$name" "$profile" > "$tmp/r-$i"
    return
  fi

  [ "$verbose" -eq 1 ] && [ "$check" != "-" ] && body="$tmp/b-$i"
  local args=(-s -o "$body" -w '%{http_code} %{time_total}' --max-time 15)
  [ "$header" != "-" ] && args+=(-H "$header")
  if [ "$profile" = "-" ]; then
    out=$(pcurl "$url" "${args[@]}" 2>/dev/null)
  else
    out=$(pcurl "@$profile" "$url" "${args[@]}" 2>/dev/null)
  fi
  code=${out%% *}
  t=${out##* }

  case "$code" in
    2??|3??) status=OK ;;
    401|403) status=FAIL; note="нет доступа или истёк токен — обновить профиль pcurl" ;;
    404)     status=FAIL; note="не найдено — сменился проект, uid или путь API" ;;
    5??)     status=FAIL; note="ошибка на стороне сервера — повторить позже" ;;
    *)       status=FAIL; code=000; note="таймаут, DNS или сеть — проверить VPN" ;;
  esac

  if [ "$status" = OK ] && [ "$body" != /dev/null ]; then
    if jq -e "$check" "$body" >/dev/null 2>&1; then
      note="форма ответа ок"
    else
      status=FAIL; note="неожиданный ответ: не выполнено $check"
    fi
  fi

  ms=$(awk -v t="${t:-0}" 'BEGIN { printf "%d", t * 1000 }' 2>/dev/null || echo 0)
  printf '%s\t%s\t%s\t%sms\t%s\n' "$name" "$status" "$code" "$ms" "$note" > "$tmp/r-$i"
}

n=0
while IFS=$'\t' read -r name profile url header check; do
  case "${name:-}" in ''|\#*) continue ;; esac
  n=$((n + 1))
  probe "$(printf '%03d' "$n")" "$name" "$profile" "$url" "${header:--}" "${check:--}" &
  [ $((n % max)) -eq 0 ] && wait
done
wait

[ "$n" -eq 0 ] && { echo "нет строк для проверки" >&2; exit 1; }

{
  printf 'SKILL\tSTATUS\tCODE\tLATENCY\tNOTE\n'
  cat "$tmp"/r-*
} | column -t -s "$(printf '\t')"

ok=$(cat "$tmp"/r-* | awk -F'\t' '$2 == "OK"' | wc -l | tr -d ' ')
echo
echo "$ok/$n OK"
