#!/usr/bin/env bash
# Tear down the zero-trust showcase (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-zt
