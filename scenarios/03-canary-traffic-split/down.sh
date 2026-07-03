#!/usr/bin/env bash
# Tear down the canary showcase (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-canary
