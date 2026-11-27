# panelgraph NETWORK graph v2: QA instructions

Version 1.0, 2026-11-20. Author: BA. The monitor-mode guidance in §7-§8 comes from the **cyber security specialist**, who is QA's consultant (task card SEC-QA in `requirements.md` §8).

What to verify: `acceptance-criteria.md`, AC-01 to AC-75. The design reference is `requirements.md`. Developer details are in `dev-instructions.md`.

---

## 1. Environment facts (2026-11-20)

| Item | Value |
|---|---|
| OS / display | Kali Linux, X11 `:0`, 1920x1080, `/bin/sh` = dash, Python 3.14.8, pycairo 1.29.1, PyGObject Pango available |
| Panel | Xfce top panel, 34 px; plugin ids `1 … 13 26 24 23 14 … 22` |
| Graph | genmon plugin **26**, command `~/.local/bin/panelgraph-show net`, update-period 250 ms. Wrapper argv: `wrapper-2.0 …/libgenmon.so 26 6291470 genmon …`. Socket window 0x60000e, 142x34 at x=1321, y=0. |
| Neighbours | cpugraph plugin 13 (0x60000c, x=1143); netload **24** (wlan0, 0x60000f, x=1463, 48x34); netload **23** (wlan1, 0x600010, x=1511, 48x34) |
| Daemon output | `/run/user/1000/panelgraph/{net.png,net.txt,mem.*,pid,lock,seen,error.log,gw.json}` |
| Interfaces | eth0 (e1000e, down); wlan0 (iwlwifi, phy0, down, **flags 0x1103 promisc** because of netdiscover pid <pid>); wlan1 (mt76x2u USB, phy1, UP, SSID HomeNet, BSSID aa:bb:cc:dd:ee:02, ch44 5220 MHz/80, -27 dBm, 192.168.1.25, ifindex 4, carrier_changes 14, default route via 192.168.1.1 metric 603, gateway MAC aa:bb:cc:dd:ee:01); docker0, virbr0, virbr-msf, vnet16/17 (0x1303), lo |
| ip_forward | 1 (docker/libvirt) |
| Tools | xwininfo, xdotool (**do not use it to move the mouse**), import/convert/magick, xwd, iw 6.17 (`/usr/sbin/iw`), curl, flock, setsid |
| Scratch root | `QA=$SCRATCH/wf3/qa`, with sandbox `SB=$QA/sb` and evidence `$QA/evidence/AC-xx/` |

## 2. SAFETY RULES (mandatory, no exceptions)

1. **Never** `pkill -f panelgraph` or `pgrep -f … | kill`: the pattern matches your own shell and kills it.
   - Kill a daemon only via its pid file (`/run/user/1000/panelgraph/pid` live, `$SB/run/panelgraph/pid` sandbox), after checking that `/proc/$pid/comm` is `panelgraph` and that `/proc/$pid/cwd` is the matching directory.
   - Even *listing* with `pgrep -f` returns your own shell. Use the /proc scans in §3 instead.
2. Do not move the mouse or click. Do not change xfconf/panel settings, restart xfce4-panel, or add/remove panel items. Screenshots are fine.
3. **Do NOT change interface state:** no airmon-ng, `iw … set`, `iw … interface add/del`, `ip link set`, `ip neigh`, nmcli changes, macchanger or firewall changes. Monitor mode, promisc, new interfaces and gateway/ARP changes are tested **only in the sandbox**. Live variants (§8) run only after the user's explicit approval of that exact step; the user runs the sudo commands.
4. Network traffic: only `curl` downloads to `/dev/null` from `deb.debian.org` with `--limit-rate`, each under 30 s. No uploads, no pings outside the approved §8 procedures.
   - Example: `curl -s -o /dev/null --limit-rate 400k --max-time 25 https://deb.debian.org/debian/dists/stable/main/Contents-all.gz`. If it 404s, pick any file over 20 MB listed under `https://deb.debian.org/debian/dists/stable/main/`.
5. No foreground shell `sleep`; wait with `timeout N tail -f /dev/null`. Python `time.sleep` inside your own scripts is fine. Run suites longer than about 9 minutes in the background and read their logs.
6. Never touch the orphaned `netdiscover` (pid <pid>). It is the user's decision (OQ-4).
7. Scratch files go only under `$QA`. At the end:
   - stop the sandbox daemon (its pid file) and the engine (`rm $SB/engine.run`);
   - leave the **live** daemon running normally.

## 3. Locating things on screen and in /proc

**Plugin 26 wrapper pid.** pgrep -f would match your own shell, so scan /proc:

```python
import os
def wrapper_pid(lib, pid_id):           # wrapper_pid("libgenmon.so", "26"), ("libnetload.so", "23")
    for p in os.listdir("/proc"):
        if not p.isdigit(): continue
        try: a = open(f"/proc/{p}/cmdline", "rb").read().split(b"\0")
        except OSError: continue
        if len(a) > 3 and a[0].endswith(b"wrapper-2.0") and a[1].endswith(lib.encode()) and a[2] == pid_id.encode():
            return int(p), int(a[3])     # (pid, socket window id as int)
```

**Screen geometry.**
- Take the socket id from above, e.g. 6291470 = 0x60000e. Then:
  ```sh
  xwininfo -display :0 -id 0x60000e | awk '/Absolute upper-left X/{x=$4} /Absolute upper-left Y/{y=$4} /Width/{w=$2} /Height/{h=$2} END{print x,y,w,h}'
  ```
  Today this prints `1321 0 142 34`.
- The 140x32 image is drawn at **x+1 … x+140, rows y+1 … y+32**, i.e. screen x 1322-1461, y 1-32. `net.png` pixel (px,py) = screen (x+1+px, y+1+py).
- Cross-check with `xwininfo -display :0 -root -tree`: plugin 26 is the 142x34 child of the 1920x35 panel window.

**Screenshots:**

```sh
import -display :0 -window root -crop 142x34+1321+0 +repage $QA/evidence/AC-xx/p26-$(date +%H%M%S.%N).png      # plugin 26
import -display :0 -window root -crop 238x34+1321+0 +repage $QA/evidence/AC-12/strip-NN.png                      # 26 + 24 + 23
```

- Screenshots are RGB without alpha. Compare only r, g, b. Transparent PNG pixels show the panel background (about #293650).
- Netload-23's region in the 238-wide crop is x 190-237.

**Live daemon identity:**
```sh
D=/run/user/1000/panelgraph
P=$(cat $D/pid)
cat /proc/$P/comm
[ /proc/$P/cwd -ef $D ] && echo live-daemon
```
Count daemons by scanning `/proc/*/comm == panelgraph` and filtering by cwd. The sandbox daemon has the same comm but cwd `$SB/run/panelgraph`.

## 4. Evidence and reporting

For each AC, store raw evidence under `$QA/evidence/AC-xx/`:
- scenario logs (JSON lines of time, tooltip lines, pixel probes);
- `net.png` and `net.txt` copies at assertion time;
- screenshots;
- command transcripts;
- sysfs snapshots.

Report (returned to the orchestrator, not written as a .md file), one row per AC:

```
AC-id | PASS / FAIL / BLOCKED / SKIPPED | evidence path(s) | measured values vs expected | note
```

- **FAIL:** include the exact assertion, the measured value and a reproduction command.
- **BLOCKED:** the environment prevented the test, e.g. the daemon was not deployed.
- **SKIPPED:** state the reason: `DEFERRED`, `NOT BUILT (Should/Could)`, `APPROVAL PENDING`, or `RECOMMENDED SKIP (OQ-10)`.

End the report with:
- totals per tag;
- the security consultant's sign-off notes (SEC-QA-1, SEC-QA-2);
- for AC-68, the answer to "do counters survive an in-place switch?".

Before any test, snapshot for AC-20:
```sh
xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids
xfconf-query -c xfce4-panel -p /plugins/plugin-26 -lv
sha256sum ~/.config/xfce4/panel/*.rc
```

---

## 5. Sandbox: build and harness

The sandbox is a **scratch copy of the deployed daemon** running with `PANELGRAPH_*` env vars that redirect every sysfs/proc path into a fake tree, a separate `XDG_RUNTIME_DIR` (separate lock and pid) and an `iw` stub.
- It needs no root and never touches real interfaces.
- `PANELGRAPH_ADDRS` must always be set. Without it the daemon would ioctl the **real** `wlan1` and show the live IP.

### 5.1 Layout
```
$SB/panelgraph-daemon              copy of ~/.local/bin/panelgraph-daemon (or $DAEMON_SRC)
$SB/sys/class/net/<if>/            type flags operstate carrier_changes ifindex
                    statistics/    rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped
                    device   -> ../../../devices/fake/<if>      (relative symlink; target dir exists)
                    phy80211 -> ../../ieee80211/phyN            ($SB/sys/class/ieee80211/phyN/name contains "phyN")
$SB/proc/net/route  arp  wireless
$SB/proc/sys/net/ipv4/ip_forward
$SB/addrs                           "wlan1 10.99.0.25" lines
$SB/iw/dev.txt  link-<if>.txt  mode (ok|hang|garbage)  calls.log  fds.<pid>.log
$SB/bin/iw                          stub (5.4)
$SB/run/                            XDG_RUNTIME_DIR -> daemon writes $SB/run/panelgraph/*
$SB/rates.json                      traffic engine input
$SB/engine.run, keepalive           engine runs while engine.run exists; it touches seen every 2 s while keepalive exists
$SB/stage/, trash/                  for atomic interface add/remove (never create temp entries directly in sys/class/net)
```

Environment for the daemon:

| Var | Value |
|---|---|
| `XDG_RUNTIME_DIR` | `$SB/run` |
| `PANELGRAPH_SYSNET` | `$SB/sys/class/net` |
| `PANELGRAPH_PROCNET` | `$SB/proc/net` |
| `PANELGRAPH_IPFORWARD` | `$SB/proc/sys/net/ipv4/ip_forward` |
| `PANELGRAPH_ADDRS` | `$SB/addrs` |
| `PANELGRAPH_IW` | `$SB/bin/iw` |
| `PANELGRAPH_ALERT_HOLD` | `20` |
| `PATH` | `/usr/bin:/bin` |

### 5.2 Harness `sbx.py`, reference implementation

Save as `$QA/sbx.py`. Scenario scripts sit next to it and `from sbx import *`.

```python
#!/usr/bin/env python3
"""panelgraph QA sandbox harness. CLI: python3 sbx.py base|engine|start|stop"""
import json, os, re, shutil, signal, socket, struct, subprocess, sys, time

QA  = "$SCRATCH/wf3/qa"
SB  = f"{QA}/sb"
NET = f"{SB}/sys/class/net"
RUN = f"{SB}/run/panelgraph"
KiB, MiB, GiB = 1024, 1024 ** 2, 1024 ** 3
ENV = {"HOME": os.path.expanduser("~"), "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": f"{SB}/run",
       "PANELGRAPH_SYSNET": NET, "PANELGRAPH_PROCNET": f"{SB}/proc/net",
       "PANELGRAPH_IPFORWARD": f"{SB}/proc/sys/net/ipv4/ip_forward",
       "PANELGRAPH_ADDRS": f"{SB}/addrs", "PANELGRAPH_IW": f"{SB}/bin/iw",
       "PANELGRAPH_ALERT_HOLD": "20"}

# ---------- files ----------
def wr(path, data):
    d, b = os.path.split(path)
    tmp = os.path.join(d, f".{b}.tmp")
    with open(tmp, "w") as f:
        f.write(f"{data}\n")
    os.replace(tmp, path)

def rd(path):
    with open(path) as f:
        return f.read().strip()

# ---------- interfaces ----------
_IFX = [10]
def make_iface(name, typ=1, dev=True, phy=None, oper="up", flags=0x1003, base=5 * GiB, carrier=1):
    stage = f"{SB}/stage/{name}"
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(f"{stage}/statistics")
    _IFX[0] += 1
    for k, v in (("type", typ), ("flags", hex(flags)), ("operstate", oper),
                 ("carrier_changes", carrier), ("ifindex", _IFX[0])):
        wr(f"{stage}/{k}", v)
    for k in ("rx_bytes", "tx_bytes"):
        wr(f"{stage}/statistics/{k}", base)
    for k in ("rx_packets", "tx_packets", "rx_errors", "tx_errors", "rx_dropped", "tx_dropped"):
        wr(f"{stage}/statistics/{k}", 0)
    if dev:
        os.makedirs(f"{SB}/sys/devices/fake/{name}", exist_ok=True)
        os.symlink(f"../../../devices/fake/{name}", f"{stage}/device")
    if phy:
        os.makedirs(f"{SB}/sys/class/ieee80211/{phy}", exist_ok=True)
        wr(f"{SB}/sys/class/ieee80211/{phy}/name", phy)
        os.symlink(f"../../ieee80211/{phy}", f"{stage}/phy80211")
    if os.path.lexists(f"{NET}/{name}"):
        del_iface(name)
    os.rename(stage, f"{NET}/{name}")            # appears atomically

def del_iface(name):
    os.makedirs(f"{SB}/trash", exist_ok=True)
    tr = f"{SB}/trash/{name}.{time.time_ns()}"
    os.rename(f"{NET}/{name}", tr)               # disappears atomically
    shutil.rmtree(tr)

def set_attr(name, key, value):                  # e.g. set_attr("wlan1", "type", 803); ("wlan0", "flags", hex(0x1103))
    wr(f"{NET}/{name}/{key}", value)

# ---------- proc/net ----------
ROUTE_HDR = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT"
ARP_HDR = "IP address       HW type     Flags       HW address            Mask     Device"
WIRELESS_HDR = ("Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n"
                " face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22")
def gwhex(ip): return "%08X" % struct.unpack("<I", socket.inet_aton(ip))[0]   # 10.99.0.1 -> 0100630A
def route_line(iface, gw="10.99.0.1", flags="0003", metric=603):
    return f"{iface}\t00000000\t{gwhex(gw) if gw else '00000000'}\t{flags}\t0\t0\t{metric}\t00000000\t0\t0\t0"
def set_routes(*lines): wr(f"{SB}/proc/net/route", "\n".join([ROUTE_HDR, *lines]))
def arp_line(ip, mac, dev, flags="0x2"): return f"{ip:<16} 0x1         {flags:<11} {mac:<21} *        {dev}"
def set_arp(*lines): wr(f"{SB}/proc/net/arp", "\n".join([ARP_HDR, *lines]))
def set_wireless(*rows):                          # rows: ("wlan1", -41)
    wr(f"{SB}/proc/net/wireless", "\n".join([WIRELESS_HDR] + [
        f" {n}: 0000   69.  {lvl}.  -256        0      0      0      0      0        0" for n, lvl in rows]))

# ---------- iw fixtures ----------
WLAN1 = dict(name="wlan1", phy="phy1", type="managed", ssid="SBX-NET", chan=36, freq=5180, width=80)
WLAN0 = dict(name="wlan0", phy="phy0", type="managed")
def MON(name, phy="phy0"): return dict(name=name, phy=phy, type="monitor", chan=44, freq=5220, width=20)
def iw_set(*vifs):
    out = []
    for phy in sorted({v["phy"] for v in vifs}, reverse=True):
        out.append(f"phy#{phy[3:]}")
        if phy == "phy0":                         # P2P-device block: parser must reset here
            out += ["\tUnnamed/non-netdev interface", "\t\twdev 0x2", "\t\taddr 02:00:00:00:00:02", "\t\ttype P2P-device"]
        for v in (v for v in vifs if v["phy"] == phy):
            out += [f"\tInterface {v['name']}", "\t\tifindex 1", "\t\twdev 0x1", "\t\taddr 02:00:00:00:00:03"]
            if v.get("ssid"): out.append(f"\t\tssid {v['ssid']}")
            out.append(f"\t\ttype {v['type']}")
            if v.get("chan"):
                out.append(f"\t\tchannel {v['chan']} ({v['freq']} MHz), width: {v['width']} MHz, center1: {v['freq']} MHz")
            out += ["\t\ttxpower 20.00 dBm", "\t\tmulticast TXQ:",
                    "\t\t\tqsz-byt\tqsz-pkt\tflows\tdrops\tmarks\toverlmt\thashcol\ttx-bytes\ttx-packets",
                    "\t\t\t0\t0\t0\t0\t0\t0\t0\t0\t\t0"]
    wr(f"{SB}/iw/dev.txt", "\n".join(out))
def iw_link(ifname, bssid="02:00:00:00:00:aa", ssid="SBX-NET", freq=5180, sig=-41, rx=650.0, tx=585.0):
    wr(f"{SB}/iw/link-{ifname}.txt", "\n".join([
        f"Connected to {bssid} (on {ifname})", f"\tSSID: {ssid}", f"\tfreq: {freq}.0",
        f"\tsignal: {sig} dBm", f"\trx bitrate: {rx} MBit/s VHT-MCS 7 80MHz short GI VHT-NSS 2",
        f"\ttx bitrate: {tx} MBit/s VHT-MCS 6 80MHz VHT-NSS 2"]))
def iw_mode(m): wr(f"{SB}/iw/mode", m)            # ok | hang | garbage

IW_STUB = r'''#!/bin/sh
L="@SB@/iw"
echo "$(date +%s.%N) start $$ $*" >> "$L/calls.log"
ls -l /proc/$$/fd > "$L/fds.$$.log" 2>&1
mode=ok; read -r mode < "$L/mode" 2>/dev/null
case "$mode" in
  hang) exec sleep 60 ;;
  garbage) echo 'zz%%%garbage'; exit 0 ;;
esac
if [ "$#" -eq 1 ] && [ "$1" = dev ]; then cat "$L/dev.txt"
elif [ "$1" = dev ] && [ "$3" = link ]; then cat "$L/link-$2.txt" 2>/dev/null || echo "Not connected."
else exit 1; fi
echo "$(date +%s.%N) end $$" >> "$L/calls.log"
'''

# ---------- traffic engine ----------
def _cfg():
    try:
        with open(f"{SB}/rates.json") as f: return json.load(f)
    except (OSError, ValueError):
        return {"rates": {}, "resets": {}}
def _save(cfg):
    tmp = f"{SB}/.rates.json.tmp"
    with open(tmp, "w") as f: json.dump(cfg, f)
    os.replace(tmp, f"{SB}/rates.json")
def set_rates(table):            # {"wlan1": (rx_Bps, tx_Bps[, rx_pps])}; value None removes
    cfg = _cfg()
    for n, v in table.items():
        if v is None: cfg["rates"].pop(n, None)
        else: cfg["rates"][n] = [float(x) for x in (list(v) + [0, 0, 0])[:3]]
    _save(cfg)
def reset_counters(name):        # simulates a counter reset to 0 (driver reload / reconnect)
    cfg = _cfg(); cfg["resets"][name] = time.time_ns(); _save(cfg)

def engine():
    wr(f"{SB}/engine.pid", os.getpid())
    state, seen_reset, cfg, mt = {}, {}, {"rates": {}, "resets": {}}, None
    last = last_touch = time.monotonic()
    while os.path.exists(f"{SB}/engine.run"):
        try:
            m = os.stat(f"{SB}/rates.json").st_mtime_ns
            if m != mt: cfg, mt = _cfg(), m
        except OSError:
            pass
        now = time.monotonic(); dt, last = now - last, now
        for n, r in list(cfg["rates"].items()):
            d = f"{NET}/{n}/statistics"
            try:
                ino = os.stat(f"{NET}/{n}").st_ino
                s = state.get(n)
                if s is None or s[3] != ino:      # new or re-created interface: continue from its files
                    s = state[n] = [int(rd(f"{d}/rx_bytes")), int(rd(f"{d}/tx_bytes")), int(rd(f"{d}/rx_packets")), ino]
                tok = cfg["resets"].get(n)
                if tok is not None and seen_reset.get(n) != tok:
                    seen_reset[n] = tok; s[0] = s[1] = s[2] = 0
                s[0] += r[0] * dt; s[1] += r[1] * dt; s[2] += r[2] * dt
                wr(f"{d}/rx_bytes", int(s[0])); wr(f"{d}/tx_bytes", int(s[1])); wr(f"{d}/rx_packets", int(s[2]))
            except (OSError, ValueError):
                state.pop(n, None)
        if os.path.exists(f"{SB}/keepalive") and now - last_touch >= 2 and os.path.isdir(RUN):
            with open(f"{RUN}/seen", "a"): pass
            os.utime(f"{RUN}/seen"); last_touch = now
        time.sleep(0.025)

def start_engine():
    open(f"{SB}/engine.run", "w").close()
    subprocess.run(["setsid", "-f", sys.executable, os.path.abspath(__file__), "engine"],
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
def stop_engine():
    try: os.unlink(f"{SB}/engine.run")    # engine exits on its own within 25 ms; never kill by pattern
    except OSError: pass

# ---------- daemon ----------
def wait_until(pred, timeout, step=0.05):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v: return v
        time.sleep(step)
    return pred()
def daemon_pid():
    try:
        pid = int(rd(f"{RUN}/pid"))
        if rd(f"/proc/{pid}/comm") == "panelgraph" and os.path.samefile(f"/proc/{pid}/cwd", RUN):
            return pid
    except (OSError, ValueError):
        pass
    return None
def start_daemon(**extra):
    os.makedirs(f"{SB}/run", exist_ok=True)
    env = dict(ENV, **{k: str(v) for k, v in extra.items()})
    subprocess.run(["setsid", "-f", "python3", f"{SB}/panelgraph-daemon"], env=env,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return wait_until(daemon_pid, 5)
def stop_daemon(sig=signal.SIGTERM):
    pid = daemon_pid()
    if pid:
        os.kill(pid, sig)
        wait_until(lambda: not os.path.exists(f"/proc/{pid}"), 5)

# ---------- base fixture ----------
def base(daemon_src=os.path.expanduser("~/.local/bin/panelgraph-daemon")):
    stop_daemon()
    for d in ("sys", "proc", "run", "stage", "trash", "iw", "bin"):
        shutil.rmtree(f"{SB}/{d}", ignore_errors=True)
    for f in ("rates.json",):
        try: os.unlink(f"{SB}/{f}")
        except OSError: pass
    for d in (NET, f"{SB}/proc/net", f"{SB}/proc/sys/net/ipv4", f"{SB}/iw", f"{SB}/bin", f"{SB}/run"):
        os.makedirs(d, exist_ok=True)
    shutil.copy2(os.environ.get("DAEMON_SRC", daemon_src), f"{SB}/panelgraph-daemon")
    set_routes(route_line("wlan1"))
    set_arp(arp_line("10.99.0.1", "02:00:00:00:00:01", "wlan1"))
    set_wireless(("wlan1", -41))
    wr(f"{SB}/proc/sys/net/ipv4/ip_forward", 1)
    wr(f"{SB}/addrs", "wlan1 10.99.0.25")
    iw_set(WLAN1, WLAN0); iw_link("wlan1"); iw_mode("ok")
    open(f"{SB}/iw/calls.log", "w").close()
    wr(f"{SB}/bin/iw", IW_STUB.replace("@SB@", SB).rstrip("\n")); os.chmod(f"{SB}/bin/iw", 0o755)
    make_iface("eth0", oper="down")
    make_iface("wlan0", phy="phy0", oper="down")
    make_iface("wlan1", phy="phy1")
    make_iface("vnet9", dev=False, oper="unknown", flags=0x1303)
    make_iface("docker0", dev=False)
    make_iface("virbr-msf", dev=False)
    make_iface("lo", typ=772, dev=False, oper="unknown", flags=0x9)
    set_rates({"wlan1": (512 * KiB, 128 * KiB), "vnet9": (MiB, MiB), "docker0": (MiB, MiB),
               "virbr-msf": (MiB, MiB), "lo": (MiB, MiB)})
    open(f"{SB}/keepalive", "w").close()

# ---------- observation ----------
def image(path=None):
    import cairo
    return cairo.ImageSurface.create_from_png(path or f"{RUN}/net.png")
def pixel(s, x, y):
    d, st = s.get_data(), s.get_stride()
    o = y * st + 4 * x
    b, g, r, a = d[o], d[o + 1], d[o + 2], d[o + 3]
    if a == 0: return "T"
    return f"{r:02X}{g:02X}{b:02X}" if a == 255 else f"A{a:02X}:{r:02X}{g:02X}{b:02X}"
def rgb(s, x, y):                                  # for RGB screenshots (alpha ignored)
    d, st = s.get_data(), s.get_stride(); o = y * st + 4 * x
    return f"{d[o + 2]:02X}{d[o + 1]:02X}{d[o]:02X}"
def tooltip(txt=None):
    import gi
    gi.require_version("Pango", "1.0")
    from gi.repository import Pango
    t = txt if txt is not None else open(f"{RUN}/net.txt", encoding="utf-8").read()
    m = t[t.index("<tool>") + 6: t.rindex("</tool>")]
    ok, _attrs, plain, _acc = Pango.parse_markup(m, -1, "\0")   # raises on invalid markup
    return [re.sub(r"\s+", " ", l).strip() for l in plain.split("\n")], m, t
UNITS = {"B": 1, "KiB": KiB, "MiB": MiB, "GiB": GiB, "TiB": 1024 * GiB}
NUM = r"([\d.]+) (B|KiB|MiB|GiB|TiB)"
def _v(m, i): return float(m.group(i)) * UNITS[m.group(i + 1)]
def total(lines):
    for l in lines:
        m = re.search(rf"Total ↓ {NUM}/s ↑ {NUM}/s Scale {NUM}/s", l)
        if m: return _v(m, 1), _v(m, 3), _v(m, 5)
def monitor(lines):
    for l in lines:
        m = re.search(rf"MONITOR .*captured {NUM}/s.*injected {NUM}/s.*Mon scale {NUM}/s", l)
        if m: return _v(m, 1), _v(m, 3), _v(m, 5)
def record(seconds, every=0.05, png=False):
    """Poll net.txt (and optionally net.png) -> list of (t_monotonic, lines, surface|None)."""
    out, end = [], time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            lines, _, _ = tooltip()
            out.append((time.monotonic(), lines, image() if png else None))
        except Exception as e:
            out.append((time.monotonic(), [f"READ-ERROR {e!r}"], None))
        time.sleep(every)
    return out
def within(v, ref, tol=0.05): return v is not None and abs(v - ref) <= tol * ref
def check(ac, cond, detail=""):
    with open(f"{QA}/results.jsonl", "a") as f:
        f.write(json.dumps({"ac": ac, "pass": bool(cond), "detail": str(detail), "t": time.time()}) + "\n")
    return cond
def strips_rows(n, H=32, y0=0):                    # expected strip row ranges (requirements §4.1)
    usable = H - (n - 1); base_h = usable // n; extra = usable % n; rows, y = [], y0
    for k in range(n):
        h = base_h + (1 if k >= n - extra else 0); rows.append((y, y + h - 1)); y += h + 1
    return rows

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "engine": engine()
    elif cmd == "base": base()
    elif cmd == "start": print(start_daemon())
    elif cmd == "stop": stop_daemon(); stop_engine()
    else: print(__doc__)
```

`strips_rows(2)` gives `[(0,14),(16,31)]`, `strips_rows(3)` gives `[(0,9),(11,20),(22,31)]`, and `strips_rows(3, 30, 1)` gives `[(1,9),(11,19),(21,30)]`. These match `requirements.md` §4.1.

### 5.3 BASE fixture
`base()` creates the following:

| Interface | type | device | phy | operstate | flags | rates (rx/tx) |
|---|---|---|---|---|---|---|
| eth0 | 1 | yes | – | down | 0x1003 | 0 |
| wlan0 | 1 | yes | phy0 | down | 0x1003 | 0 |
| wlan1 | 1 | yes | phy1 | up | 0x1003 | 512 KiB/s / 128 KiB/s |
| vnet9 | 1 | no | – | unknown | 0x1303 | 1 MiB/s / 1 MiB/s |
| docker0, virbr-msf | 1 | no | – | up | 0x1003 | 1 MiB/s each way |
| lo | 772 | no | – | unknown | 0x9 | 1 MiB/s |

The remaining fixture files:
- **Counters:** every counter starts at 5 GiB, which catches any "new interface counted from 0" bug.
- **route:** default `wlan1 via 10.99.0.1 metric 603`.
- **arp:** `10.99.0.1 → 02:00:00:00:00:01 (0x2) on wlan1`.
- **wireless:** `wlan1 -41`.
- **ip_forward:** 1.
- **addrs:** `wlan1 10.99.0.25`.
- **iw fixtures:** wlan1 `SBX-NET` ch36 5180/80, link BSSID `02:00:00:00:00:aa`, rx 650 / tx 585 Mbit/s; phy0 has a P2P-device block before wlan0.

Expected BASE tooltip once steady (with F-11 built; whitespace collapsed):
```
■■ Total ↓ 512.0 KiB/s ↑ 128.0 KiB/s Scale 512.0 KiB/s
wlan1 ★ SBX-NET -41 dBm ch36 5180 MHz/80 rx 650/tx 585 Mbit/s ↓ 512.0 KiB/s ↑ 128.0 KiB/s
Gateway 10.99.0.1 02:00:00:00:00:01 via wlan1, IP 10.99.0.25
Up 5 min …
Idle: eth0 no carrier · wlan0 not connected
```
Numbers are ±5 %.

### 5.4 iw stub
`base()` writes `$SB/bin/iw` from `IW_STUB`.
- **Logging:** every call goes to `calls.log` (start/end with pid) and its fds to `fds.<pid>.log`.
- **Modes** (`iw_mode()`): `ok` serves the fixtures; `hang` does `exec sleep 60`, keeping the same pid so the daemon's kill works; `garbage` returns junk.
- **"Missing" test:** restart the daemon with `start_daemon(PANELGRAPH_IW="/nonexistent/iw")`.

### 5.5 Running
```sh
cd $QA
python3 -c 'import sbx; sbx.base()'
python3 -c 'import sbx; sbx.start_engine(); print(sbx.start_daemon())'
# ... scenario scripts ...
python3 sbx.py stop        # SIGTERM via the sandbox pid file + engine stop
```
Run each scenario in a fresh `base()` unless it says "continues". Steady = `time.sleep(34)` after the last rate change.

### 5.6 Pixel conventions
- `pixel(image(), x, y)` returns `"FF4F00"`, `"T"` (alpha 0), or `"Aaa:rrggbb"` for partial alpha, which is **always a FAIL** because anti-aliasing must be off.
- Heights: count consecutive identical pixels upward from a strip's bottom row. Tolerance ±2 px.

---

## 6. Sandbox scenarios

Each scenario lists its steps and expected results. All timings are measured with `record()` from the moment the fixture change call returns.

| Scenario | Steps | ACs |
|---|---|---|
| **S-A Base** | `base()`, start engine and daemon, wait 34 s. Probe the tooltip, pixels and stub logs. | AC-09, AC-13, AC-14 (512), AC-19 (click in sandbox net.txt too), AC-22, AC-36 (S-A part), AC-38, AC-03 (stub fds), AC-40 (120 s log) |
| **S-Z Zero** | `base()`, `set_rates({"wlan1": (0,0)})` before start; wait 34 s → `Scale 64.0 KiB/s`. Then set 512/128 → wait 34 s → set 0 → wait 34 s → 64.0 again. | AC-14 |
| **S-Q Step** | `base()` with wlan1 at 0; start; wait 34 s. `set_rates({"wlan1": (512*KiB, 0)})` at t0; `record(5, png=True)`. Check the AC-16 limits. In the PNG series, the nonzero span's left edge moves left 1 px per tick. | AC-16, AC-13 |
| **S-B airmon-style** | From the S-A steady state: `del_iface("wlan0"); make_iface("wlan0mon", typ=803, phy="phy0"); set_rates({"wlan0mon": (512*KiB, 0, 1000)}); iw_set(WLAN1, MON("wlan0mon"))`. `record(3)`, then wait 34 s. Variant: rx 0 for the solid baseline. | AC-24, AC-25, AC-27, AC-30 (solid), AC-31, AC-15 (2-strip variant with wlan1 tx 300 B/s) |
| **S-C in-place switch** | From S-A steady: `set_rates({"wlan1": (2*MiB, 0)})` and in the **same** step `set_attr("wlan1","type",803); set_routes(); iw_set(MON("wlan1","phy1"), WLAN0)`. The counters continue from about 5 GiB. `record(36)` with 50 ms polls. | AC-23, AC-24, AC-37 (monitor-only at 34 s) |
| **S-G switch back** | Continues S-C: `set_attr("wlan1","type",1); set_routes(route_line("wlan1")); set_rates({"wlan1": (512*KiB,128*KiB)}); iw_set(WLAN1, WLAN0)`. `record(36, png=True)`. | AC-32 |
| **S-D vif alongside** | S-A steady + `make_iface("wlan1mon", typ=803, phy="phy1"); set_rates({"wlan1mon": (512*KiB,0,1000)}); iw_set(WLAN1, MON("wlan1mon","phy1"), WLAN0)`, wait 34 s. **Variant for AC-28:** wlan1 (128 KiB, 32 KiB), wlan1mon (8 MiB, 0). | AC-33, AC-28 |
| **S-E monitor down** | S-B steady, then `set_attr("wlan0mon","flags",hex(0x1002)); set_attr("wlan0mon","operstate","down"); set_rates({"wlan0mon": (0,0)})`, wait 34 s. | AC-30 (dotted) |
| **S-F injected** | S-B with `set_rates({"wlan0mon": (512*KiB, 256*KiB, 1000)})`, wait 34 s; keep it 70 s to verify that S1 stays silent. | AC-29, AC-31 |
| **S-H strips** | `base()`; `set_attr("eth0","operstate","up")`; `make_iface("usb0")`; rates eth0 (256K,0), usb0 (128K,0), wlan1 (512K,128K); add wlan0mon (512K,0) as in S-B → **H1**, wait 34 s. `del_iface("wlan0mon")` → wait 34 s → **H2**. `set_attr("wlan0","operstate","up")`, wlan0 (64K,0) → wait 34 s → **H3**. Hysteresis from H2: eth0 rate 0 + operstate down at t0, `record(36, png=True)`. Then eth0 operstate up, rate 0 → strip back within 6.5 s. | AC-34, AC-35, AC-36 |
| **S-I promisc** | S-A steady; `set_attr("wlan0","flags",hex(0x1103))` → line within 6.5 s; back to `0x1003` → gone within 6.5 s. Add `wlan0mon` (803) with flags `0x1103` → no PROMISC line for it. vnet9 (0x1303) is never named. Throughout, the PNG has no FF00FF/FFA0FF/FF2020 (except from the monitor in the last step, which is checked separately) and 1 strip until wlan0mon is added. | AC-44 |
| **S-J0 gateway edge** | `set_routes(route_line("wlan1"), route_line("eth0", metric=100))` with eth0 up → `via eth0`; `set_arp(arp_line("10.99.0.1","02:00:00:00:00:01","wlan1","0x0"))` → MAC `?`; `set_routes()` → `No default route`; tun0 (65534, no dev) + `set_routes(route_line("tun0", gw=None, flags="0001"))` → `Gateway ? ? via tun0, IP ?`. | AC-46 |
| **S-J1 alert** | S-A steady, wait ≥ 10 s more (baseline taken). `set_arp(arp_line("10.99.0.1","02:00:00:00:de:ad","wlan1"))` at t0. `record(14, png=True)`. Assert the frame (all 340 px), the inset content pixels, the `!!` line and one extra `link` call in calls.log. | AC-47 |
| **S-J2…J6 negatives** | Each from a fresh baseline, 25 s observation. J2: `set_attr("wlan1","carrier_changes",2)` then the MAC change 1 s later. J3: new MAC with flags `0x0`. J4: add the row `arp_line("10.99.0.1","02:00:00:00:00:77","eth0")` (the route stays on wlan1). J5: baseline arp `00:00:5e:00:01:01` (restart from base with it), then `00:00:5e:00:01:02`. J6: `iw_link("wlan1", bssid="02:00:00:00:00:bb")` and the MAC change in the same step. | AC-48 |
| **S-J7 hold** | Continues J1: at t1 restore MAC `02:00:00:00:00:01`. Frame present at t1+19 s, absent by t1+27 s; `!!` line still present. | AC-49 |
| **S-J8 persistence** | During an active alert (J1 again): check gw.json keys; `stop_daemon()`; `start_daemon()` → frame + `!!` within 6.5 s. Separately: in steady state, gw.json mtime is unchanged over 60 s. | AC-50 |
| **S-J9 accept** | During an active alert: `os.unlink(f"{RUN}/gw.json")` → frame cleared and `Gateway MAC accepted` within 6.5 s; gw.json `mac` = `02:00:00:00:de:ad`; no alert for 30 s. | AC-51 |
| **S-K iw** | S-A, then: (1) `iw_mode("hang")` for 60 s: max gap between net.txt content changes ≤ 0.75 s; every stub pid in calls.log is gone (`/proc/<pid>` absent) ≤ 2 s after its start; `(stale` ≤ 12 s; `Wi-Fi details unavailable (timeout)` ≤ 45 s; error.log mtime changes ≤ 1 time per distinct error over 120 s; no `<txt>!</txt>`. (2) `iw_mode("garbage")` → `(parse)`. (3) `iw_mode("ok")`, then restart with `PANELGRAPH_IW=/nonexistent/iw` → `(iw missing)`. (4) Budget: `iw_mode("ok")`, count calls over 120 s; remove wlan0/wlan1 (no phy) → 0 calls in 60 s; wlan1 operstate down → no `link` calls. In all cases the `Gateway` line stays correct. | AC-40, AC-41, AC-03 |
| **S-L hostile SSID** | `WLAN1` with `ssid=r'a&b<c>"d</tool><click>touch ' + QA + r'/pwned</click>\x07\x0a'`; wait ≤ 12 s. Assert the AC-42 tag counts (in the raw net.txt), that Pango parse succeeds, the literal text, and length ≤ 32. | AC-42 |
| **S-M hot-plug** | S-A steady; `make_iface("usb0")` (5 GiB base) + rates (128K,0) → `record(3)`; then `del_iface("usb0")` → `record(3)`. | AC-26 |
| **S-N lifecycle** | (1) AC-06: a second `start_daemon()` while running → only one pid. (2) AC-07: `os.unlink(f"{SB}/keepalive")` → daemon gone at 30-32 s; pid file gone; lock kept. (3) AC-08: `os.mkdir(f"{RUN}/net.png.tmp")` → "!" ≤ 1 s, error.log has `net:`; `os.rmdir` → recovers ≤ 6.5 s; mem.txt has no "!". | AC-06, AC-07, AC-08 |
| **S-O reconnect + suspend** | (1) S-A steady; at t0: `set_attr("wlan1","operstate","down")`; t0+3 s: `reset_counters("wlan1"); set_attr("wlan1","carrier_changes",3); set_attr("wlan1","operstate","up"); set_arp(arp_line("10.99.0.1","02:00:00:00:00:99","wlan1")); iw_set(dict(WLAN1, ssid="SBX-OTHER"), WLAN0); iw_link("wlan1", ssid="SBX-OTHER", bssid="02:00:00:00:00:cc")`; `record(30, png=True)`. (2) `os.kill(daemon_pid(), signal.SIGSTOP)`, wait 10 s, `SIGCONT`, `record(5)`. | AC-17, AC-18 |
| **S-R replacements + worst case** | (1) All NICs down, rates 0, 34 s → no opaque pixel + `No managed interface up` + Idle line with three NICs. (2) Remove every `device`/`phy` interface → `No network interfaces`. (3) Worst case (AC-43): H1 + J1 alert + wlan0 flags 0x1103 + eth0 up + tun0 → ≤ 10 lines, order, glyph spans. | AC-37, AC-43 |
| **S-P Shoulds** (only those built) | AC-52: wlan1 (100K, 300K) for 70 s; then wlan1 tx 0 and wlan0mon tx 300K. AC-53: `set_routes(route_line("eth0"))` with eth0 up. AC-54: `make_iface("tun0", typ=65534, dev=False, oper="unknown", flags=0x1091)` + `wg0` with 1 MiB/s. AC-55: eth0 + wlan1 up, then `ip_forward` 0. AC-56: `iw_set(WLAN1, dict(WLAN0, type="AP"))` with wlan0 up; then `mesh point`, `IBSS`. AC-57: `make_iface("wwan0", typ=65534)` with rx 256K. AC-58: `set_attr("wlan1","ifindex",99); reset_counters("wlan1")`. | AC-52 to AC-58 |

---

## 7. Security consultant guidance: how to check WLAN monitor mode (summary)

From the cyber security specialist; agreed with Network and the BA.

1. **Detection:** an interface is in monitor mode when `type ∈ {801,802,803}` **and** it has a `phy80211` or `device` link. airmon-ng creates a new `wlanXmon` (counters from 0). `iw dev wlanX set type monitor` keeps the name and the counters (the latter still to be confirmed live in AC-68).
2. **What must be true** in every monitor scenario:
   - **Captured bytes are never in `Total`**, not even on the switch tick: AC-23, AC-31.
   - The monitor strip uses #FF00FF (captured) / #FFA0FF (injected) with its own scale.
   - The baseline is solid when up and dotted when down.
   - The MONITOR line names the vif, phy, channel and state.
3. **Promisc is not monitor.** PROMISC is a tooltip line only. Bridge ports (vnet*, 0x1303) are never reported.
4. **Unattended testing is sandbox only.** QA never runs airmon-ng, iw set, ip link or nmcli.
5. **Live checks need user approval**, step by step (§8). wlan1 carries the uplink and must never be touched. **Never `airmon-ng check kill`.** No deauth or injection (OQ-12).
6. The security consultant reviews the sandbox fixture before the first run (SEC-QA-1) and adjudicates failing security ACs (SEC-QA-2).

---

## 8. Live procedures that need user approval

Each L-step is approved separately by the user, and the user runs the `sudo` lines. QA observes, takes screenshots and records. The security consultant gives go/no-go (SEC-QA-3) and watches the guard (SEC-QA-4).

### 8.0 Pre-checks and guard (run before and every 5 s during any L-step)
```sh
G_BSSID=$(iw dev wlan1 link | awk '/Connected to/{print $3}')     # record, e.g. aa:bb:cc:dd:ee:02
G_CC=$(cat /sys/class/net/wlan1/carrier_changes)                  # record, e.g. 14
guard() {
  ip route show default | grep -q 'default via 192.168.1.1 dev wlan1' || { echo FAIL-route; return 1; }
  L=$(iw dev wlan1 link)
  echo "$L" | grep -q 'SSID: HomeNet' && echo "$L" | grep -q "Connected to $G_BSSID" || { echo FAIL-ssid; return 2; }
  ping -c1 -W1 192.168.1.1 >/dev/null || { echo FAIL-ping; return 3; }      # approved live procedure only
  [ "$(cat /sys/class/net/wlan1/carrier_changes)" = "$G_CC" ] || { echo FAIL-carrier; return 4; }
  echo OK
}
```
- Also record before starting: `cat /sys/class/net/wlan0/flags`, `nmcli -t -f DEVICE,TYPE,STATE dev`, `iw dev`, `ip -br link`, `cat /sys/class/net/wlan0/statistics/rx_bytes`.
- **Any guard failure triggers an immediate rollback** of the current step.

### 8.1 L0: netdiscover (user decision, OQ-4 / AC-70)
- Recommended, not required for L1: the user runs `sudo kill <pid>`. Then check that the 0x100 bit clears in `/sys/class/net/wlan0/flags` and the `PROMISC wlan0` line disappears within 6.5 s (AC-70).
- If it keeps running:
  - On link down, its raw sockets stay bound (ENETDOWN) and the promisc refcount stays, so PROMISC returns after rollback.
  - On interface delete (L3), its sockets are unbound for good and it will error out or spin. It never rebinds to the new wlan0.

### 8.2 L1: add a monitor vif on phy0 (AC-67). Least disruptive.
Steps (user, sudo):
```sh
sudo nmcli device set wlan0 managed no            # this device only, before link down, so NM does not re-up it
sudo ip link set wlan0 down
sudo iw phy phy0 interface add wlan0mon type monitor
sudo ip link set wlan0mon up
sudo iw dev wlan0mon set channel 44                # same channel as HomeNet, so our own traffic is captured
nmcli -t -f DEVICE,STATE dev | grep wlan0mon       # must be "unmanaged"; else: sudo nmcli device set wlan0mon managed no
```
Observation (QA):
- Within 12 s, net.txt has `MONITOR wlan0mon (phy0, ch44 5220 MHz, up)`.
- Run a 25 s download: `curl -s -o /dev/null --limit-rate 500k --max-time 25 <deb.debian.org file>`.
- During the download:
  - take screenshots every 1 s (§3);
  - the upper strip (rows 0-14) shows FF4F00 and the lower strip (rows 16-31) shows FF00FF;
  - `Total ↓` matches the wlan1 sysfs rate within ±10 % (AC-10 method), and the captured rate is **not** included;
  - the HomeNet line is unchanged; netload 23 rises in orange.
- The guard reports OK throughout.

Rollback (user, sudo):
```sh
sudo ip link set wlan0mon down
sudo iw dev wlan0mon del
sudo ip link set wlan0 up
sudo nmcli device set wlan0 managed yes
```
Verify:
- the guard is OK;
- `iw dev` has no wlan0mon;
- wlan0 flags are 0x1003 (or 0x1103 if netdiscover is alive);
- `nmcli` shows wlan0 `disconnected`;
- the tooltip `MONITOR` line is gone within 0.6 s (`monitor ended …` is shown until the strip scrolls out).

### 8.3 L2: in-place switch of wlan0 (AC-68). Optional, separate approval.
```sh
cat /sys/class/net/wlan0/statistics/rx_bytes        # QA records BEFORE
sudo nmcli device set wlan0 managed no
sudo ip link set wlan0 down
sudo iw dev wlan0 set type monitor                 # mac80211 refuses this while up (EBUSY), hence down first
sudo ip link set wlan0 up
sudo iw dev wlan0 set channel 44
cat /sys/class/net/wlan0/statistics/rx_bytes        # QA records AFTER -> answers "do counters survive?"
```
Observation:
- `MONITOR wlan0 (phy0` within 0.6 s.
- `Total` never includes the captured bytes (50 ms polling of net.txt during a 25 s download: `Total ↓` ≤ 1.1 × the wlan1 sysfs rate).
- Screenshots as in L1.

Rollback:
```sh
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up
sudo nmcli device set wlan0 managed yes
```
Verify as in L1.

### 8.4 L3: `airmon-ng start wlan0`, the user's real workflow (AC-69). Optional, separate approval.
```sh
sudo airmon-ng start wlan0          # NO "check kill". Ignore its warning about interfering processes.
nmcli -t -f DEVICE,STATE dev        # wlan0mon must be unmanaged; else stop and roll back
```
Safety notes:
- Safe for wlan1, which is on a different phy (phy1). Without check kill, NetworkManager and wpa_supplicant are untouched.
- wlan0 is deleted. The recreated wlan0 starts with permaddr aa:bb:cc:dd:ee:03 until NM applies its random MAC again. Monitor mode is passive, so the MAC is exposed only on injection, which is not done.

Observation:
- The monitor strip and `MONITOR wlan0mon (phy0 …` appear within 0.6 s.
- `wlan0` leaves the Idle line.
- The guard reports OK.

Rollback:
```sh
sudo airmon-ng stop wlan0mon
sudo nmcli device set wlan0 managed yes    # only if nmcli shows wlan0 unmanaged
```
Verify:
- wlan0 exists;
- the monitor strip disappears within 34 s;
- the guard is OK;
- NM manages wlan0.

### 8.5 Other approval-gated checks
| AC | What the user does | What QA checks |
|---|---|---|
| AC-70 | Stops netdiscover (L0) | PROMISC line gone within 6.5 s |
| AC-71 | Hovers over the graph; reports or screenshots the tooltip | Coloured ■ glyphs, no raw markup, template order |
| AC-72 | Reconnects Wi-Fi or switches network | No "!", new SSID within 12 s, no `!!`, no spike > 1.1× sysfs |
| AC-73 | Suspends and resumes the laptop | Daemon alive (or restarted once), no "!", no spike, no false `!!` |
| AC-74 | **Recommended skip** (OQ-10) | Only if approved: `sudo ip neigh replace 192.168.1.1 lladdr 02:00:00:00:de:ad dev wlan1 nud reachable` → frame within 12 s; rollback `sudo ip neigh del 192.168.1.1 dev wlan1` |
| AC-75 | DEFERRED (OQ-12) | Only if approved, during L1: `sudo aireplay-ng --test wlan0mon` (never `-0`) → FFA0FF in the monitor strip |

---

## 9. Live procedures that need no approval (read-only, plus allowed curl)

| AC | Procedure |
|---|---|
| AC-01 | Sampler: find the wrapper pid (§3); every 50 ms for 60 s, read `/proc/<pid>/wchan` and log it. Compute the longest run of `pipe_read`/`anon_pipe_read`; it must be ≤ 1.0 s. Run it during idle, during a download, and wrapped around AC-04 and AC-05. Crops 2 s apart during the download must differ. |
| AC-02 | `env -i HOME=$HOME XDG_RUNTIME_DIR=/run/user/1000 PATH=/nonexistent /bin/sh ~/.local/bin/panelgraph-show net > $E/out.txt 2> $E/err.txt; echo $?`, then `cmp` against `net.txt` (retry ×3 if it changed). Check the `seen` mtime before and after. |
| AC-03 | `ls -l /proc/$(cat $D/pid)/fd` and `ls -l /proc/<wrapper26>/fd`: intersect the `pipe:[n]` inodes (must be empty); there must be no `/dev/pts`. Sandbox part: `$SB/iw/fds.*.log`. |
| AC-04 / AC-05 | `kill` / `kill -9` via the pid file (§3 identity check first). Poll `$D/pid` and the /proc scan every 100 ms for 20 s and log the distinct live-dir panelgraph pids. |
| AC-10 | Python: start curl in the background (400k, 25 s). From t = 5 s, run 10 windows of 2 s, each comparing Δ(sum rx_bytes of eth0, wlan0, wlan1)/Δt against the mean `Total ↓` from `tooltip(open(D+'/net.txt').read())` read every 250 ms. Same for ↑. |
| AC-11 | `grep Color_ ~/.config/xfce4/panel/netload-2*.rc`; scan every pixel of live `net.png` for allowed colours; check a screenshot during a download. |
| AC-12 | A 35 s series of 238x34 crops every 1 s (idle 5 s, curl 500k 25 s, idle 5 s). Count FF4F00 in plugin-26 columns x 137-140 of the crop (image x 136-139) and in netload-23 x 190-237. |
| AC-13 (live) | Live `net.png` is 140x32, RGBA; gap columns are T. |
| AC-19 | `grep -o '<click>[^<]*</click>' $D/net.txt` gives exactly one `xfce4-taskmanager`. |
| AC-20 | Compare against the §4 snapshot at the end of testing. |
| AC-21 | `P=$(cat $D/pid); a=$(awk '{print $14+$15}' /proc/$P/stat); timeout 60 tail -f /dev/null; b=$(awk '{print $14+$15}' /proc/$P/stat)`; CPU % = (b − a)/60 with CLK_TCK 100; `grep VmRSS /proc/$P/status`. Once idle, once during a 500k download (two 25 s downloads back to back within the window are allowed; each < 30 s). Abort if the pid changed. |
| AC-39 | Compare tooltip lines with `/proc/net/wireless`, `iw dev wlan1 info`, `/proc/net/arp`, `ip -4 -o addr show wlan1` (all read-only). |
| AC-45 | `cat /sys/class/net/wlan0/flags` vs the PROMISC line; vnet16/17 never named. |

---

## 10. AC procedure index and skip list

| AC | Where | Mode |
|---|---|---|
| AC-01 to AC-05 | §9 | live, read-only |
| AC-06, AC-07, AC-08 | S-N | sandbox |
| AC-09 | S-A | sandbox |
| AC-10, AC-11, AC-12 | §9 | live + curl |
| AC-13 | S-Q + §9 | sandbox + live |
| AC-14 | S-Z / S-A | sandbox |
| AC-15 | S-B variant (+ 1-strip variant: S-A with wlan1 tx 300 B/s) | sandbox |
| AC-16 | S-Q | sandbox |
| AC-17, AC-18 | S-O | sandbox |
| AC-19, AC-20, AC-21 | §9 | live |
| AC-22 | static grep + S-A | sandbox |
| AC-23, AC-24 | S-C (+ S-B) | sandbox |
| AC-25, AC-27 | S-B | sandbox |
| AC-26 | S-M | sandbox |
| AC-28 | S-D variant | sandbox |
| AC-29 | S-F | sandbox |
| AC-30 | S-B variant (solid), S-E (dotted) | sandbox |
| AC-31 | S-B to S-H | sandbox |
| AC-32 | S-G | sandbox |
| AC-33 | S-D | sandbox |
| AC-34, AC-35, AC-36 | S-H (+ S-A) | sandbox |
| AC-37 | S-C, S-R | sandbox |
| AC-38 | S-A | sandbox |
| AC-39 | §9 | live, read-only |
| AC-40, AC-41 | S-K | sandbox |
| AC-42 | S-L | sandbox |
| AC-43 | S-R(3) | sandbox |
| AC-44 | S-I | sandbox |
| AC-45 | §9 | live, read-only |
| AC-46 | S-J0 | sandbox |
| AC-47 to AC-51 | S-J1, S-J2-6, S-J7, S-J8, S-J9 | sandbox |
| AC-52 to AC-58 | S-P | sandbox, **only if built**; otherwise SKIPPED (not built) |
| AC-59 to AC-63 | – | **SKIPPED** (Could) unless the developer reports them built |
| AC-64, AC-65, AC-66 | – | **SKIPPED** (DEFERRED). AC-65 is covered only by AC-20. |
| AC-67, AC-68, AC-69 | §8.2-8.4 | **APPROVAL**. SKIPPED (approval pending) until the user approves each step. |
| AC-70, AC-71, AC-72, AC-73 | §8.5 | **APPROVAL** (user action) |
| AC-74 | §8.5 | **APPROVAL**; recommended SKIP (OQ-10) |
| AC-75 | §8.5 | **DEFERRED + APPROVAL**; SKIPPED |

**Order of work:**
1. Snapshot (§4).
2. SEC-QA-1 fixture review.
3. Sandbox suite (S-A … S-R, S-P).
4. Live read-only (§9).
5. Report.
6. Approval-gated items (§8), only if and when the user approves.
7. Clean up the sandbox (stop the daemon via its pid file, `rm $SB/engine.run`) and leave the live daemon running.
