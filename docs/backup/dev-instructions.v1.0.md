# panelgraph NETWORK graph v2: developer instructions

Version 1.0, 2026-11-20. Author: BA.

Read `requirements.md` §4 (binding design) and `acceptance-criteria.md` (what QA will check) first. If anything here seems to conflict with those, stop and ask the BA; do not improvise.

## 1. Files

| File | Action |
|---|---|
| `~/.local/bin/panelgraph-daemon` | **Main work.** Today 392 lines. Keep it a single file (atomic deploy). An optional helper module next to it (`~/.local/bin/panelgraph_net.py`) is allowed, but it makes deploys non-atomic. Recommended: no module. |
| `~/.local/bin/panelgraph-show` | **No change needed.** If you touch it, it must stay builtins-only on the hot path, and AC-01 to AC-06 must be re-run. |
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

## 5. Architecture v2

### 5.1 Per-tick sampler (F-01). Fixes DEF-01.

```text
names = listdir(SYSNET)                      # OSError -> []
drop cache entries whose name vanished
for n in sorted(names):
    c = cache.get(n) or Entry(n):            # new name: check links once
        c.has_dev = exists(f"{SYSNET}/{n}/device")
        c.has_phy = exists(f"{SYSNET}/{n}/phy80211")
        c.phy     = read(f"{SYSNET}/{n}/phy80211/name") if c.has_phy else None
    if not (c.has_dev or c.has_phy): continue            # bridges, veth, tun, lo, ...: never read per tick
    try:
        rx, tx = int(read(stat/rx_bytes)), int(read(stat/tx_bytes))
        rxp = int(read(stat/rx_packets)) if c.kind == "monitor" else 0
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
- **Cost:** about 10 reads per tick. Measured ≈ 0.31 ms.
- **rx_packets:** the first tick of a new monitor vif reads `rx_packets` as 0 into prev. That is fine, because that tick's delta is discarded anyway (new kind).

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
- **Monitor strip active:** any monitor vif exists **or** any history state ≠ 0.
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

1. **For every name in `SYSNET`:** `type` (all names, needed for VPN/ppp), and for candidates `operstate`, `flags`, `carrier_changes`, `ifindex`.
   - F-16: if the ifindex changed, re-check the links and set `prev = None`.
2. **Default route:** parse `f"{PROCNET}/route"`.
   - Rows with Destination `00000000`, Mask `00000000` and flags & RTF_UP.
   - The lowest Metric wins.
   - The gateway is the little-endian hex → dotted quad if flags & RTF_GATEWAY, else `?`.
3. **Gateway MAC:** `f"{PROCNET}/arp"`. The row with IP == gw and Device == iface and flags & ATF_COM gives the MAC; otherwise `?`.
4. **Signal:** `f"{PROCNET}/wireless"`. Skip the 2 header lines; `name, rest = line.split(":", 1)`; `level = int(float(rest.split()[2]))`.
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
- **SSID decoding.** iw prints non-printables, edge spaces and `\` as `\xNN`.
  ```python
  raw = re.sub(rb"\\x([0-9a-fA-F]{2})", lambda m: bytes([int(m[1], 16)]), ssid.encode("utf-8", "surrogateescape"))
  s = raw.decode("utf-8", "replace"); s = "".join(ch for ch in s if unicodedata.category(ch) != "Cc")[:32]
  ```
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
frame on  <=> alert active and (mismatch persists or now < clear_at)
'!!' line <=> alert_seen_this_run (stays until daemon exit) or a restored active alert
```

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
- Keys: `iw:timeout`, `iw:missing`, `iw:parse`, `route`, `arp`, `wireless`, `ioctl`, `gwjson`, `scan`.

## 6. Ordered implementation tasks

| # | Task | Satisfies ACs |
|---|---|---|
| T0 | Back up (§7). Create the scratch work dir. Build or reuse QA's sandbox harness (`qa-instructions.md` §5) for self-testing. | – |
| T1 | Path/env hooks (§4). Replace every hard-coded `/sys/class/net` and `/proc/net`. Add `ADDRS_FILE` and `ALERT_HOLD`. | AC-22 |
| T2 | Per-tick sampler + delta rule + per-key smoothing with zero-fill (§5.1) | AC-09, AC-16, AC-17, AC-18, AC-23, AC-24, AC-25, AC-26, AC-31 |
| T3 | Per-key histories, strip manager, scales (§5.2) | AC-13, AC-14, AC-15, AC-34, AC-35, AC-36 |
| T4 | `NetGraph` renderer: strips, monitor colours, baseline, bars (§5.3) | AC-11, AC-27, AC-28, AC-29, AC-30, AC-32, AC-33, AC-37 (image) |
| T5 | Slow scan: operstate/flags/carrier/ifindex, route, arp, wireless, addresses, ip_forward, promisc (§5.4) | AC-44, AC-46, AC-38 (gateway part) |
| T6 | Async iw runner + parsers + SSID decoding + stale/unavailable (§5.5) | AC-40, AC-41, AC-38, AC-03 (sandbox) |
| T7 | Tooltip builder with escaping and glyphs (§5.7) | AC-37, AC-42, AC-43 |
| T8 | M2 alert, frame + inset rendering, gw.json, acceptance (§5.6) | AC-47, AC-48, AC-49, AC-50, AC-51 |
| T9 | Shoulds F-11 to F-16 (§5.8). If time runs out, ship without them and tell QA which are built. | AC-52 to AC-58 |
| T10 | Self-test all sandbox ACs. Deploy (§8). Run the live read-only checks AC-01 to AC-05, AC-10, AC-11, AC-19 to AC-21, AC-39, AC-45. Hand over to QA. | regression set |

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
4. If `net.txt` shows `<txt>!</txt>`: read `$D/error.log`, fix or roll back (§7), and restart again.
5. Leave the daemon running.

## 9. Definition of done

- [ ] All NEW-MUST sandbox ACs (AC-22 to AC-51) pass in your self-test. QA confirms independently.
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
