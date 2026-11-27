# panelgraph NETWORK graph: requirements

Version 1.2, 2026-11-20. Author: Business Analyst (BA).
Sources: user requests R3-R10 and NFRs; user decisions (a)-(c); the cyber security specialist's QA consultation on WLAN monitor mode (v1.2; see section 8 and `qa-instructions.md` §11); the networking and cyber security specialists' assessments, their two rounds of answers and their sign-off corrections (v1.1, see section 9); the BA's read-only checks of `~/.local/bin/panelgraph-daemon` (392 lines), `~/.local/bin/panelgraph-show` (27 lines), live sysfs/proc and xfconf on 2026-11-20.

This file is the single source of truth, together with:
- `acceptance-criteria.md`: AC-01 to AC-79. Every AC id cited here is defined there. Its "coverage map" lists the sandbox and live ACs for each aspect of the monitor-mode colour decision.
- `dev-instructions.md`: how to build it.
- `qa-instructions.md`: how to verify it, including the security specialist's QA consultation (§11, "WLAN monitor mode testing").

Where these documents disagree with the interview transcript, these documents win. The BA resolved every conflict between the specialists, recorded in section 6 "Decision log".

---

## 1. Overview

The panel graph is a cpugraph-style history of network load in the user's Xfce top panel.
- Panel: 34 px tall, X11 `:0`, 1920x1080. OS: Kali Linux, `/bin/sh` = dash.
- Panel item: xfce4-genmon-plugin 4.3, item 26, wrapper `wrapper-2.0 ... libgenmon.so 26`.
- Position: socket window 0x60000e, 142x34 at screen x=1321, y=0. The image is drawn at screen x 1322-1461, y 1-32.
- Neighbours: the cpugraph (plugin 13) to its left. Netload plugins 24 (wlan0) and 23 (wlan1) to its right, at x=1463 and x=1511.

| Component | Role |
|---|---|
| `~/.local/bin/panelgraph-daemon` | Python 3.14 + pycairo 1.29.1. Samples every 250 ms and writes `{mem,net}.{png,txt}` to `/run/user/1000/panelgraph/`. |
| `~/.local/bin/panelgraph-show net` | Run by genmon every 250 ms. Prints the genmon markup and starts the daemon if needed. |

The user's laptop is a pentest machine:
- Monitor mode (airmon-ng, giving wlan0mon/wlan1mon), VPNs, USB Wi-Fi or tethering, and lab bridges (docker0, virbr0, virbr-msf, vnet*) are normal.
- The graph must show the real NIC load correctly.
- It must make capture or monitor activity visible.
- It should surface the few security signals worth seeing, without turning the user's own pentest work into alarm noise.

### 1.1 In scope
- The NETWORK graph: image, tooltip, daemon behaviour and robustness.
- Monitor-mode visibility in a separate colour, per user decision (a).
- Security signals: PROMISC, gateway line, gateway-MAC alert; Shoulds: sustained upload, route moved, VPN.
- Test hooks for sandbox QA. The security specialist's QA consultation, per user decision (b).

### 1.2 Out of scope / needs user approval
| Item | Status |
|---|---|
| RAM graph | **Deferred.** Its panel item was removed. Do not restore it, do not add a panel item, do not change `mem` rendering. The daemon keeps rendering `mem.{png,txt}` unchanged; see OQ-9. |
| Adding or removing panel items | Needs user approval. None is planned. |
| Changing the genmon update period (250 ms, `xfconf /plugins/plugin-26/update-period`) | Open question OQ-1. Not changed. |
| Changing interface state (airmon-ng, `iw set type`, `ip link`, nmcli, macchanger, firewall) | Never done by Dev or QA unattended. Live monitor tests need user approval (AC-67 to AC-69). |
| Desktop notifications (S3 notify-send) | Deferred until the user approves (OQ-5). |
| Listening ports, connection counts, packet-rate alarms, MAC-randomization alerts, lab or VM traffic, "lab mode" toggle | **Will not be built.** The security specialist judged these noise for this user. |

### 1.3 Roles
| Role | Responsibility |
|---|---|
| User | Owns decisions, approves live interface-state tests, runs `sudo` commands for live tests. |
| BA | Owns these four documents. |
| Developer | Implements per `dev-instructions.md`. Must not change system state beyond replacing the two scripts and restarting the daemon via its pid file. |
| QA | Verifies per `qa-instructions.md`, unattended in a sandbox plus read-only live checks. |
| Networking specialist | Owns the data-source, classification and image-geometry design. |
| Cyber security specialist | Owns the security signals. Is **QA's consultant for WLAN monitor-mode testing** (task card in section 8). |

---

## 2. User requirements (source of truth)

| Id | User's words / meaning |
|---|---|
| R3 | "display upload and download summarized from all wlan and lan networks, showing upload and download different colors" |
| R4 | Validate with timed screenshots and "check with 'net' monitors" (netload plugins 23/24) |
| R5 | "match colors with 'Net' monitor next to graph" |
| R6 | "displaying proper wlan info in graph" |
| R7 | "displaying upload/download load on several network cards (e.g. wlan0 and wlan1) on a graph" |
| R8 | "how to display wlan0mon and wlan1mon if something is in monitoring mode. that should be visible to user." |
| R9 | Security view: "what might be important to user to see ... to see strange activity" |
| R10 | User request (verbatim): "add task fo cyber security agent to assist/consult QA on how to check WLAN in monitor mode. BA should document everything. In Monitor mode graph should dislpay traffic in a different collor." It led to UD-a, UD-b and UD-c below. |
| UD-a | Monitor-mode traffic is drawn in a **different colour** from managed download #FF4F00 / upload #FFE500, clearly visible on the dark panel (bg ~#293650), and is **never** added to the managed sum. |
| UD-b | The cyber security specialist consults QA on checking WLAN monitor mode. QA gets an unattended sandbox procedure, plus a live procedure that needs user approval. |
| UD-c | The BA documents everything: current and future functions, decisions, the monitor colour design and the security QA guidance. |
| NFR-1 | Never freeze the panel item. |
| NFR-2 | Auto-recover after the daemon is killed. |
| NFR-3 | No respawn storms. |
| NFR-4 | Cheap: runs 4x/s forever, no per-tick process spawns (one spawn per ~5 s is acceptable), prefer /proc, /sys, netlink. |
| NFR-5 | Numbers match the /sys counters. |
| NFR-6 | Survive Wi-Fi switch, hot-plug and suspend. |
| NFR-7 | Errors are visible. |

Earlier user decisions:
- Focus on finalising the NETWORK graph.
- The RAM graph is deferred.
- The genmon period stays as is (OQ-1).
- Panel items need approval.

---

## 3. CURRENT FUNCTIONALITY (as-built, 2026-11-20)

Markers:
- [N] confirmed by the networking specialist.
- [S] confirmed by the cyber security specialist.
- [BA] confirmed by the BA in the code or live system.

Line numbers refer to the current `panelgraph-daemon`.

### 3.1 Data sources [N][S][BA]
- **Interface selection**, `physical_ifaces()` lines 52-71:
  - An interface is counted when `/sys/class/net/<if>/type == 1` (ARPHRD_ETHER) and `/sys/class/net/<if>/device` exists.
  - The list is refreshed every 20 ticks (~5 s, line 284).
  - Live, it counts `eth0` (e1000e), `wlan0` (iwlwifi, phy0) and `wlan1` (mt76x2u USB, phy1).
  - Excluded: `docker0`, `virbr0`, `virbr-msf` and `vnet16/17` (type 1, no device link), and `lo` (type 772).
  - Excluded by construction: VPN tun/wg, VLAN, bond and macvlan (no device link; their traffic is counted once on the underlying NIC), and monitor-mode interfaces (type 803).
  - Included: USB tethering (rndis/cdc_ether/ipheth: type 1 with device link).
- **Counters** (`read_counters()` lines 84-93): `statistics/rx_bytes` and `tx_bytes` (64-bit), read every tick for the interfaces in the last 5 s list.
  - Only interfaces present in both consecutive samples count.
  - A negative delta, such as a counter reset, counts as 0.
  - A vanished interface is skipped silently.
  - The wlan1 counters update per packet, so they are not lazy [N].
- **Up/down**: `operstate` in {up, unknown} counts as up, read every 5 s. It is used only for the tooltip name list.

### 3.2 Rates, smoothing, units [N][BA]
- Sample interval 0.25 s (`INTERVAL`) on the monotonic clock.
- Rate = bytes over the last 4 samples / their summed time (`NET_SMOOTH=4`, about 1 s).
- Units are 1024-based (KiB/s), matching netload `Values_As_Bits=false`.
- `human()` formats `0 B/s`, `10.9 KiB/s`, `1.2 MiB/s`.

### 3.3 Scale [N][BA]
- One linear scale is shared by down and up: `max(64 KiB/s, every rx and tx value in the 128-sample history)`. The history covers 32 s.

### 3.4 Image (net.png) [N][S][BA]
- 140x32 px, ARGB32, transparent background. Anti-aliasing off.
- Columns:

| x | Content |
|---|---|
| 0-3 | Current-value **download bar**, #FF4F00 |
| 4-5 | Gap, transparent |
| 6-9 | Current-value **upload bar**, #FFE500 |
| 10-11 | Gap, transparent |
| 12-139 | History, 1 px per 250 ms sample, newest at x=139. With fewer than 128 samples the history is right-aligned. |

- Column height = `max(1, round(min(1, v/scale) * 32))` for any nonzero value, else 0, drawn from row 31 upward.
- In each column the larger value is painted first, so the smaller stays visible on top.
- Colours: download #FF4F00 = rgb(255,79,0); upload #FFE500 = rgb(255,229,0). They equal netload `Color_In` and `Color_Out` in `~/.config/xfce4/panel/netload-23.rc` and `netload-24.rc` (R5) [BA].
- The PNG is re-rendered only when bar or column heights change. It is written atomically (`.tmp` + `os.replace`).

### 3.5 Tooltip and markup (net.txt) [BA]
- Format: `<img>/run/user/1000/panelgraph/net.png</img><click>xfce4-taskmanager</click><tool>…</tool>`.
- The tooltip text is html-escaped as a whole (`quote=False`), and genmon renders it as Pango markup.
- Lines:
  1. Comma-separated up interfaces, or `no interface up` / `no network interfaces`.
  2. `Down: X`
  3. `Up: Y`
  4. `Scale: Z`
- Live: `wlan1 / Down: 2.1 KiB/s / Up: 1.5 KiB/s / Scale: 72.5 KiB/s`.
- **Click** runs `xfce4-taskmanager`.

### 3.6 Lifecycle [BA]
**panelgraph-show** (shell builtins only on the hot path):
- Reads `pid`, checks `/proc/<pid>/comm == panelgraph` and `/proc/<pid>/cwd -ef $d`.
- If that fails and `flock -n lock` succeeds, it starts the daemon with `setsid -f … </dev/null >/dev/null 2>&1`.
- Touches `seen` (`true 2>/dev/null > "$d/seen"`).
- Prints `$d/net.txt` with a `read` loop, or `<txt>…</txt>` if the file is missing.

**Daemon start:**
- Closes inherited fds 3..SC_OPEN_MAX. Genmon waits for EOF on pipes, and leaked fds froze the panel before.
- `makedirs`, `chdir(DIR)`, `flock(LOCK_EX|LOCK_NB)` on `lock`. If the lock is held, it exits quietly.
- Sets comm to `panelgraph`, installs a SIGTERM handler that exits 0, and writes the pid file atomically.

**Each tick:**
- `lost_lock()`: exits if the lock path no longer names the held inode.
- Every 20 ticks: rescans interfaces and runs `ensure_pidfile()`.
- Renders mem, then net. Each has its own try/except.
- Idle exit: if the `seen` mtime is unchanged for more than 30 s of monotonic time.

**Exit:** removes the pid file if it still holds our pid.

**Errors:**
- A failing graph writes `error.log` with timestamp and traceback. `write_fallback` overwrites the file, so it holds **only the most recent error** [BA].
- The graph's txt is replaced by `<txt>!</txt>` with a tooltip `panelgraph net error: … see …/error.log`.
- The graph retries after 5 s (`ERROR_RETRY`).
- On a fatal error outside the per-graph handlers: logs, shows "!" on both graphs and holds the lock for 30 s (`FATAL_HOLD`) so genmon cannot respawn it 8x/s.

### 3.7 Robustness guarantees today [N][S][BA]
- No pipe leak to genmon. One instance via flock. A stale or reused pid is detected via comm+cwd.
- Recovery after kill or kill -9 within about one genmon period.
- The idle clock is monotonic, so wall-clock jumps and suspend do not cause a false idle exit.
- Hot-unplug is tolerated: a vanished interface is skipped, and a counter reset counts as 0.

### 3.8 Cost [BA]
- Daemon about 1.0 % of one core, RSS 19 MB (pid <pid>, measured 2026-11-20).
- No process spawns.
- The wrapper uses shell builtins only when the daemon is healthy.

### 3.9 Known deviations and defects of the as-built graph
| Id | Description | Confirmed |
|---|---|---|
| DEF-01 | **In-place monitor switch leaks captured bytes into the managed sum.** `type` is checked only in the 5 s rescan, but counters are read every tick. After `iw dev wlanX set type monitor` (same name, type 1→803), captured frames count as **download** for up to 5 s, plus the delta across the switch. This violates UD-a. Fix: F-01. | [N][BA] |
| DEF-02 | **Monitor mode is invisible.** A monitor card silently disappears from the sum and the tooltip (fails R8). Fix: F-04. | [N][S][BA] |
| DEF-03 | The tooltip has no Wi-Fi details (SSID, signal, channel, IP, gateway), no per-card numbers and no security lines (fails R6, R7, R9). Fix: F-05 to F-09. | [N][S] |
| DEF-05 | **No sandbox test hooks (BLOCKER for QA).** The deployed daemon (pid <pid>) uses none of the `PANELGRAPH_*` variables and hard-codes `/sys/class/net` (lines 58, 64, 69, 78, 87). Monitor mode therefore cannot be tested without changing real interfaces. Until F-02 is built, every sandbox monitor AC is BLOCKED, and runs on a sed-patched copy count only as `SMOKE`. Fix: F-02 (dev task T1, first). | [S][BA] |
| DOC-01 | **Forwarding counts twice.** `ip_forward=1` permanently here (docker/libvirt). Traffic routed between two physical NICs (hotspot, MITM bridge) appears as both down and up, so the sum means "NIC throughput", not "internet usage". Shown conditionally by F-13. | [N][S] |
| DOC-02 | Cellular modems (qmi_wwan/mbim, type 65534) are not counted. Fix: F-15 (Should). | [N] |
| DOC-03 | A NIC moved into another network namespace disappears from the graph. Accepted. | [N] |
| DOC-04 | Interfaces are tracked by name. A rename or fast replug is tolerated only through the `max(0, …)` clamp. Fix: F-16 (Should). | [N] |
| DOC-05 | The daemon still renders `mem.{png,txt}` 4x/s although no panel item shows them. Accepted under the RAM deferral (OQ-9). | [BA] |

### 3.10 Live security baseline observed (read-only) [S][BA]
- `netdiscover` pid <pid> has been running about 22.5 h. Parent: sudo <ppid>. It holds 2 raw sockets on wlan0 and keeps wlan0 **promiscuous**: `/sys/class/net/wlan0/flags = 0x1103`, admin UP, operstate down, carrier_changes 25. `ip link` does **not** show PROMISC for socket-held promisc, so the sysfs `flags` file is the reliable source. User decision: OQ-4.
- Default route: wlan1 via 192.168.1.1, metric 603. Gateway MAC aa:bb:cc:dd:ee:01 (REACHABLE, flags 0x2). BSSID aa:bb:cc:dd:ee:02, SSID HomeNet, ch44 5220 MHz/80, -27 dBm, IP 192.168.1.25. wlan1 carrier_changes 14, ifindex 4.
- Bridge ports (vnet16/17) are always promiscuous (0x1303) and are ignored by design.
- TX drop totals are nonzero (wlan0 191, wlan1 96, vnet16 40321), so only deltas may ever be used.
- NetworkManager assigns MACs by software on wlan0 and wlan1 (`addr_assign_type 3`; wlan0 permaddr aa:bb:cc:dd:ee:03), so MAC-change alerts would be noise.

---

## 4. FUTURE FUNCTIONALITY

MoSCoW priority. One developer pass delivers all **Must** items. **Should** items follow in the same pass if time allows; otherwise in a second pass. **Could** items are backlog. **Deferred** items need a user decision first.

### 4.0 Common definitions (binding for all F-items)

**Paths and test hooks.** Every sysfs/proc path comes from a constant overridable by environment. Defaults are the real paths.

| Env var | Default | Used for |
|---|---|---|
| `PANELGRAPH_SYSNET` | `/sys/class/net` | all per-interface files |
| `PANELGRAPH_PROCNET` | `/proc/net` | `route`, `arp`, `wireless` |
| `PANELGRAPH_IPFORWARD` | `/proc/sys/net/ipv4/ip_forward` | forwarding note |
| `PANELGRAPH_IW` | `shutil.which("iw")`, else `/usr/sbin/iw` | iw executable (genmon's PATH may lack /usr/sbin) |
| `PANELGRAPH_ADDRS` | unset, meaning use the SIOCGIFADDR ioctl | file of `ifname a.b.c.d` lines, used instead of the ioctl (sandbox; real names like wlan1 would otherwise leak the live IP) |
| `PANELGRAPH_ALERT_HOLD` | `600` (s) | M2 frame hold after the MAC returns to baseline |
| `XDG_RUNTIME_DIR` | already supported | output dir `$XDG_RUNTIME_DIR/panelgraph` |

**Interface classification**, evaluated **every tick** (F-01) [N][S agreed]. `has_dev` = `<if>/device` exists; `has_phy` = `<if>/phy80211` exists.
- Both links (and the phy name) are checked when a name is first seen, **and re-checked for every name in each 5 s slow scan**. Both positive and negative results are refreshed (D-32).
- Reason: with a per-tick `listdir`, a name can be listed in the short window after the kernel creates `/sys/class/net/<if>` but before it adds the `device` link (device_add) or the `phy80211` link (cfg80211 NETDEV_REGISTER notifier). This happens, for example, when `airmon-ng stop` re-creates wlan0. A negative result cached at that moment would be permanent for the netdev's lifetime: a NIC with no device link would never be counted, and a Wi-Fi card with no phy80211 link would be treated as wired (no Wi-Fi details, `no carrier` wording). Today's code re-checks every 5 s (`physical_ifaces()`, line 284), so caching until the name disappears would be a regression.
- Consequence: an interface whose links appear late is classified correctly within ≤ 5 s (T5). A link change flips the kind, which discards that tick's delta (delta rule below). Cost: 2 `exists()` calls + 1 small read per name per 5 s, negligible.
- The sandbox cannot reproduce the race (`make_iface()` renames a fully built directory), so this rule is verified by code review only (AC-22 static part).

| Kind | type | has_dev | has_phy | Managed sum | Drawn as | Tooltip |
|---|---|---|---|---|---|---|
| Ethernet | 1 | yes | no | **yes** | managed strip | yes |
| Managed Wi-Fi (station) | 1 | yes | yes | **yes** | managed strip | yes, Wi-Fi details |
| AP / mesh / IBSS vif | 1 | yes | yes | **yes** | managed strip | yes, `[AP]`/`[mesh]`/`[IBSS]` (F-14) |
| USB tethering (rndis/cdc_ether/ipheth) | 1 | yes | no | **yes** | managed strip | yes |
| **Monitor** | **801, 802 or 803** | yes **or** has_phy | usually | **NO, never** | **monitor strip** | `MONITOR …` line |
| wwan modem | 65534 | yes | no | yes (Should F-15; ignored until built) | managed strip | yes |
| tun / wg VPN | 65534 | no | no | no | not drawn | `VPN wg0 up` (Should F-12) |
| ppp | 512 | no | no | no | not drawn | `ppp0 up` (Could F-17) |
| bridge / veth / vnet / docker / virbr* | 1 | no | no | no | not drawn | never |
| lo | 772 | no | no | no | not drawn | never |

- Monitor rule: `type ∈ {801, 802, 803} and (has_phy or has_dev)`.
- Promisc rule: `type == 1 and has_dev and flags & 0x100 (IFF_PROMISC)`, checked even when the interface is down. A monitor interface never gets a PROMISC line.

**Delta rule** (F-01) [N][S]. Each tick, for each candidate interface (has_dev or has_phy), read in this order:
1. `statistics/rx_bytes`, `statistics/tx_bytes` and `statistics/rx_packets`, **for every candidate** (not only for interfaces that were monitor at the previous tick)
2. then `type`
3. then `flags` (monitor interfaces only, for the IFF_UP bit)

Why `rx_packets` is read for every candidate (D-31): if it were read only when the previous kind was monitor, the tick on which an interface first becomes monitor (an in-place switch or a new vif) would store 0 as the packet baseline. On the next tick the kind is unchanged, so the frame delta would be the whole lifetime counter (live wlan0: 13,871,277), and the tooltip would show about `13871.3k fr/s` for 1 s. The cost is one extra small read per candidate per tick (3 live).

- A delta is credited to class C (managed or monitor) only if the interface had class C at both the previous and the current read.
- If the class changed, or the interface is new this tick, the delta is discarded and the current values become the baseline.
- A negative delta counts as 0.
- An interface that vanished (read fails) is dropped with no error.
- Consequence: captured bytes are never in the managed sum, not even on the switch tick. At most 250 ms of managed bytes is lost at a switch, which is negligible because the switch needs the link down.

**Rates.** As today: 1 s smoothing (4 samples) per interface, per direction, KiB units.

**Sample index.** `abs_idx` counts samples since daemon start. The monitor baseline dot pattern uses it.

### 4.1 Image layout v2: 140x32 px, unchanged width [N][S]

**Content box:**
- Normal: x 0-139, y 0-31 (H=32).
- **While the M2 alert is on:** x 1-138, y 1-30 (H=30), and a frame is drawn (see below). Decision D-11.

**Columns** (x0 = 0 normal, 1 during alert):

| Element | Normal x | Alert x |
|---|---|---|
| down / captured-rx current bar (4 px) | 0-3 | 1-4 |
| gap | 4-5 | 5 |
| up / injected-tx current bar (4 px) | 6-9 | 6-9 |
| gap | 10-11 | 10 |
| history, 128 columns, newest right | 12-139 | 11-138 |

**Strips** (horizontal bands, R7):
- n = number of active strips, at most 3. Separator rows are fully transparent (alpha 0) across the content width.
- Formula: `usable = H − (n − 1)`, `base = usable // n`, `extra = usable % n`. Strip k (0 = top) has height `base + (1 if k ≥ n − extra else 0)`.

| n | Normal rows (H=32) | Alert rows (H=30) | Separator rows normal / alert |
|---|---|---|---|
| 1 | 0-31 | 1-30 | – |
| 2 | 0-14, 16-31 | 1-14, 16-30 | 15 / 15 |
| 3 | 0-9, 11-20, 22-31 | 1-9, 11-19, 21-30 | 10, 21 / 10, 20 |

**Strip order:**
- Managed strips come first, sorted by interface name (eth0 < usb0 < wlan0 < wlan1), then the monitor strip, always at the bottom.
- With a monitor strip, at most 2 managed slots; without one, 3.
- If more managed cards are active than slots, the last managed slot becomes **"other"**: the sum of that card and all later cards.

**Inside a strip** of height h with bottom row yb:
- value height = `max(1, round(min(1, v/scale) · h))` for v > 0, else 0, drawn from yb upward.
- Each strip has its own current-value bars at the bar x positions, within the strip rows, showing that strip's newest values.
- Paint order per column: monitor baseline (if any) first, then the larger of the two values, then the smaller.

**Managed strips:**
- Colours: down #FF4F00, up #FFE500. **One shared managed scale** = `max(64 KiB/s, all rx/tx values of all managed strips' visible history)`.
- Key = interface name. The "other" strip is keyed "other".

**Monitor strip** (UD-a), at most one, aggregating all monitor vifs:

| Element | Colour | Contrast vs #293650 |
|---|---|---|
| captured rx columns and bar | **#FF00FF** (magenta) | 3.9:1 |
| injected tx columns and bar | **#FFA0FF** (light magenta) | 6.8:1 |

- Own **monitor scale** = `max(64 KiB/s, monitor rx/tx history)`, so heavy capture never flattens the managed strips.
- For comparison: orange 3.7:1, yellow 9.5:1, cpugraph cyan 9.2:1.
- Magenta and orange have nearly equal luminance and differ by hue. They stay distinguishable for protan and deutan vision. For tritan vision the strip position and the tooltip compensate [N][S].
- **Monitor baseline:** 1 px #FF00FF on the monitor strip's bottom row, in **history columns only** (not under the bars, not in the gaps), for every column whose monitor state is not `none`:
  - state `up` (any monitor vif has IFF_UP): pixel lit.
  - state `down` (monitor vifs exist, none up): lit only when that column's `abs_idx % 2 == 0`. The dotted line scrolls cleanly.
  - Monitor state is stored per column (none/down/up, 1 byte).

**Strip lifetime (hysteresis):**
- Managed strip for card X: active while X's `operstate ∈ {up, unknown}` (5 s scan) **or** X's 128-sample history contains a nonzero value. It appears on the first tick the condition holds. It disappears when both are false, which happens at most 32 s after traffic stops.
- Monitor strip: active while any monitor vif exists (even if down) **or** any column's monitor state ≠ none **or** any monitor rx/tx value in the 128-column history is nonzero (D-33). It appears on the first tick a monitor vif is seen (≤1 tick).
  - Why the third condition: the state drops to none on the tick the last vif disappears, but the 1 s smoothing window keeps the monitor rx/tx nonzero for about 3 more ticks. Without it, the strip would vanish when the last state ≠ none column scrolls out while nonzero captured columns are still in the history, and those columns would be dropped as the layout changes. This matches the managed rule. The strip still disappears 32-34 s after the switch back (AC-32).
- A new strip's history starts as zeros (no state), so all strips stay column-aligned.
- No strip active at all: one empty full-height managed view. Bars 0, scale 64 KiB/s.
- Monitor active and no managed strip: the monitor strip takes all rows. No empty managed strip.

**Single managed strip:** exactly today's look. Its values equal the Total line, because a card without a strip contributed 0 bytes in the window [N].

**R3 vs R7** (D-18): R3 ("summarized") is met by the shared managed scale plus the always-present `Total` tooltip line. With 2+ managed strips the image shows per-card strips (R7).

**M2 alert frame** (F-09):
- While the alert is on, every pixel with `y == 0 or y == 31 or x == 0 or x == 139` is opaque **#FF2020**: 340 pixels.
- Content is drawn inside x 1-138, y 1-30 with H=30, so nothing is hidden.
- #FF2020 is used nowhere else, so any #FF2020 pixel is a frame pixel, and no content pixel may ever be #FF2020.
- The frame shape, not its hue, is the cue (colour-vision safe).

**Removed proposals:** the 2 px magenta top band and the 4 px status slot (D-08).

### 4.2 Tooltip v2 [N][S]
genmon 4.3 calls `gtk_widget_set_tooltip_markup` (libgenmon.so imports it) [N], so the tooltip is **Pango markup**.

**Escaping rules (security-relevant):**
- Every interpolated untrusted string is passed through `html.escape(s, quote=False)` individually: interface names, SSID, MACs, iw strings, error texts.
- The markup (`<span>`, `<b>`) is added after escaping and is never escaped itself.
- Never escape the whole assembled tooltip.
- SSID handling:
  1. Decode iw's `\xNN` escapes to bytes.
  2. UTF-8 decode with `errors="replace"`.
  3. Remove control characters (Unicode category Cc, including newline).
  4. Truncate to 32 characters.
  5. Escape.
- Rationale: the SSID is attacker-controlled. An unescaped `</tool><click>cmd</click>` would inject a genmon click command, and a bad `&` blanks the tooltip.

**Glyph legend:** `■` (U+25A0) wrapped in `<span foreground="#RRGGBB">`.

| Glyph | Colour |
|---|---|
| managed down | #FF4F00 |
| managed up | #FFE500 |
| monitor captured | #FF00FF |
| monitor injected | #FFA0FF |

**Template**, top to bottom. Optional lines appear only when they apply. Worst case is 10 lines.

| # | Line | When |
|---|---|---|
| L1 | `<b>!! Gateway MAC changed HH:MM aa:bb:cc:dd:ee:01 → de:ad:be:ef:00:01 via wlan1</b>`, then ` \| Default route moved wlan1→eth0 HH:MM` if both. Or `Gateway MAC accepted HH:MM` (10 min after acceptance). | alert, route move or acceptance |
| L2 | `■■ Total ↓ 512.0 KiB/s ↑ 128.0 KiB/s   Scale 512.0 KiB/s` (■ in down/up colours) | always; replacements below |
| L3-L5 | One line per strip, top to bottom. Position label `top`/`mid`/`bottom` only when 2+ strips. Managed Wi-Fi: `top  wlan1 ★ HomeNet -27 dBm ch44 5220 MHz/80  rx 780/tx 867 Mbit/s  ↓ 10.9 KiB/s ↑ 10.0 KiB/s`. Wired: `top  eth0 ★  ↓ … ↑ …`. Other: `mid  other: usb0+wlan1  ↓ … ↑ …`. Card with history but now down: `wlan0 (down)  ↓ … ↑ …`. | per strip |
| (strip line) | Monitor: `bottom  ■ MONITOR wlan0mon (phy0, ch44 5220 MHz, up)  ■ captured 1.2 MiB/s  ■ injected 0 B/s  1.2k fr/s · not in total · Mon scale 2.0 MiB/s`. Several vifs: see "MONITOR line with several vifs" below. Strip present only from history: `bottom  monitor ended HH:MM:SS`. | monitor strip |
| L6 | `Gateway 192.168.1.1 aa:bb:cc:dd:ee:01 via wlan1, IP 192.168.1.25`. Unknown parts are `?`. Or `No default route`. | always |
| L7 | `PROMISC wlan0 (packet capture running)` (names comma-joined) | promisc NIC exists |
| L8 | Segments joined by ` · `: `VPN wg0 up` (F-12), `Sustained upload 3m20s` (F-11), `Up 5 min 12.3 MiB` (F-11, always once F-11 is built) | any segment |
| L9 | `Forwarding on: traffic routed between wlan1 and eth0 is counted on both` | F-13 condition |
| L10 | `Idle: eth0 no carrier · wlan0 not connected` (physical managed NICs without a strip) | any idle NIC |

**MONITOR line with several vifs** (D-34). R8 names wlan0mon **and** wlan1mon; two vifs on different phys and channels is the common pentest setup.
- One monitor strip and one MONITOR line, whatever the number of vifs.
- Each vif gets its own parenthesised group `<name> (<phy>, ch<N> <F> MHz, <state>)`; groups are sorted by name and joined by ` + `. The captured, injected and fr/s figures that follow are sums over all vifs.
- Example: `bottom  ■ MONITOR wlan0mon (phy0, ch44 5220 MHz, up) + wlan1mon (phy1, ch6 2437 MHz, down)  ■ captured 512.0 KiB/s  ■ injected 0 B/s  1.0k fr/s · not in total · Mon scale 512.0 KiB/s`.
- `<state>` per vif: `up` if that vif's `flags` has IFF_UP (0x1), else `down`. It is **never** derived from `operstate`: real mac80211 monitor vifs report operstate `unknown`.
- If `iw dev` gives no channel for a vif (typical for an admin-down vif, or before the first iw result), the channel part is omitted: `wlan1mon (phy1, down)`.
- The aggregate baseline (4.1) is solid if **any** vif is up, dotted if all are down.
- This applies equally to an in-place switched name (`wlan0 (phy0, …)`).

Notes on the strip lines:
- `★` marks the default-route interface.
- Signal comes from `/proc/net/wireless`, falling back to iw link. The interface column of `/proc/net/wireless` is right-aligned with leading spaces (live: ` wlan1: 0000   70.  -27. …`), so the name must be stripped before matching. Channel, frequency and width come from `iw dev`. Bitrates come from `iw link`, rounded to integers.
- **SSID source** (D-35): the `ssid` line of `iw dev`; if `iw dev` has no `ssid` line for that interface, the `SSID:` line of `iw dev <if> link`. Both parsers pass the SSID through the **same** function: decode `\xNN` → UTF-8 with replace → strip Unicode Cc → truncate to 32 → escape (rules above). Both use iw's `\xNN` escaping, so both are attacker-controlled input.
- Unavailable Wi-Fi details: the last good values are kept with ` (stale Ns)` for up to 30 s. After that the line reads `wlan1 ★ Wi-Fi details unavailable (iw missing|timeout|parse)  ↓ … ↑ …`.
- The `fr/s` figure comes from the monitor `rx_packets` delta (informational).

Idle-state wording for L10:
- Wired: admin-up and operstate down → `no carrier`; admin-down → `down`.
- Wi-Fi: admin-up and operstate down → `not connected`; admin-down → `down`.

**Line-count guarantee:** at most 3 strip lines (managed plus monitor) + L1 + L2 + L6-L10 = 10.

**L2 replacements:**

| Condition | L2 text |
|---|---|
| monitor strip present, no managed strip | `No managed link (capture only)` |
| physical NICs exist, no strip at all | `No managed interface up` |
| no physical NIC at all | `No network interfaces` |

**Fallback** if Pango markup ever fails to render (OQ-8): the same lines in plain text, with `[DOWN]` `[UP]` `[MON]` `[INJ]` `[!!]` tags instead of glyphs.

### 4.3 Feature list

#### MUST

| Id | Feature | Traces | Agreed design (summary; full spec in 4.0-4.2 and dev-instructions) | Data source / cost | Confirmed | ACs |
|---|---|---|---|---|---|---|
| F-01 | **Per-tick classification + delta rule** (fixes DEF-01) | UD-a, R3, R8, NFR-5/6 | `listdir(SYSNET)` every tick. has_dev/has_phy checked on first sight and re-checked for every name in the 5 s scan (D-32). Read rx_bytes, tx_bytes and rx_packets for every candidate, then type, each tick; flags for monitor vifs (D-31). Class-change → discard + rebaseline. New interfaces visible within 1 tick. | listdir + ~13 small reads/tick ≈ 0.35 ms ≈ 0.14 % CPU [N measured 0.31 ms for ~10 reads; +3 rx_packets reads] | N, S, BA | AC-23, AC-24, AC-25, AC-26, AC-09 |
| F-02 | **Sandbox test hooks** (M4). **Blocker for all sandbox monitor tests** (DEF-05). | UD-b, NFR-7 | Env vars in 4.0. Defaults equal the real paths. No other behaviour change. Every per-interface path and the phy name are built from `SYSNET`; nothing else is hard-coded (D-40). | none | S, N, BA | AC-22, AC-79 |
| F-03 | **Per-card strips** | R7, R3 | 4.1 geometry, ordering, "other" slot, hysteresis, shared managed scale, per-strip bars | per-strip deques of 128 (rx, tx), negligible | N, S | AC-34, AC-35, AC-36, AC-15 |
| F-04 | **Monitor-mode strip in its own colours** | R8, R10, UD-a | Bottom strip. #FF00FF captured rx, #FFA0FF injected tx, own scale (64 KiB/s floor), magenta bars, solid/dotted baseline. Never in the managed sum or S1. Detection by type + link, never by name. Summary card: 4.6. | per tick | N, S | AC-27 to AC-33, AC-37, AC-76, AC-77, AC-78, AC-79; live AC-67 to AC-69 |
| F-05 | **Wi-Fi info in tooltip** | R6 | Per-strip Wi-Fi line, ★ default, gateway line (merged with F-08) and IP (ioctl SIOCGIFADDR). **Never nmcli**: a rescan took 15 s, and it dies after `airmon-ng check kill`. iw runs asynchronously, alternating `iw dev` / `iw dev <wifi> link` every 10 s each (≤1 spawn per 5 s), 1 s kill timeout, never two at once. | `/proc/net/route`, `/proc/net/wireless`, ioctl every 5 s; iw ≈1.4-2 ms per spawn | N, S | AC-38, AC-39, AC-40, AC-41 |
| F-06 | **Tooltip v2 with safe escaping and glyph legend** | R6, R7, R8, R9, NFR-1 | 4.2 template, ≤10 lines, Pango-valid | per tick string build | N, S | AC-42, AC-43, AC-37 |
| F-07 | **PROMISC line** (tooltip only, no pixels) | R9 | `PROMISC <if> (packet capture running)` for type 1 + device + IFF_PROMISC. vnet/bridge ports ignored. | `flags` in the 5 s scan, 0.35-0.42 ms [S measured] | S, N | AC-44, AC-45, AC-70 |
| F-08 | **Gateway line** (M3 merged with R6) | R6, R9 | `Gateway <ip> <mac> via <if>, IP <addr>`. Default route = `/proc/net/route` row with Destination 00000000, Mask 00000000, flags & RTF_UP (0x1), lowest Metric. Gateway IP from the Gateway column if flags & RTF_GATEWAY (0x2), else `?`. MAC from the `/proc/net/arp` row with IP == gw, Device == iface, flags & 0x2, else `?`. | 5 s scan | S, N | AC-38, AC-39, AC-46 |
| F-09 | **Gateway MAC change alert** (M2) | R9 | See 4.4. Red frame (#FF2020, 340 px, content inset) + `!!` line, persisted in `gw.json`, accepted via `rm`. | 5 s scan, plus one extra `iw link` on a first mismatch (rare) | S, N | AC-47 to AC-51 |
| F-10 | **Robust auxiliary-data handling** | NFR-1, NFR-7 | iw, ioctl, route, arp and wireless failures never raise to the graph handler. Tooltip shows stale/unavailable markers. `error.log` gets one entry per distinct error key per 10 min, **without** the "!" marker. The "!" marker stays only for rendering/IO failures of the graph itself (as today). | – | N, BA | AC-41, AC-08 |

#### SHOULD

| Id | Feature | Traces | Design | Confirmed | ACs |
|---|---|---|---|---|---|
| F-11 | **S1 sustained upload + Up 5 min** | R9 | Two `deque(maxlen=300)` of 1 s buckets (managed rx, managed tx) with running sums (about 5 KB, O(1)). Condition: last 60 s average managed tx > 256 KiB/s **and** tx_sum(60 s) > rx_sum(60 s). While true, show `Sustained upload <m>m<ss>s` = seconds since the condition became continuously true + 60. Always show `Up 5 min <human bytes>` (sum of the tx buckets, or since start if shorter). Managed tx only, never monitor-injected tx. Resets on daemon restart. | S | AC-52 |
| F-12 | **S2 default route moved + VPN line** | R9 | `Default route moved <oldif>→<newif> HH:MM` when (iface, gw) of the default route changed between 5 s scans and the old iface's carrier_changes did not change. Shown 10 min in L1. `VPN <names> up` for type 65534 without device link with operstate up/unknown. Tooltip only, never in the sum. | S, N | AC-53, AC-54 |
| F-13 | **Conditional forwarding note** | R3 (DOC-01) | L9 when `ip_forward == 1` **and** ≥2 managed NICs (type 1 + device) have operstate up. Names = the first two up managed NICs by name. Never counts monitor vifs. Hidden today (only wlan1 up). | S; N accepted | AC-55 |
| F-14 | **AP/mesh/IBSS flag** | R6, R9 | From `iw dev` type: `AP`→`[AP]`, `mesh point`→`[mesh]`, `IBSS`→`[IBSS]`, `P2P-GO`→`[AP]` after the interface name. | N; S agreed | AC-56 |
| F-15 | **wwan modems counted** | R3 (DOC-02) | type 65534 **with** a device link is classed managed | N | AC-57 |
| F-16 | **ifindex tracking** | NFR-6 (DOC-04) | Read `ifindex` in the 5 s scan. On change, discard that interface's delta and rebaseline (history kept). | N | AC-58 |

#### COULD (backlog; built only if the user asks)
| Id | Feature | Design | ACs |
|---|---|---|---|
| F-17 | ppp line | `ppp0 up` in L8 for type 512 interfaces | AC-59 |
| F-18 | C1 errors/drops | L8 segment `Errors <if> +N` only when rx/tx errors + drops grow > 100 in 5 s | AC-60 |
| F-19 | C2 DNS change | `/etc/resolv.conf` mtime + nameserver lines compared every 5 s, L8 segment `DNS changed HH:MM` | AC-61 |
| F-20 | CLOCK_BOOTTIME deltas | Use `time.clock_gettime(CLOCK_BOOTTIME)` for rate time deltas across suspend | AC-62 |
| F-21 | nl80211 netlink instead of iw | Zero spawns | AC-63 |

#### DEFERRED (needs a user decision)
| Id | Feature | Gate | ACs |
|---|---|---|---|
| F-22 | S3 desktop notification (`notify-send`) once per M2 event | OQ-5 | AC-64 |
| F-23 | RAM graph | user deferral | AC-65 |
| F-24 | genmon update period change | OQ-1 | AC-66 |

### 4.4 F-09 gateway-MAC alert: full rule [S][N]

**Scan:** every 5 s, inside the tick % 20 block.
- Read the default route (F-08), giving `(iface, gw_ip)`.
- Read the ARP row for `gw_ip` on `iface`. Only rows with flags & 0x2 (complete) are used. A missing or incomplete entry never alerts and never updates the baseline.

**Baseline** = `{iface, gw_ip, mac, carrier_changes(iface), bssid}`. Re-baselined silently when:
1. there is no baseline yet;
2. `(iface, gw_ip)` differs from the baseline (route move; handled by F-12, not M2);
3. `carrier_changes(iface)` changed (reconnect or Wi-Fi switch);
4. the BSSID (from the latest `iw link`) changed (roam, mesh, extender);
5. both the old and new MAC are virtual-router MACs: `00:00:5e:00:01:xx` (VRRPv4), `00:00:5e:00:02:xx` (VRRPv6), `00:00:0c:07:ac:xx` (HSRP).

**Mismatch handling:**
- On a first mismatch (complete entry, MAC ≠ baseline, none of 2-5 true), the daemon requests an immediate `iw dev <iface> link` on the next tick. This run is outside the alternation and is rare.
- The **alert fires** at the next 5 s scan if the mismatch persists and the fresh BSSID equals the baseline BSSID. If iw is unavailable or the interface is wired, it fires anyway.
- Latency: ≤ 2 scans ≈ 10 s plus 1 s slack.

**While alerting:**
- Frame on, L1 `!! Gateway MAC changed HH:MM <old> → <new> via <if>`.
- The frame stays while the mismatch lasts, and for `PANELGRAPH_ALERT_HOLD` (default 600 s) after the MAC returns to baseline.
- The `!!` line stays until the daemon exits, and is restored after a restart while the persisted alert is active.

**Persistence:** `$XDG_RUNTIME_DIR/panelgraph/gw.json`.
- Fields: `iface, gw_ip, mac, carrier_changes, bssid, alert_since, alert_mac`; `alert_since` is epoch seconds or null.
- Written atomically (tmp + rename), **only when a field changes**.
- Loaded at start. If the stored `(iface, gw_ip)` equals the current one and `carrier_changes` is unchanged, it is used as the baseline; otherwise the daemon re-baselines.
- On tmpfs, so a reboot re-baselines (documented limitation).

**User acceptance** of a legitimately new router MAC: `rm -f "$XDG_RUNTIME_DIR/panelgraph/gw.json"`.
- If the file is missing at a scan while the daemon held a baseline, the daemon adopts the current MAC, clears the frame and the `!!` line, rewrites gw.json and shows `Gateway MAC accepted HH:MM` in L1 for 10 min.
- Reconnecting Wi-Fi also re-baselines (rule 3).

**Frame evaluation:** the frame on/off condition (mismatch persists, or now < `clear_at` = mismatch end + `ALERT_HOLD`) is evaluated **every tick**, not only in the 5 s scan. Otherwise the frame could last until about t1 + 30 s and fail AC-49 ("gone by t1 + 27 s"). The mismatch itself is still detected in the 5 s scan.

**Known limitations** (the user should not overrate M2):
- A cache already poisoned when the baseline is first taken cannot be detected.
- The user's own bettercap/arpspoof poisons other hosts, not this cache, so it does not trigger.
- **Re-baselining hides attacks that coincide with a reconnect.** Because the baseline is silently re-taken on a `carrier_changes` or BSSID change (rules 3 and 4), a deauth-forced reconnect to an evil twin, or ARP poisoning raced in right after a reconnect, is accepted as the new baseline without an alert. M2 detects only **in-session** poisoning of the gateway ARP entry (same link, same BSSID).
- **IPv4 only.** Only `/proc/net/arp` is watched. IPv6 NDP spoofing and rogue router advertisements are not covered.

### 4.5 Not to be built (security specialist, agreed)
- Listening ports and connection counts (msf handlers, `nc -lvnp`, kdeconnect *:1716 are normal here; would need `ss`).
- Packet-rate vs byte-rate alarms (the user's own nmap).
- MAC-randomization alerts.
- Any display of virbr-msf/virbr0/docker/vnet traffic or their promisc state.
- A "lab mode" toggle: limiting checks to physical NICs already keeps lab activity quiet.
- `carrier_changes` in the tooltip: roaming and suspend raise it, so it is meaningless to the user. It is used only internally (M2, S2).

### 4.6 Monitor-mode colour design at a glance (user decision a; D-04, D-07, D-09 to D-14, D-33, D-34)

This is a summary card for Dev and QA. The binding detail is in 4.0 to 4.2.

| Aspect | Decision |
|---|---|
| When | Any interface with `type ∈ {801, 802, 803}` and a `phy80211` or `device` link: an airmon-ng `wlanXmon`, an `iw … interface add … type monitor` vif, or `wlanX` switched in place. The interface name is never used. |
| Captured (rx) colour | **#FF00FF** magenta: history columns, the **left** current-value bar and the baseline marker. Contrast 3.9:1 on #293650. |
| Injected (tx) colour | **#FFA0FF** light magenta: history columns and the **right** current-value bar. Contrast 6.8:1. |
| Why two colours | Dark means received and light means sent, mirroring managed orange/yellow; injection, the risky action, stands out. The user may still pick one colour or another hue (OQ-2). |
| Where | One aggregated monitor strip, always at the **bottom** of the 140x32 image, below a transparent separator row. With no managed strip it takes the whole image. |
| Scale | Its own `Mon scale` = max(64 KiB/s, monitor history), so a busy channel never flattens the managed strips. |
| Marker | 1 px #FF00FF on the strip's bottom row, history columns only: solid while any vif is admin-up (IFF_UP), dotted while all are down. Never derived from operstate. |
| Sum | **Never** added to `Total`, the managed strips, S1 (sustained upload) or the forwarding note, not even on the switch tick (per-tick delta rule). |
| Tooltip | `■ MONITOR <vif> (<phy>, ch<N> <F> MHz, up\|down)  ■ captured …  ■ injected …  … fr/s · not in total · Mon scale …`. Several vifs are joined by ` + `. After the last vif goes: `monitor ended HH:MM:SS` until the strip scrolls out (32-34 s). |
| Not monitor | PROMISC never turns anything magenta (D-09); it is a tooltip line only. |
| Verified by | Sandbox: AC-23 to AC-33, AC-37, AC-76 to AC-79 (`qa-instructions.md` §11.1 to §11.6). Live, requires user approval: AC-67, AC-68, AC-69 (§11.7); injection AC-75 is deferred (OQ-12). |

---

## 5. OPEN QUESTIONS FOR THE USER

The developer implements the **RECOMMENDED** option unless the user decides otherwise.

| Id | Question | Options | RECOMMENDED |
|---|---|---|---|
| OQ-1 | Change the genmon update period of plugin 26 (now 250 ms)? | (a) keep 250 ms; (b) 500 ms; (c) 1000 ms | **(a) keep 250 ms**. The graph is designed for 1 px per 250 ms. No change to xfconf. |
| OQ-2 | Monitor-mode colours (decision a) | (a) two colours: captured #FF00FF + injected #FFA0FF; (b) one colour #FF00FF for both; (c) another hue, e.g. violet #B07CFF | **(a)**. Agreed by both specialists. Injection is the risky action and stands out; it mirrors managed dark=received / light=sent. |
| OQ-3 | Approve live monitor-mode QA on wlan0/phy0 (wlan1 never touched, no `airmon-ng check kill`)? | (a) L1 only (add a monitor vif); (b) L1 + L2 (in-place switch); (c) L1 + L2 + L3 (`airmon-ng start wlan0`); (d) none (sandbox only) | **(c)**, each step approved separately at run time and run by the user with sudo. L1 is the minimum to see the real colours. L2 answers the open "do counters survive?" question. L3 is the user's real workflow. |
| OQ-4 | The orphaned `sudo netdiscover` (pid <pid>, about 22.5 h) keeps wlan0 promiscuous. Stop it? | (a) user stops it (`sudo kill <pid>`); (b) leave it running | **(a)**. Otherwise `PROMISC wlan0` is shown permanently. Stopping it is also the live check AC-70. Agents never touch it. |
| OQ-5 | Desktop notification (notify-send) once per gateway-MAC alert (S3)? | (a) no (defer); (b) yes | **(a) defer**. Frame + tooltip are enough; avoids a spawn path and notification noise. |
| OQ-6 | Build Could items C1 (errors/drops) and C2 (DNS change)? | (a) backlog; (b) build now | **(a) backlog** |
| OQ-7 | Count cellular wwan modems (type 65534 with device link) in the sum (F-15)? | (a) yes; (b) no | **(a) yes**. They are physical NICs; tun/wg stay excluded (no device link). |
| OQ-8 | Tooltip glyph legend | (a) Pango coloured `■` glyphs; (b) plain-text tags `[MON]` etc. | **(a)**. libgenmon uses tooltip markup. QA validates with Pango; the user verifies visually in AC-71. |
| OQ-9 | The daemon still renders the removed RAM graph files 4x/s | (a) keep as is (RAM deferred); (b) stop rendering mem | **(a) keep**. Out of scope; no behaviour change for a deferred feature. |
| OQ-10 | Live gateway-MAC test (poisoning your own ARP entry with `ip neigh replace`) breaks connectivity for seconds | (a) skip, sandbox only; (b) run with approval | **(a) skip** |
| OQ-11 | Live Wi-Fi switch and suspend/resume regression checks (AC-72, AC-73) | (a) user performs them at a convenient time while QA records; (b) skip | **(a)** |
| OQ-12 | Injection test `aireplay-ng --test wlan0mon` (probe requests only, never deauth) | (a) out of scope; (b) run with separate approval | **(a) out of scope**. Injected-tx colour is verified in the sandbox (AC-29). |
| OQ-13 | **Conflict between the specialists' sign-off corrections** (section 9, items 2 and 9) on the AC-24 frame-rate test: Network asks for a packet-counter base of 5,000,000 in the sandbox and a limit of fr/s ≤ **1.1 ×** the fixture pps; Security asks for 4,000,000 and ≤ **1.05 ×**. | (a) base 5,000,000, limit 1.1 ×; (b) base 4,000,000, limit 1.05 ×; (c) base 5,000,000, limit 1.05 × | **(a)**. The base only has to be large (both values expose the bug as millions of fr/s); 5,000,000 mirrors the 5 GiB byte base. The limit must be 1.1 ×: at the 1000 pps fixture the tooltip shows `1.0k`/`1.1k fr/s`, a 100 fr/s (10 %) display step, so a correct build that shows `1.1k` (true value 1050-1099) would fail a 1.05 × limit. QA applies (a) unless the user decides otherwise. |

---

## 6. Decision log

| Id | Decision | By | Rationale |
|---|---|---|---|
| D-01 | RAM graph deferred; its panel item removed; do not restore | User | Focus on the network graph |
| D-02 | genmon update period unchanged (OQ-1) | User | Open question |
| D-03 | Adding panel items needs user approval | User | – |
| D-04 | **Monitor traffic is drawn in a different colour and never added to the managed sum** | User (a) | R8 visibility |
| D-05 | Security specialist acts as QA consultant for monitor-mode testing | User (b) | – |
| D-06 | BA documents everything (these four files) | User (c) | – |
| D-07 | Monitor colours #FF00FF (captured rx) / #FFA0FF (injected tx). The BA chose Network's #FFA0FF over Security's #FF9CFF (negligible difference; measured contrast 6.8:1). Both agreed. | N, S, BA | Dark=received / light=sent mirrors orange/yellow; injection stands out |
| D-08 | Image stays **140x32**. No 4 px status slot, no 2 px top band. | N, S | Panel layout unchanged; colour already signals monitor mode |
| D-09 | Promisc is tooltip-only. **One colour = one meaning:** magenta means monitor traffic only. | S, N, BA | netdiscover keeps wlan0 promisc permanently, which would mean alert fatigue |
| D-10 | Monitor strip has its own scale (64 KiB/s floor) and sits at the bottom | N, S | Busy-channel capture would flatten the managed graph |
| D-11 | **M2 frame #FF2020 drawn with content inset** to x 1-138, y 1-30 while alerting (Network's option ii). Security preferred painting over the content. The BA chose inset because it hides nothing (row 31 holds 1 px values and the monitor baseline, column 139 the newest sample). Security's own assertion "(139,1) is FF4F00 while (139,16) is FF2020" was inconsistent with painting over, and is consistent only with inset. | BA (N proposed) | Nothing hidden; unambiguous QA |
| D-12 | Monitor baseline drawn in **history columns only**, not under the bars. Network said "including under the bars"; Security asserted "(7,31) transparent". The BA chose history-only so the bars truthfully show 0. | BA | Unambiguous pixels |
| D-13 | Baseline solid while any monitor vif is up, dotted (`abs_idx % 2 == 0`) while all are down | S, N | Mode stays visible even when idle |
| D-14 | Monitor rule `type ∈ {801,802,803} and (phy80211 or device)`; promisc rule type 1 + device + IFF_PROMISC | N, S | Covers legacy prism/WEXT drivers |
| D-15 | Per-tick listdir + type read; read type after counters; class change = discard + rebaseline | N, S, BA | Fixes DEF-01; ≤1-tick latency; 0.12 % CPU |
| D-16 | Strip geometry formula and the ≤3-strip limit; monitor always bottom; "other" slot for overflow managed cards | N | Readable at 32 px |
| D-17 | Managed strips keyed by interface name; one aggregated monitor strip. An in-place switch therefore shows the old managed strip scrolling out plus the monitor strip. | N | Same name holds both modes |
| D-18 | R3 is satisfied by the shared managed scale + the Total line; R7 strips take precedence in the image | N, BA | 32 px cannot show both |
| D-19 | iw async via Popen + poll, 1 s kill, never two at once, alternating each 10 s; no `subprocess.run(timeout=)` | N | A D-state mt76 USB hang must never stall a tick |
| D-20 | Never use nmcli in the daemon | N | 15 s rescans; gone after check kill |
| D-21 | Forwarding note shown only when ip_forward=1 and ≥2 managed NICs are up | S; N accepted | Always-on note would be noise |
| D-22 | `carrier_changes` internal only | S, N | Meaningless to the user |
| D-23 | M2 acceptance by deleting gw.json; also re-baselines on carrier, BSSID or route change; VRRP/HSRP ranges ignored | S | Few false positives |
| D-24 | M2 debounce: confirmed on a second scan with a fresh BSSID | BA (refines S) | Avoids roam/extender race false alarms; latency ≤ 11 s |
| D-25 | S1 uses 300×1 s buckets of managed traffic only | S | 32 s history is too short |
| D-26 | S3 notify-send deferred; C1/C2 Could | S, user gate | – |
| D-27 | Sandbox hooks as env vars (4.0), including `PANELGRAPH_ADDRS` and `PANELGRAPH_IPFORWARD`, added by the BA | S, BA | A fake `wlan1` would otherwise leak the live IP via the ioctl |
| D-28 | Live interface-state tests only with user approval; never `airmon-ng check kill`; never touch wlan1 or global NM | S, user | wlan1 is the uplink |
| D-29 | Tooltip v2 template and escaping rules (4.2); the gateway appears once (M3 merged with R6) | N, S | ≤10 lines; injection-safe |
| D-30 | Error policy: auxiliary failures shown in the tooltip and rate-limited in error.log, no "!"; render/IO failures keep the "!" marker | N, BA | A silently broken monitor would be worse than none |
| D-31 | `rx_packets` is read for **every** candidate every tick, before `type` (replaces "only for monitor interfaces") | N, S (sign-off) | A 0 baseline on the first monitor tick made the next fr/s the whole lifetime counter (~13.9M live on wlan0) |
| D-32 | `device`/`phy80211` links and the phy name are re-checked for every name in the 5 s slow scan (both positive and negative results refreshed). The alternative "cache only positive results" was not chosen because it costs 2 `exists()` per non-candidate name (docker0, virbr*, vnet*, lo) per tick. | N (sign-off), BA chose the variant | A link added after the name appears (airmon-ng stop re-creates wlan0) would otherwise be missed for the netdev's lifetime; today's code re-checks every 5 s |
| D-33 | Monitor strip also stays active while any nonzero monitor rx/tx value is in the history | N (sign-off) | The 1 s smoothing tail outlives the last state ≠ none column |
| D-34 | MONITOR line with several vifs: one strip, one line, one `<name> (<phy>, ch<N> <F> MHz, <state>)` group per vif joined by ` + `, sums after; state from IFF_UP, never operstate | S (sign-off), BA format | R8 names both wlan0mon and wlan1mon; mac80211 monitor vifs report operstate `unknown` |
| D-35 | Tooltip SSID comes from `iw dev` (`ssid`), falling back to `iw link` (`SSID:`); both through one decode → strip Cc → truncate → escape function | S (sign-off), BA chose the primary source | Both sources are attacker-controlled; channel/width already come from `iw dev` |
| D-36 | M2 frame on/off evaluated every tick | S (sign-off) | AC-49 timing |
| D-37 | Live monitor tests tune the monitor to the BSS's full width (`set freq <ctrl> 80 <center1>`), not `set channel 44` (20 MHz); captured must be ≥ 50 % of the wlan1 rx rate or the leak check is INCONCLUSIVE | N, S (sign-off) | A 20 MHz receiver cannot decode 80 MHz VHT data frames, so the not-in-Total check could not fail |
| D-38 | Sandbox realism: packet counters start at a large base; monitor vifs use operstate `unknown`; one S-B variant uses type 802; `/proc/net/wireless` and `iw link` fixtures use different signal values; S-H keeps wlan0 when adding wlan0mon; J2 removes the ARP row before the carrier change | N, S (sign-off) | Each closes a gap where a buggy build would pass or a correct build would fail |
| D-39 | The security specialist's QA consultation on WLAN monitor mode (UD-b) is adopted as `qa-instructions.md` §11: the sandbox-hook gate, fixture checklist, fixtures S-B…S-U, pass checks, pitfalls, and the live run sheet. Every live step is marked **REQUIRES USER APPROVAL**. It confirms the existing design; no design change. | S (consultant), BA | One place for QA to follow; consistent with D-04 to D-38 |
| D-40 | Missing sandbox hooks in the deployed daemon are a **blocker** (DEF-05). Sandbox acceptance runs only on the developer's build with real `PANELGRAPH_*` hooks. A sed-patched copy gives `SMOKE` results only. The phy name must also be read through `SYSNET`. | S, BA | A patched copy does not prove that the shipped code honours the hooks; the real `/sys/class/ieee80211` would mask a wrong phy lookup |
| D-41 | Three new sandbox ACs from the consultation: AC-77 (vif removed while captured history is on screen), AC-78 (pixel-exact palette, no partial alpha), AC-79 (detection independent of the name, with a `mon0` vif and a type-1 decoy `wlan2mon`; phy `phy5` exists only in the fake tree) | S, BA | Closes the pitfalls "monitor detected by name", "partial alpha" and the untested vif-removal path |
| D-42 | Live AC-67 extended: the captured bar and baseline marker are checked on screen, and the `wlan0mon` rx_bytes rate is compared with the tooltip `captured` figure; after rollback, `monitor ended` and the strip scroll-out are checked. Live injection, if ever approved (OQ-12), is phy0 only, never `-0`, and the user accepts that it exposes the permanent MAC aa:bb:cc:dd:ee:03. | S, BA | Live evidence for every aspect of decision (a); safety of the uplink card |

---

## 7. Traceability matrix

| Requirement | Design items | ACs |
|---|---|---|
| R3 summed down/up, colours | 3.1-3.4, F-01, F-03, F-13, F-15, D-18 | AC-09, AC-10, AC-13, AC-14, AC-15, AC-36, AC-55, AC-57 |
| R4 timed screenshots vs netload | 3.4, QA screenshot procedure | AC-11, AC-12 |
| R5 colours match netload | 3.4 | AC-11 |
| R6 Wi-Fi info | F-05, F-06, F-08, F-14 | AC-38, AC-39, AC-43, AC-46, AC-56, AC-71 |
| R7 several cards | F-03, 4.1 | AC-34, AC-35, AC-36, AC-15 |
| R8 monitor mode visible | F-01, F-04, D-04, D-07, D-10-D-14, D-31, D-33, D-34, D-41 | AC-23 to AC-33, AC-37, AC-67, AC-68, AC-69, AC-76, AC-77, AC-78, AC-79 |
| R10 user request (security task, document everything, different colour) | UD-a, UD-b, UD-c, 4.6, section 8, D-39 to D-42 | see the UD rows |
| R9 security view | F-07, F-08, F-09, F-11, F-12, F-17-F-19, F-22 | AC-42, AC-44, AC-45, AC-47 to AC-54, AC-59 to AC-61, AC-64, AC-70, AC-74, AC-75 |
| UD-a monitor colour, never summed | F-01, F-04, 4.6 | AC-23, AC-24, AC-27 to AC-33, AC-67, AC-68, AC-69, AC-76, AC-77, AC-78, AC-79 (coverage map in acceptance-criteria) |
| UD-b security QA consultation | F-02, section 8 (SEC-QA-0 to SEC-QA-6), qa-instructions §7, §8, §11 | AC-22, AC-67 to AC-69, AC-77 to AC-79 |
| UD-c documentation | these files | (review) |
| NFR-1 never freeze | 3.6, F-05 (async iw), F-06 (escaping), F-10 | AC-01, AC-02, AC-03, AC-41, AC-42 |
| NFR-2 auto-recover | 3.6 | AC-04, AC-05 |
| NFR-3 no respawn storm | 3.6 | AC-05, AC-06 |
| NFR-4 cheap | F-01 cost, D-19 | AC-02, AC-07, AC-21, AC-40 |
| NFR-5 numbers match /sys | 3.1-3.2, F-01 | AC-10, AC-16, AC-23 |
| NFR-6 Wi-Fi switch / hot-plug / suspend | F-01, F-16, F-20 | AC-17, AC-18, AC-25, AC-26, AC-58, AC-62, AC-72, AC-73 |
| NFR-7 errors visible | 3.6, F-10 | AC-08, AC-41 |
| Scope: no panel/xfconf change, RAM deferred | 1.2 | AC-20, AC-65, AC-66 |

---

## 8. Security specialist: QA consultation task card (decision b)

**Task SEC-QA**, owner: cyber security specialist. Consumer: QA.

| Sub-task | Description | Output |
|---|---|---|
| SEC-QA-0 | **Done 2026-11-20 (v1.2).** Wrote the QA consultation on how to check WLAN monitor mode: the sandbox procedure QA can run unattended, and the live procedure that needs the user's approval. Found blocker DEF-05. | `qa-instructions.md` §11; D-39 to D-42; AC-77 to AC-79 |
| SEC-QA-1 | Run the gate in qa-instructions §11.0, then review QA's sandbox fixture (qa-instructions §5, checklist §11.1, scenarios S-T/S-U in §11.2) before the first run: fake tree completeness (type, flags, operstate, carrier_changes, ifindex, statistics, device/phy80211 links, proc/net route/arp/wireless, ip_forward, addrs, iw stub fixtures), plus scenarios S-B…S-S against the threat cases (airmon rename, in-place switch, vif alongside managed, two vifs on two phys, down vif, injection, switch back, promisc incl. bridge-port noise, gateway MAC change incl. all false-positive cases, persistence, acceptance). Realism rules agreed at sign-off (D-38): monitor vifs are created with operstate `unknown` (as real mac80211 vifs), so a build that takes monitor state from operstate fails AC-30; one S-B variant uses type 802 (prism); packet counters start at 5,000,000; the hostile SSID is placed in both `iw dev` and `iw link` fixtures. | sign-off note or a list of corrections to QA |
| SEC-QA-2 | Be on call during the sandbox run to interpret failures in AC-23 to AC-33, AC-44 to AC-51 and AC-76 to AC-79 (security-signal false positives or negatives) | verdict per failing AC: product defect vs fixture defect |
| SEC-QA-3 | Before any live step: confirm with the user that the approval covers exactly that step (L0-L3); confirm the pre-checks and the rollback commands (qa-instructions §8); confirm the monitor is tuned with `set freq` to wlan1's full channel width (D-37) | go / no-go |
| SEC-QA-4 | During live steps: watch the wlan1 guard checks every 5 s (default route, SSID/BSSID, gateway ping, carrier_changes 14) and call an immediate rollback on any deviation | live log |
| SEC-QA-5 | After live steps: confirm the rollback state (wlan0 flags 0x1003 or 0x1103 if netdiscover is alive, NM managed, no wlan0mon, PROMISC line state as expected) and record the answer to the "do counters survive an in-place switch?" question (AC-68) for the BA | note appended to the QA report |
| SEC-QA-6 | Before the first acceptance run: confirm with Dev that T1 (sandbox hooks, DEF-05) is in the shipped build, and check the developer's self-test of AC-77 to AC-79 | go / no-go for the sandbox acceptance run |

The security specialist does not run sudo commands and does not change interface state. The user runs them, or explicitly authorises QA per step.

---

## 9. Change log

### v1.2 (2026-11-20): security specialist's monitor-mode QA consultation
Trigger: user request R10 ("add task for cyber security agent to assist/consult QA on how to check WLAN in monitor mode. BA should document everything. In Monitor mode graph should display traffic in a different colour."). The BA checked the consultant's blocker claim against the deployed daemon: it has no `PANELGRAPH_*` variables and hard-codes `/sys/class/net` at lines 58, 64, 69, 78 and 87 (pid <pid>).

| # | Change | Where applied |
|---|---|---|
| 1 | New QA section "WLAN monitor mode testing (consulted with the security specialist)": gate, fixture checklist, fixtures, traffic engine, pass checks, pitfalls, reporting, and the live run sheet marked REQUIRES USER APPROVAL | qa §11; pointers in qa §7, §8.2 and §10 |
| 2 | DEF-05 blocker (no sandbox hooks); `SMOKE` result status; D-40 | req §3.9, F-02; dev §4.1, T1, DoD; qa §4, §11.0; AC-22 |
| 3 | New ACs AC-77 (vif removal), AC-78 (palette), AC-79 (name-independent detection, phy via SYSNET); scenarios S-T and S-U; D-41 | AC file; qa §11.2, §10; dev §5.10, T2, T4 |
| 4 | Live AC-67 and AC-68 extended (on-screen bar and marker checks, vif counter vs tooltip, disappearance after rollback); AC-75 safety notes; D-42 | AC file; qa §8.2, §11.7 |
| 5 | Monitor-mode colour design summary card; coverage map of the colour decision (sandbox vs live ACs) | req §4.6; AC file |
| 6 | Task card: SEC-QA-0 (done), SEC-QA-1 updated, SEC-QA-6 added; R10 and traceability rows | req §2, §7, §8 |

Backups of v1.1 of all four files: `~/.local/share/panelgraph/backup/*.v1.1.md`.

### v1.1 (2026-11-20): specialists' sign-off corrections
The BA applied 17 corrections (N = networking specialist, S = cyber security specialist). Items about current behaviour were checked against the code and live system: `physical_ifaces()` re-checks the device link every 5 s (line 284); `/proc/net/wireless` has a leading space before `wlan1:`; live `iw dev` shows wlan1 at `channel 44 (5220 MHz), width: 80 MHz, center1: 5210 MHz`; wlan0 `rx_packets` = 13,871,277.

| # | From | Correction | Where applied |
|---|---|---|---|
| 1, 9 | N, S | `rx_packets` read for every candidate every tick; the "that is fine" note was wrong (D-31) | req §4.0 delta rule, F-01; dev §5.1 |
| 2, 9 | N, S | Sandbox packet counters start at a large base; S-C gets 1000 pps; AC-24 bounds fr/s. Numeric conflict → **OQ-13** (recommended: 5,000,000 base, 1.1 ×) | qa §5.2, §5.3, §6 S-C; AC-24; AC global conventions |
| 3 | N | Links re-checked in the 5 s scan, not cached for the name's lifetime (D-32) | req §4.0; dev §5.1, §5.4 |
| 4 | N | `/proc/net/wireless` name must be stripped; fixtures use different signal values (wireless -41, link -45) so the iw fallback cannot hide the bug | req §4.2 notes; dev §5.4 item 4; qa §5.2 `iw_link`; AC-38 |
| 5 | N | S-H adds wlan0mon without deleting wlan0, so H3 can run; wlan0 expected in the Idle line in H1, H2 and S-R(3) | qa §6 S-H, S-R; AC-34, AC-43 |
| 6, 8 | N, S | Live L1/L2 tune the monitor to the full BSS width (`set freq 5220 80 5210`, values read at test time); captured ≥ 50 % of wlan1 rx; Total checked with the AC-10 2 s window method; 20 MHz fallback → INCONCLUSIVE (D-37) | qa §8.2, §8.3; AC-67, AC-68 |
| 7 | N | Monitor strip lifetime also covers nonzero monitor history (D-33) | req §4.1; dev §5.2 |
| 10 | S | Two monitor vifs: format specified (D-34); new scenario S-S and **AC-76** | req §4.2; dev §5.7; qa §6 S-S; AC-76 |
| 11 | S | AC-32: no FF00FF/FFA0FF at x = 139 from t0 + 1.25 s (smoothing tail) | AC-32 |
| 12 | S | J2 made deterministic: remove the ARP row and bump carrier_changes in one step, add the new MAC 1 s later | qa §6 S-J2; AC-48 |
| 13 | S | AC-44 "no monitor pixels" holds only until wlan0mon is added | AC-44 |
| 14 | S | Hostile SSID also in `iw link`; SSID source and shared decode path stated (D-35) | req §4.2; dev §5.5; qa §6 S-L; AC-42 |
| 15 | S | Monitor vifs created with operstate `unknown`; S-B variant with type 802 | qa §5, §6 (S-B, S-C, S-D, S-F, S-H, S-I, S-R, S-S); AC-25, AC-30 |
| 16 | S | M2 frame on/off evaluated every tick (D-36) | req §4.4; dev §5.6 |
| 17 | S | Two M2 known limitations added (reconnect re-baseline; IPv4 only) | req §4.4 |

Backups of v1.0 of all four files: `~/.local/share/panelgraph/backup/*.v1.0.md`.
