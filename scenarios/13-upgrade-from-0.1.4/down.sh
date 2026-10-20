#!/usr/bin/env bash
# Tear down the upgrade scenario (deletes the whole kind cluster).
set -euo pipefail
cd "$(dirname "$0")"
rm -f .proxy-ip
kind delete cluster --name zeno-upgrade
