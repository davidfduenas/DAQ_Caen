#!/usr/bin/env bash
set -euo pipefail

# Repo root = parent of utils/, wherever the repo is cloned.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Override any of these from the environment; defaults match the lab setup.
INFLUX_HOST="${INFLUX_HOST:-127.0.0.1}"
INFLUX_PORT="${INFLUX_PORT:-8086}"
INFLUX_DB="${INFLUX_DB:-NOvA_DTG_CAEN}"
MEASUREMENT="${MEASUREMENT:-DT5730S}"
LOCK_FILE="${CAEN_LOCK:-${repo_dir}/.caen.lock}"

mkdir -p "${repo_dir}/logs"

while true; do
  flock -n "${LOCK_FILE}" "${repo_dir}/utils/read_temp_influx" \
    --influx-host "${INFLUX_HOST}" \
    --influx-port "${INFLUX_PORT}" \
    --influx-db "${INFLUX_DB}" \
    --measurement "${MEASUREMENT}" \
    --once >>"${repo_dir}/logs/temp_influx.log" 2>&1 || true

  sleep 5
done
