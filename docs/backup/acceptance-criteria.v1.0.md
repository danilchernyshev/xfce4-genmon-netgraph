# panelgraph NETWORK graph: acceptance criteria

Version 1.0, 2026-11-20. Author: BA.

How this file fits with the others:
- Requirements and designs: `requirements.md`. Ids cited: R3-R9, UD-a/b, NFR-1…7, F-xx, D-xx.
- Procedures, the sandbox harness, fixture values, scenario scripts S-A…S-Q and the live steps L0-L3: `qa-instructions.md`.

## Tags
| Tag | Meaning |
|---|---|
| REGRESSION | Existing behaviour that must keep working |
| NEW-MUST | Must ship in this pass |
| NEW-SHOULD | Ship if implemented in this pass. If not implemented, QA reports SKIPPED (not built). |
| NEW-COULD | Backlog. QA reports SKIPPED unless the developer reports it as built. |
| DEFERRED | Needs a user decision first. QA reports SKIPPED. |

**APPROVAL** marks an AC that changes interface state or needs the mouse or user action. QA runs it only after explicit user approval of that exact step. Otherwise QA reports SKIPPED (approval pending).

## Global conventions
| Name | Definition |
|---|---|
| Sandbox | Scratch daemon copy + fake tree + `PANELGRAPH_*` env vars (qa-instructions §5). Fixture values: SSID `SBX-NET`, IP `10.99.0.25`, gateway `10.99.0.1` / `02:00:00:00:00:01`, BSSID `02:00:00:00:00:aa`. |
| Steady | Rates held ≥ 33 s, so every column and the scale reflect them |
| Pixel(x,y) | Read from `net.png` with pycairo (qa-instructions §5.6). Colours are written as RRGGBB at alpha 255. `T` = transparent (alpha 0). |
| Rate tolerance | ±5 % vs fake rates (sandbox); ±10 % vs `/sys` (live) |
| Height tolerance | ±2 px. Point checks are chosen ≥ 3 px away from the expected edges. |
| Latency classes | **T1** (per tick): observed ≤ 0.6 s. **T5** (5 s scan): ≤ 6.5 s. **Tiw** (iw-derived): ≤ 12 s. **TM2** (gateway alert): ≤ 12 s. Measured from the fixture change, with 50 ms polling. |
| Tooltip text | `<tool>…</tool>` parsed with `Pango.parse_markup`, then whitespace runs collapsed to one space before substring/regex checks |
| "!" marker | `net.txt` contains `<txt>!</txt>` |

Default fixture "BASE" (qa-instructions §5.3):
- `eth0` down, `wlan0` (phy0) down, `wlan1` (phy1) up at rx 512 KiB/s / tx 128 KiB/s.
- Noise interfaces `vnet9`, `docker0`, `virbr-msf`, `lo`, each growing at 1 MiB/s.
- Every counter starts at 5 GiB.

---

## REGRESSION

**AC-01: Panel item never freezes** (NFR-1). Live, read-only.
- Given: plugin 26's wrapper pid, found via the /proc cmdline scan in qa-instructions §3 (never `pgrep -f`).
- When: `/proc/<pid>/wchan` is sampled every 50 ms for 60 s, during idle and during a curl download. Repeat during AC-04 and AC-05.
- Then:
  - No run of consecutive `pipe_read`/`anon_pipe_read` samples lasts longer than 1.0 s.
  - Two crops of the plugin-26 region taken 2 s apart during the download differ.
- Pass: both conditions hold.

**AC-02: Wrapper hot path uses builtins only** (NFR-4, NFR-1). Live.
- Given: the live daemon is healthy.
- When: `env -i HOME=$HOME XDG_RUNTIME_DIR=/run/user/1000 PATH=/nonexistent /bin/sh ~/.local/bin/panelgraph-show net` runs.
- Then:
  - Exit status is 0.
  - stdout is byte-identical to `cat /run/user/1000/panelgraph/net.txt` read immediately before or after (retry up to 3 times if the text changed in between).
  - `seen` mtime advanced.
  - No "command not found" on stderr.

**AC-03: No inherited or leaked pipes** (NFR-1). Live + sandbox.
- Live:
  - The set of `pipe:[inode]` targets in `/proc/<daemon>/fd` shares no inode with `/proc/<wrapper26>/fd`.
  - The daemon has no fd open on `/dev/pts/*`.
- Sandbox: the iw stub logs `/proc/$$/fd` on each call. It must show only 0 (`/dev/null`), 1 (a pipe), 2 (`/dev/null`) and at most one fd for the stub script itself. Never the daemon's `lock` file.

**AC-04: Recovery after SIGTERM** (NFR-2). Live.
- When: `kill "$(cat /run/user/1000/panelgraph/pid)"`.
- Then:
  - Within 1.5 s the pid file holds a different pid.
  - That pid has comm `panelgraph` and cwd `/run/user/1000/panelgraph`.
  - Exactly one such process exists (scan `/proc/*/comm` + cwd).
  - `net.txt` mtime keeps advancing during traffic.
  - AC-01 sampling shows no freeze.

**AC-05: Recovery after kill -9, no respawn storm** (NFR-2, NFR-3). Live.
- When: `kill -9 "$(cat /run/user/1000/panelgraph/pid)"`.
- Then:
  - A new daemon runs within 1.5 s.
  - Sampling `/proc` every 100 ms for 20 s shows at most 2 distinct live-dir `panelgraph` pids (old + new) and never more than 1 at a time after the new one starts.
  - No "!" marker.

**AC-06: Single instance** (NFR-3). Sandbox.
- When: a second copy of the daemon is started with the same env while the first runs.
- Then: the second exits within 1 s, the pid file is unchanged, and only one sandbox `panelgraph` process exists.

**AC-07: Idle exit after 30 s** (NFR-4). Sandbox.
- When: keepalive is removed, so `seen` stops changing.
- Then:
  - The daemon exits 30-32 s after the last `seen` touch.
  - `run/panelgraph/pid` is removed; `lock` remains.
  - On restoring keepalive and starting it again, it runs normally.

**AC-08: Error marker, error.log, auto-recovery** (NFR-7). Sandbox, S-A.
- When: `mkdir $SB/run/panelgraph/net.png.tmp` (the render then fails).
- Then:
  - Within 1 s `net.txt` shows the "!" marker, with a tooltip starting `panelgraph net error:` and naming `error.log`.
  - `error.log` contains `net:` and a traceback.
  - `mem.txt` has no "!".
- After `rmdir`: the normal `<img>` markup returns within 6.5 s.

**AC-09: Physical-NIC selection and exclusions** (R3). Sandbox, S-A steady.
- Then:
  - `Total ↓` = 512 KiB/s ±5 % and `↑` = 128 KiB/s ±5 %, although vnet9, docker0, virbr-msf and lo each add 1 MiB/s.
  - The tooltip never contains `vnet9`, `docker0`, `virbr-msf` or `lo`.
  - Exactly 1 strip.

**AC-10: Tooltip matches /sys counters** (NFR-5, R3). Live, curl allowed.
- Given: `curl -s -o /dev/null --limit-rate 400k --max-time 25 <deb.debian.org large file>`.
- When: from t = 5 s, ten consecutive 2 s windows are taken. In each window:
  - the sysfs rate = Δ(sum of rx_bytes of eth0, wlan0, wlan1) / Δt;
  - the tooltip value = mean of `Total ↓` read every 250 ms.
- Then:
  - ≥ 8 of 10 windows have |tooltip − sysfs| ≤ 10 % of sysfs.
  - Same for ↑, with tolerance max(10 %, 2 KiB/s).

**AC-11: Colours match netload** (R5). Static + live.
- Then:
  - `Color_In=rgb(255,79,0)` and `Color_Out=rgb(255,229,0)` in `netload-23.rc` and `netload-24.rc`.
  - Live `net.png` contains only these opaque colours: FF4F00, FFE500, and, only when applicable, FF00FF, FFA0FF, FF2020.
  - A screenshot taken during a download contains exact FF4F00 pixels in both the plugin-26 region and the netload-23 region.

**AC-12: Timed screenshots vs netload** (R4). Live, curl allowed.
- When: screenshots of the panel strip from plugin 26 to netload 23 are taken every 1 s for 35 s: 5 s idle, then a 25 s `--limit-rate 500k` download, then 5 s idle.
- Then, in ≥ 80 % of the screenshots from t = 8 s to t = 29 s:
  - plugin 26's newest 4 history columns contain FF4F00;
  - netload-23's region contains FF4F00.
- Also: during the download `Total ↓` = 500 KiB/s ±10 %. The 5 idle screenshots before the download show no FF4F00 column taller than 25 % of the height in the newest 4 columns.

**AC-13: Image geometry** (R3). Sandbox + live.
- `net.png` is 140×32, RGBA (PNG colour type 6).
- Gap columns x 4, 5, 10, 11 are T in all rows (normal mode).
- History is 128 columns, newest at x = 139. S-Q: after a 0→512 KiB/s step, the left edge of the nonzero span moves 1 px left per tick (±1) over 5 s.

**AC-14: Shared scale with 64 KiB/s floor** (R3). Sandbox.
- With all rates 0, steady: `Scale 64.0 KiB/s`.
- S-A steady: Scale = 512 KiB/s ±5 %.
- 34 s after the rates return to 0: `Scale 64.0 KiB/s` again.

**AC-15: Paint order and minimum 1 px** (R3, R7). Sandbox.
- wlan1 at rx 512 KiB/s and tx 300 B/s, steady (1 strip):
  - Pixel(139,31) = FFE500 and Pixel(139,30) = FF4F00.
  - Pixel(7,31) = FFE500 and Pixel(7,30) = T.
- With 2 strips (S-B layout), the same holds in the managed strip at rows 14/13.

**AC-16: 1 s smoothing** (NFR-5). Sandbox, S-Q.
- When: wlan1 rx steps from 0 to 512 KiB/s at t0.
- Then:
  - Every `Total ↓` read before t0 + 0.6 s is < 70 % of 512.
  - A read ≥ 90 % of 512 occurs by t0 + 1.5 s.
  - No read ever exceeds 105 %.

**AC-17: Wi-Fi reconnect / switch survives** (NFR-6). Sandbox, S-O part 1.
- When: wlan1 goes operstate down for 3 s, then up. At the same time its counters reset to 0 and continue, `carrier_changes` +2, and the iw fixtures switch to SSID `SBX-OTHER` with gateway MAC `02:00:00:00:00:99`.
- Then:
  - No `Total ↓` read exceeds 1.1 × 512 KiB/s.
  - No "!" marker.
  - The tooltip shows `SBX-OTHER` within Tiw.
  - **No** M2 alert (no FF2020 pixel, no `!!`) during the following 30 s.

**AC-18: Suspend approximation** (NFR-6). Sandbox, S-O part 2.
- When: `kill -STOP` on the sandbox daemon for 10 s (keepalive running), then `kill -CONT`.
- Then:
  - The daemon is still running.
  - `net.txt` updates within 0.6 s.
  - No `Total ↓` read exceeds 1.1 × 512 KiB/s.

**AC-19: Click action unchanged.** Live.
- `net.txt` contains exactly one `<click>xfce4-taskmanager</click>`.
- QA does **not** click.

**AC-20: Panel configuration untouched** (scope). Live.
- `xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids` = `1 2 3 4 5 6 7 8 9 10 11 12 13 26 24 23 14 15 16 17 18 19 20 21 22`.
- `xfconf-query -c xfce4-panel -p /plugins/plugin-26 -lv` is unchanged: command `~/.local/bin/panelgraph-show net`, `update-period 250`.
- No plugin command contains `panelgraph-show mem`.
- `sha256sum ~/.config/xfce4/panel/*.rc` matches the pre-test snapshot.

**AC-21: Cost** (NFR-4). Live, after deployment of v2.
- Over 60 s idle and 60 s during a `--limit-rate 500k` download:
  - daemon CPU = Δ(utime+stime)/100/60 × 100 ≤ **2.0 %** of one core in each window (baseline 1.0 %);
  - `VmRSS` ≤ 40 MB.

---

## NEW-MUST

**AC-22: Sandbox hooks** (UD-b, F-02). Static + sandbox.
- Static: the daemon reads `PANELGRAPH_SYSNET`, `PANELGRAPH_PROCNET`, `PANELGRAPH_IPFORWARD`, `PANELGRAPH_IW`, `PANELGRAPH_ADDRS` and `PANELGRAPH_ALERT_HOLD` (grep). Defaults are the real paths and 600.
- Sandbox S-A: the tooltip contains `SBX-NET`, `10.99.0.25` and `10.99.0.1`, and never `HomeNet`, `192.168.1.` or `aa:bb:cc`.
- Live (AC-39) still shows the real values.

**AC-23: In-place switch never leaks captured bytes** (UD-a, R8, DEF-01, F-01). Sandbox, S-C.
- When: at t0, wlan1 `type` is written 1→803, the default route is removed, and rx continues at 2 MiB/s.
- Then:
  - In net.txt polled every 50 ms from t0 − 2 s to t0 + 35 s, `Total ↓` is never > 1.05 × 512 KiB/s.
  - It falls to < 5 KiB/s by t0 + 1.5 s.
  - The monitor strip and the `MONITOR wlan1` line appear within T1.

**AC-24: No pre-switch or pre-existing bytes in the first monitor sample** (R8, F-01). Sandbox, S-C and S-B.
- Counters start at 5 GiB.
- S-C: `captured` is never > 2.2 MiB/s and `Mon scale` is never > 2.2 MiB/s from t0 to t0 + 35 s.
- S-B: a new `wlan0mon` with a 5 GiB base and rx 512 KiB/s gives `captured` never > 0.55 MiB/s.

**AC-25: New or removed interfaces detected per tick** (R8, NFR-6). Sandbox, S-B.
- When: `wlan0` is deleted and `wlan0mon` (type 803, device, phy0) is created atomically.
- Then:
  - The monitor strip (FF00FF at Pixel(139,31) once rx > 0) and the `MONITOR wlan0mon` line appear within T1.
  - `ch44 5220 MHz` appears in the MONITOR line within Tiw.
  - The deleted interface causes no "!" marker and no error.log entry.

**AC-26: Hot-plug without spikes** (NFR-6). Sandbox, S-M.
- When: `usb0` (type 1, device, operstate up, counters at 5 GiB, rx 128 KiB/s) is added.
- Then:
  - It is counted within T1 (`Total ↓` reaches 640 KiB/s ±5 % within 2 s).
  - No read exceeds 1.1 × 640 KiB/s.
- On removal: no "!" marker, and `Total ↓` returns to 512 ±5 % within 2 s.

**AC-27: Monitor strip pixels and colours** (UD-a, F-04). Sandbox, S-B steady (wlan1 512/128 + wlan0mon rx 512, tx 0).
- 2 strips; row 15 is T for all x.
- Managed strip (rows 0-14):
  - Pixel(139,5) = FF4F00; Pixel(139,14) = FFE500; Pixel(1,5) = FF4F00.
- Monitor strip (rows 16-31):
  - Pixel(139,20) = FF00FF; Pixel(139,31) = FF00FF; Pixel(1,20) = FF00FF.
  - Pixel(7,31) = T; Pixel(7,20) = T.
- No pixel anywhere is FFA0FF or FF2020.
- Tooltip contains `MONITOR wlan0mon (phy0`, `captured 512` (±5 %), `injected 0 B/s`, `not in total`.

**AC-28: Separate monitor scale** (UD-a, D-10). Sandbox, S-D variant (wlan1 128/32 KiB/s, wlan1mon rx 8 MiB/s), steady.
- Pixel(139,3) = FF4F00: the managed strip is still full height.
- `Scale` = 128 KiB/s ±5 %; `Mon scale` = 8 MiB/s ±5 %.

**AC-29: Injected tx colour** (UD-a). Sandbox, S-F (wlan0mon rx 512, tx 256 KiB/s), steady.
- Monitor strip: Pixel(139,20) = FF00FF; Pixel(139,28) = FFA0FF; Pixel(7,28) = FFA0FF; Pixel(7,20) = T; Pixel(1,20) = FF00FF.
- `injected 256` (±5 %) in the tooltip.
- Managed `Total ↑` = 128 KiB/s ±5 %.

**AC-30: Monitor baseline solid / dotted** (R8, D-12, D-13). Sandbox.
- **Solid**, S-B with wlan0mon rx = 0 (up), steady:
  - Pixel(x,31) = FF00FF for every x in 12-139.
  - Rows 16-30 for x 12-139 are T.
  - Pixel(1,31) and Pixel(7,31) are T.
- **Dotted**, S-E (wlan0mon flags 0x1002 = admin down, rx 0), steady:
  - On row 31, x 12-139: exactly 64 pixels are FF00FF and the rest are T, alternating between neighbours.
  - Rows 16-30 for x 12-139 are T.
  - The tooltip MONITOR line ends its state with `, down)`.

**AC-31: Monitor bytes never in the managed totals** (UD-a, R3). Sandbox, all monitor scenarios (S-B to S-H).
- In every 50 ms poll, `Total ↓/↑` ≤ 1.05 × the fake managed rates. Steady values are within ±5 %.
- In S-F, the `Sustained upload` segment never appears (if F-11 is built).

**AC-32: Switch back to managed** (R8). Sandbox, S-G after S-C.
- When: wlan1 `type` 803→1, with the route restored.
- Then:
  - Within T1 the tooltip has no `MONITOR ` line; it shows `monitor ended HH:MM:SS` while the strip remains.
  - From then on, column x = 139 contains no FF00FF/FFA0FF.
  - The monitor strip is gone between 32 s and 34 s later: exactly 1 strip; strip-count sequence 2 → 1 with no flapping.
  - The wlan1 managed strip shows traffic within T1 + 1 s.

**AC-33: Monitor vif alongside managed on the same phy** (R8). Sandbox, S-D (wlan1 managed + wlan1mon type 803, phy1).
- 2 strips with the AC-27 pixels.
- Tooltip has both `wlan1 ★` and `MONITOR wlan1mon (phy1`.
- `Total` counts wlan1 only (±5 %).

**AC-34: Strip geometry and the "other" slot** (R7, F-03). Sandbox, S-H.
- **H1**: eth0 rx 256, usb0 rx 128, wlan1 512/128, wlan0mon rx 512; steady.
  - 3 strips; rows 10 and 21 are T for all x.
  - Pixel(139,8) = FF4F00; Pixel(139,3) = T; Pixel(139,15) = FF4F00; Pixel(139,20) = FFE500; Pixel(139,26) = FF00FF.
  - Tooltip strip labels: `top eth0`, `mid other: usb0+wlan1`, `bottom` … `MONITOR wlan0mon`.
- **H2**: wlan0mon removed, steady after 34 s.
  - 3 strips. Pixel(139,7) = FF4F00; Pixel(139,2) = T; Pixel(139,20) = FF4F00; Pixel(139,15) = T; Pixel(139,25) = FF4F00; Pixel(139,31) = FFE500.
  - Labels `top eth0`, `mid usb0`, `bottom wlan1`.
- **H3**: wlan0 also up at rx 64.
  - Labels `top eth0`, `mid usb0`, `bottom other: wlan0+wlan1`.

**AC-35: Strip hysteresis** (R7). Sandbox, S-H2.
- When: at t0 eth0 rx goes to 0 and operstate to down.
- Then: 3 strips remain until t0 + 32 s, then exactly 2 strips by t0 + 34 s (sequence 3 → 2 once).
- When: eth0 operstate goes up with zero traffic.
- Then: the eth0 strip appears within T5.

**AC-36: Total vs strips** (R3, D-18). Sandbox.
- S-A: the wlan1 strip line's `↓ … ↑ …` equals the `Total` values (identical text).
- S-H1: `Total ↓` = 896 KiB/s ±5 % (256 + 128 + 512).

**AC-37: Replacement texts and monitor-only layout** (R6, R8). Sandbox.
- **S-C steady (34 s after the switch):**
  - 1 strip occupying rows 0-31: Pixel(139,6) = FF00FF, Pixel(139,31) = FF00FF.
  - Tooltip contains `No managed link (capture only)` and `No default route`.
- **All NICs down, no traffic, steady:**
  - The image has no opaque pixel.
  - `No managed interface up` and `Idle: eth0 no carrier · wlan0 not connected · wlan1 not connected`.
- **Empty `sys/class/net`:** `No network interfaces`.

**AC-38: Wi-Fi details in tooltip (sandbox)** (R6, F-05, F-08). Sandbox, S-A, within Tiw of start.
- The tooltip contains:
  - `wlan1 ★ SBX-NET -41 dBm ch36 5180 MHz/80`
  - `rx 650/tx 585 Mbit/s`
  - `Gateway 10.99.0.1 02:00:00:00:00:01 via wlan1, IP 10.99.0.25`
  - `Idle: eth0 no carrier · wlan0 not connected`
- The P2P-device (`Unnamed/non-netdev`) block in the fixture does not change wlan0's or wlan1's type.

**AC-39: Wi-Fi details live** (R6). Live, read-only, no approval needed.
- The tooltip's wlan1 line contains `wlan1 ★ HomeNet`.
- The dBm value equals the level in `/proc/net/wireless` ±3.
- `ch<N> <F> MHz/<W>` equals `iw dev wlan1 info` channel, frequency and width.
- `Gateway 192.168.1.1 <MAC> via wlan1, IP 192.168.1.25`, where MAC = the `/proc/net/arp` entry for 192.168.1.1 and IP = `ip -4 -o addr show wlan1`.
- `eth0` and `wlan0` appear in the `Idle:` line.

**AC-40: iw spawn budget and non-blocking execution** (NFR-4, D-19). Sandbox, stub call log over 120 s.
- ≤ 25 invocations; `dev` and `dev <if> link` alternate.
- Consecutive starts are ≥ 4.5 s apart (except one extra `link` right after a gateway mismatch in AC-47).
- Never two calls running at once (start/end log).
- With no `phy80211` in the fixture (wlan0/wlan1 removed): 0 invocations in 60 s.
- With no managed Wi-Fi up: no `link` invocations.

**AC-41: iw failure handling** (NFR-1, NFR-7, F-10). Sandbox.
- **hang** mode (stub `exec sleep 60`):
  - The largest gap between successive `net.txt` content changes stays ≤ 0.75 s while traffic jitters.
  - Each stub pid is gone ≤ 2 s after its start.
  - The tooltip shows `(stale` within 12 s, then `Wi-Fi details unavailable (timeout)` within 45 s.
  - The graph and the Total stay correct.
  - `error.log` changes at most once per distinct error within 120 s.
  - No "!" marker.
- **garbage** mode: `(parse)`.
- **missing** (daemon restarted with `PANELGRAPH_IW=/nonexistent/iw`): `(iw missing)` within 45 s.
- In all modes the gateway line (route/arp based) stays correct.

**AC-42: Hostile SSID is escaped** (R9, NFR-1). Sandbox, S-L.
- Fixture SSID bytes: `a&b<c>"d</tool><click>touch $QA/pwned</click>` + `\x07` + `\x0a`, written in iw's `\xNN` form.
- Then:
  - `net.txt` has exactly one `<tool>`, one `</tool>`, one `<click>xfce4-taskmanager</click>`.
  - `Pango.parse_markup` succeeds.
  - The plain tooltip contains `a&b<c>"d</tool>` (literal) and no BEL or newline inside the SSID.
  - The SSID shown is ≤ 32 characters.
  - `$QA/pwned` never exists.

**AC-43: Tooltip template** (R6-R9, F-06). Sandbox, worst case = S-H1 + M2 alert + promisc wlan0 (exists, down) + forwarding (eth0 and wlan1 up) + tun0 VPN (if Shoulds are built).
- ≤ 10 lines.
- Line order: `!!`, `Total`, strip lines top→bottom, `Gateway`, `PROMISC`, VPN/upload, `Forwarding`, `Idle`.
- Pango-valid markup.
- Raw markup contains `<span foreground="#FF4F00">■</span>`, `<span foreground="#FFE500">■</span>`, `<span foreground="#FF00FF">■</span>` and `<span foreground="#FFA0FF">■</span>`.

**AC-44: PROMISC line** (R9, F-07). Sandbox, S-I.
- wlan0 flags 0x1003→0x1103: `PROMISC wlan0 (packet capture running)` appears within T5; it disappears within T5 when set back.
- `vnet9` (0x1303, no device) is never named.
- A monitor vif with 0x1103 gets no PROMISC line.
- During the whole scenario, no FF00FF/FFA0FF/FF2020 pixel appears and the strip count stays 1.

**AC-45: PROMISC live** (R9). Live, read-only.
- If `/sys/class/net/wlan0/flags` has bit 0x100 (netdiscover running), the tooltip contains `PROMISC wlan0`. If not, it does not.
- `vnet16`/`vnet17` are never named.

**AC-46: Gateway line edge cases** (R6, F-08). Sandbox.
- Two default routes (wlan1 metric 603, eth0 metric 100, eth0 up): `via eth0` within T5.
- ARP entry with flags 0x0: MAC shown as `?`.
- No default route: `No default route`.
- Default route without RTF_GATEWAY (flags 0x0001, dev tun0): `Gateway ? ? via tun0, IP ?`.

**AC-47: Gateway MAC alert fires** (R9, F-09). Sandbox, S-J1.
- When: in the S-A steady state, the ARP MAC for 10.99.0.1 changes to `02:00:00:00:de:ad` (complete), with no carrier or BSSID change.
- Then, within TM2:
  - All 340 frame pixels (`y∈{0,31}` or `x∈{0,139}`) = FF2020.
  - No interior pixel (x 1-138, y 1-30) is FF2020.
  - Content is inset: Pixel(138,6) = FF4F00, Pixel(138,28) = FFE500, Pixel(2,6) = FF4F00, Pixel(7,28) = FFE500; x = 5 and x = 10 are T for y 1-30.
  - Tooltip first line: `!! Gateway MAC changed HH:MM 02:00:00:00:00:01 → 02:00:00:00:de:ad via wlan1`.
  - The stub log shows one extra `link` call after the first mismatch.

**AC-48: No false positives** (R9). Sandbox, S-J2…S-J6. Each case is observed for 25 s: no FF2020 pixel and no `!!`.
- J2: carrier_changes +1, then the MAC changes.
- J3: new MAC with flags 0x0.
- J4: an extra ARP row `10.99.0.1 … 02:00:00:00:00:77 … eth0` (the route stays on wlan1).
- J5: baseline `00:00:5e:00:01:01` → `00:00:5e:00:01:02` (VRRP).
- J6: BSSID changes in `link-wlan1.txt` and the MAC changes in the same step.

**AC-49: Alert hold and clear** (R9). Sandbox, S-J7, `PANELGRAPH_ALERT_HOLD=20`.
- When: after AC-47, the MAC returns to baseline at t1.
- Then:
  - The frame stays until at least t1 + 20 s and is gone by t1 + 27 s.
  - The `!!` line is still present after the frame clears.

**AC-50: Alert persistence** (R9). Sandbox, S-J8.
- `gw.json` exists, with keys `iface, gw_ip, mac, carrier_changes, bssid, alert_since, alert_mac`.
- Its mtime is unchanged over 60 s of steady state.
- During an active alert: stop the daemon via its pid file and start it again with the same env. The frame and the `!!` line return within T5.

**AC-51: User acceptance of a new MAC** (R9, D-23). Sandbox, S-J9.
- When: during an active alert, `rm -f $SB/run/panelgraph/gw.json`.
- Then, within T5:
  - The frame clears.
  - The `!!` line is replaced by `Gateway MAC accepted HH:MM`.
  - `gw.json` is recreated with `mac` = the new MAC.
  - No alert during the next 30 s.

---

## NEW-SHOULD (SKIPPED if not built)

**AC-52: Sustained upload and Up 5 min** (R9, F-11). Sandbox.
- wlan1 at tx 300 KiB/s, rx 100 KiB/s from t0: `Sustained upload` appears between t0 + 60 s and t0 + 67 s.
- `Up 5 min` = the fake managed tx bytes over the last min(300 s, daemon uptime) ±5 %. QA computes the reference from its own rate timeline: 128 KiB/s before t0, 300 KiB/s after.
- With wlan0mon tx 300 KiB/s and managed tx 0: never appears.

**AC-53: Default route moved** (R9, F-12). Sandbox.
- Route iface wlan1 → eth0 (eth0 up), no carrier change: `Default route moved wlan1→eth0 HH:MM` appears within T5.
- It does not appear when wlan1's carrier_changes increments in the same step.

**AC-54: VPN line, not summed** (R9, R3). Sandbox.
- `tun0` and `wg0` (type 65534, no device, operstate unknown) growing at 1 MiB/s: `VPN tun0, wg0 up` (or `VPN tun0+wg0 up`) appears within T5.
- `Total` is unchanged (±5 %).

**AC-55: Forwarding note** (R3, F-13). Sandbox.
- ip_forward 1, eth0 and wlan1 up: `Forwarding on: traffic routed between eth0 and wlan1 is counted on both` appears within T5.
- It is hidden within T5 when ip_forward = 0, or when only one managed NIC is up.
- It is never shown counting a monitor vif.

**AC-56: AP/mesh/IBSS flag** (R6, F-14). Sandbox.
- The `iw dev` fixture sets wlan0 `type AP` (wlan0 up): `wlan0 [AP]` appears within Tiw.
- `mesh point` gives `[mesh]`; `IBSS` gives `[IBSS]`.

**AC-57: wwan counted** (R3, F-15). Sandbox.
- `wwan0` (type 65534 + device, up, rx 256 KiB/s): `Total ↓` rises by 256 ±5 % within 2 s.

**AC-58: ifindex change** (NFR-6, F-16). Sandbox.
- wlan1's ifindex changes and its counters drop to 1000 at the same step, then continue: no read > 1.1 × 512 KiB/s and no "!".

## NEW-COULD (SKIPPED unless built)
| AC | Feature | Test |
|---|---|---|
| AC-59 | ppp line (F-17) | `ppp0` type 512 operstate unknown gives `ppp0 up` within T5 and is not summed |
| AC-60 | C1 errors/drops (F-18) | rx_errors +150 within 5 s gives `Errors wlan1 +150` within T5; +50 gives nothing |
| AC-61 | C2 DNS change (F-19) | Live read-only is not possible; covered only by the developer's unit test. Sandbox needs a hook (not specified). |
| AC-62 | CLOCK_BOOTTIME (F-20) | Real suspend; requires approval (see AC-73) |
| AC-63 | nl80211 (F-21) | 0 iw invocations in 120 s, with AC-38 still passing |

## DEFERRED (SKIPPED)
| AC | Feature | Test (if ever approved) |
|---|---|---|
| AC-64 | S3 notify-send (F-22) | Exactly one notification per M2 event |
| AC-65 | RAM graph (F-23) | Out of scope. Covered only by AC-20 (no mem panel item). |
| AC-66 | genmon period change (F-24) | Only after an OQ-1 decision |

---

## Live tests that need user approval (APPROVAL)

The procedures are in qa-instructions §8 (security specialist guidance).
- Every step runs on wlan0/phy0 only.
- Never `airmon-ng check kill`; never touch wlan1 or global NetworkManager.
- The user executes or explicitly authorises each sudo command.
- The guard checks run every 5 s, and any failure means immediate rollback.

**AC-67: L1, monitor vif on phy0** (R8, UD-a). NEW-MUST, APPROVAL.
- Given: L1 steps 1-6 done; guard passes.
- When: a 25 s curl download at `--limit-rate 500k` runs over wlan1.
- Then:
  - Within T1 + Tiw, net.txt has `MONITOR wlan0mon (phy0, ch44 5220 MHz, up)`.
  - Screenshots show 2 strips: FF4F00 in the upper strip, FF00FF in the lower one.
  - `Total ↓` matches the wlan1 sysfs rate per AC-10 (±10 %); captured bytes are not included.
  - The guard passes throughout.
- After rollback: within T1 the `MONITOR` line is gone, and the guard passes.

**AC-68: L2, in-place switch of wlan0** (R8). NEW-MUST, APPROVAL.
- Then:
  - The tooltip shows `MONITOR wlan0 (phy0` within T1.
  - Total never includes captured bytes (AC-23 method, live).
  - `rx_bytes` before and after the switch is recorded, answering "do counters survive?" (survive if after ≥ before).
- After rollback:
  - wlan0 flags are 0x1003 (or 0x1103 if netdiscover is alive).
  - NM shows wlan0 `disconnected` (managed).
  - The guard passes.

**AC-69: L3, `airmon-ng start wlan0` without check kill** (R8). NEW-MUST, APPROVAL.
- Then:
  - `wlan0mon` appears, giving the monitor strip and `MONITOR wlan0mon` within T1.
  - NM shows wlan0mon unmanaged.
  - The guard passes throughout.
- After `airmon-ng stop wlan0mon`:
  - wlan0 exists again and the monitor strip scrolls out (≤ 34 s).
  - NM manages wlan0.
  - The guard passes.

**AC-70: PROMISC clears when netdiscover stops** (R9). NEW-MUST, APPROVAL (the user stops pid <pid> per OQ-4).
- `/sys/class/net/wlan0/flags` loses 0x100, and the `PROMISC wlan0` line disappears within T5.

**AC-71: Tooltip renders correctly on screen** (R6, OQ-8). NEW-MUST, APPROVAL (the user hovers; agents must not move the mouse).
- The user confirms:
  - the coloured ■ glyphs show (not raw `<span…>` text);
  - the lines match the template;
  - the SSID is readable.
- Evidence: the user's screenshot or statement.

**AC-72: Live Wi-Fi switch** (NFR-6). REGRESSION, APPROVAL (the user switches network or reconnects).
- No "!" marker and no daemon restart.
- The tooltip shows the new SSID within Tiw.
- No M2 alert.
- No `Total` read > 1.1 × the sysfs rate.

**AC-73: Live suspend/resume** (NFR-6). REGRESSION, APPROVAL.
- After resume:
  - The daemon is running, or was restarted once by genmon.
  - No "!" marker.
  - No `Total` spike > 1.1 × the sysfs rate in the first 5 s.
  - No M2 alert, unless the gateway really changed.

**AC-74: Live gateway-MAC alert** (R9). NEW-MUST, APPROVAL. **Recommended: skip** (OQ-10).
- `sudo ip neigh replace 192.168.1.1 lladdr 02:00:00:00:de:ad dev wlan1 nud reachable` gives the frame within TM2.
- Rollback: `sudo ip neigh del 192.168.1.1 dev wlan1` (connectivity is disrupted until it is relearned).

**AC-75: Live injection test** (R8). DEFERRED, APPROVAL (OQ-12).
- `sudo aireplay-ng --test wlan0mon` (never `-0`/deauth) during L1 gives FFA0FF columns in the monitor strip.
