#!/usr/bin/env bash

# Полностью удаляет контейнер, TAP-интерфейс и образ DHCP-лаборатории.
# Исходники и каталог logs остаются на диске.

set -Eeuo pipefail

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LAB_DIR}/logs"
LOG_FILE="${LOG_DIR}/stop.log"
TAP_IF="tap-dhcp"
IMAGE_NAME="dhcp-lab"
CONTAINER_NAME="dhcp-lab"
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

if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  log "Удаление контейнера ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
else
  log "Контейнер ${CONTAINER_NAME} уже отсутствует"
fi

if ip link show "${TAP_IF}" >/dev/null 2>&1; then
  log "Удаление интерфейса ${TAP_IF}"
  "${SUDO[@]}" ip link delete "${TAP_IF}"
else
  log "Интерфейс ${TAP_IF} уже отсутствует"
fi

if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  log "Удаление образа ${IMAGE_NAME}"
  docker image rm -f "${IMAGE_NAME}" >/dev/null
else
  log "Образ ${IMAGE_NAME} уже отсутствует"
fi

log "DHCP-лаборатория полностью остановлена"
log "Лог остановки: ${LOG_FILE}"
