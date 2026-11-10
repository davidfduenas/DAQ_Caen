#!/usr/bin/env bash
set -euo pipefail
# Repo root = parent of orchestrator/, wherever the repo is cloned.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

# Optional local overrides (gitignored)
if [[ -f "${script_dir}/.env" ]]; then source "${script_dir}/.env"; fi

export INFLUX_HOST INFLUX_PORT INFLUX_DB INFLUX_USER INFLUX_PASS
export DATA_DIR UTILS_DIR SW_BIN TH_BIN

# -------- defaults if .env doesn't define them --------
: "${UTILS_DIR:=${repo_dir}/utils}"
: "${DATA_DIR:=${repo_dir}/data}"
: "${SW_BIN:=${repo_dir}/daq_threshold_v1.0.0}"
: "${TH_BIN:=${SW_BIN}}"

: "${DAQ_CHANNEL:=0}"
: "${DAQ_THRESHOLD:=164}" #20mV
: "${TH_N_EVENTS:=10000}"
: "${SW_N_EVENTS:=1000}"

# Influx v1 (optional defaults)
: "${INFLUX_HOST:=127.0.0.1}"
: "${INFLUX_PORT:=8086}"
: "${INFLUX_DB:=NOvA_DTG_CAEN}"

# -------- single-host lock to avoid CAEN collisions --------
lock="${CAEN_LOCK:-${repo_dir}/.caen.lock}"
exec 9>"$lock"
flock -n 9 || { echo "[warn] DAQ busy (lock)"; exit 0; }

# Ensure output dir exists
mkdir -p "${DATA_DIR}"

run="$("${UTILS_DIR}/next_run_number.sh")"
ts="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"

sw_ok=1
th_ok=1

# --- Software Trigger Run ---
mode="sw"
root_out="${DATA_DIR}/run_${run}_${ts}_${mode}.root"
echo "[run] SW acquisition -> ${root_out}"
"${SW_BIN}" \
  -n "${SW_N_EVENTS}" \
  -m sw \
  -c "${DAQ_CHANNEL}" \
  -r 1500 \
  --root "${root_out}" || sw_ok=0

"${UTILS_DIR}/heartbeat_influx.sh" "DT5730S" "${sw_ok}" "mode=sw,run=${run}"

# --- Threshold Trigger Run ---
mode="self"
root_out="${DATA_DIR}/run_${run}_${ts}_${mode}.root"
echo "[run] Threshold acquisition -> ${root_out}"
"${TH_BIN}" \
  -n "${TH_N_EVENTS}" \
  -m self \
  -c "${DAQ_CHANNEL}" \
  -t "${DAQ_THRESHOLD}" \
  -r 1500 \
  --post 80 \
  --root "${root_out}" || th_ok=0

"${UTILS_DIR}/heartbeat_influx.sh" "DT5730S" "${th_ok}" "mode=self,run=${run}"
