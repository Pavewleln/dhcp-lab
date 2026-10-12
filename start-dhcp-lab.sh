#!/usr/bin/env bash

# Создаёт TAP-интерфейс, собирает образ и запускает DHCP-сервер.
# Для подробной трассировки: ./start-dhcp-lab.sh --debug

set -Eeuo pipefail

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LAB_DIR}/logs"
LOG_FILE="${LOG_DIR}/start.log"
TAP_IF="tap-dhcp"
TAP_ADDR="10.10.10.2/24"
IMAGE_NAME="dhcp-lab"
CONTAINER_NAME="dhcp-lab"
TAP_OWNER="${SUDO_USER:-${USER:-root}}"
DEBUG=0

usage()
{
  echo "Использование: $0 [--debug]"
}

case "${1:-}" in
  "") ;;
  --debug) DEBUG=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log()
{
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

trap 'status=$?; log "Ошибка в строке ${BASH_LINENO[0]}, код ${status}"' ERR

if (( DEBUG )); then
  set -x
fi

if [[ ${EUID} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

for command_name in ip docker; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "Команда ${command_name} не найдена"
    exit 1
  fi
done

log "Подготовка интерфейса ${TAP_IF}"
if ! ip link show "${TAP_IF}" >/dev/null 2>&1; then
  "${SUDO[@]}" ip tuntap add dev "${TAP_IF}" mode tap user "${TAP_OWNER}"
fi

# На лабораторном TAP должен остаться только адрес DHCP-сервера.
"${SUDO[@]}" ip -4 address flush dev "${TAP_IF}"
"${SUDO[@]}" ip address add "${TAP_ADDR}" dev "${TAP_IF}"
"${SUDO[@]}" ip link set "${TAP_IF}" up

log "Сборка образа ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${LAB_DIR}"

# Повторный запуск всегда заменяет старый лабораторный контейнер.
if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  log "Удаление старого контейнера ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

log "Запуск контейнера ${CONTAINER_NAME}"
docker run -d \
  --name "${CONTAINER_NAME}" \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --log-driver local \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -v "${LAB_DIR}/dnsmasq.conf:/etc/dnsmasq.conf:ro" \
  "${IMAGE_NAME}" >/dev/null

sleep 1
if [[ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")" != "true" ]]; then
  log "Контейнер завершился с ошибкой"
  docker logs "${CONTAINER_NAME}"
  exit 1
fi

log "DHCP-сервер запущен: ${TAP_IF} (${TAP_ADDR})"
docker ps --filter "name=^/${CONTAINER_NAME}$" \
  --format 'Контейнер: {{.Names}} — {{.Status}}'
docker logs --tail 20 "${CONTAINER_NAME}"
log "Лог запуска: ${LOG_FILE}"
