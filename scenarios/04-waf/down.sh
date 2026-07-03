#!/usr/bin/env bash
# Tear down the WAF showcase (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-waf
