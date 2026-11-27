# panelgraph NETWORK graph v2: developer instructions

Version 1.4, 2026-11-27. **v1.4 adds the code standard (§10)** that the tech lead set for F-25, generalised for later changes.

Version 1.3, 2026-11-27. **v1.3 adds the hover popup (F-25) and the private runtime dir (F-26):** the helper file and the wrapper line (§1), helper constraints (§3), new hooks (§4.1), the SSID rule with `clean()` and the iw drain to EOF (§5.5), the design summary (§5.11), tasks T10 to T14 (§6; the former T10 "self-test and deploy" is now T15), deploy of three files (§8) and the DoD (§9).

Version 1.2, 2026-11-20. Author: BA. **v1.2 adds the security specialist's QA consultation requirements:**
- §4.1, the sandbox hooks as a **blocker** (DEF-05);
- §5.10, the consolidated **monitor-mode colour task**;
- task table entries for AC-77 to AC-79.

v1.1 applied the specialists' sign-off corrections (`requirements.md` §9): §5.1 sampler (rx_packets for all candidates, link re-check), §5.2 monitor strip lifetime, §5.4 `/proc/net/wireless` parser, §5.5 SSID source, §5.6 per-tick frame evaluation, §5.7 several-vif MONITOR line.

Read `requirements.md` §4 (binding design) and `acceptance-criteria.md` (what QA will check) first. If anything here seems to conflict with those, stop and ask the BA; do not improvise.

## 1. Files

| File | Action |
|---|---|
| `~/.local/bin/panelgraph-daemon` | **Main work.** Today 392 lines. Keep it a single file (atomic deploy). An optional helper module next to it (`~/.local/bin/panelgraph_net.py`) is allowed, but it makes deploys non-atomic. Recommended: no module. |
| `~/.local/bin/panelgraph-show` | v1.3: two changes only, both builtins: the absolute-`XDG_RUNTIME_DIR` `case` (F-26) and the `net.host` line (F-25). It must stay builtins-only on the hot path, and AC-01 to AC-06 must be re-run. |
| `~/.local/bin/panelgraph-popup` | v1.3, **new**: the hover popup helper (F-25). One file, stdlib + cairo, ctypes for X. Started only by the daemon. |
| `install.sh` | Copies and `chmod +x`es all three files in `bin/`. |
| `~/.local/share/panelgraph/backup/` | Backups (§7) |
| Scratch: `$SCRATCH/wf3/dev/` | Your working copy and sandbox runs |

Do **not** touch:
- xfconf or panel settings, panel items, `~/.config/xfce4/panel/*`
- the mem graph code path (the RAM graph is deferred; keep `mem` rendering exactly as is)
- interface state

## 2. Safety rules (mandatory)

- **Never** `pkill -f panelgraph` or `pgrep -f … | kill`: the pattern matches your own shell and kills it. Stop a daemon only via its pid file, after checking `/proc/$pid/comm == panelgraph`.
- Do not move the mouse or click. Do not change xfconf or panel settings, restart xfce4-panel, or add or remove panel items.
- Do not change interface state: no airmon-ng, `iw … set`, `ip link set`, nmcli changes, macchanger or firewall changes. Test monitor mode **only** in the sandbox.
- Network traffic: only `curl` downloads to `/dev/null` from `deb.debian.org` with `--limit-rate`, each under 30 s.
- No foreground `sleep` in the shell. Wait with `timeout N tail -f /dev/null`.
- Leave the live daemon running normally at the end.

## 3. Constraints to keep (as-built behaviour that must survive)

- **fd hygiene:** `os.closerange(3, SC_OPEN_MAX)` first thing in `main()`. Every subprocess uses `stdin=DEVNULL, stderr=DEVNULL, close_fds=True, start_new_session=True`.
- **Single instance and identity:** `flock(LOCK_EX|LOCK_NB)` on `lock`; `/proc/self/comm = "panelgraph"`; `chdir(DIR)`; atomic pid file; `lost_lock()` check each tick; `ensure_pidfile()` every 5 s; on exit, pid file removed only if it still holds our pid.
- **Idle exit:** `seen` mtime unchanged for more than 30 s on `time.monotonic()`.
- **Errors:** per-graph try/except with the `"!"` marker (`show_error`), `error.log`, retry after 5 s, `FATAL_HOLD` 30 s while holding the lock. Keep the temp file name **`net.png.tmp`** (QA's AC-08 relies on it).
- **Atomic writes** of png and txt (`.tmp` + `os.replace`). Re-render the PNG only when the pixel key changes or the file is missing. Rewrite the txt only when the text changes or the file is missing.
- **Cost (NFR-4):**
  - No process spawn per tick; at most one `iw` spawn per 5 s (plus the rare M2 extra).
  - Never `nmcli`, `ip`, `ss` or `subprocess.run`.
  - Target ≤ 2.0 % of one core and RSS ≤ 40 MB (AC-21).
- **Runtime dir (F-26, D-55):** the resolver lines and `secure_dir()` are byte-identical in the daemon and the helper and marked as such; QA diffs them. No `/tmp` fallback; `main()` calls `secure_dir()` before writing anything and returns 1 when it fails.
- **Helper (F-25, D-54):**
  - comm `panelgraph-pop`, **never** `panelgraph`: panelgraph-show and QA count daemons by that comm.
  - It is started only from the daemon's slow scan (`PopupHelper.poll`), at most once per 5 s; the wrapper never starts it.
  - It spawns nothing, imports nothing beyond the stdlib and cairo, and never grabs, warps, sets focus or sends events. No key, motion or button masks; `XSelectInput` only on the item's socket window; XI2 raw button events only on root and only while pending or shown.
  - Every exit path removes `popup.pid` only if it holds the helper's pid. Exit codes 0/1/2/3 as in requirements §4.7.6.
- **The daemon stays X-free:** no ctypes, gi or X library import, ever.
- **Constants unchanged:** `INTERVAL 0.25`, `HISTORY 128`, `HEIGHT 32`, `BAR_W 4`, `BAR_GAP 2`, `NET_FLOOR 64 KiB`, `NET_SMOOTH 4`, `IDLE_EXIT 30`, `ERROR_RETRY 5`, `FATAL_HOLD 30`, `CLICK "xfce4-taskmanager"`, `human()` formatting.

## 4. Exact constants for v2

```python
import os, shutil
SYSNET     = os.environ.get("PANELGRAPH_SYSNET", "/sys/class/net")
PROCNET    = os.environ.get("PANELGRAPH_PROCNET", "/proc/net")
IPFORWARD  = os.environ.get("PANELGRAPH_IPFORWARD", "/proc/sys/net/ipv4/ip_forward")
ADDRS_FILE = os.environ.get("PANELGRAPH_ADDRS")            # None -> SIOCGIFADDR ioctl
IW         = os.environ.get("PANELGRAPH_IW") or shutil.which("iw") or "/usr/sbin/iw"
ALERT_HOLD = float(os.environ.get("PANELGRAPH_ALERT_HOLD", "600"))

DOWN   = (1.0, 79/255, 0.0)      # #FF4F00  managed download
UP     = (1.0, 229/255, 0.0)     # #FFE500  managed upload
MON_RX = (1.0, 0.0, 1.0)         # #FF00FF  monitor captured rx (+ baseline)
MON_TX = (1.0, 160/255, 1.0)     # #FFA0FF  monitor injected tx
ALERT  = (1.0, 32/255, 32/255)   # #FF2020  M2 frame, used nowhere else
HEX = {"down": "FF4F00", "up": "FFE500", "mrx": "FF00FF", "mtx": "FFA0FF"}

ARPHRD_ETHER, ARPHRD_NONE, ARPHRD_PPP = 1, 65534, 512
MONITOR_TYPES = {801, 802, 803}
IFF_UP, IFF_PROMISC = 0x1, 0x100
RTF_UP, RTF_GATEWAY = 0x1, 0x2
ATF_COM = 0x2
VRRP_PREFIXES = ("00:00:5e:00:01:", "00:00:5e:00:02:", "00:00:0c:07:ac:")
IW_TIMEOUT = 1.0
LOG_ONCE_PERIOD = 600
MAX_STRIPS = 3
```

The existing `DOWN`/`UP` tuples (0.309804, 0.898039) are the same colours; keep whichever form you like, but the PNG bytes must be exactly FF4F00/FFE500.

Image geometry: `requirements.md` §4.1. Summary:

```
content box   normal: x0=0, y0=0, W=140, H=32      alert: x0=1, y0=1, W=138, H=30
down/rx bar   x0 .. x0+3                            up/tx bar  x0+6 .. x0+9  (always x 6-9)
history       x0+W-128 .. x0+W-1  (normal 12..139, alert 11..138), newest rightmost
strips        n<=3; usable=H-(n-1); base=usable//n; extra=usable%n;
              height[k] = base + (1 if k >= n-extra else 0); 1 transparent separator row between strips
value height  max(1, round(min(1, v/scale)*h)) if v>0 else 0, from the strip's bottom row upward
paint order   per column: monitor baseline -> larger value -> smaller value
frame (alert) every pixel with y in {0,31} or x in {0,139} = #FF2020, painted last (340 px)
```

The alert-mode bar position is a derived consequence: down bar x 1-4, gap x 5, up bar x 6-9, gap x 10. Use exactly that; QA asserts Pixel(2,6) and Pixel(7,28) in AC-47.

### 4.1 BLOCKER: sandbox hooks (DEF-05, F-02, task T1). Do this first.

QA cannot run any sandbox monitor test until this is done (`qa-instructions.md` §11.0). The deployed v1 daemon (392 lines, pid <pid> on 2026-11-20) uses **none** of the `PANELGRAPH_*` variables:
- It reads the hard-coded `/sys/class/net` (lines 58, 64, 69, 78, 87).
- It keeps only type-1 interfaces, so a monitor interface is dropped silently.

Requirements:

| Hook | Default (the real path) | Must cover |
|---|---|---|
| `PANELGRAPH_SYSNET` | `/sys/class/net` | `listdir`, and every per-interface file: `type`, `flags`, `operstate`, `carrier_changes`, `ifindex`, `statistics/*`, `device`, `phy80211`. Also the phy name, read as `f"{SYSNET}/{n}/phy80211/name"` (follows the relative link) or `os.path.join(os.path.dirname(SYSNET), "ieee80211", phy, "name")`. **Never** a literal `/sys/class/ieee80211`. |
| `PANELGRAPH_PROCNET` | `/proc/net` | `route`, `arp`, `wireless` |
| `PANELGRAPH_IPFORWARD` | `/proc/sys/net/ipv4/ip_forward` | forwarding note |
| `PANELGRAPH_IW` | `shutil.which("iw")` or `/usr/sbin/iw` | every iw spawn |
| `PANELGRAPH_ADDRS` | unset (use SIOCGIFADDR) | when set, **all** IPv4 lookups come from the file and the ioctl is never called. Otherwise a fake `wlan1` leaks the live IP. |
| `PANELGRAPH_ALERT_HOLD` | `600` | M2 frame hold |
| `XDG_RUNTIME_DIR` | **required, absolute** (v1.3, F-26) | output dir; no `/tmp` fallback |
| `PANELGRAPH_POPUP` | `1` | `0` disables the hover popup helper |
| `PANELGRAPH_POPUP_CMD` | `panelgraph-popup` next to the daemon | **test only**; must be absolute (else the popup is disabled and logged once); resolved at import |
| `PANELGRAPH_POPUP_XID` | unset | helper target window (decimal or `0x` hex); skips `net.host` |
| `PANELGRAPH_POPUP_MONITORS` | unset | helper monitor override `x,y,w,h;…` |
| `PANELGRAPH_DAEMON_PID` | set by the daemon | helper's parent pid; missing/invalid → helper exit 3 |

QA's static gate (AC-22):
- `grep` finds all six names.
- Outside comments, `/sys/class/net`, `/proc/net`, `/proc/sys/net` and `/sys/class/ieee80211` appear only inside the `os.environ.get(…, default)` constant lines.
- No other behaviour changes when the variables are unset.
- QA will **not** accept results from a sed-patched copy (`SMOKE` only). Ship the hooks in the real file.

## 5. Architecture v2

### 5.1 Per-tick sampler (F-01). Fixes DEF-01.

```text
names = listdir(SYSNET)                      # OSError -> []
drop cache entries whose name vanished
for n in sorted(names):
    c = cache.get(n) or Entry(n)             # new name: check links now ...
    if c.is_new or slow_scan_tick:           # ... AND re-check every name in each 5 s slow scan (D-32)
        c.has_dev = exists(f"{SYSNET}/{n}/device")
        c.has_phy = exists(f"{SYSNET}/{n}/phy80211")
        c.phy     = read(f"{SYSNET}/{n}/phy80211/name") if c.has_phy else None
    if not (c.has_dev or c.has_phy): continue            # bridges, veth, tun, lo, ...: never read per tick
    try:
        rx, tx = int(read(stat/rx_bytes)), int(read(stat/tx_bytes))
        rxp = int(read(stat/rx_packets))     # ALWAYS, for every candidate (D-31); never 0 as a placeholder
        t = int(read(type))                  # READ TYPE AFTER THE COUNTERS (guarantees no leak)
    except (OSError, ValueError): c.prev = None; continue  # vanished mid-tick: no error
    kind = "monitor" if t in MONITOR_TYPES else \
           "managed" if (t == ARPHRD_ETHER and c.has_dev) or (t == ARPHRD_NONE and c.has_dev and WWAN_ENABLED) else None
    if kind == "monitor": c.admin_up = read_flags(n) & IFF_UP   # 1 extra read per monitor vif
    if c.prev is not None and c.prev_kind == kind and kind:
        drx, dtx, drp = (max(0, a - b) for a, b in zip((rx, tx, rxp), c.prev))
        credit (drx, dtx) to managed[n]  or  (drx, dtx, drp) to the monitor aggregate
    # else: kind changed, new, or vanished -> discard the delta (rebaseline)
    c.prev, c.prev_kind, c.kind = (rx, tx, rxp), kind, kind
dt = now - prev_t (monotonic)
```

- **Classification:** follow the table in requirements §4.0 exactly.
- **WWAN_ENABLED:** True once F-15 is built; False before that.
- **Cost:** about 13 reads per tick live (10 measured at ≈ 0.31 ms, plus one `rx_packets` per candidate: eth0, wlan0, wlan1).
- **rx_packets must be read for every candidate, every tick** (D-31). Do **not** read it only when the previous kind was monitor. If you did, the tick on which an interface first becomes monitor (in-place switch or new vif) would store 0 into `prev`; that tick's delta is discarded, but the stored 0 becomes the **baseline of the next tick**, where `prev_kind == kind`, so `drp` = the whole lifetime counter. Live wlan0 has 13,871,277 → about `13871.3k fr/s` in the tooltip for 1 s. AC-24 catches this (sandbox packet counters start at 5,000,000).
- **Link re-check** (D-32): the kernel can list `/sys/class/net/<if>` before it adds the `device` link (device_add) or the `phy80211` link (cfg80211 NETDEV_REGISTER notifier), e.g. when `airmon-ng stop` re-creates wlan0. A negative result cached at that moment would be permanent for the netdev's lifetime. So re-check `device`, `phy80211` and the phy name for **every** name in each slow scan (`tick % 20 == 0`), refreshing both positive and negative results. A changed result changes `kind`, so that tick's delta is discarded automatically. Cost: 2 `exists()` + ≤ 1 read per name per 5 s. The sandbox cannot reproduce this race, so QA checks it by code review (AC-22 static part).

**Smoothing and history:**
- Every tick, for **every tracked managed key**, append `(dt, drx, dtx)` to that key's `deque(maxlen=NET_SMOOTH)` window. Append zeros when it produced no data this tick (down, vanished, or now monitor).
- If you skip this, a card that just switched to monitor would keep its last managed rate forever (AC-23 requires Total < 5 KiB/s within 1.5 s).
- Then rate = Σbytes / Σdt, and append `(rx_rate, tx_rate)` to that key's history `deque(maxlen=128)`.
- A new key's history is created **pre-filled with 128 × (0, 0)** so all strips stay column-aligned.
- Tracked managed keys are all names currently classed managed, plus any key whose history still holds a nonzero value. Drop a key when neither applies.
- **Monitor aggregate:** the same window/history mechanism, with history entries `(rx_rate, tx_rate, state)`. `state` ∈ {0 none, 1 down, 2 up}: 2 if any monitor vif has IFF_UP, 1 if vifs exist but none is up, 0 if none exist. Track `mon_names`, `mon_phys`, `pkt_rate`, and the wall time when the last vif disappeared (for "monitor ended").
- `abs_idx += 1` every tick. A history column i (0 = oldest) has index `abs_idx - (127 - i)`.
- **Total** = Σ over tracked managed keys of the current smoothed rate. This is the R3 sum; it never includes monitor bytes.

### 5.2 Strip manager (F-03)

- **Active managed key:** `kind == managed and operstate ∈ {up, unknown}` (from the 5 s scan) **or** a nonzero value in its history.
  - A card that is now monitor is not "managed now"; its managed strip lives only while its history is nonzero (≤ 32 s).
- **Monitor strip active:** any monitor vif exists **or** any history state ≠ 0 **or** any nonzero monitor rx/tx value in the history (D-33).
  - The third condition is needed because the state is 0 from the tick the last vif disappears, while the 1 s smoothing window keeps monitor rx/tx nonzero for about 3 more ticks. Without it, the layout would change while nonzero captured columns are still in the history. Same principle as the managed rule.
- Layout:
  - `slots = MAX_STRIPS - (1 if monitor active else 0)`.
  - Managed keys sorted by name.
  - If there are more than `slots`, the last slot becomes `other` = column-wise sum of the remaining keys' histories (and current values).
  - Monitor strip last (bottom).
  - No strip at all: one empty managed strip (full height, zeros, scale floor).
- **Managed scale** = max(NET_FLOOR, every rx/tx in every **displayed** managed strip history, including the "other" sum).
- **Monitor scale** = max(NET_FLOOR, every monitor rx/tx in its history).

### 5.3 Renderer (F-03, F-04, F-09)

- Replace the generic net path of `Graph.update`/`_render` with a `NetGraph` that receives a layout:
  ```
  (alert: bool, strips: [(kind, (bar_a_h, bar_b_h), [(a_h, b_h) per col], [lit per col] or None)])
  ```
- The pixel key = that tuple. It is cheap to compare; re-render only when it changes.
- Keep `Graph` unchanged for `mem`.
- `cairo.FORMAT_ARGB32`, `ANTIALIAS_NONE`, transparent background.
- Per strip:
  - bars at `x0` and `x0+6`, inside the strip rows;
  - baseline (monitor only, history columns only, bottom row, lit per D-12/D-13);
  - columns in two passes: larger value first, then smaller. Ties: paint a (rx) first, then b.
- Colours:
  - managed: a = DOWN, b = UP;
  - monitor: a = MON_RX, b = MON_TX.
- Frame: painted last, when alert.
- No other colour may ever be drawn. In particular, never draw #FF2020 except the frame.

### 5.4 Slow scan, every 20 ticks (F-05, F-07, F-08, F-09, F-12, F-13, F-16)

Each item sits in its own try/except. A failure calls `log_once(key, msg)` and leaves the previous values in place. **Never** let these raise into the graph handler (no "!" for auxiliary data, D-30).

1. **For every name in `SYSNET`:** re-check the `device`/`phy80211` links and the phy name (D-32, see §5.1), `type` (all names, needed for VPN/ppp), and for candidates `operstate`, `flags`, `carrier_changes`, `ifindex`.
   - F-16: if the ifindex changed, set `prev = None` (the links are re-checked anyway).
2. **Default route:** parse `f"{PROCNET}/route"`.
   - Rows with Destination `00000000`, Mask `00000000` and flags & RTF_UP.
   - The lowest Metric wins.
   - The gateway is the little-endian hex → dotted quad if flags & RTF_GATEWAY, else `?`.
3. **Gateway MAC:** `f"{PROCNET}/arp"`. The row with IP == gw and Device == iface and flags & ATF_COM gives the MAC; otherwise `?`.
4. **Signal:** `f"{PROCNET}/wireless"`. Skip the 2 header lines; `name, rest = line.split(":", 1)`; **`name = name.strip()`**; `level = int(float(rest.split()[2]))`.
   - The interface column is right-aligned with leading spaces (live: ` wlan1: 0000   70.  -27.  -256 …`; the sandbox writes ` wlan1:` too). Without `strip()` the name is ` wlan1` and never matches.
   - The iw-link fallback would hide this bug, so the sandbox uses different values (wireless -41, `iw link` -45) and AC-38 expects -41.
5. **IPv4 address:** for the default iface and each Wi-Fi/wired iface that has a strip.
   - `ADDRS_FILE` set: read its `ifname a.b.c.d` lines.
   - Otherwise: `fcntl.ioctl(sock, 0x8915 /*SIOCGIFADDR*/, struct.pack("256s", name.encode()[:15]))[20:24]`, using one AF_INET/SOCK_DGRAM socket created at start (close-on-exec is the Python default).
   - On error: `?`.
6. **ip_forward:** `IPFORWARD` (F-13).
7. **Promisc list:** type 1 + has_dev + flags & IFF_PROMISC, checked even when down (F-07).
8. **VPN list:** type 65534 without device link, operstate up/unknown (F-12). ppp: type 512 (F-17, Could).
9. **M2 state machine and gw.json** (§5.6). **S2 route-moved** detection (F-12).
10. `ensure_pidfile()` (existing).

### 5.5 iw runner (F-05, F-10, D-19). Must never block a tick.

```text
state: proc, started, cmd, killed, buf; results[cmd] = {ok_at, data, fail_reason, fail_at}
each tick:
  if proc:
     read available stdout (fd set non-blocking) into buf
     if proc.poll() is None:
        if not killed and now - started > IW_TIMEOUT: proc.kill(); killed = True; fail(cmd, "timeout")
        return                        # never start another until this one is reaped
     if not killed: parse(cmd, buf) -> ok or fail(cmd, "parse")
     close stdout; proc = None
  want = pending_m2_link or ("dev" if tick % 40 == 0 and any_phy) or ("link" if tick % 40 == 20 and link_target) or None
  if want: try Popen([IW, "dev"] or [IW, "dev", target, "link"], stdin=DEVNULL, stdout=PIPE,
                      stderr=DEVNULL, close_fds=True, start_new_session=True)
           except OSError: fail(want, "iw missing")
```

- **Never use `subprocess.run(timeout=…)`.** After the kill it waits again, and an mt76 USB hang in D-state would block the tick forever.
- **`link_target`:** the default-route interface if it is managed Wi-Fi with operstate up; otherwise the first such Wi-Fi by name; otherwise `None` (skip).
- **`iw dev` parser** (verified against the real output in `requirements.md` §3.10 and `qa-instructions.md` §5.4):
  - `phy#N` sets the current phy and clears the current interface.
  - `Unnamed/non-netdev interface` clears the current interface, so the P2P-device `type` must not overwrite wlan0.
  - `Interface X` starts a record.
  - Inside a record: `ifindex`, `type <rest>`, `ssid <rest>`, `channel (\d+) \((\d+) MHz\)(?:, width: (\d+) MHz)?`.
  - Ignore the `multicast TXQ` table lines.
- **`iw link` parser:** `Connected to ([0-9a-f:]{17})`, `SSID: (.*)`, `freq: ([\d.]+)`, `signal: (-?\d+) dBm`, `rx bitrate: ([\d.]+) MBit/s`, `tx bitrate: ([\d.]+) MBit/s`. `Not connected.` means no link data.
  - A parse failure is output that is neither empty nor matches any `Interface`/`Connected`/`Not connected` line.
- **Drain to EOF after exit** (v1.3, D-57): once `proc.poll()` reports the exit, call `_drain()` again before parsing. iw may write and exit between the first drain and `poll()`; without the second drain a lost `Connected to …` reads as "not connected" and the M2 BSSID guard is skipped. The writer has exited, so this cannot block; the 64 KiB cap still bounds it. Empty output is still not a failure (rule above).
- **SSID source** (D-35): the tooltip SSID comes from the `ssid` line of `iw dev`; if `iw dev` has none for that interface, from the `SSID:` line of `iw dev <if> link`. Both use iw's `\xNN` escaping and both are attacker-controlled.
- **SSID decoding.** iw prints non-printables, edge spaces and `\` as `\xNN`. **Both parsers call the same function** (`decode_ssid`), and its result is escaped with `esc()` at interpolation time (§5.7): decode → strip Cc/Cf/Cs/Co/Cn/Zl/Zp with `clean()` (v1.3, D-56) → truncate to 32 → escape.
  ```python
  BAD_CATS = frozenset({"Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"})

  def clean(s, n, ell=True):
      s = str(s).encode("utf-8", "replace").decode("utf-8")
      s = "".join(ch for ch in s if unicodedata.category(ch) not in BAD_CATS)
      if len(s) <= n:
          return s
      return s[:n - 1] + "…" if ell else s[:n]

  def decode_ssid(ssid):
      raw = re.sub(rb"\\x([0-9a-fA-F]{2})", lambda m: bytes([int(m[1], 16)]), ssid.encode("utf-8", "surrogateescape"))
      return clean(raw.decode("utf-8", "replace"), 32, ell=False)
  ```
  `clean()` also sanitises every popup.json label (40) and span row (96). `esc()` is unchanged.
- **Stale handling:**
  - If the latest attempt of a command failed and it has a previous success, show ` (stale Ns)` with N = now − ok_at.
  - Once N > 30, or with no previous success, show `Wi-Fi details unavailable (<reason>)` with reason ∈ {`iw missing`, `timeout`, `parse`}.
  - Route, arp and sysfs-based parts keep working.

### 5.6 M2 gateway-MAC alert (F-09)

Implement exactly `requirements.md` §4.4.

```text
scan(route=(iface, gw), mac (complete only) , cc=carrier_changes[iface], bssid=last iw link bssid for iface or None):
  if mac is None: return                                   # incomplete / missing never alerts
  if gw.json was deleted while we had a baseline:          # user acceptance
       baseline = current; alert=None; accepted_at=now; write; return
  if no baseline or (iface,gw) != baseline.key or cc != baseline.cc or (bssid and baseline.bssid and bssid != baseline.bssid) \
     or (mac.startswith(VRRP) and baseline.mac.startswith(VRRP)):
       baseline = current (keep alert state); write if changed; pending=None; return
  if mac == baseline.mac: pending=None; if alert active and mismatch ended: alert.clear_at = alert.clear_at or now + ALERT_HOLD
  elif pending is None: pending = (mac, now); request one immediate "iw dev <iface> link" (if Wi-Fi)
  elif fresh link result newer than pending.time shows bssid == baseline.bssid, or iface not Wi-Fi, or iw failed:
       alert = {since: now, old: baseline.mac, new: mac}; alert_seen_this_run = True; write
frame on  <=> alert active and (mismatch persists or now < clear_at)     # EVALUATED EVERY TICK (D-36)
'!!' line <=> alert_seen_this_run (stays until daemon exit) or a restored active alert
```

- **Frame timing** (D-36): `scan()` runs every 20 ticks, but the `frame on` condition (and therefore the pixel key) must be evaluated **every tick**. `clear_at` = mismatch end (the scan that sees the baseline MAC again) + `ALERT_HOLD`. If you evaluate it only in the scan, the frame can last until about t1 + 30 s and fails AC-49 ("gone by t1 + 27 s" with `ALERT_HOLD=20`).

- **gw.json:** `$DIR/gw.json` = `{"iface","gw_ip","mac","carrier_changes","bssid","alert_since","alert_mac"}`.
  - Write atomically, only when a field changes.
  - Load at start. Use it as the baseline only if `(iface, gw_ip)` and `carrier_changes` still match; otherwise re-baseline. Restore an alert whose hold has not expired.
- **"Gateway MAC accepted HH:MM":** shown in L1 for 10 min.
- **Route moved (F-12):**
  - `(iface, gw)` changed between scans and the old iface's carrier_changes did not change: show `Default route moved <old>→<new> HH:MM` in L1 for 10 min.
  - Joined with ` | ` if the `!!` text is also present.

### 5.7 Tooltip builder (F-06)

Build the tooltip from the template in `requirements.md` §4.2.

- `esc = lambda s: html.escape(str(s), quote=False)` is applied to every interpolated **value**: names, SSID, MAC, iw strings, error reasons.
- `glyph = lambda hx: f'<span foreground="#{hx}">■</span>'` is inserted **after** escaping.
- Wrap the `!!` line in `<b>…</b>`.
- Never escape the assembled markup.
- `NetGraph` writes `f"<img>{png}</img><click>{CLICK}</click><tool>{markup}</tool>\n"`.
- Keep the line order and the ≤ 10-line guarantee.
- **MONITOR line** (D-34): one line for the one monitor strip. Per vif, sorted by name: `f"{esc(name)} ({esc(phy)}, ch{N} {F} MHz, {state})"`, joined by ` + `; drop `, ch… MHz` when `iw dev` gave no channel for that vif. `state` = `up` if that vif's `flags & IFF_UP`, else `down`; **never** use `operstate` (mac80211 monitor vifs report `unknown`). The captured/injected/fr/s figures are sums over all vifs. Example in `requirements.md` §4.2.
- **Number formats:**
  - rates use `human(v, "B/s")`;
  - bitrates are `round(float)`;
  - frames: `<1000 → f"{n:.0f} fr/s"`, else `f"{n/1000:.1f}k fr/s"`;
  - times `HH:MM` (`monitor ended` uses `HH:MM:SS`), from `time.strftime`.
- **Idle wording** (L10):
  - wired: admin-up + operstate not up → `no carrier`; admin-down → `down`;
  - Wi-Fi (has_phy): `not connected` / `down`.
  - Join with ` · `.
- **Self-check at development time:** run `Pango.parse_markup(markup, -1, "\0")` in your sandbox tests. Do **not** import gi in the daemon.

### 5.8 Should features (F-11 to F-16)

- **F-11:**
  - Two `deque(maxlen=300)` of per-second managed rx/tx byte buckets, plus running sums. Bucket boundaries follow monotonic seconds.
  - Sustained = last 60 buckets average tx > 256 KiB/s and Σtx(60) > Σrx(60).
  - `Sustained upload {m}m{ss}s` = continuous-true seconds + 60.
  - `Up 5 min {human bytes}` is always shown.
- **F-12:** route moved (§5.6) and `VPN <names> up`.
- **F-13:** forwarding note per requirements.
- **F-14:** `[AP]`/`[mesh]`/`[IBSS]` from the `iw dev` type (`AP`, `P2P-GO` → `[AP]`; `mesh point` → `[mesh]`; `IBSS` → `[IBSS]`).
- **F-15:** `WWAN_ENABLED = True`.
- **F-16:** ifindex check in the slow scan.

### 5.9 Error logging

- `log_once(key, text)`: call the existing `log_error` at most once per key per 600 s. `error.log` still holds only the latest entry; that is accepted.
- Keys: `iw:timeout`, `iw:missing`, `iw:parse`, `route`, `arp`, `wireless`, `ioctl`, `gwjson`, `scan`, `popup` (v1.3: popup.json write errors, helper exits other than 0/2, a relative `PANELGRAPH_POPUP_CMD`, spawn failures).
- The helper has its own `log_once` that appends to `popup.log`, at most once per key per 600 s (`LOG_ONCE_PERIOD`). Each call opens it with `O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK` and mode 0600, requires `S_ISREG` via fstat, and does one `os.write` of the whole entry; when `st_size` plus the entry would pass `POPUP_LOG_MAX` (16384 B) it restarts the file with `write_atomic`. An entry keeps its last `POPUP_LOG_ENTRY_MAX` (4096) code points, so a traceback keeps its last frames. `OSError` is swallowed (nowhere left to report). This is the one exception to "every write goes through `write_atomic`": appending keeps the root cause next to what followed it. Keys: `attach`, `doc`, `render`, `place`, `xi`, `env`, `x`, `lib:Xi`/`lib:Xinerama`/`lib:Xrandr`, `crash`.

### 5.10 Monitor-mode colour task (user decision a, D-04, D-07). Consolidated checklist.

The user decided that monitor-mode traffic is drawn in a **different colour** and **never** added to the managed sum. Everything below is already specified in §4, §5.1-§5.3 and §5.7. This list is the single checklist QA will verify (coverage map in `acceptance-criteria.md`).

1. **Detection** (§5.1): `type ∈ {801, 802, 803}` **and** (`device` or `phy80211` link). **Never by name**: `mon0` is a monitor, and a type-1 NIC called `wlan2mon` is managed (AC-79). In-place switches keep the name (AC-23, AC-68).
2. **Never summed** (§5.1 delta rule): read the counters, then `type`, every tick. Credit a delta only when the class is the same at both reads. On a class change, discard and rebaseline. Zero-fill the managed window of a card that became monitor. Read `rx_packets` for every candidate (D-31). (AC-23, AC-24, AC-31)
3. **State** from `flags & IFF_UP` of each vif, **never** from `operstate` (monitor vifs report `unknown`). (AC-30, AC-76)
4. **Colours, pixel-exact**, with `ANTIALIAS_NONE` and opaque pixels only (AC-78):
   - captured rx columns and the **left** bar = `MON_RX` #FF00FF;
   - injected tx columns and the **right** bar = `MON_TX` #FFA0FF;
   - the baseline marker = #FF00FF.
   - No other colour in the monitor strip; never FF4F00/FFE500 there.
5. **Layout:**
   - one aggregated monitor strip, always at the **bottom**, separated by one fully transparent row;
   - own `Mon scale` = max(64 KiB/s, monitor history);
   - bars inside the strip rows at x0..x0+3 and x0+6..x0+9;
   - the baseline on the strip's bottom row, history columns only: solid if any vif is up, dotted on `abs_idx % 2 == 0` if all are down. (AC-27 to AC-30)
6. **Lifetime:**
   - The strip appears on the first tick a vif is seen.
   - When the last vif disappears (removed or switched back), the MONITOR line becomes `monitor ended HH:MM:SS` within one tick.
   - The strip stays while a state ≠ none or a nonzero monitor value is in the history (D-33), then disappears 32-34 s later with no flapping and no "!". (AC-32, AC-77)
7. **Tooltip** (§5.7): `■ MONITOR <vif> (<phy>, ch<N> <F> MHz, up|down)  ■ captured …  ■ injected …  … fr/s · not in total · Mon scale …`.
   - Per-vif groups are sorted by name and joined by ` + `.
   - Glyph spans are `#FF00FF`/`#FFA0FF`.
   - The phy name is read through `SYSNET` (AC-79 uses a `phy5` that exists only in the sandbox).
   - Names are escaped. (AC-27, AC-43, AC-76)
8. **Promisc is never magenta** (D-09): tooltip line only. (AC-44)

### 5.11 Hover popup (F-25) and private runtime dir (F-26). v1.3.

The binding design is `requirements.md` §4.7 (with D-46 to D-58). This is the implementation map.

**Wrapper (`bin/panelgraph-show`).** Replace the `${XDG_RUNTIME_DIR:-/tmp}` line by the `case` refusal (§4.7.1). Right after it, refuse a `$d` that is a symlink or exists and is not ours (`[ -h ]`, `[ -e ]`, `[ -O ]`, on every call); the daemon's `secure_dir()` refuses the same dirs, so both the wrapper and the daemon refuse a symlinked runtime dir or one owned by another uid (D-55). After the `seen` line add `[ "$1" = net ] && printf '%s\n' "$PPID" 2>/dev/null > "$d/net.host"`. Both are builtins; every added line carries a comment with the reason and spec id; `dash -n` must pass and AC-02 must stay byte-identical.

**Daemon (`bin/panelgraph-daemon`), additions only:**
- Constants: `BAD_CATS`, `POPUP_SCHEMA`, `POPUP_LABEL_MAX` 40, `POPUP_SPAN_MAX` 96, `POPUP_RETRY` {0: 5, 2: 5, 3: 300}, `POPUP_RETRY_ELSE` 30, `POPUP_RETRY_SPAWN` 300, `POPUP_QUIET_RC` (0, 2), `POPUP_ERROR_ROWS`; the D-55 block (`DIR_MODE`, `UMASK`, `_XDG`, `DIR`); runtime paths derived only when `DIR` is set (`POPUP_JSON`, `NET_HOST` among them); env hooks `POPUP`, `POPUP_CMD`, `POPUP_XID_SET`, `DISPLAY`.
- Helpers: `clean()`, `secure_dir()`.
- `NetMonitor.popup_rows(managed, mon_active)` (+ `_strip_label`, `_monitor_row`), called by `build()`; result in `self.popup`. `tooltip()` is unchanged.
- `PopupHelper` (`alive`, `poll`, `feed`, `kill`). `run()`: `helper.poll(start)` in the existing slow block; `helper.feed(netmon.popup)` after `net.update()`; `helper.feed(POPUP_ERROR_ROWS)` best effort in the net failure branch; `helper.kill()` in `finally`. `main()`: `secure_dir()` right after `closerange`.
- `IwRunner.poll`: `_drain()` again before `_finish()` (D-57).
- Per-tick cost of the additions (measured): ≤ 65 µs worst case (`popup_rows` 6 µs, changed `feed` 58 µs, `alive` 1 µs).

**Helper (`bin/panelgraph-popup`), one file in the daemon's layout order:**
1. Constants (identity, exit codes, timing, input limits, look, states), env hooks read once, the D-55 block, Xlib constants named after X.h/XI2.h/shape.h, ctypes structures named after the Xlib types (`XEvent` union padded to 24 longs, partial `XImageHead`), and **one** declaration table `LIBS` bound by `proto()` with `restype`/`argtypes` for every function.
2. Pure helpers, unit-testable without X (A9): `secure_dir`, `write_atomic`, `log_once`, `read_capped`, `parse_pid`, `parse_xid`, `read_host_pid`, `resolve_host`, `parse_monitors`, `parse_dpi`, `parse_doc`, `layout`, `draw`, `corner_insets`, `shape_spans`, `pick_monitor`, `place`.
3. X side: `load_libs`, the module-level `CFUNCTYPE` error handlers, class `Popup` (window creation, item lookup, geometry, upload, state machine, event loop), `open_popup`, `serve`, `main`.
- Importing the file has no side effects (no X connection, chdir, write or signal handler).
- Wakeups (D-58): `ITEM_MASK_HIDDEN` (Enter|Leave) on the socket in IDLE, PENDING and SUPPRESSED; `ITEM_MASK_SHOWN` (+ StructureNotify) from the start of `show()`, before the rects are read so no move is missed, and back to the hidden mask on every hide or failed show; `NoEventMask` on `detach()`, because xfce4-panel keeps the socket for a respawned wrapper (`XSync` first, then the expected BadWindow is absorbed into `seen_errors`). All through the one `select_item()` call site. `find_item()` returns the wrapper's pidfd with the XID, and the loop selects on it. `geometry()` reads the panel rect and monitors once per show (`frame`); a ConfigureNotify while shown only clears `geo`, so the next refresh reads the item rect again.
- Sonames are loaded directly (`libX11.so.6`, …): `ctypes.util.find_library` would run `ldconfig`, and the helper starts no processes. X11, Xext and libc are required: an `OSError` (or missing symbol) on any of them → exit 3. Xi, Xinerama and Xrandr are optional: a failure is logged once (`lib:<key>`) and degrades (no raw-button hide; the root as the only monitor), never an exit.

## 6. Ordered implementation tasks

| # | Task | Satisfies ACs |
|---|---|---|
| T0 | Back up (§7). Create the scratch work dir. Build or reuse QA's sandbox harness (`qa-instructions.md` §5) for self-testing. | – |
| T1 | **BLOCKER, first.** Path/env hooks (§4, §4.1). Replace every hard-coded `/sys/class/net`, `/proc/net`, `/proc/sys/net` and `/sys/class/ieee80211`. Read the phy name through `SYSNET`. Add `ADDRS_FILE` and `ALERT_HOLD`. Tell QA as soon as T1 is in a build, so the sandbox gate (qa §11.0) can pass. | AC-22, AC-79 (phy part) |
| T2 | Per-tick sampler + delta rule + per-key smoothing with zero-fill (§5.1); name-independent monitor detection (§5.10 item 1) | AC-09, AC-16, AC-17, AC-18, AC-23, AC-24, AC-25, AC-26, AC-31, AC-79 |
| T3 | Per-key histories, strip manager, scales (§5.2) | AC-13, AC-14, AC-15, AC-34, AC-35, AC-36 |
| T4 | `NetGraph` renderer: strips, monitor colours, baseline, bars (§5.3, checklist §5.10) | AC-11, AC-27, AC-28, AC-29, AC-30, AC-32, AC-33, AC-37 (image), AC-76 (image), AC-77, AC-78 |
| T5 | Slow scan: link re-check, operstate/flags/carrier/ifindex, route, arp, wireless, addresses, ip_forward, promisc (§5.4) | AC-44, AC-46, AC-38 (gateway part) |
| T6 | Async iw runner + parsers + SSID decoding + stale/unavailable (§5.5) | AC-40, AC-41, AC-38, AC-03 (sandbox) |
| T7 | Tooltip builder with escaping and glyphs (§5.7) | AC-37, AC-42, AC-43, AC-76 (MONITOR line) |
| T8 | M2 alert, frame + inset rendering, gw.json, acceptance (§5.6) | AC-47, AC-48, AC-49, AC-50, AC-51 |
| T9 | Shoulds F-11 to F-16 (§5.8). If time runs out, ship without them and tell QA which are built. | AC-52 to AC-58 |
| T10 | **v1.3, first, its own commit.** Private runtime dir (F-26, §4.7.1): resolver + `secure_dir()` in the daemon (and later, byte-identical, in the helper); the wrapper's `case` refusal. Separate commits follow for the iw drain (D-57) and `clean()` + the docstring pointer (D-56, CR-8). | AC-94, AC-95, AC-96, AC-02 |
| T11 | Wrapper `net.host` line (§5.11) | AC-80, AC-01 to AC-06 |
| T12 | Daemon popup feed: `popup_rows`, `PopupHelper`, popup.json writes (§5.11) | AC-81, AC-82, AC-83, AC-92 (regression part) |
| T13 | Helper `bin/panelgraph-popup` and `install.sh` (three files) (§5.11, requirements §4.7.6-§4.7.10) | AC-84 to AC-91, AC-97 to AC-99, AC-92 (static gate) |
| T14 | Docs (requirements, AC, dev, qa §12, README) | review; AC-93 hand-off |
| T15 | (was T10 in v1.2) Self-test all sandbox ACs. Deploy (§8). Run the live read-only checks AC-01 to AC-05, AC-10, AC-11, AC-19 to AC-21, AC-39, AC-45. Hand over to QA. | regression set |

Could items (F-17 to F-21) and deferred items (F-22 to F-24): do not build unless the BA or user says so.

## 7. Backup and rollback

```sh
B=~/.local/share/panelgraph/backup; mkdir -p "$B"
cp -a ~/.local/bin/panelgraph-daemon "$B/panelgraph-daemon.v1-2026-11-20"
cp -a ~/.local/bin/panelgraph-show   "$B/panelgraph-show.v1-2026-11-20"
sha256sum "$B"/* > "$B/SHA256SUMS"
```

**Rollback** (any time):

```sh
cp -a "$B/panelgraph-daemon.v1-2026-11-20" ~/.local/bin/.panelgraph-daemon.new
mv -f ~/.local/bin/.panelgraph-daemon.new ~/.local/bin/panelgraph-daemon
# then restart the live daemon (section 8)
```

## 8. Deploy and restart the live daemon safely

1. Check the candidate:
   - `python3 -m py_compile <scratch>/panelgraph-daemon`
   - the full sandbox suite passes (the sandbox uses a separate `XDG_RUNTIME_DIR`, so it never collides with the live lock or pid)
2. Install atomically. panelgraph-show may exec the file at any moment, so never write it in place:
   ```sh
   cp <scratch>/panelgraph-daemon ~/.local/bin/.panelgraph-daemon.new
   chmod 755 ~/.local/bin/.panelgraph-daemon.new
   mv -f ~/.local/bin/.panelgraph-daemon.new ~/.local/bin/panelgraph-daemon
   ```
3. Restart via the pid file only:
   ```sh
   D=/run/user/1000/panelgraph; P=$(cat "$D/pid")
   [ "$(cat /proc/$P/comm 2>/dev/null)" = panelgraph ] && [ /proc/$P/cwd -ef "$D" ] && kill "$P"
   timeout 2 tail -f /dev/null
   P2=$(cat "$D/pid"); echo "old=$P new=$P2 comm=$(cat /proc/$P2/comm)"; head -c 300 "$D/net.txt"
   ```
   genmon's next `panelgraph-show` call (≤ 250 ms) starts the new daemon. Expected: new pid, comm `panelgraph`, `net.txt` starting with `<img>`.
   - v1.3: install `panelgraph-popup` (and `panelgraph-show`) the same atomic way (`cp` to `.name.new`, `chmod 755`, `mv -f`) **before** restarting the daemon. Stopping the daemon also stops the helper (pidfd, PDEATHSIG and the daemon's `killpg`); the new daemon starts the new helper within one slow scan (≤ 5.5 s) once `net.host` exists. Never kill the helper by pattern; if needed, use `popup.pid` after checking comm `panelgraph-pop` and the cwd.
4. If `net.txt` shows `<txt>!</txt>`: read `$D/error.log`, fix or roll back (§7), and restart again.
5. Leave the daemon running.

## 9. Definition of done

- [ ] T1 sandbox hooks are in the real file, and QA's gate (qa-instructions §11.0) passes.
- [ ] All NEW-MUST sandbox ACs (AC-22 to AC-51 and AC-76 to AC-79) pass in your self-test. QA confirms independently.
- [ ] All REGRESSION ACs not needing approval (AC-01 to AC-21) pass after deployment.
- [ ] Each Should is either built and passing (AC-52 to AC-58), or listed as "not built" in your hand-off.
- [ ] Cost: AC-21 (≤ 2.0 % CPU, ≤ 40 MB RSS), AC-40 (≤ 1 iw spawn / 5 s).
- [ ] Backups exist in `~/.local/share/panelgraph/backup/` with checksums.
- [ ] The live daemon runs the new version; `net.txt` has no "!"; panel config untouched (AC-20).
- [ ] Hand-off note to QA and BA:
  - the version deployed;
  - which Shoulds are built;
  - any deviation from these documents (which needs BA sign-off);
  - the env vars and fixture assumptions QA needs.
- [ ] No live interface-state test was performed. Those (AC-67 to AC-75) are for QA with the user's approval.
- [ ] v1.3 (F-25/F-26): AC-80 to AC-92 and AC-94 to AC-99 pass in the self-test (virtual X only, never `:0`); AC-01 to AC-79 re-run; AC-93 handed to the user as an install + hover checklist.
- [ ] v1.3: `python3 -X dev -W error -m py_compile` on both Python files, `dash -n bin/panelgraph-show`, `bash -n install.sh`; the AC-22 and AC-92 static gates pass; the D-55 block is byte-identical in daemon and helper.
- [ ] v1.3: no `__pycache__`, scratch paths or prototype leftovers committed. Privacy grep over the diff and new files (SEC-14): no MAC other than `aa:bb:cc:dd:ee:0N` and `02:00:00:00:00:xx`, no IPv4 other than `192.168.1.x` and `10.99.0.x`, no `/home/<user>` other than `/home/kali`, no real SSID; no live `net.txt`, `popup.json` or `popup.log` content in the docs.

## 10. Code standard

Binding for every change to `bin/panelgraph-daemon`, `bin/panelgraph-popup`, `bin/panelgraph-show` and `install.sh`. The reviewer rejects a change that breaks a rule here. Written by the tech lead for F-25 (v1.3) and kept for later work.

### 10.1 Files and structure
- The daemon is one file and the helper is one file: no packages, no modules next to them, no `__pycache__` in git.
- Imports are stdlib only, plus `cairo`, imported lazily inside the render functions. The daemon never imports `ctypes`, `gi` or any X library.
- File order: shebang and docstring; imports, alphabetical, one per line; constants; `PANELGRAPH_*` env constants; pure helpers; classes; `run()`; `main()`; `if __name__ == "__main__": sys.exit(main())`.
- No side effects at import time beyond computing constants (no X connection, chdir, file write or signal handler), so QA can load a file with `SourceFileLoader`.

### 10.2 Constants and env hooks
- Every tunable number or string (timings, paddings, colours, caps, backoffs, exit codes) is an `UPPER_SNAKE` constant in the top block, with a trailing comment giving the unit and the spec id, e.g. `SHOW_DELAY = 0.5  # s hover before show (D-49)`. No magic numbers in function bodies, except 0, 1 and obvious indices.
- Env overrides are named `PANELGRAPH_*` and read once at import. A malformed value falls back to the default without raising, or is ignored with a log entry. Every hook is listed in `requirements.md` §4.0, the README testing table and §4.1 here.
- `/sys/class/net`, `/proc/net`, `/proc/sys/net` and `/sys/class/ieee80211` appear only as defaults of the `PANELGRAPH_*` constants (AC-22).
- Colours come only from the palette constants (`requirements.md` §4.1) and the helper's popup colours. `#FF2020` appears only in the alert frame.

### 10.3 Naming and style
- `snake_case` functions, methods and locals; `CapWords` classes; a leading underscore for internals (`_drain`, `_finish`). Methods use the existing verbs: `poll(now)`, `alive()`, `kill()`, `update()`, `fail()`, `scan()`, `tick()`.
- Short locals (`c`, `k`, `st`, `now`) are fine in tight loops; anything that lives longer than about 10 lines gets a descriptive name.
- 4-space indent, lines ≤ 110 characters, double quotes, f-strings. No type annotations (ctypes field and argtype declarations are not annotations). `__slots__` on small per-interface or per-row value classes.

### 10.4 Function size and shape
- New functions: ≤ 40 lines and ≤ 3 levels of nesting. An X event dispatcher may reach 60 lines if it is a flat `if`/`elif` on the event type that calls one handler per transition.
- One function does one thing. Keep pure computation (parsing, layout, placement) separate from X calls, so it can be probed without a display.
- Do not grow `tooltip()` or `build()` with new logic; add a method and call it.
- No copy-paste between the daemon and the helper, except the runtime-dir resolver and `secure_dir()`. That block stays byte-identical in both files, marked by a comment (D-55), and QA diffs it.

### 10.5 Error handling
- Daemon: every auxiliary step has its own `try`/`except`, logs through `log_once(key, repr(e))` with a stable key, and never sets the "!" marker or touches `net.txt`/`mem.txt` (D-30). `except Exception` is allowed only at those auxiliary boundaries and the graph boundaries in `run()`; everywhere else catch the narrow exception (`OSError`, `ValueError`, `ProcessLookupError`, `BlockingIOError`).
- No bare `except:`. No `except Exception: pass` without a comment that says why silence is correct.
- Helper: messages go to `popup.log` through `log_once` (bounded by `POPUP_LOG_MAX`, D-54). Render, load and place failures keep the last good state and never exit. Only the named exit codes are used (`EXIT_OK`, `EXIT_CRASH`, `EXIT_BUSY`, `EXIT_UNAVAILABLE`).
- No `print()`, no stderr output (stderr is DEVNULL), and no traceback anywhere except `error.log` or `popup.log`.

### 10.6 Subprocess and cost (NFR-4)
- Exactly two `Popen` sites: `IwRunner` and `PopupHelper`. Each uses an argv list, `stdin`/`stderr=DEVNULL` (the helper also `stdout=DEVNULL`), `close_fds=True` and `start_new_session=True`. Never `subprocess.run`/`call`/`check_output`, `shell=True`, `os.system`, `os.popen`, `nmcli`, `ip` or `ss`. The helper spawns nothing (it loads library sonames directly, because `ctypes.util.find_library` runs `ldconfig`).
- Per-tick daemon work stays O(strips); anything heavier goes into the `SLOW_EVERY` block. State the per-tick cost of new daemon code in µs in the commit message.
- Helper: no timers and no pointer polling while hidden (the select timeout is `None` in IDLE), except the 2 s re-attach retry while DETACHED.

### 10.7 Files and atomicity
- Every runtime-file write goes through `write_atomic` (`path + ".tmp"`, then `os.replace`); `popup.log` is the one append-only file.
- The helper writes only `popup.pid`, `popup.pid.tmp`, `popup.lock` and `popup.log`. Its reads use `O_NOFOLLOW`, an `fstat` `S_ISREG` check and a size cap.
- Remove a pid file only when it holds our own pid.

### 10.8 POSIX sh (`bin/panelgraph-show`)
- The hot path uses dash builtins only (`case`, `[`, `read`, `printf`, `echo`, `true`, `while`). A new exec is allowed only in the rare "daemon not running" branch.
- Put `2>/dev/null` before `>` on a redirection whose failure must not kill dash, and do not redirect `:`; use `true` or `printf`.
- No bashisms (`[[ ]]`, `$UID`, arrays, `local`, `source`, `$'…'`); `dash -n` must pass. `test -O` and `-ef` are deliberate: dash, bash and busybox support them, and a strictly POSIX check would need an exec on the hot path.
- Every added line has a comment with the reason and the spec id. AC-02 output stays byte-identical.

### 10.9 ctypes (helper)
- One declaration table: each library function is bound once, with `restype` and `argtypes` set. Calling an unbound ctypes function is forbidden.
- Structs are `ctypes.Structure`/`Union` subclasses named after the Xlib type; no numeric pointer offsets.
- X constants are named module constants (`EnterWindowMask = 1 << 4`, …), which keeps the AC-92 static gate greppable.
- Keep `CFUNCTYPE` callbacks referenced at module level. `XFree` everything Xlib allocates, and nothing it does not.

### 10.10 Comments and docstrings
- Comments explain why, cite the constraint or spec id (D-xx, F-xx, AC-xx, NFR-x) or warn about a trap. No comments that restate the code.
- Every class and non-trivial function has a one- to three-line docstring that says what it guarantees, not how.
- English only. No real SSIDs, MACs, IPs or usernames in code, comments, fixtures or docs: use `HomeNet`, `aa:bb:cc:dd:ee:0N`, `192.168.1.x` and the sandbox's `10.99.0.x` / `02:00:…` values.

### 10.11 No dead code
- No commented-out code, unused imports, constants or parameters, debug flags, prototype leftovers or hard-coded scratch paths. Every env hook and constant is used and documented.

### 10.12 Dependencies and install
- No new runtime dependency unless it ships with a standard Kali XFCE install and is listed in the README Requirements.
- A missing optional library degrades the feature, never the graph: the helper exits `EXIT_UNAVAILABLE` and the daemon backs off for 300 s.
- `install.sh` and the README Uninstall section list every file in `bin/`.

### 10.13 Commits and static analysis
- Each commit compiles with `python3 -X dev -W error -m py_compile` on both Python files and passes `dash -n` / `bash -n`. English messages, one topic per commit, no unrelated refactors.
- Before merge, run bandit, ruff, pyflakes3 and shellcheck against `main` and justify every new non-style finding (fix it, or waive it with the rule it follows).
