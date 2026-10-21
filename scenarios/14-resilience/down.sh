#!/usr/bin/env bash
# Tear down the resilience scenario (deletes the whole kind cluster).
set -euo pipefail
kind delete cluster --name zeno-resilience
