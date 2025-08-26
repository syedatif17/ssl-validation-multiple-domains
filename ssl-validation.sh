#!/usr/bin/env bash
# Run: bash tls_dns_seq.sh domains.txt results.txt


set -euo pipefail

DOMAINS_FILE="${1:-domains.txt}"
OUT_FILE="${2:-scan_$(date +%Y%m%d_%H%M%S).txt}"

PORT="${PORT:-443}"
ATTEMPTS="${ATTEMPTS:-3}"
VERBOSE="${VERBOSE:-0}"            # 0 = -brief, 1 = full
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"
OPENSSL_TIMEOUT="${OPENSSL_TIMEOUT:-30}"  # seconds to wait for openssl

if [[ ! -f "$DOMAINS_FILE" ]]; then
  echo "Domains file not found: $DOMAINS_FILE" >&2
  exit 1
fi

# s_client flags (with SNI)
SCLIENT_FLAGS=( -connect "" -servername "" -showcerts )
[[ "$VERBOSE" -eq 0 ]] && SCLIENT_FLAGS=( -connect "" -servername "" -brief -showcerts )

# timeout binary (Linux = timeout, macOS = gtimeout)
TIMEOUT_BIN="timeout"
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"; else TIMEOUT_BIN=""; fi
fi
run_with_timeout () {
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$OPENSSL_TIMEOUT" "$@" </dev/null 2>&1
  else
    "$@" </dev/null 2>&1
  fi
}

echo "Writing to: $OUT_FILE"
: > "$OUT_FILE"

mapfile -t DOMAINS < <(sed -E 's/#.*$//' "$DOMAINS_FILE" | awk 'NF')

for domain in "${DOMAINS[@]}"; do
  {
    printf '==================== %s:%s ====================\n' "$domain" "$PORT"
    date -u +"Start: %Y-%m-%dT%H:%M:%SZ"
    echo

    # ---- openssl attempts ----
    for (( i=1; i<=ATTEMPTS; i++ )); do
      echo ">>> Attempt $i for $domain:$PORT"
      output="$(run_with_timeout openssl s_client \
                 -connect "${domain}:${PORT}" -servername "$domain" \
                 ${VERBOSE:+-showcerts})"
      status=$?
      if [[ $status -ne 0 ]]; then
        echo "[ERROR] openssl attempt $i failed (exit $status or timeout ${OPENSSL_TIMEOUT}s)"
      fi
      echo "$output"
      echo
      (( SLEEP_BETWEEN > 0 )) && sleep "$SLEEP_BETWEEN"
    done

    # ---- nslookup ----
    echo ">>> nslookup $domain"
    if command -v nslookup >/dev/null 2>&1; then
      if ! nslookup "$domain"; then
        echo "[ERROR] nslookup failed for $domain"
      fi
    else
      echo "[ERROR] nslookup command not found"
    fi
    echo

    date -u +"End:   %Y-%m-%dT%H:%M:%SZ"
    printf '================== end %s:%s ==================\n\n' "$domain" "$PORT"
  } >> "$OUT_FILE"
done

echo "Done."
