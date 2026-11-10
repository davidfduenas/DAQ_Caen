#!/usr/bin/env bash
set -euo pipefail

while true; do
  flock -n /home/dduenas/DAQ_Caen/.caen.lock /home/dduenas/DAQ_Caen/utils/read_temp_influx \
    --influx-host 127.0.0.1 \
    --influx-port 8086 \
    --influx-db NOvA_DTG_CAEN \
    --measurement DT5730S \
    --once >>/home/dduenas/DAQ_Caen/logs/temp_influx.log 2>&1 || true

  sleep 5
done
