# Setup: CAEN HV supply + DT5730S digitizer on Linux

This fork of [BrunoGelli/DAQ_Caen](https://github.com/BrunoGelli/DAQ_Caen) is used together with two other repos:

| Repo | Purpose |
|---|---|
| [davidfduenas/DAQ_Caen](https://github.com/davidfduenas/DAQ_Caen) (this one) | Digitizer DAQ, temperature monitor, `scope.py` viewer |
| [davidfduenas/caen-dt5471p-monitor](https://github.com/davidfduenas/caen-dt5471p-monitor) | HV supply control and monitoring (fork of [BrunoGelli/caen-dt5533e-monitor](https://github.com/BrunoGelli/caen-dt5533e-monitor)) |
| [davidfduenas/tmuxsessions](https://github.com/davidfduenas/tmuxsessions) | tmux startup scripts for both |

Branch `lab-setup` of each fork holds the lab modifications.

There are three ways to set this up:
1. **Automatic installer:** `install.sh` in [caen-lab-setup](https://github.com/davidfduenas/caen-lab-setup) (Debian/Ubuntu).
2. **Manual steps:** sections 2 to 7 of this document.
3. **Docker:** see `DOCKER.md` in caen-lab-setup.

In every case you need the CAEN libraries (section 2) and, for the HV supply, the udev rule (section 6).

## 1. What you must adapt to your setup

| Item | Where | Default |
|---|---|---|
| HV serial device | `HV_SERIAL_PORT` (tmuxsessions) | `/dev/ttyDT5471P0` (needs the udev rule in section 6) |
| InfluxDB host / port / database | `INFLUX_HOST`, `INFLUX_PORT`, `INFLUX_DB` | `127.0.0.1`, `8086`, `NOvA_DTG_CAEN` |
| Folder locations | `DAQ_DIR`, `HV_DIR` (tmuxsessions) | `~/DAQ_Caen`, `~/caen-dt5471p-monitor` |
| ROOT environment script | `ROOT_SETUP` | `~/root/bin/thisroot.sh` |
| Trigger threshold | `-t` on the DAQ command line | depends on your detector and baseline |
| Channels read out | `SetChannelEnableMask(handle, 0x03)` in `daq_threshold_v1.0.0.cpp` | ch0 + ch1 (hardcoded; edit and recompile for other channels) |
| HV limits | none enforced by the software | you set `iset` and `vset` by hand |

All shell scripts take these as environment variables, so nothing needs editing. Example:
```bash
INFLUX_DB=mydb HV_SERIAL_PORT=/dev/ttyACM0 ~/tmuxsessions/start_hvcaen.sh
```
`scope.py` reads `*.txt` files from `data/` next to the script; set `DAQ_DATA_DIR` to use another folder.

## 2. Install
```bash
sudo apt install tmux git g++ build-essential curl unzip python3-venv python3-tk python3-numpy python3-matplotlib \
  libcurl4-openssl-dev libssl-dev libx11-dev libxpm-dev libxft-dev libxext-dev libusb-1.0-0-dev libtbb-dev
```
(`python3-numpy` and `python3-matplotlib` are needed by `scope.py`. `libtbb-dev` is needed by the ROOT binary download: without it, compiling the DAQ fails with `libtbb.so.12 ... not found`.)
- CAEN libraries: see "CAEN libraries" below.
- ROOT (default location `~/root`).
- InfluxDB v1 and Grafana.

### CAEN libraries

The DAQ needs the CAEN libraries. Bruno's [DAQ_Caen](https://github.com/BrunoGelli/DAQ_Caen) README lists them as a requirement but gives no installation steps. They are downloaded from CAEN's website (registration required).

Versions on the lab machine where the DAQ works (output of `ldconfig -p | grep -i caen`):

| Library | Version | Location |
|---|---|---|
| CAENVME | v4.1.3 | `/usr/lib` |
| CAENComm | v1.8.0 | `/usr/lib` |
| CAENDigitizer | v2.19.0 | `/usr/lib` (header: `/usr/include/CAENDigitizer.h`) |

`caen_felib` and `caen_dig2` are not installed there and are not needed for the DT5730S.

Install them in the order CAENVME, CAENComm, CAENDigitizer. As a reference, Bruno's older repository [Legacy-AmBE_DAQ_DQM](https://github.com/BrunoGelli/Legacy-AmBE_DAQ_DQM) (see its `Singularity.def`) installs each of these by running `sh install_x64` inside the package's `lib` folder. His versions there are older (4.0.2, 1.7.0, 2.18.0), and that repository builds an Apptainer container, which is separate from this setup.

Check that they are installed:
```bash
ldconfig -p | grep -i caen                        # libCAENVME, libCAENComm, libCAENDigitizer
ls /usr/include/CAENDigitizer.h                   # header used to compile the DAQ
printf '#include <CAENDigitizer.h>\nint main(){return 0;}\n' | g++ -x c++ - -lCAENDigitizer -o /tmp/caen_test && echo "CAEN libraries OK"
```

The caen-lab-setup repo includes these three libraries and their headers as `docker/caen/caen-installed.tgz`, made on the lab machine with:
```bash
tar -czf ~/caen-installed.tgz /usr/lib/libCAEN* /usr/include/CAEN*
```
`install.sh` installs it system-wide on a new machine (native install), and the Docker build installs it inside the image (see its `DOCKER.md`). They are CAEN's files: see `docker/caen/NOTICE.md` in that repo for what they are and the terms we know of.

## 3. Database and Grafana
```bash
influx -execute 'CREATE DATABASE NOvA_DTG_CAEN'
```
In Grafana (`http://localhost:3000`) add an InfluxDB data source (`http://localhost:8086`, your database) and build or import dashboards.

## 4. Clone
```bash
git clone -b lab-setup https://github.com/davidfduenas/DAQ_Caen.git ~/DAQ_Caen
git clone -b lab-setup https://github.com/davidfduenas/caen-dt5471p-monitor.git ~/caen-dt5471p-monitor
git clone https://github.com/davidfduenas/tmuxsessions.git ~/tmuxsessions
chmod +x ~/tmuxsessions/*.sh
mkdir -p ~/DAQ_Caen/data ~/DAQ_Caen/logs

cd ~/caen-dt5471p-monitor
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## 5. Build
```bash
source ~/root/bin/thisroot.sh
cd ~/DAQ_Caen
g++ -O2 -std=c++17 daq_threshold_v1.0.0.cpp -o daq_threshold_v1.0.0 $(root-config --cflags --libs) -lCAENDigitizer
g++ -O2 -std=c++17 utils/read_temp_influx.cpp -o utils/read_temp_influx -lCAENDigitizer -lcurl
```
Both commands compiled successfully in the Docker container (Ubuntu 24.04, ROOT 6.32.04, CAEN libraries v4.1.3 / v1.8.0 / v2.19.0). The only warnings say that `CAEN_DGTZ_OpenDigitizer` is deprecated since CAENDigitizer 2.18.

Optional alias for the live viewer: `alias scope='python3 ~/DAQ_Caen/scope.py'`.

## 6. HV supply device name (udev)
The HV script opens `/dev/ttyDT5471P0`. Create it:

1. Plug in the supply and run `lsusb`; note the `vendor:product` ID (the Python tool defaults to `21e1:0006`).
2. `sudo nano /etc/udev/rules.d/99-caen.rules`, one line, with your IDs:
   ```
   SUBSYSTEM=="tty", ATTRS{idVendor}=="21e1", ATTRS{idProduct}=="0006", SYMLINK+="ttyDT5471P0", MODE="0666", ENV{ID_MM_DEVICE_IGNORE}="1"
   ```
3. `sudo udevadm control --reload-rules && sudo udevadm trigger`, then replug.
4. `ls -l /dev/ttyDT5471P0` should show a link to `ttyACM0` or `ttyUSB0`.

With several supplies, add `ATTRS{serial}=="<number>"` (from `udevadm info -a -n /dev/ttyACM0 | grep serial`) and use a distinct `SYMLINK` name per supply.

The digitizer needs no name: the DAQ opens it by USB link number.

## 7. First test (HV supply off)
1. `~/tmuxsessions/start_digcaen.sh`: the top pane prints "Temperatures sent".
2. `./daq_threshold_v1.0.0 -n 100 -m sw -c 0 -r 1500 --txt data/test.txt`, then run `scope`.
3. `~/tmuxsessions/start_hvcaen.sh`, type `start` in the top pane, check VMON and IMON in Grafana.

## 8. Operation

The lab's original operating instructions (HV and DAQ in WSL) are in this Google Doc, which may require access: [Operating Instructions](https://docs.google.com/document/d/1mQslpxoBDvs9HkDt69Xr__bFLzD0LlA4ytbHnuLEeo8/edit?tab=t.0). This section is based on it.

**HV** (`start_hvcaen.sh`, three panes: monitor, voltage, current)
1. Top pane: `start` (logs to InfluxDB).
2. Current pane: `set iset 200`.
3. Voltage pane: `set vset 200`, then `on`.
4. Ramp up in steps (`set vset 400`, `600`, ...), waiting at each step and checking the current is stable.
5. Shutdown: ramp down in steps, then `off`.

**DAQ** (`start_digcaen.sh`: temperature monitor on top, two panes for runs)
```bash
./daq_threshold_v1.0.0 -n 50000 -m self -c 0 -t 100 -r 15000 --post 80 --txt data/run.txt
```
Timed run (change `timeout` to the run length):
```bash
timeout 900s ./daq_threshold_v1.0.0 -n 999999999 -m self -c 0 -t 50 -r 2048 --post 80 --txt data/<runname>.txt > logs/<runname>.log
```

| Option | Meaning |
|---|---|
| `-n` | number of events |
| `-t` | threshold, ADC counts below baseline |
| `-r` | record length in samples (2 ns each; 15000 = 30 µs) |
| `-c` | channel |
| `--post` | post-trigger size, percent |
| `--txt` | text output file |
| `-m self` | trigger on threshold crossing |
| `-m sw` | fixed-interval recording (baseline and noise) |
| `-m ext` | trigger from front-panel TRG-IN |

## 9. Troubleshooting
| Symptom | Fix |
|---|---|
| `/dev/ttyDT5471P0` missing | udev IDs don't match `lsusb`; redo section 6. |
| Supply silent, name present | `sudo systemctl stop ModemManager`. |
| Permission denied on the port | `sudo usermod -aG dialout $USER`, log in again. |
| "Failed to open digitizer" | Check the CAEN libraries with the commands in section 2; if it works under `sudo`, add a USB permission rule for the digitizer. |
| `scope` shows no window | Install `python3-tk`. |

## Automatic installation and Docker
The [caen-lab-setup](https://github.com/davidfduenas/caen-lab-setup) repo bundles all three repos. It provides:
- `install.sh`, which performs sections 2 to 6 on Debian/Ubuntu (the CAEN libraries are installed by hand first);
- a Docker setup (`DOCKER.md`) with InfluxDB, Grafana and a container that has ROOT, the CAEN libraries, the DAQ programs and the HV tools.

## Credits
The DAQ code, utilities and monitor in these repos were written by **Bruno P. Gelli** ([BrunoGelli/DAQ_Caen](https://github.com/BrunoGelli/DAQ_Caen) and [BrunoGelli/caen-dt5533e-monitor](https://github.com/BrunoGelli/caen-dt5533e-monitor)). The forks only contain small lab-specific modifications. Please credit the original repositories when using or citing this work.

> **Warning:** these instructions were generated by Claude (an AI assistant made by Anthropic). They have not been tested on every system, and the hardware steps have not been verified here. Review each step, especially commands that use `sudo`, before running it.
