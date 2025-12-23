#!/bin/sh
# helpers/status.sh — collecte des statuts via kctl
# Dépend de: paths.sh (_now, STATUS_DIR, LAST_RUN_JSON)

# --- last_run.json (début/fin) ---

status_on_start() {
  mkdir -p "$STATUS_DIR" 2>/dev/null || :
  ts="$(_now)"
  jq -n \
    --arg start "$ts" \
    --arg op "$SYNC_OP" \
    --arg flags "$SYNC_FLAGS" \
    --arg dest "$LOCAL_DIR" \
    '{start_at:$start, end_at:null, op:$op, flags:$flags, destination:$dest, exit_code:null}' \
    >"$LAST_RUN_JSON".tmp 2>/dev/null || :
  mv -f "$LAST_RUN_JSON".tmp "$LAST_RUN_JSON" 2>/dev/null || :
  chmod 644 "$LAST_RUN_JSON" 2>/dev/null || :
}

status_on_end() {
  rc="${1:-0}"
  ts="$(_now)"
  if [ -s "$LAST_RUN_JSON" ]; then
    jq --arg end "$ts" --argjson code "$rc" '.end_at=$end | .exit_code=$code' \
      "$LAST_RUN_JSON" >"$LAST_RUN_JSON".new 2>/dev/null || {
        jq -n --arg end "$ts" --argjson code "$rc" '{start_at:null,end_at:$end,exit_code:$code}' >"$LAST_RUN_JSON".new
      }
    mv -f "$LAST_RUN_JSON".new "$LAST_RUN_JSON" 2>/dev/null || :
  else
    jq -n --arg end "$ts" --argjson code "$rc" '{start_at:null,end_at:$end,exit_code:$code}' >"$LAST_RUN_JSON"
  fi
  chmod 644 "$LAST_RUN_JSON" 2>/dev/null || :
}