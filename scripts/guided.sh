#!/usr/bin/env bash
# Processo guiado: domínio, IP, certificado e publicação ZTNA do SegPortal.
# --yes usa variáveis de ambiente (ou o padrão). --dry-run só grava a configuração.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${ROOT}/instance/.local"
YES=0
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "uso: $0 [--yes] [--dry-run]"
      echo "Pergunta domínio, IP, certificado e upstreams, depois sobe a instância Octelium."
      exit 0
      ;;
    *) echo "argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

if [[ "$YES" != 1 && ! -t 0 ]]; then
  echo "Sem terminal interativo. Rode de novo com --yes e as variáveis OCTELIUM_* / SEGPORTAL_*." >&2
  exit 1
fi

ask() {
  local __name="$1" __prompt="$2" __default="$3" __answer
  if [[ "$YES" == 1 ]]; then
    printf -v "$__name" '%s' "${!__name:-$__default}"
    return
  fi
  read -r -p "${__prompt} [${__default}]: " __answer
  printf -v "$__name" '%s' "${__answer:-$__default}"
}

valid_domain() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?)+$ ]]
}

valid_host() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

echo "SegPortal + Octelium — instalação guiada"
echo "O Cluster Octelium não entra no Docker Compose. Ele usa uma instância Linux."
echo

ask MODE "Perfil (1=microVM local, 2=VPS já existente, 3=mesmo Kubernetes)" "${MODE:-1}"
ask OCTELIUM_DOMAIN "Domínio do Cluster" "${OCTELIUM_DOMAIN:-octelium.segportal.local}"
ask OCTELIUM_PUBLIC_IP "IP público (vazio = detectar na instância)" "${OCTELIUM_PUBLIC_IP:-}"
ask OCTELIUM_NAT "Instância atrás de NAT? (s/n)" "${OCTELIUM_NAT:-s}"
ask OCTELIUM_FORCE_MACHINE_IP "Publicar o IP interno da máquina? (s/n) [laboratório APENAS]" "${OCTELIUM_FORCE_MACHINE_IP:-n}"
ask OCTELIUM_CERT_MODE "Certificado (1=laboratório inseguro, 2=PEM existente, 3=pular)" "${OCTELIUM_CERT_MODE:-2}"
ask SEGPORTAL_ALLOW_INSECURE_SSH "Permitir host key ignorada do jump-ssh? (s/n) [laboratório APENAS]" "${SEGPORTAL_ALLOW_INSECURE_SSH:-n}"
ask SEGPORTAL_JUMP_HOST_KEY "Host key pública do jump-ssh (vazio em laboratório)" "${SEGPORTAL_JUMP_HOST_KEY:-}"

OCTELIUM_CERT_FILE="${OCTELIUM_CERT_FILE:-}"
OCTELIUM_KEY_FILE="${OCTELIUM_KEY_FILE:-}"
if [[ "$OCTELIUM_CERT_MODE" == "2" ]]; then
  ask OCTELIUM_CERT_FILE "Caminho do fullchain.pem" "${OCTELIUM_CERT_FILE}"
  ask OCTELIUM_KEY_FILE "Caminho do privkey.pem" "${OCTELIUM_KEY_FILE}"
fi

ask SEGPORTAL_UPSTREAM_HOST "IP do SegPortal visto pela instância" "${SEGPORTAL_UPSTREAM_HOST:-10.0.2.2}"
ask SEGPORTAL_GUACAMOLE_PORT "Porta do Guacamole" "${SEGPORTAL_GUACAMOLE_PORT:-8080}"
ask SEGPORTAL_PORTAL_PORT "Porta do portal-auth" "${SEGPORTAL_PORTAL_PORT:-8090}"
ask SEGPORTAL_DESKTOP_FINANCEIRO "IP do desktop financeiro (RDP)" "${SEGPORTAL_DESKTOP_FINANCEIRO:-10.10.20.51}"
ask SEGPORTAL_DESKTOP_ADMIN "IP do desktop admin (RDP)" "${SEGPORTAL_DESKTOP_ADMIN:-10.10.20.10}"
ask SEGPORTAL_JUMP_HOST "IP do jump SSH" "${SEGPORTAL_JUMP_HOST:-10.10.20.10}"

if [[ "$MODE" == "1" ]]; then
  ask OCTELIUM_VM_MEMORY "Memória da microVM (MiB)" "${OCTELIUM_VM_MEMORY:-2560}"
  ask OCTELIUM_VM_CPUS "vCPUs" "${OCTELIUM_VM_CPUS:-2}"
  ask OCTELIUM_SSH_PORT "Porta SSH no host" "${OCTELIUM_SSH_PORT:-2222}"
  ask OCTELIUM_HTTPS_PORT "Porta HTTPS no host" "${OCTELIUM_HTTPS_PORT:-8443}"
fi

valid_domain "$OCTELIUM_DOMAIN" || { echo "domínio inválido: $OCTELIUM_DOMAIN" >&2; exit 1; }
valid_host "$SEGPORTAL_UPSTREAM_HOST" || { echo "upstream inválido" >&2; exit 1; }
valid_port "$SEGPORTAL_GUACAMOLE_PORT" || { echo "porta do Guacamole inválida" >&2; exit 1; }
valid_port "$SEGPORTAL_PORTAL_PORT" || { echo "porta do portal-auth inválida" >&2; exit 1; }
if [[ -n "$OCTELIUM_PUBLIC_IP" ]]; then
  valid_host "$OCTELIUM_PUBLIC_IP" || { echo "IP público inválido" >&2; exit 1; }
fi
if [[ "$OCTELIUM_CERT_MODE" == "2" ]]; then
  [[ -f "$OCTELIUM_CERT_FILE" && -f "$OCTELIUM_KEY_FILE" ]] || {
    echo "certificado ou chave PEM não encontrados" >&2
    exit 1
  }
fi

# Segurança: em produção, host key do jump-ssh é OBRIGATÓRIA.
FORCE_MACHINE_IP_NORM="$(echo "$OCTELIUM_FORCE_MACHINE_IP" | tr '[:upper:]' '[:lower:]')"
ALLOW_INSECURE_NORM="$(echo "$SEGPORTAL_ALLOW_INSECURE_SSH" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$SEGPORTAL_JUMP_HOST_KEY" && "$ALLOW_INSECURE_NORM" != "s" && "$ALLOW_INSECURE_NORM" != "y" ]]; then
  echo "ERRO: defina SEGPORTAL_JUMP_HOST_KEY (host key do jump-ssh)." >&2
  echo "      Ou confirme SEGPORTAL_ALLOW_INSECURE_SSH=s apenas em laboratório." >&2
  exit 1
fi

PROFILE="instance"
case "$MODE" in
  1|2) PROFILE="instance" ;;
  3) PROFILE="cluster" ;;
  *) echo "perfil inválido: $MODE" >&2; exit 1 ;;
esac

mkdir -p "$LOCAL"
ENV_FILE="${LOCAL}/guided.env"
cat > "$ENV_FILE" <<EOF
MODE=${MODE}
OCTELIUM_DOMAIN=${OCTELIUM_DOMAIN}
OCTELIUM_PUBLIC_IP=${OCTELIUM_PUBLIC_IP}
OCTELIUM_NAT=${OCTELIUM_NAT}
OCTELIUM_FORCE_MACHINE_IP=${OCTELIUM_FORCE_MACHINE_IP}
OCTELIUM_CERT_MODE=${OCTELIUM_CERT_MODE}
OCTELIUM_CERT_FILE=${OCTELIUM_CERT_FILE}
OCTELIUM_KEY_FILE=${OCTELIUM_KEY_FILE}
SEGPORTAL_UPSTREAM_HOST=${SEGPORTAL_UPSTREAM_HOST}
SEGPORTAL_GUACAMOLE_PORT=${SEGPORTAL_GUACAMOLE_PORT}
SEGPORTAL_PORTAL_PORT=${SEGPORTAL_PORTAL_PORT}
SEGPORTAL_DESKTOP_FINANCEIRO=${SEGPORTAL_DESKTOP_FINANCEIRO}
SEGPORTAL_DESKTOP_ADMIN=${SEGPORTAL_DESKTOP_ADMIN}
SEGPORTAL_JUMP_HOST=${SEGPORTAL_JUMP_HOST}
SEGPORTAL_JUMP_HOST_KEY=${SEGPORTAL_JUMP_HOST_KEY}
SEGPORTAL_ALLOW_INSECURE_SSH=${SEGPORTAL_ALLOW_INSECURE_SSH:-n}
OCTELIUM_VM_MEMORY=${OCTELIUM_VM_MEMORY:-2560}
OCTELIUM_VM_CPUS=${OCTELIUM_VM_CPUS:-2}
OCTELIUM_SSH_PORT=${OCTELIUM_SSH_PORT:-2222}
OCTELIUM_HTTPS_PORT=${OCTELIUM_HTTPS_PORT:-8443}
PROFILE=${PROFILE}
EOF
chmod 0600 "$ENV_FILE"

echo
echo "Resumo gravado em ${ENV_FILE}"
echo "  domínio: ${OCTELIUM_DOMAIN}"
echo "  perfil:  ${PROFILE} (modo ${MODE})"
echo "  upstream SegPortal: http://${SEGPORTAL_UPSTREAM_HOST}:${SEGPORTAL_GUACAMOLE_PORT}"
echo "  certificado: modo ${OCTELIUM_CERT_MODE}"

if [[ "$DRY" == 1 ]]; then
  echo "Dry-run: nenhuma instância foi criada."
  exit 0
fi

if [[ "$YES" != 1 ]]; then
  read -r -p "Continuar e aplicar? (s/n) [s]: " CONFIRM
  CONFIRM="${CONFIRM:-s}"
  [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]] || { echo "Cancelado."; exit 0; }
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

if [[ "$MODE" == "1" ]]; then
  "${ROOT}/instance/create-instance.sh"
elif [[ "$MODE" == "2" ]]; then
  nat_flags=()
  [[ "$OCTELIUM_NAT" == "s" || "$OCTELIUM_NAT" == "S" ]] && nat_flags+=(--nat)
  [[ "$OCTELIUM_FORCE_MACHINE_IP" == "s" || "$OCTELIUM_FORCE_MACHINE_IP" == "S" ]] && nat_flags+=(--force-machine-ip)
  ip_flag=()
  [[ -n "$OCTELIUM_PUBLIC_IP" ]] && ip_flag+=(--public-ip "$OCTELIUM_PUBLIC_IP")
  echo "Na VPS, como root:"
  echo "  curl -fsSL -o install-cluster.sh https://octelium.com/install-cluster.sh"
  echo "  bash install-cluster.sh --domain ${OCTELIUM_DOMAIN} ${nat_flags[*]} ${ip_flag[*]}"
fi

export SEGPORTAL_UPSTREAM_HOST SEGPORTAL_GUACAMOLE_PORT SEGPORTAL_PORTAL_PORT
export SEGPORTAL_DESKTOP_FINANCEIRO SEGPORTAL_DESKTOP_ADMIN SEGPORTAL_JUMP_HOST
export SEGPORTAL_JUMP_HOST_KEY
export SEGPORTAL_ALLOW_INSECURE_SSH
"${ROOT}/scripts/apply.sh" --profile "$PROFILE" --upstream-host "$SEGPORTAL_UPSTREAM_HOST"

if [[ "$OCTELIUM_CERT_MODE" == "1" ]]; then
  echo "Laboratório: export OCTELIUM_INSECURE_TLS=true"
  echo "export OCTELIUM_DOMAIN=${OCTELIUM_DOMAIN}"
elif [[ "$OCTELIUM_CERT_MODE" == "2" && "$MODE" == "1" ]]; then
  echo "Depois que a VM terminar o instalador, envie o certificado:"
  echo "  scp -P ${OCTELIUM_SSH_PORT:-2222} -i ${LOCAL}/id_ed25519 ${OCTELIUM_CERT_FILE} ${OCTELIUM_KEY_FILE} ubuntu@127.0.0.1:/tmp/"
  echo "  ssh -p ${OCTELIUM_SSH_PORT:-2222} -i ${LOCAL}/id_ed25519 ubuntu@127.0.0.1 sudo octops cert --cert /tmp/$(basename "$OCTELIUM_CERT_FILE") --key /tmp/$(basename "$OCTELIUM_KEY_FILE") --kubeconfig /etc/rancher/k3s/k3s.yaml"
else
  echo "Certificado ficou para uma etapa posterior (octops cert)."
fi
