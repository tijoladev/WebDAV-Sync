#!/bin/sh
# helpers/snapshot.sh — collecte snapshot (static / dynamic)
# Dépend de: paths.sh (_now, RC_ADDR, LOCAL_DIR, LAST_RUN_JSON), kctl.sh

# --- parse "rclone version" (texte) → objet plat ---
_parse_rclone_version_flat() {
  awk '
    BEGIN { print "{"; first=1 }
    NR==1 {
      vers=$2
      if (vers!="") { printf "%s\"rclone\":\"%s\"", (first?"":","), vers; first=0 }
      next
    }
    {
      line=$0; gsub(/\r/,"",line)
      sub(/^[[:space:]]*-[[:space:]]*/,"",line)
      idx=index(line,":")
      if (idx>0) {
        key=substr(line,1,idx-1); val=substr(line,idx+1)
        sub(/^[[:space:]]*/,"",key); sub(/[[:space:]]*$/,"",key)
        sub(/^[[:space:]]*/,"",val); sub(/[[:space:]]*$/,"",val)
        gsub(/\\/,"\\\\",key); gsub(/\"/,"\\\"",key)
        gsub(/\\/,"\\\\",val); gsub(/\"/,"\\\"",val)
        printf "%s\"%s\":\"%s\"", (first?"":","), key, val; first=0
      }
    }
    END { print "}" }
  '
}

# --- Snapshot STATIC (appelé 1x au chargement) ---
# Retourne: rclone version info
snapshot_static() {
  ts="$(_now)"

  kctl version
  if [ "${KCTL_RC:-1}" -eq 0 ] && [ -n "${KCTL_STDOUT:-}" ]; then
    ver_json="$(printf '%s\n' "$KCTL_STDOUT" | _parse_rclone_version_flat)"
  else
    ver_json='{}'
  fi

  jq -n \
    --arg ts "$ts" \
    --argjson rclone "$ver_json" \
    '{extracted_at: $ts, rclone: $rclone}'
}

# --- Snapshot DYNAMIC (appelé toutes les 30s) ---
# Retourne: remote (disk), local (disk), last_run
snapshot_dynamic() {
  ts="$(_now)"

  # about remote (JSON direct)
  kctl about-remote
  about_json="$(kctl_stdout_json_or_empty)"

  # local : du / df
  bytes="$(busybox du -sb -- "$LOCAL_DIR" 2>/dev/null | awk '{print $1}')"
  [ -n "$bytes" ] || bytes=0
  df_line="$(busybox df -B1 -- "$LOCAL_DIR" 2>/dev/null | awk 'NR==2 {print $2, $4}')"
  set -- $df_line
  total="${1:-0}"; free="${2:-0}"
  local_json="$(
    jq -n --arg path "$LOCAL_DIR" \
          --argjson bytes "$bytes" \
          --argjson total "$total" \
          --argjson free "$free" \
          '{ path:$path, size:{bytes:$bytes}, filesystem:{ total_bytes:$total, free_bytes:$free } }'
  )"

  # last_run (fichier JSON persistant)
  if [ -s "$LAST_RUN_JSON" ]; then
    last_run="$(cat "$LAST_RUN_JSON" 2>/dev/null || echo '{}')"
    echo "$last_run" | jq . >/dev/null 2>&1 || last_run='{}'
  else
    last_run='{}'
  fi

  jq -n \
    --arg ts "$ts" \
    --argjson remote "$about_json" \
    --argjson local "$local_json" \
    --argjson last "$last_run" \
    '{extracted_at: $ts, remote: $remote, local: $local, last_run: $last}'
}

# --- Snapshot complet (rétrocompatibilité) ---
snapshot_collect() {
  type="${1:-full}"
  case "$type" in
    static)  snapshot_static ;;
    dynamic) snapshot_dynamic ;;
    *)
      # full = les deux combinés (rétrocompat)
      ts="$(_now)"
      static_json="$(snapshot_static)"
      dynamic_json="$(snapshot_dynamic)"
      # Merge les deux
      printf '%s\n%s' "$static_json" "$dynamic_json" | jq -s 'add | .extracted_at = $ts' --arg ts "$ts"
      ;;
  esac
}