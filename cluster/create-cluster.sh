#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-greeter:1.0.0}"

kind create cluster --name greeter --config "$SCRIPT_DIR/kind-config.yaml"
kind load docker-image "$IMAGE" --name greeter
