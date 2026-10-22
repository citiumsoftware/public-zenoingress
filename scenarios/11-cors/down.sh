#!/usr/bin/env bash
# Tear down the CORS scenario (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-cors
