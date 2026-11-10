#!/usr/bin/env python3
"""Live oscilloscope-style viewer for DT5730 DAQ text files (raw ADC).
Reads only the tail of the newest .txt file, so it stays fast even for
multi-GB files. Only complete events are plotted (the last event in the
file is treated as complete only once a following header is seen).
Channel is read from the file."""
import os, glob
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
matplotlib.rcParams['toolbar'] = 'None'
import matplotlib.pyplot as plt
import matplotlib.animation as animation

# ── Settings (edit if needed) ──
DATA_DIR   = os.environ.get("DAQ_DATA_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
N_WAVE     = 1            # how many recent waveforms to overlay
INTERVAL   = 0.000000004         # refresh seconds
TAIL_BYTES = 8_000_000    # bytes to read from the end of the file
COLORS     = ["black", "red", "blue", "green", "darkorange"]  # waveform colors

def newest_file(d):
    files = glob.glob(os.path.join(d, "*.txt"))
    return max(files, key=os.path.getmtime) if files else None

def read_tail(path, nbytes):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        if size > nbytes:
            f.seek(size - nbytes)
            f.readline()  # discard partial line
        return f.read().decode(errors="ignore").splitlines()

def get_events(path, n):
    """Return (channel, [complete waveforms]). The final event is only
    kept if a subsequent '# Event' header proves it finished writing."""
    if not path or not os.path.exists(path):
        return None, []
    lines = read_tail(path, TAIL_BYTES)

    # Index of every event header in the tail
    headers = [i for i, l in enumerate(lines) if l.startswith("# Event")]
    if len(headers) < 2:
        return None, []   # need at least one header after an event to be sure it's complete

    events, ch = [], None
    # Only iterate events that are followed by another header (i.e. complete)
    for h in range(len(headers) - 1):
        start = headers[h]
        end   = headers[h + 1]
        hdr = dict(t.split("=", 1) for t in lines[start].split() if "=" in t)
        ch = int(hdr.get("ch", 0))
        samples = []
        for s in lines[start + 1:end]:
            s = s.strip()
            if s:
                try:
                    samples.append(int(s))
                except ValueError:
                    pass
        if samples:
            events.append(np.array(samples, dtype=float))

    return ch, events[-n:]

fig, ax = plt.subplots(figsize=(10, 6))

def update(_):
    ax.clear()
    path = newest_file(DATA_DIR)
    ch, events = get_events(path, N_WAVE)
    for k, w in enumerate(events):
        t = np.arange(len(w)) * 2.0  # ns at 500 MS/s
        ax.plot(t, w, linewidth=0.8, color=COLORS[k % len(COLORS)])
    ax.set_xlabel("Time (ns)")
    ax.set_ylabel("ADC counts")
    name = os.path.basename(path) if path else "no file"
    chtxt = f"Ch{ch}" if ch is not None else "Ch?"
    ax.set_title(f"{chtxt} — last {len(events)} complete waveforms — {name}")

ani = animation.FuncAnimation(fig, update, interval=int(INTERVAL * 1000), cache_frame_data=False)
plt.show()