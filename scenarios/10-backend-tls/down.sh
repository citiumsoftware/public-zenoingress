#!/usr/bin/env bash
# Tear down the backend-TLS scenario (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-backend-tls
