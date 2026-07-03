#!/usr/bin/env bash
# Tear down the HA scenario: remove both edge containers + delete the cluster.
set -euo pipefail
docker rm -f edge-a edge-b 2>/dev/null || true
kind delete cluster --name zeno-ha
