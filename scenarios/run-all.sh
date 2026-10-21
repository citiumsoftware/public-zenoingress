#!/usr/bin/env bash
# Run the runnable scenarios one after another (each in its own kind cluster,
# torn down afterwards) and write a summary you can send back with your pilot
# feedback.
#
#   ./run-all.sh                 # 02-14
#   ./run-all.sh 09 10 13        # just these
#
# Logs and the summary go to results/<timestamp>/. Uses the same overrides as
# the scenarios (see lib/common.sh).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source lib/common.sh

if [ $# -gt 0 ]; then
  scenarios=()
  for n in "$@"; do scenarios+=("$(ls -d "${n}"-*/ | head -1)"); done
else
  scenarios=()
  for d in [0-9][0-9]-*/; do
    [ "$d" = 01-basic-http-routing/ ] || scenarios+=("$d")
  done
fi

out="results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
summary="$out/summary.txt"
{
  echo "zenoingress scenario run, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "version ${ZENOINGRESS_VERSION}, chart ${ZENOINGRESS_CHART}, Gateway API ${GATEWAY_API_VERSION}"
  echo "kind $(kind version 2>/dev/null | awk '{print $2}'), kubectl $(kubectl version --client -o json 2>/dev/null | sed -nE 's/.*"gitVersion": "([^"]+)".*/\1/p' | head -1), helm $(helm version --short 2>/dev/null)"
  echo
} > "$summary"

for dir in "${scenarios[@]}"; do
  name="${dir%/}"
  log="$out/$name.log"
  echo "==> $name"
  start=$(date +%s)
  (
    cd "$name" || exit 1
    ./up.sh && ./verify.sh || exit 1
    if [ -x ./upgrade.sh ]; then ./upgrade.sh && ./verify.sh || exit 1; fi
  ) >"$log" 2>&1
  rc=$?
  # Keep the cluster state of a failed scenario for the report.
  if [ "$rc" != 0 ]; then
    kubectl get gateway,listenerset,httproute,backendtlspolicy -A -o yaml >"$out/$name.resources.yaml" 2>/dev/null
    kubectl get pods -A >"$out/$name.pods.txt" 2>/dev/null
    for ns in $(kubectl get deploy -A -l app.kubernetes.io/name -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u); do
      kubectl -n "$ns" logs -l app.kubernetes.io/component=controller --tail=300 >"$out/$name.controller.log" 2>/dev/null
    done
  fi
  (cd "$name" && ./down.sh) >>"$log" 2>&1
  secs=$(( $(date +%s) - start ))
  if [ "$rc" = 0 ]; then result=PASS; else result=FAIL; fi
  printf '%-34s %s  (%ss)\n' "$name" "$result" "$secs" | tee -a "$summary"
done

echo
echo "Summary: $summary"
grep -q FAIL "$summary" && exit 1 || exit 0
