#!/usr/bin/env bash
# Tear down the simple-ingress showcase (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-simple
