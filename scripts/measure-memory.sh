#!/usr/bin/env bash
# Samples the memory footprint of the Playground app on the booted simulator together with the
# simulator's WebKit processes (WebContent, GPU, Networking). Web view pages run in those processes,
# which the app cannot measure itself. Simulator processes are Mac processes, so `footprint` sees them.
# Usage: scripts/measure-memory.sh [seconds]   (samples until Ctrl-C without an argument)
set -euo pipefail

duration="${1:-}"
baseline=""
peak=0
peak_web_content=0

sample() {
  local pids
  pids=$(ps -axo pid=,comm= | awk '/CoreSimulator/ && (/Playground\.app\/Playground$/ || /com\.apple\.WebKit\./) { print $1 }')
  [[ -n "$pids" ]] || return 0
  # Prints: total app web_content web_content_count other_webkit (bytes, except the count).
  footprint --noCategories -f bytes $(printf -- '-p %s ' $pids) 2>/dev/null | awk '
    /\]: .*Footprint: [0-9]+ B/ {
      bytes = $(NF - 5)
      if ($1 == "Playground") app += bytes
      else if ($1 == "com.apple.WebKit.WebContent") { web_content += bytes; web_content_count++ }
      else other += bytes
    }
    END { printf "%d %d %d %d %d\n", app + web_content + other, app, web_content, web_content_count, other }'
}

mb() { echo "$(( $1 / 1048576 )) MB"; }

report() {
  [[ -n "$baseline" ]] || exit 0
  echo
  echo "baseline $(mb "$baseline"), peak $(mb "$peak"), growth $(mb $(( peak - baseline ))), peak WebContent processes $peak_web_content"
  exit 0
}
trap report INT TERM

started=$SECONDS
while [[ -z "$duration" || $(( SECONDS - started )) -lt "$duration" ]]; do
  read -r total app web_content web_content_count other <<< "$(sample)"
  if [[ -n "${total:-}" ]]; then
    baseline="${baseline:-$total}"
    (( total > peak )) && peak=$total
    (( web_content_count > peak_web_content )) && peak_web_content=$web_content_count
    echo "total $(mb "$total")  app $(mb "$app")  WebContent $(mb "$web_content") in $web_content_count  GPU+Networking $(mb "$other")"
  fi
  sleep 0.2
done
report
