#!/usr/bin/env bash
# Tear down the Gateway-per-team scenario (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-per-team
