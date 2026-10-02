#!/usr/bin/env bash
# Ferramentas do operador SegPortal para falar com a instância Octelium.
# Não instala o Cluster. O Cluster vive na VM (create-instance.sh).
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  version="${KUBECTL_VERSION:-v1.32.2}"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
  esac
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
  sudo install -m 0755 "$tmp" /usr/local/bin/kubectl
  rm -f "$tmp"
fi

if ! command -v octeliumctl >/dev/null 2>&1 || ! command -v octelium >/dev/null 2>&1; then
  curl -fsSL https://octelium.com/install.sh | bash
fi

echo "kubectl: $(command -v kubectl)"
echo "octelium: $(command -v octelium)"
echo "octeliumctl: $(command -v octeliumctl)"