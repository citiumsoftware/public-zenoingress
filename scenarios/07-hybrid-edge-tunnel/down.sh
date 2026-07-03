#!/usr/bin/env bash
# Tear down the hybrid-edge scenario: remove the edge container + delete the cluster.
set -euo pipefail
docker rm -f zeno-edge 2>/dev/null || true
kind delete cluster --name zeno-tunnel
