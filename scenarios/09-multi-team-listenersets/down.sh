#!/usr/bin/env bash
# Tear down the multi-team scenario (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-teams
