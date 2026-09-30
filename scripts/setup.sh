#!/bin/bash
set -e
echo "=== DavTro Setup ==="
echo "1. Upewnij sie, ze masz zainstalowane: docker, kubectl, kustomize, helm (opcjonalnie)"
echo "2. Zbuduj obrazy: docker build -t davtro-fastapi ./backend-fastapi"
echo "3. Zastosuj manifesty: kubectl apply -k manifests/overlays/production"
echo "4. Sprawdz status: kubectl get pods -n davtro02"
