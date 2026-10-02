#!/usr/bin/env bash
# Cria uma instância Linux (microVM KVM) só para o Cluster Octelium.
# O SegPortal em si continua no Docker Compose. Octelium não entra nele.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL="${ROOT}/.local"
mkdir -p "$LOCAL"

DOMAIN="${OCTELIUM_DOMAIN:-octelium.segportal.local}"
MEMORY="${OCTELIUM_VM_MEMORY:-2560}"
CPUS="${OCTELIUM_VM_CPUS:-2}"
DISK_GB="${OCTELIUM_VM_DISK_GB:-24}"
SSH_PORT="${OCTELIUM_SSH_PORT:-2222}"
HTTPS_PORT="${OCTELIUM_HTTPS_PORT:-8443}"
IMAGE_URL="${OCTELIUM_CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
IMAGE="${LOCAL}/noble-server-cloudimg-amd64.img"
DISK="${LOCAL}/octelium.qcow2"
SEED="${LOCAL}/seed.iso"
PIDFILE="${LOCAL}/qemu.pid"
SESSION="octelium-instance"
TMUX_CONF="/exec-daemon/tmux.portal.conf"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v cloud-localds >/dev/null 2>&1 || ! command -v qemu-img >/dev/null 2>&1; then
  echo "Faltam qemu-system-x86_64, qemu-img e cloud-localds." >&2
  echo "sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils" >&2
  exit 1
fi

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Instância Octelium já está em execução (pid $(cat "$PIDFILE"))."
  echo "SSH: ssh -i ${LOCAL}/id_ed25519 -p ${SSH_PORT} ubuntu@127.0.0.1"
  exit 0
fi

if [[ ! -f "${LOCAL}/id_ed25519" ]]; then
  ssh-keygen -t ed25519 -N "" -f "${LOCAL}/id_ed25519" -C "segportal-octelium" >/dev/null
fi
pubkey="$(cat "${LOCAL}/id_ed25519.pub")"

install_flags=()
case "${OCTELIUM_NAT:-s}" in
  s|S|yes|true|1) install_flags+=(--nat) ;;
esac
case "${OCTELIUM_FORCE_MACHINE_IP:-s}" in
  s|S|yes|true|1) install_flags+=(--force-machine-ip) ;;
esac
if [[ -n "${OCTELIUM_PUBLIC_IP:-}" ]]; then
  install_flags+=(--public-ip "${OCTELIUM_PUBLIC_IP}")
fi
flags_text="${install_flags[*]:-}"

sed \
  -e "s|__SSH_PUBLIC_KEY__|${pubkey}|" \
  -e "s|__OCTELIUM_DOMAIN__|${DOMAIN}|" \
  -e "s|__INSTALL_FLAGS__|${flags_text}|" \
  "${ROOT}/cloud-init/user-data" > "${LOCAL}/user-data"
cp "${ROOT}/cloud-init/meta-data" "${LOCAL}/meta-data"
cloud-localds "$SEED" "${LOCAL}/user-data" "${LOCAL}/meta-data"

if [[ ! -f "$IMAGE" ]]; then
  echo "Baixando imagem Ubuntu 24.04..."
  curl -fL --retry 3 -o "${IMAGE}.partial" "$IMAGE_URL"
  mv "${IMAGE}.partial" "$IMAGE"
fi

if [[ ! -f "$DISK" ]]; then
  cp --reflink=auto "$IMAGE" "$DISK" 2>/dev/null || cp "$IMAGE" "$DISK"
  qemu-img resize "$DISK" "${DISK_GB}G"
fi

accel=(-machine accel=tcg -cpu qemu64)
if [[ -r /dev/kvm ]]; then
  accel=(-enable-kvm -cpu host)
fi

tmux_bin=(tmux)
if [[ -f "$TMUX_CONF" ]]; then
  tmux_bin=(tmux -f "$TMUX_CONF")
fi
if "${tmux_bin[@]}" has-session -t "=$SESSION" 2>/dev/null; then
  "${tmux_bin[@]}" kill-session -t "=$SESSION"
fi

echo "Subindo instância Octelium (${DOMAIN}, ${MEMORY} MiB, ${CPUS} vCPU)."
"${tmux_bin[@]}" new-session -d -s "$SESSION" -c "$LOCAL" -- \
  qemu-system-x86_64 \
  "${accel[@]}" \
  -m "$MEMORY" \
  -smp "$CPUS" \
  -drive "file=${DISK},if=virtio,format=qcow2" \
  -drive "file=${SEED},if=virtio,format=raw,media=cdrom" \
  -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${HTTPS_PORT}-:443" \
  -device virtio-net-pci,netdev=n0 \
  -display none \
  -serial mon:stdio \
  -pidfile "$PIDFILE" \
  -name octelium,process=segportal-octelium

echo "SSH: ssh -i ${LOCAL}/id_ed25519 -p ${SSH_PORT} -o StrictHostKeyChecking=no ubuntu@127.0.0.1"
echo "HTTPS publicado no host: https://127.0.0.1:${HTTPS_PORT}"
echo "O SegPortal no host é alcançado pela VM em http://10.0.2.2:8080 e :8090."
echo "Log do instalador, depois do SSH: sudo tail -f /var/log/octelium-segportal.log"
