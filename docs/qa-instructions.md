# panelgraph NETWORK graph v2: QA instructions

Version 1.3, 2026-11-20. v1.3: AC-10 tick-matched method (D-43), AC-52 window t0+44-50 s (D-44), user decisions D-45 (all RECOMMENDED options). Author: BA. **v1.2 adds §11 "WLAN monitor mode testing (consulted with the security specialist)"**: the consultant's full sandbox procedure (gate on the sandbox hooks, fixture checklist, new scenarios S-T and S-U, pass checks, pitfalls) and the live run sheet marked REQUIRES USER APPROVAL. It also adds the `SMOKE` result status and AC-77 to AC-79. v1.1 applied the specialists' sign-off corrections (`requirements.md` §9): harness packet base and signal fixture, monitor vifs with operstate `unknown`, S-B type-802 variant, S-C pps, S-H keeps wlan0, deterministic S-J2, hostile SSID in both iw fixtures, new S-S (AC-76), live L1/L2 tuned with `set freq` at full width. The monitor-mode guidance in §7-§8 comes from the **cyber security specialist**, who is QA's consultant (task card SEC-QA in `requirements.md` §8).

What to verify: `acceptance-criteria.md`, AC-01 to AC-79. The design reference is `requirements.md`. Developer details are in `dev-instructions.md`.

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
AC-id | PASS / FAIL / BLOCKED / SKIPPED / INCONCLUSIVE | evidence path(s) | measured values vs expected | note
```

- **SMOKE:** a result from a sed-patched daemon copy, used while the developer's build lacks the `PANELGRAPH_*` hooks (§11.0, DEF-05). It is informative only and never counts as PASS.
- **INCONCLUSIVE:** used only for AC-67/AC-68 sub-checks when the live capture could not be made discriminating (the monitor could not be tuned to the full channel width). Never report such a sub-check as PASS.

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
PKT_BASE = 5_000_000                             # packet counters start large, like bytes (OQ-13)
def make_iface(name, typ=1, dev=True, phy=None, oper="up", flags=0x1003, base=5 * GiB, carrier=1):
    # Monitor vifs: always pass oper="unknown" (real mac80211 monitor vifs report it; SEC-QA-1).
    stage = f"{SB}/stage/{name}"
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(f"{stage}/statistics")
    _IFX[0] += 1
    for k, v in (("type", typ), ("flags", hex(flags)), ("operstate", oper),
                 ("carrier_changes", carrier), ("ifindex", _IFX[0])):
        wr(f"{stage}/{k}", v)
    for k in ("rx_bytes", "tx_bytes"):
        wr(f"{stage}/statistics/{k}", base)
    for k in ("rx_packets", "tx_packets"):
        wr(f"{stage}/statistics/{k}", PKT_BASE)  # catches a 0 packet baseline on the first monitor tick (AC-24)
    for k in ("rx_errors", "tx_errors", "rx_dropped", "tx_dropped"):
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
def iw_link(ifname, bssid="02:00:00:00:00:aa", ssid="SBX-NET", freq=5180, sig=-45, rx=650.0, tx=585.0):
    # sig -45 differs on purpose from /proc/net/wireless (-41): AC-38 must show -41
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
def frames(lines):                                # MONITOR line fr/s figure, e.g. "1.0k fr/s" -> 1000.0
    for l in lines:
        if "MONITOR" in l:
            m = re.search(r"([\d.]+)(k?) fr/s", l)
            if m: return float(m.group(1)) * (1000 if m.group(2) else 1)
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
- **Counters:** every byte counter starts at 5 GiB and every packet counter (`rx_packets`, `tx_packets`) at 5,000,000 (`PKT_BASE`), which catches any "new interface counted from 0" or "packet baseline stored as 0" bug.
- **route:** default `wlan1 via 10.99.0.1 metric 603`.
- **arp:** `10.99.0.1 → 02:00:00:00:00:01 (0x2) on wlan1`.
- **wireless:** `wlan1 -41` (written with a leading space, ` wlan1:`, as the kernel does).
- **ip_forward:** 1.
- **addrs:** `wlan1 10.99.0.25`.
- **iw fixtures:** wlan1 `SBX-NET` ch36 5180/80, link BSSID `02:00:00:00:00:aa`, link signal **-45 dBm** (differs from wireless -41 on purpose), rx 650 / tx 585 Mbit/s; phy0 has a P2P-device block before wlan0.

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
| **S-B airmon-style** | From the S-A steady state: `del_iface("wlan0"); make_iface("wlan0mon", typ=803, phy="phy0", oper="unknown"); set_rates({"wlan0mon": (512*KiB, 0, 1000)}); iw_set(WLAN1, MON("wlan0mon"))`. `record(3)`, then wait 34 s; in every poll from t0 to t0 + 35 s, `frames(lines)` ≤ 1100. Variant: rx 0 for the solid baseline. **Variant 802:** the same with `typ=802` (prism) → same strip and MONITOR line (AC-25). | AC-24, AC-25, AC-27, AC-30 (solid), AC-31, AC-15 (2-strip variant with wlan1 tx 300 B/s) |
| **S-C in-place switch** | From S-A steady: `set_rates({"wlan1": (2*MiB, 0, 1000)})` and in the **same** step `set_attr("wlan1","type",803); set_attr("wlan1","operstate","unknown"); set_routes(); iw_set(MON("wlan1","phy1"), WLAN0)`. The byte counters continue from about 5 GiB and `rx_packets` from 5,000,000 (static before t0, 1000 pps after). `record(36)` with 50 ms polls; `frames(lines)` ≤ 1100 in every poll. | AC-23, AC-24, AC-37 (monitor-only at 34 s) |
| **S-G switch back** | Continues S-C: `set_attr("wlan1","type",1); set_attr("wlan1","operstate","up"); set_routes(route_line("wlan1")); set_rates({"wlan1": (512*KiB,128*KiB)}); iw_set(WLAN1, WLAN0)`. `record(36, png=True)`. | AC-32 |
| **S-D vif alongside** | S-A steady + `make_iface("wlan1mon", typ=803, phy="phy1", oper="unknown"); set_rates({"wlan1mon": (512*KiB,0,1000)}); iw_set(WLAN1, MON("wlan1mon","phy1"), WLAN0)`, wait 34 s. **Variant for AC-28:** wlan1 (128 KiB, 32 KiB), wlan1mon (8 MiB, 0). | AC-33, AC-28 |
| **S-E monitor down** | S-B steady, then `set_attr("wlan0mon","flags",hex(0x1002)); set_attr("wlan0mon","operstate","down"); set_rates({"wlan0mon": (0,0)})`, wait 34 s. | AC-30 (dotted) |
| **S-F injected** | S-B with `set_rates({"wlan0mon": (512*KiB, 256*KiB, 1000)})`, wait 34 s; keep it 70 s to verify that S1 stays silent. | AC-29, AC-31 |
| **S-H strips** | `base()`; `set_attr("eth0","operstate","up")`; `make_iface("usb0")`; rates eth0 (256K,0), usb0 (128K,0), wlan1 (512K,128K); add wlan0mon **beside wlan0, without deleting wlan0**: `make_iface("wlan0mon", typ=803, phy="phy0", oper="unknown"); set_rates({"wlan0mon": (512*KiB, 0, 1000)}); iw_set(WLAN1, WLAN0, MON("wlan0mon"))` → **H1** (expect `Idle: wlan0 not connected`), wait 34 s. `del_iface("wlan0mon")` → wait 34 s → **H2**. `set_attr("wlan0","operstate","up")`, wlan0 (64K,0) → wait 34 s → **H3**. Hysteresis from H2: eth0 rate 0 + operstate down at t0, `record(36, png=True)`. Then eth0 operstate up, rate 0 → strip back within 6.5 s. | AC-34, AC-35, AC-36 |
| **S-I promisc** | S-A steady; `set_attr("wlan0","flags",hex(0x1103))` → line within 6.5 s; back to `0x1003` → gone within 6.5 s. Add `make_iface("wlan0mon", typ=803, phy="phy0", oper="unknown", flags=0x1103)` → no PROMISC line for it. vnet9 (0x1303) is never named. Throughout, the PNG has no FF00FF/FFA0FF/FF2020 (except from the monitor in the last step, which is checked separately) and 1 strip until wlan0mon is added. | AC-44 |
| **S-J0 gateway edge** | `set_routes(route_line("wlan1"), route_line("eth0", metric=100))` with eth0 up → `via eth0`; `set_arp(arp_line("10.99.0.1","02:00:00:00:00:01","wlan1","0x0"))` → MAC `?`; `set_routes()` → `No default route`; tun0 (65534, no dev) + `set_routes(route_line("tun0", gw=None, flags="0001"))` → `Gateway ? ? via tun0, IP ?`. | AC-46 |
| **S-J1 alert** | S-A steady, wait ≥ 10 s more (baseline taken). `set_arp(arp_line("10.99.0.1","02:00:00:00:de:ad","wlan1"))` at t0. `record(14, png=True)`. Assert the frame (all 340 px), the inset content pixels, the `!!` line and one extra `link` call in calls.log. | AC-47 |
| **S-J2…J6 negatives** | Each from a fresh baseline, 25 s observation. J2 (deterministic reconnect; the kernel flushes neighbour entries on carrier loss): in **one** step, first `set_arp()` (removes the 10.99.0.1 row), then `set_attr("wlan1","carrier_changes",2)`; 1 s later `set_arp(arp_line("10.99.0.1","02:00:00:00:00:99","wlan1"))` (complete). Expected: no alert. J3: new MAC with flags `0x0`. J4: add the row `arp_line("10.99.0.1","02:00:00:00:00:77","eth0")` (the route stays on wlan1). J5: baseline arp `00:00:5e:00:01:01` (restart from base with it), then `00:00:5e:00:01:02`. J6: `iw_link("wlan1", bssid="02:00:00:00:00:bb")` and the MAC change in the same step. | AC-48 |
| **S-J7 hold** | Continues J1: at t1 restore MAC `02:00:00:00:00:01`. Frame present at t1+19 s, absent by t1+27 s; `!!` line still present. | AC-49 |
| **S-J8 persistence** | During an active alert (J1 again): check gw.json keys; `stop_daemon()`; `start_daemon()` → frame + `!!` within 6.5 s. Separately: in steady state, gw.json mtime is unchanged over 60 s. | AC-50 |
| **S-J9 accept** | During an active alert: `os.unlink(f"{RUN}/gw.json")` → frame cleared and `Gateway MAC accepted` within 6.5 s; gw.json `mac` = `02:00:00:00:de:ad`; no alert for 30 s. | AC-51 |
| **S-K iw** | S-A, then: (1) `iw_mode("hang")` for 60 s: max gap between net.txt content changes ≤ 0.75 s; every stub pid in calls.log is gone (`/proc/<pid>` absent) ≤ 2 s after its start; `(stale` ≤ 12 s; `Wi-Fi details unavailable (timeout)` ≤ 45 s; error.log mtime changes ≤ 1 time per distinct error over 120 s; no `<txt>!</txt>`. (2) `iw_mode("garbage")` → `(parse)`. (3) `iw_mode("ok")`, then restart with `PANELGRAPH_IW=/nonexistent/iw` → `(iw missing)`. (4) Budget: `iw_mode("ok")`, count calls over 120 s; remove wlan0/wlan1 (no phy) → 0 calls in 60 s; wlan1 operstate down → no `link` calls. In all cases the `Gateway` line stays correct. | AC-40, AC-41, AC-03 |
| **S-L hostile SSID** | `H = r'a&b<c>"d</tool><click>touch ' + QA + r'/pwned</click>\x07\x0a'`; `iw_set(dict(WLAN1, ssid=H), WLAN0); iw_link("wlan1", ssid=H)` (**both** fixtures, because the build may read the SSID from either; D-35); wait ≤ 12 s (one full `dev` + `link` alternation, ≤ 20 s, to be sure both were parsed). Assert the AC-42 tag counts (in the raw net.txt), that Pango parse succeeds, the literal text, and length ≤ 32. | AC-42 |
| **S-M hot-plug** | S-A steady; `make_iface("usb0")` (5 GiB base) + rates (128K,0) → `record(3)`; then `del_iface("usb0")` → `record(3)`. | AC-26 |
| **S-N lifecycle** | (1) AC-06: a second `start_daemon()` while running → only one pid. (2) AC-07: `os.unlink(f"{SB}/keepalive")` → daemon gone at 30-32 s; pid file gone; lock kept. (3) AC-08: `os.mkdir(f"{RUN}/net.png.tmp")` → "!" ≤ 1 s, error.log has `net:`; `os.rmdir` → recovers ≤ 6.5 s; mem.txt has no "!". | AC-06, AC-07, AC-08 |
| **S-O reconnect + suspend** | (1) S-A steady; at t0: `set_attr("wlan1","operstate","down")`; t0+3 s: `reset_counters("wlan1"); set_attr("wlan1","carrier_changes",3); set_attr("wlan1","operstate","up"); set_arp(arp_line("10.99.0.1","02:00:00:00:00:99","wlan1")); iw_set(dict(WLAN1, ssid="SBX-OTHER"), WLAN0); iw_link("wlan1", ssid="SBX-OTHER", bssid="02:00:00:00:00:cc")`; `record(30, png=True)`. (2) `os.kill(daemon_pid(), signal.SIGSTOP)`, wait 10 s, `SIGCONT`, `record(5)`. | AC-17, AC-18 |
| **S-R replacements + worst case** | (1) All NICs down, rates 0, 34 s → no opaque pixel + `No managed interface up` + Idle line with three NICs. (2) Remove every `device`/`phy` interface → `No network interfaces`. (3) Worst case (AC-43): H1 (wlan0 kept, wlan0mon with `oper="unknown"`) + J1 alert + wlan0 flags 0x1103 + eth0 up + tun0 → ≤ 10 lines, order, glyph spans; expect `PROMISC wlan0` and `Idle: wlan0 not connected`. | AC-37, AC-43 |
| **S-S two monitor vifs** | `base()`; before start: `set_attr("eth0","operstate","up"); set_attr("wlan1","operstate","down"); set_rates({"eth0": (256*KiB, 64*KiB), "wlan1": (0, 0)}); set_routes(route_line("eth0")); set_arp(arp_line("10.99.0.1","02:00:00:00:00:01","eth0")); wr(f"{SB}/addrs", "eth0 10.99.0.25")`; start; wait 34 s; record `Total` (256/64). **SS1** at t0, in one step: `del_iface("wlan0"); del_iface("wlan1"); make_iface("wlan0mon", typ=803, phy="phy0", oper="unknown"); make_iface("wlan1mon", typ=803, phy="phy1", oper="unknown", flags=0x1002); set_rates({"wlan1": None, "wlan0mon": (256*KiB, 0, 500), "wlan1mon": (256*KiB, 0, 500)}); iw_set(MON("wlan0mon","phy0"), dict(MON("wlan1mon","phy1"), chan=6, freq=2437))`; `record(36, png=True)`. **SS2**: both monitor rates (0, 0), wait 34 s. **SS3**: `set_attr("wlan0mon","flags",hex(0x1002))`, wait 34 s. | AC-76, AC-31 |
| **S-P Shoulds** (only those built) | AC-52: wlan1 at the default (512K, 128K) for ≥ 30 s, then (100K, 300K) for 70 s; expect the first `Sustained upload` at t0 + 44-50 s; then wlan1 tx 0 and wlan0mon tx 300K. AC-53: `set_routes(route_line("eth0"))` with eth0 up. AC-54: `make_iface("tun0", typ=65534, dev=False, oper="unknown", flags=0x1091)` + `wg0` with 1 MiB/s. AC-55: eth0 + wlan1 up, then `ip_forward` 0. AC-56: `iw_set(WLAN1, dict(WLAN0, type="AP"))` with wlan0 up; then `mesh point`, `IBSS`. AC-57: `make_iface("wwan0", typ=65534)` with rx 256K. AC-58: `set_attr("wlan1","ifindex",99); reset_counters("wlan1")`. | AC-52 to AC-58 |

---

## 7. Security consultant guidance: how to check WLAN monitor mode (summary)

From the cyber security specialist; agreed with Network and the BA. **The full, step-by-step consultation is §11.** That includes the sandbox-hook gate, the fixture checklist, scenarios S-T and S-U, the pass-check table and the live run sheet that REQUIRES USER APPROVAL.

1. **Detection:** an interface is in monitor mode when `type ∈ {801,802,803}` **and** it has a `phy80211` or `device` link. airmon-ng creates a new `wlanXmon` (counters from 0). `iw dev wlanX set type monitor` keeps the name and the counters (the latter still to be confirmed live in AC-68).
2. **What must be true** in every monitor scenario:
   - **Captured bytes are never in `Total`**, not even on the switch tick: AC-23, AC-31.
   - The monitor strip uses #FF00FF (captured) / #FFA0FF (injected) with its own scale.
   - The baseline is solid when up and dotted when down.
   - The MONITOR line names the vif, phy, channel and state; with several vifs, one group per vif joined by ` + ` (AC-76).
   - The monitor state comes from IFF_UP in `flags`, never from `operstate` (real monitor vifs report `unknown`). Sandbox monitor vifs are therefore always created with `oper="unknown"`.
3. **Promisc is not monitor.** PROMISC is a tooltip line only. Bridge ports (vnet*, 0x1303) are never reported.
4. **Unattended testing is sandbox only.** QA never runs airmon-ng, iw set, ip link or nmcli.
5. **A live capture test only proves "not in Total" if the capture is large.** HomeNet runs VHT80 (ch44, 80 MHz, center1 5210 MHz). A monitor tuned with `set channel 44` listens at 20 MHz and cannot decode the 80 MHz data frames of our own download; it captures only beacons and management/control frames (a few KiB/s), which hide inside the ±10 % tolerance. Always tune with `set freq <ctrl> <width> <center1>` read from `iw dev wlan1 info`, and require captured ≥ 50 % of the wlan1 rx rate; otherwise the leak check is INCONCLUSIVE.
6. **Live checks need user approval**, step by step (§8). wlan1 carries the uplink and must never be touched. **Never `airmon-ng check kill`.** No deauth or injection (OQ-12).
7. The security consultant reviews the sandbox fixture before the first run (SEC-QA-1) and adjudicates failing security ACs (SEC-QA-2).

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
# Tune to wlan1's FULL channel width. Read the values at test time (today: 44 5220 80 5210):
iw dev wlan1 info | sed -n 's/.*channel \([0-9]*\) (\([0-9]*\) MHz), width: \([0-9]*\) MHz, center1: \([0-9]*\) MHz.*/CH=\1 F=\2 W=\3 C1=\4/p'
sudo iw dev wlan0mon set freq 5220 80 5210         # = set freq $F $W $C1 with the values printed above
iw dev wlan0mon info | grep channel                # must show width: 80 MHz, center1: 5210 MHz
nmcli -t -f DEVICE,STATE dev | grep wlan0mon       # must be "unmanaged"; else: sudo nmcli device set wlan0mon managed no
```
- If `set freq … 80 …` is rejected by the driver: run `sudo iw dev wlan0mon set channel <CH>`, record the error, and report the AC-67 capture and not-in-Total checks as **INCONCLUSIVE** (never PASS).
Observation (QA):
- Within 12 s, net.txt has `MONITOR wlan0mon (phy0, ch<CH> <F> MHz, up)` (today `ch44 5220 MHz`).
- Run a 25 s download: `curl -s -o /dev/null --limit-rate 500k --max-time 25 <deb.debian.org file>`.
- During the download:
  - take screenshots every 1 s (§3);
  - the upper strip (rows 0-14) shows FF4F00 and the lower strip (rows 16-31) shows FF00FF;
  - using the AC-10 method (10 windows of 2 s from t = 5 s, mean of 250 ms tooltip reads per window, against Δ wlan1 `rx_bytes`/Δt): mean `captured` ≥ 50 % of the wlan1 sysfs rx rate in ≥ 8 windows (proves the capture is substantial), and mean `Total ↓` within ±10 % of the wlan1 sysfs rx rate in ≥ 8 windows (proves it is **not** included). Do not compare single 50 ms polls with an instantaneous rate;
  - the HomeNet line is unchanged; netload 23 rises in orange;
  - also run the consultant's checks in §11.7 step 6: the captured bar and the baseline marker are FF00FF on screen, there is no FFA0FF, and Δ`wlan0mon/statistics/rx_bytes`/Δt matches `captured` ±10 % in ≥ 8 of 10 windows.
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
sudo iw dev wlan0 set freq 5220 80 5210             # values from `iw dev wlan1 info` at test time, as in L1
cat /sys/class/net/wlan0/statistics/rx_bytes        # QA records AFTER -> answers "do counters survive?"
```
- Same 80 MHz fallback rule as L1: if rejected, `set channel <CH>`, and the capture/not-in-Total checks are INCONCLUSIVE.

Observation:
- `MONITOR wlan0 (phy0` within 0.6 s.
- During a 25 s `--limit-rate 500k` download, with the AC-10 2 s window method: captured ≥ 50 % of the wlan1 sysfs rx rate and `Total ↓` within ±10 % of the wlan1 sysfs rx rate, each in ≥ 8 of 10 windows.
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
| AC-10 | Python: start curl in the background (400k, 25 s). Every 50 ms log the summed rx/tx_bytes of eth0, wlan0, wlan1 with `time.time()`, and `net.txt` with its `st_mtime` (= daemon tick). For each distinct tick pair `Total ↓`/`↑` with the sysfs rate over [tick − 1 s, tick] (linear interpolation). From t = 5 s, 10 windows of 2 s by tick time: mean tooltip vs mean reference, ↓ and ↑; plus the 20 s mean check. Collapse whitespace when parsing (v2 has 3 spaces before `Scale`). Reference script: `$SCRATCH/wf3/qa3/ac10v13.py`. |
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
| AC-31 | S-B to S-H, S-S | sandbox |
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
| AC-76 | S-S | sandbox |
| AC-77 | S-T (§11.2) | sandbox |
| AC-78 | every monitor scenario PNG series (S-B, S-B802, S-C, S-D, S-F, S-S, S-T, S-U) | sandbox |
| AC-79 | S-U (§11.2) | sandbox |
| AC-52 to AC-58 | S-P | sandbox, **only if built**; otherwise SKIPPED (not built) |
| AC-59 to AC-63 | – | **SKIPPED** (Could) unless the developer reports them built |
| AC-64, AC-65, AC-66 | – | **SKIPPED** (DEFERRED). AC-65 is covered only by AC-20. |
| AC-67, AC-68, AC-69 | §8.2-8.4 | **APPROVAL**. SKIPPED (approval pending) until the user approves each step. |
| AC-70, AC-71, AC-72, AC-73 | §8.5 | **APPROVAL** (user action) |
| AC-74 | §8.5 | **APPROVAL**; recommended SKIP (OQ-10) |
| AC-75 | §8.5 | **DEFERRED + APPROVAL**; SKIPPED |

**Order of work:**
1. Snapshot (§4).
2. Run the sandbox-hook gate (§11.0). If it fails, the sandbox monitor ACs are BLOCKED, and smoke runs are reported as `SMOKE`.
3. SEC-QA-1 fixture review (checklist §11.1).
4. Sandbox suite (S-A … S-U, S-P).
5. Live read-only (§9).
6. Report.
7. Approval-gated items (§8, run sheet §11.7), only if and when the user approves.
8. Clean up the sandbox (stop the daemon via its pid file, `rm $SB/engine.run`) and leave the live daemon running.

---

## 11. WLAN monitor mode testing (consulted with the security specialist)

**Source:** the cyber security specialist's QA consultation, delivered 2026-11-20 and documented by the BA in v1.2. It covers task card SEC-QA in `requirements.md` §8 and user decisions UD-a and UD-b. It agrees with `requirements.md` §4.0, §4.1, §4.2 and D-04 to D-42, and with §5 to §8 of this file. Where §11 is more specific, §11 wins. The consultant changed no interface state and no product files.

**What is being tested (user decision a):**
- Monitor-mode traffic is drawn in a **different colour**: captured rx #FF00FF (magenta) and injected tx #FFA0FF (light magenta).
- It sits in its **own bottom strip**, with its own `Mon scale` (64 KiB/s floor).
- The strip has **magenta current-value bars** and a **magenta baseline marker** on its bottom row: solid while any monitor vif is up, dotted while all are down.
- The tooltip has a **`MONITOR` line**.
- Monitor traffic is **never** added to the managed `Total`.

There are two procedures:
- **§11.1 to §11.6, the sandbox:** QA runs it unattended.
- **§11.7, the live procedure:** it **REQUIRES USER APPROVAL** for each step.

### 11.0 Gate: the sandbox hooks must exist (BLOCKER for Dev, DEF-05)

As of 2026-11-20, the deployed `~/.local/bin/panelgraph-daemon` (392 lines, pid <pid>) uses **none** of the `PANELGRAPH_*` variables:
- It reads the hard-coded `/sys/class/net`.
- It keeps only type-1 interfaces, so every monitor interface is dropped silently: no strip and no tooltip line (DEF-02).

Before any sandbox run, QA runs this gate on the build under test:

```sh
DAEMON=${DAEMON_SRC:-$HOME/.local/bin/panelgraph-daemon}
for v in PANELGRAPH_SYSNET PANELGRAPH_PROCNET PANELGRAPH_IPFORWARD PANELGRAPH_IW PANELGRAPH_ADDRS PANELGRAPH_ALERT_HOLD; do
  grep -q "$v" "$DAEMON" && echo "ok   $v" || echo "MISSING $v"
done
# Hard-coded paths may appear ONLY as the default value of a constant (comments are ignored):
grep -n '/sys/class/net\|/proc/net\|/sys/class/ieee80211\|/proc/sys/net' "$DAEMON" | grep -v '^[0-9]*:[[:space:]]*#'
```

**Pass criteria:**
- All six variables are present. (`XDG_RUNTIME_DIR` is already supported.)
- Outside comments, every hard-coded path appears only in an `os.environ.get(…, "<default>")` line.
- Every per-interface path, including the phy name, is built from `SYSNET`:
  - `{SYSNET}/<if>/phy80211/name`, which follows the relative link into `$SB/sys/class/ieee80211/phyN`;
  - or `dirname(SYSNET)/ieee80211/<phy>/name`.
  - It must never be a literal `/sys/class/ieee80211`.

**If the gate fails:**
- Every sandbox monitor AC is **BLOCKED (sandbox hooks missing, DEF-05)**: AC-22 to AC-33, AC-37, AC-76 to AC-79, and the sandbox parts of AC-03 and AC-40 to AC-51.
- QA may run a **sed-patched copy** as a **smoke test** only, and must report those results as `SMOKE`, never `PASS`. The acceptance run must use the developer's build with real hooks.
- `PANELGRAPH_ADDRS` must **always** be set in the sandbox. Without it, the SIOCGIFADDR ioctl reads the real `wlan1` address and the tooltip shows the live IP (AC-22 fails).

### 11.1 Fake interface directory (checklist for SEC-QA-1)

Use the §5.2 harness (`$QA/sbx.py`) under `$QA/sb`. Every fake interface `make_iface()` creates must have the following:

| Item | Content |
|---|---|
| `type` | 1 for managed. 803 for monitor (radiotap). Also run one 802 (prism) variant. |
| `flags` | hex, e.g. `0x1003` |
| `operstate` | `up` / `down` / `unknown` |
| `carrier_changes`, `ifindex` | integers |
| `statistics/rx_bytes`, `tx_bytes`, `rx_packets`, `tx_packets` | byte counters start at **5 GiB**, packet counters at **5,000,000** |
| `device` | **relative** symlink to `../../../devices/fake/<if>`, whose target exists |
| `phy80211` | relative symlink to `../../ieee80211/phyN`, where `$SB/sys/class/ieee80211/phyN/name` contains `phyN` (Wi-Fi only) |

**Rules for monitor vifs:**
- `type` 803; one variant uses 802.
- `operstate` is **`unknown`**, as real mac80211 monitor vifs report it. Always call `make_iface(..., oper="unknown")`.
- Up or down is set **only through `flags`**: `0x1003` is admin up, `0x1002` is admin down. A build that takes the state from `operstate` fails AC-30 and AC-76.
- Counters start at 5 GiB and 5,000,000 packets. A build that counts a new vif from 0, or stores 0 as the packet baseline, then shows a huge first sample (AC-24).
- **Create and remove atomically:** stage the directory, then `rename` it in (`make_iface()`), and remove it by renaming it out (`del_iface()`). Never build or delete files directly inside `sys/class/net`.

### 11.2 Fixtures to cover

| Case | Scenario | Steps (summary; exact code in §6 or below) | ACs |
|---|---|---|---|
| airmon-style rename | **S-B** | delete wlan0, create wlan0mon (803, phy0) | AC-24, AC-25, AC-27, AC-30 solid, AC-31, AC-78 |
| airmon-style, prism | **S-B variant 802** | same with `typ=802` | AC-25, AC-78 |
| managed + vif on one phy | **S-D** | wlan1 managed + wlan1mon (803, phy1) | AC-28, AC-33, AC-78 |
| in-place switch | **S-C** | wlan1 `type` 1→803 and operstate `unknown`, route cleared, counters keep running | AC-23, AC-24, AC-37, AC-78 |
| switch back | **S-G** | wlan1 `type` 803→1, route restored | AC-32 |
| vif down | **S-E** | wlan0mon flags 0x1002, rx 0 | AC-30 dotted |
| injection | **S-F** | wlan0mon tx 256 KiB/s | AC-29, AC-31, AC-78 |
| two vifs on two phys | **S-S** | wlan0mon (phy0, up) + wlan1mon (phy1, down) | AC-76, AC-31 |
| **vif removed while captured history is on screen** | **S-T** (new, below) | S-D steady, then delete wlan1mon | AC-77 |
| **name-independent detection** | **S-U** (new, below) | `mon0` (803, phy5) + decoy `wlan2mon` (type 1, device link) | AC-79 |
| promisc is not monitor | **S-I** | wlan0 0x1103; vnet9 0x1303 | AC-44 |
| hostile SSID markup | **S-L** | SSID with markup in both iw fixtures | AC-42 |

**S-T, vif removed with captured history on screen** (AC-77):
```python
# fresh base(); start engine + daemon; wait 34 s (S-A steady)
make_iface("wlan1mon", typ=803, phy="phy1", oper="unknown")
set_rates({"wlan1mon": (512*KiB, 0, 1000)}); iw_set(WLAN1, MON("wlan1mon", "phy1"), WLAN0)
time.sleep(34)                                   # S-D steady: 2 strips, magenta history full
t0 = time.monotonic()
del_iface("wlan1mon"); set_rates({"wlan1mon": None}); iw_set(WLAN1, WLAN0)
rec = record(36, png=True)                       # 50 ms polls with PNG
```

**S-U, name-independent detection and phy from the fake tree** (AC-79):
```python
# fresh base(); start engine + daemon; wait 34 s
make_iface("mon0", typ=803, phy="phy5", oper="unknown")     # no real phy5 exists on this laptop
make_iface("wlan2mon")                                      # decoy: type 1 + device link, operstate up, no phy
set_rates({"mon0": (256*KiB, 0, 500), "wlan2mon": (128*KiB, 0)})
iw_set(WLAN1, WLAN0, MON("mon0", "phy5"))
time.sleep(34)
```

### 11.3 Driving traffic

- The engine (`sbx.engine()`) adds `rate × Δt` to `rx_bytes` for captured traffic and to `tx_bytes` for injected traffic. It adds packets to `rx_packets` at the fixture pps, the third element of the `set_rates` tuple.
- Use 1000 pps for S-B, S-C, S-D, S-F, S-T and 500 pps per vif for S-S and S-U.
- Change rates and fixture files in **one** step (consecutive calls without a sleep in between), so the switch tick is exercised.

### 11.4 Pass checks

The pixel helper (`pixel()`, §5.6) must **never** return partial alpha (`Aaa:rrggbb`). Any partial-alpha pixel is a FAIL (AC-78).

| Check | Expected | AC |
|---|---|---|
| Colours | captured columns and the **left** bar (x 0-3) = **FF00FF**; injected columns and the **right** bar (x 6-9) = **FFA0FF** | AC-27, AC-29 |
| Layout | monitor strip at the **bottom**, rows 16-31 with 2 strips (rows 22-31 with 3); row 15 fully T (separator) with 2 strips; own `Mon scale` with a 64 KiB/s floor | AC-27, AC-28, AC-34 |
| S-B point checks | Pixel(139,20) = FF00FF, Pixel(1,20) = FF00FF, Pixel(7,20) = **T** (the injected bar is 0) | AC-27 |
| S-F point checks | Pixel(139,28) = FFA0FF, Pixel(7,28) = FFA0FF | AC-29 |
| Baseline marker | row 31, x 12-139: **all 128** pixels FF00FF while any vif is up; **exactly 64**, alternating, while all vifs are down. Bar positions (1,31) and (7,31) are T. | AC-30, AC-76 |
| Never summed | in **every** 50 ms poll, `Total` ≤ **1.05 ×** the managed fixture rate, including on the switch tick | AC-23, AC-31, AC-76, AC-79 |
| No zero baseline | `captured` < **1.1 ×** the fixture value; `fr/s` ≤ **1.1k** at 1000 pps | AC-24 |
| Tooltip line | `■ MONITOR <vif> (<phy>, ch<N> <F> MHz, up\|down)  ■ captured …  ■ injected …  … fr/s · not in total · Mon scale …`; with several vifs the groups are joined by ` + ` | AC-27, AC-76 |
| Vif disappears | within 0.6 s the line becomes `monitor ended HH:MM:SS`; from t0 + 1.25 s, column 139 has no FF00FF/FFA0FF; the strip is gone 32-34 s after t0 with no flapping; no "!" and no new error.log entry | AC-32, AC-77 |
| Palette | every pixel of every recorded PNG ∈ {T, FF4F00, FFE500, FF00FF, FFA0FF} (+ FF2020 only on frame pixels during an M2 alert); FF00FF/FFA0FF appear **only** while a monitor strip is active | AC-78 |

Helper code for AC-78 and the "never summed" check (append to your scenario script):
```python
ALLOWED = {"T", "FF4F00", "FFE500", "FF00FF", "FFA0FF"}
def palette_violations(s, alert=False):
    bad = []
    for y in range(32):
        for x in range(140):
            p = pixel(s, x, y)
            frame = y in (0, 31) or x in (0, 139)
            if p in ALLOWED or (alert and frame and p == "FF2020"):
                continue
            bad.append((x, y, p))                 # includes any "Aaa:rrggbb" partial-alpha pixel
    return bad
def never_summed(rec, managed_rx, managed_tx=None, tol=1.05):
    over = [(t, l) for t, l, _ in rec if (tt := total(l)) and
            (tt[0] > tol * managed_rx or (managed_tx is not None and tt[1] > tol * managed_tx))]
    return over                                   # must be empty
```

### 11.5 Consultant's pitfalls: what a buggy build looks like, and which AC catches it

| Pitfall | Symptom | Caught by |
|---|---|---|
| Captured traffic inflating `Total` | a build that classifies interfaces only every 5 s, or keeps a counter baseline across a type change, leaks for up to 5 s after an in-place switch | AC-23, AC-31 |
| Monitor detected **by name** | `mon0` not shown as monitor, or a type-1 NIC named `wlan2mon` drawn magenta or left out of `Total`. Detection must use `type` plus `phy80211` or `device`. Test `mon0` and in-place `wlan0`/`wlan1`. | AC-79, AC-23, AC-68 |
| Up/down taken from `operstate` | monitor vifs always report `unknown`, so the baseline is never dotted, or never solid | AC-30, AC-76 |
| A vif hidden from the tooltip, or two vifs merged into one name | the MONITOR line lists one vif | AC-76 |
| Promisc treated as monitor | magenta pixels for wlan0 at 0x1103. Promisc gives a tooltip line only. Bridge ports (vnet*, 0x1303) are never reported. | AC-44, AC-45 |
| Zero packet or byte baseline | first sample shows ~5000k fr/s or ~5 GiB/s | AC-24 |
| Phy name read from the real `/sys/class/ieee80211` | MONITOR line names the wrong phy in the sandbox (`phy5` exists only in the fake tree) | AC-79, AC-22 |
| Hostile SSID markup | broken tooltip, or an injected `<click>` | AC-42 |
| Partial-alpha pixels (anti-aliasing on) | `Aaa:rrggbb` from `pixel()` | AC-78 |
| A 20 MHz live monitor on an 80 MHz BSS | captures too little to prove the leak check, so the live check cannot fail | AC-67/AC-68 INCONCLUSIVE rule (D-37) |

### 11.6 Reporting the sandbox run

- Run S-B, S-B802, S-C, S-G, S-D, S-E, S-F, S-S, S-T and S-U, each from a fresh `base()` unless it says "continues".
- Store PNG series and tooltip logs under `$QA/evidence/AC-xx/`.
- The consultant (SEC-QA-2) gives a **product defect vs fixture defect** verdict for each failing monitor AC, and QA records it in the report.
- Results from a sed-patched copy are reported as `SMOKE` (§11.0).

### 11.7 Live procedure: REQUIRES USER APPROVAL

> **REQUIRES USER APPROVAL. Each step (L1, L2, L3) needs its own explicit approval from the user. The user runs every `sudo` line. QA only observes, takes screenshots and reads sysfs. Without approval, AC-67, AC-68 and AC-69 are reported as SKIPPED (approval pending).**

**Hard limits:**
- Use **only wlan0 (phy0)**. Never touch **wlan1 or phy1**: wlan1 is the uplink (HomeNet) and the card the user is connected through.
- Never run `airmon-ng check kill`. Never change global NetworkManager state.
- **No injection** unless the user decides OQ-12. Never `aireplay-ng -0` (deauth). Never inject on phy1. Injection would also expose wlan0's permanent MAC `aa:bb:cc:dd:ee:03`.
- Traffic is generated **passively**: only our own `curl --limit-rate 500k --max-time 25` download from deb.debian.org.

**Run sheet.** The exact commands are in §8 and are repeated here so this section can be followed on its own:

1. **Approval:** record the user's approval text for this exact step (L1, L2 or L3), with the time.
2. **Consultant go/no-go** (SEC-QA-3): pre-checks done, rollback commands ready, `set freq` values read.
3. **Pre-checks** (§8.0): record `G_BSSID`, `G_CC`, `/sys/class/net/wlan0/flags` (today `0x1103` because netdiscover is running), `nmcli -t -f DEVICE,TYPE,STATE dev`, `iw dev`, `ip -br link` and wlan0 `rx_bytes`.
4. **Start the guard** (§8.0 `guard()`), run it **every 5 s** for the whole step, and log the output. **Any failure means an immediate rollback** (SEC-QA-4).
5. **L1, add a vif** (least disruptive; AC-67). The user runs:
   ```sh
   sudo nmcli device set wlan0 managed no
   sudo ip link set wlan0 down
   sudo iw phy phy0 interface add wlan0mon type monitor
   sudo ip link set wlan0mon up
   iw dev wlan1 info      # read channel, freq, width, center1 (today: 44, 5220, 80, 5210)
   sudo iw dev wlan0mon set freq 5220 80 5210       # set freq <F> <W> <C1> with today's values
   iw dev wlan0mon info | grep channel              # must show width: 80 MHz, center1: 5210 MHz
   ```
   If the driver rejects 80 MHz, the user runs `sudo iw dev wlan0mon set channel <CH>`. QA records the error, and the capture and not-in-Total checks become **INCONCLUSIVE**, never PASS.
6. **What QA must see during L1:**
   - Within **12 s**: orange (FF4F00) in the top strip, magenta (FF00FF) in the bottom strip, and the line `MONITOR wlan0mon (phy0, ch44 5220 MHz, up)`.
   - **Bar and marker colours on screen.** In the 142x34 crop of plugin 26, crop (x, y) = net.png (x+1, y+1).
     - The captured bar, crop (2-5, 17-32), is FF00FF whenever `captured` > 0.
     - The baseline marker, crop row 32, x 13-140, is FF00FF in every column (solid, because the vif is up).
     - No FFA0FF appears (no injection).
   - **The 25 s download**, using the AC-10 method: 10 windows of 2 s from t = 5 s, each the mean of 250 ms tooltip reads against Δ`/sys/class/net/wlan1/statistics/rx_bytes`/Δt. Each condition must hold in **≥ 8 of 10** windows:
     - `captured` ≥ **50 %** of the wlan1 rx rate (the capture is substantial);
     - `Total ↓` within **±10 %** of the wlan1 rx rate (captured traffic is **not** in Total).
     - If either condition misses, or 80 MHz was rejected, the result is **INCONCLUSIVE**, never PASS.
   - **Vif counter vs tooltip:** in the same windows, Δ`/sys/class/net/wlan0mon/statistics/rx_bytes`/Δt is within ±10 % of the mean `captured` figure in ≥ 8 of 10 windows.
   - The HomeNet line is unchanged, netload 23 rises in orange, and the guard is OK throughout.
7. **L1 rollback.** The user runs:
   ```sh
   sudo ip link set wlan0mon down
   sudo iw dev wlan0mon del
   sudo ip link set wlan0 up
   sudo nmcli device set wlan0 managed yes
   ```
   Verify:
   - the guard is OK;
   - `iw dev` shows no wlan0mon;
   - wlan0 flags are **0x1103** while netdiscover is still running (0x1003 once it is stopped);
   - nmcli shows wlan0 `disconnected` (managed).
   - The tooltip shows `monitor ended HH:MM:SS` within 0.6 s, column 139 has no magenta from t0 + 1.25 s, and the monitor strip is gone within 34 s, with no "!".
8. **L2, in-place switch** (**separate approval**; AC-68). QA records wlan0 `rx_bytes` **before**. The user runs:
   ```sh
   sudo nmcli device set wlan0 managed no
   sudo ip link set wlan0 down
   sudo iw dev wlan0 set type monitor
   sudo ip link set wlan0 up
   sudo iw dev wlan0 set freq 5220 80 5210
   ```
   QA records `rx_bytes` **after**. This answers "do counters survive?" (they survive if after ≥ before). Checks:
   - `MONITOR wlan0 (phy0` appears within 0.6 s;
   - the download checks are the same as in L1, with the same INCONCLUSIVE rule.
   
   **Rollback:** `sudo ip link set wlan0 down; sudo iw dev wlan0 set type managed; sudo ip link set wlan0 up; sudo nmcli device set wlan0 managed yes`, then verify as in step 7.
9. **L3, `airmon-ng start wlan0`** (**separate approval**; AC-69). The user runs `sudo airmon-ng start wlan0`, **without** check kill.
   - wlan0mon must be unmanaged in nmcli; if not, stop and roll back.
   - Checks: the monitor strip and `MONITOR wlan0mon (phy0` appear within 0.6 s, wlan0 leaves the Idle line, and the guard is OK.
   
   **Rollback:** `sudo airmon-ng stop wlan0mon`. Re-enable NetworkManager management (`sudo nmcli device set wlan0 managed yes`) **only if** nmcli shows wlan0 as unmanaged. Verify: wlan0 exists, the monitor strip is gone within 34 s, the guard is OK, and NM manages wlan0.
10. **After every live step** (SEC-QA-5): the consultant confirms the rollback state, and QA appends to the report:
    - the guard log;
    - the screenshots;
    - the window table;
    - the AC-68 counter answer.

**Injection (AC-75) stays DEFERRED** (OQ-12). Even if the user approves it later, it is limited to `sudo aireplay-ng --test wlan0mon` during L1, on phy0 only. Never `-0`, and never phy1.
