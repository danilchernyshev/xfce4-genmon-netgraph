# panelgraph NETWORK graph: acceptance criteria

Version 1.4, 2026-11-27. **v1.4 adds the hover popup (F-25) and the private runtime dir (F-26)**: 20 new ACs, AC-80 to AC-99, in the section "NEW-MUST (v1.4)"; AC-93 is live and under APPROVAL. AC-42 is extended by AC-95. The file now defines AC-01 to AC-99 (99 ACs). Version 1.3, 2026-11-20. v1.3: AC-10 tick-matched method (D-43), AC-52 window t0+44-50 s (D-44), user decisions D-45 (all RECOMMENDED options). Author: BA. **v1.2 documents the security specialist's monitor-mode QA consultation** (`qa-instructions.md` §11, `requirements.md` D-39 to D-42):
- AC-22, AC-67, AC-68 and AC-75 changed.
- AC-77, AC-78 and AC-79 added.
- New "Monitor-mode colour decision: coverage map".

v1.1 applied the specialists' sign-off corrections (`requirements.md` §9): AC-24, AC-25, AC-30, AC-32, AC-34, AC-38, AC-42, AC-43, AC-44, AC-48, AC-67, AC-68 changed; AC-76 added.

How this file fits with the others:
- Requirements and designs: `requirements.md`. Ids cited: R3-R11, UD-a/b, NFR-1…7, F-xx, D-xx.
- Procedures, the sandbox harness, fixture values, scenario scripts S-A…S-U and the live steps L0-L3: `qa-instructions.md`. The monitor-mode consultation is §11 there.

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
| SMOKE | A result from a sed-patched daemon copy while the build lacks the sandbox hooks (DEF-05). It never counts as PASS. |
| Automated / requires_user_approval | Sandbox and read-only live ACs are automated: QA runs them unattended. **APPROVAL** ACs are `requires_user_approval`. |

Default fixture "BASE" (qa-instructions §5.3):
- `eth0` down, `wlan0` (phy0) down, `wlan1` (phy1) up at rx 512 KiB/s / tx 128 KiB/s.
- Noise interfaces `vnet9`, `docker0`, `virbr-msf`, `lo`, each growing at 1 MiB/s.
- Every byte counter starts at 5 GiB; every packet counter (`rx_packets`, `tx_packets`) starts at 5,000,000 (OQ-13).
- Signal fixtures differ on purpose: `/proc/net/wireless` says -41 dBm, `iw link` says -45 dBm.
- Monitor vifs are created with operstate `unknown`, like real mac80211 monitor vifs; their up/down state comes from `flags` (IFF_UP).

## Monitor-mode colour decision: coverage map (UD-a, D-04, D-07)

The user decided that monitor-mode traffic is shown in a **different colour** and never added to the managed sum. Each aspect of that decision has a sandbox AC that QA runs unattended, and a live AC that needs the user's approval.

| Aspect | Expected | Sandbox AC (automated) | Live AC (requires_user_approval) |
|---|---|---|---|
| Distinct colour pixels | captured rx #FF00FF, injected tx #FFA0FF; never FF4F00/FFE500 in the monitor strip | AC-27, AC-29, AC-33, AC-76 | AC-67 (captured), AC-75 (injected; DEFERRED) |
| Pixel-exact palette, no partial alpha | only T, FF4F00, FFE500, FF00FF, FFA0FF (+ FF2020 frame) | AC-78, AC-11 (live palette, no approval) | AC-67 (screenshots) |
| Never added to the managed sum | `Total` ≤ 1.05 × the managed rate in every poll, also on the switch tick | AC-23, AC-24, AC-31, AC-33, AC-76, AC-79 | AC-67, AC-68 (Total ±10 % of wlan1 rx, captured ≥ 50 %) |
| Own scale | `Mon scale` with a 64 KiB/s floor; managed strip not flattened | AC-28 | – |
| Current-value bar colour | left bar FF00FF (captured), right bar FFA0FF (injected), inside the monitor strip | AC-27, AC-29 | AC-67 (captured bar on screen) |
| Marker (baseline) | row 31 of the monitor strip, history columns only: solid while any vif is up, dotted (64 px) while all are down | AC-30, AC-76 | AC-67 (solid on screen) |
| Layout | monitor strip at the bottom, transparent separator row | AC-27, AC-34, AC-37 | AC-67 |
| Tooltip | `■ MONITOR <vif> (<phy>, ch<N> <F> MHz, up\|down) ■ captured … ■ injected … … fr/s · not in total · Mon scale …`; several vifs joined by ` + `; glyph spans #FF00FF/#FFA0FF | AC-27, AC-43, AC-76, AC-79 | AC-67, AC-68, AC-69, AC-71 (rendering) |
| Monitor interface appearing | strip and line within T1, airmon rename, prism type 802, vif beside managed, in-place switch, any name | AC-23, AC-25, AC-33, AC-79 | AC-67, AC-68, AC-69 |
| Monitor interface disappearing | `monitor ended HH:MM:SS` within T1, no magenta at x 139 from t0 + 1.25 s, strip gone 32-34 s, no flapping, no "!" | AC-32 (switch back), AC-77 (vif removed) | AC-67, AC-68, AC-69 (after rollback) |
| Promisc is not monitor | no magenta for PROMISC | AC-44 | AC-45 (read-only), AC-70 |
| Test hooks exist (gate) | `PANELGRAPH_*` hooks; nothing hard-coded | AC-22 | – |

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

**AC-10: Tooltip matches /sys counters** (NFR-5, R3). Live, curl allowed. *Method revised in v1.3 (D-43).*
- Given: `curl -s -o /dev/null --limit-rate 400k --max-time 25 <deb.debian.org large file>`.
- When: every 50 ms, QA logs the summed rx_bytes/tx_bytes of eth0, wlan0, wlan1 (wall clock) and `net.txt` with its mtime. The mtime identifies the daemon tick that wrote the tooltip. For each distinct tick, `Total ↓`/`↑` is paired with a **tick-matched reference**: the sysfs rate over [tick − 1 s, tick], interpolated between the 50 ms samples. This is exactly the 1 s window the daemon averages (NET_SMOOTH = 4), so neither bursty traffic nor the read phase can split it. From t = 5 s, ten consecutive 2 s windows (by tick time) are taken; per window, tooltip value = mean over its ticks, reference = mean of their references.
- Then:
  - ↓: ≥ 8 of 10 windows have |tooltip − reference| ≤ 10 % of reference. Reference script: `…/scratchpad/wf3/qa3/ac10v13.py`.
  - ↑: same, with tolerance max(10 %, 2 KiB/s).
  - Over t = 5-25 s, the mean tooltip ↓ and ↑ are each within ±10 % of the plain sysfs rate over the same 20 s (no systematic bias).
- Rationale: v1.2 compared the 1 s average with a sysfs delta over the same 2 s window, which has a built-in 0.5 s lag; bursty uploads (2-26 KiB/s) then failed 2-4 windows although the 20 s means agreed within 1-6 % (QA rounds 1-3, dev2 analysis).

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
- Static: the daemon reads `PANELGRAPH_SYSNET`, `PANELGRAPH_PROCNET`, `PANELGRAPH_IPFORWARD`, `PANELGRAPH_IW`, `PANELGRAPH_ADDRS` and `PANELGRAPH_ALERT_HOLD` (grep, gate script in qa-instructions §11.0). Defaults are the real paths and 600.
- Static (v1.2): outside comments, `/sys/class/net`, `/proc/net`, `/proc/sys/net` and `/sys/class/ieee80211` appear only as default values of the env-overridable constants.
  - Every per-interface path and the phy name are built from `SYSNET`: via `<if>/phy80211/name`, or `dirname(SYSNET)/ieee80211/<phy>/name`.
  - The as-built v1 daemon fails this (DEF-05). While it fails, every sandbox monitor AC is **BLOCKED**.
- Acceptance runs on the developer's build. Results from a sed-patched copy are `SMOKE` only.
- Static (code review, D-32): the `device`/`phy80211` links are re-checked for every name in the 5 s slow scan, not cached for the name's lifetime. The sandbox cannot reproduce the late-link race, so this is a review check; QA quotes the code lines as evidence.
- Sandbox S-A: the tooltip contains `SBX-NET`, `10.99.0.25` and `10.99.0.1`, and never `HomeNet`, `192.168.1.` or `aa:bb:cc`.
- Live (AC-39) still shows the real values.

**AC-23: In-place switch never leaks captured bytes** (UD-a, R8, DEF-01, F-01). Sandbox, S-C.
- When: at t0, wlan1 `type` is written 1→803, the default route is removed, and rx continues at 2 MiB/s.
- Then:
  - In net.txt polled every 50 ms from t0 − 2 s to t0 + 35 s, `Total ↓` is never > 1.05 × 512 KiB/s.
  - It falls to < 5 KiB/s by t0 + 1.5 s.
  - The monitor strip and the `MONITOR wlan1` line appear within T1.

**AC-24: No pre-switch or pre-existing bytes or packets in the first monitor samples** (R8, F-01, D-31). Sandbox, S-C and S-B.
- Byte counters start at 5 GiB, packet counters at 5,000,000.
- S-C (wlan1 rx 2 MiB/s, 1000 pps after t0): `captured` is never > 2.2 MiB/s and `Mon scale` is never > 2.2 MiB/s from t0 to t0 + 35 s.
- S-B: a new `wlan0mon` with a 5 GiB base and rx 512 KiB/s gives `captured` never > 0.55 MiB/s.
- **Frame rate:** in S-C and in S-B (1000 pps each), from t0 to t0 + 35 s, the MONITOR line's `fr/s` figure never exceeds **1.1 ×** the fixture pps, i.e. never more than `1.1k fr/s` (OQ-13; 1.1 × because the display step at 1000 fr/s is 0.1k). A build that stores 0 as the packet baseline on the first monitor tick shows about `5000.0k fr/s` and fails.

**AC-25: New or removed interfaces detected per tick** (R8, NFR-6). Sandbox, S-B.
- When: `wlan0` is deleted and `wlan0mon` (type 803, device, phy0) is created atomically.
- Then:
  - The monitor strip (FF00FF at Pixel(139,31) once rx > 0) and the `MONITOR wlan0mon` line appear within T1.
  - `ch44 5220 MHz` appears in the MONITOR line within Tiw.
  - The deleted interface causes no "!" marker and no error.log entry.
- **Variant type 802 (prism)**: the same steps with `wlan0mon` created as type 802 give the same monitor strip and `MONITOR wlan0mon` line within T1, and `Total` unchanged (±5 %). This exercises the `{801, 802, 803}` rule (D-14).

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
- The monitor vif's operstate is `unknown` in both cases (as on real hardware); up/down comes from `flags`. A build that derives the state from `operstate == "up"` shows dotted in the Solid case and fails.
- **Solid**, S-B with wlan0mon rx = 0 (flags 0x1003, admin up), steady:
  - Pixel(x,31) = FF00FF for every x in 12-139.
  - Rows 16-30 for x 12-139 are T.
  - Pixel(1,31) and Pixel(7,31) are T.
- **Dotted**, S-E (wlan0mon flags 0x1002 = admin down, rx 0), steady:
  - On row 31, x 12-139: exactly 64 pixels are FF00FF and the rest are T, alternating between neighbours.
  - Rows 16-30 for x 12-139 are T.
  - The tooltip MONITOR line ends its state with `, down)`.

**AC-31: Monitor bytes never in the managed totals** (UD-a, R3). Sandbox, all monitor scenarios (S-B to S-H, S-S).
- In every 50 ms poll, `Total ↓/↑` ≤ 1.05 × the fake managed rates. Steady values are within ±5 %.
- In S-F, the `Sustained upload` segment never appears (if F-11 is built).

**AC-32: Switch back to managed** (R8). Sandbox, S-G after S-C.
- When: wlan1 `type` 803→1, with the route restored.
- Then:
  - Within T1 the tooltip has no `MONITOR ` line; it shows `monitor ended HH:MM:SS` while the strip remains.
  - From t0 + 1.25 s on, column x = 139 contains no FF00FF/FFA0FF. (Before that, the 1 s smoothing window may still carry a nonzero captured value in the newest column.)
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
  - wlan0 still exists (wlan0mon is added beside it, not instead of it), so the tooltip has `Idle: wlan0 not connected`.
- **H2**: wlan0mon removed, steady after 34 s.
  - 3 strips. Pixel(139,7) = FF4F00; Pixel(139,2) = T; Pixel(139,20) = FF4F00; Pixel(139,15) = T; Pixel(139,25) = FF4F00; Pixel(139,31) = FFE500.
  - Labels `top eth0`, `mid usb0`, `bottom wlan1`. `Idle: wlan0 not connected`.
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
  - `wlan1 ★ SBX-NET -41 dBm ch36 5180 MHz/80` (-41 is the `/proc/net/wireless` value; `iw link` says -45. Showing **-45 is a FAIL**: it means the `/proc/net/wireless` parser does not match the right-aligned ` wlan1:` name and the iw fallback hid it.)
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
- Fixture SSID bytes: `a&b<c>"d</tool><click>touch $QA/pwned</click>` + `\x07` + `\x0a`, written in iw's `\xNN` form, in **both** the `iw dev` fixture (`ssid`) and the `iw link` fixture (`SSID:`), so the check holds whichever source the build uses (D-35).
- Then:
  - `net.txt` has exactly one `<tool>`, one `</tool>`, one `<click>xfce4-taskmanager</click>`.
  - `Pango.parse_markup` succeeds.
  - The plain tooltip contains `a&b<c>"d</tool>` (literal) and no BEL or newline inside the SSID.
  - The SSID shown is ≤ 32 characters.
  - `$QA/pwned` never exists.
- Extended in v1.4 (AC-95): the fixture SSID also carries U+2028, `!! Gateway MAC changed`, U+202E and U+200B (as `\xe2\x80\xa8`, `\xe2\x80\xae`, `\xe2\x80\x8b`). The tooltip line count is unchanged, no line starts with `!!`, and none of those three code points appears anywhere in `net.txt`.

**AC-43: Tooltip template** (R6-R9, F-06). Sandbox, worst case = S-H1 + M2 alert + promisc wlan0 (exists, down) + forwarding (eth0 and wlan1 up) + tun0 VPN (if Shoulds are built).
- ≤ 10 lines. (With wlan0 kept beside wlan0mon in H1, this case reaches exactly 10 lines when all Shoulds are built: `!!`, Total, 3 strips, Gateway, `PROMISC wlan0`, VPN/upload, Forwarding, `Idle: wlan0 not connected`.)
- Line order: `!!`, `Total`, strip lines top→bottom, `Gateway`, `PROMISC`, VPN/upload, `Forwarding`, `Idle`.
- Pango-valid markup.
- Raw markup contains `<span foreground="#FF4F00">■</span>`, `<span foreground="#FFE500">■</span>`, `<span foreground="#FF00FF">■</span>` and `<span foreground="#FFA0FF">■</span>`.

**AC-44: PROMISC line** (R9, F-07). Sandbox, S-I.
- wlan0 flags 0x1003→0x1103: `PROMISC wlan0 (packet capture running)` appears within T5; it disappears within T5 when set back.
- `vnet9` (0x1303, no device) is never named.
- A monitor vif with 0x1103 gets no PROMISC line.
- Until wlan0mon is added, no FF00FF/FFA0FF/FF2020 pixel appears and the strip count stays 1. (After that, the monitor strip is expected; it is not part of this AC.)

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
- J2 (reconnect, deterministic): in one step the 10.99.0.1 ARP row is removed and then carrier_changes +1 (the kernel flushes neighbour entries on carrier loss); 1 s later the new MAC row is added as complete (0x2).
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

**AC-76: Two monitor vifs on different phys** (R8, UD-a, D-34). Sandbox, S-S. Added in v1.1.
- Given: eth0 managed up at rx 256 / tx 64 KiB/s (default route via eth0), steady; then airmon-style on both cards: wlan0 and wlan1 deleted, `wlan0mon` (type 803, phy0, operstate unknown, flags 0x1003 = up, rx 256 KiB/s, 500 pps) and `wlan1mon` (type 803, phy1, operstate unknown, flags 0x1002 = admin down, rx 256 KiB/s, 500 pps); `iw dev` fixture: wlan0mon ch44 5220 MHz, wlan1mon ch6 2437 MHz.
- **SS1**, steady:
  - Exactly 2 strips (eth0 rows 0-14, monitor rows 16-31; row 15 T for all x): **exactly one** monitor strip and exactly one line containing `MONITOR`.
  - Pixel(139,5) = FF4F00; Pixel(139,20) = FF00FF.
  - `captured` = 512 KiB/s ±5 %; `injected 0 B/s`.
  - The MONITOR line contains, in this order, `wlan0mon (phy0, ch44 5220 MHz, up) + wlan1mon (phy1, ch6 2437 MHz, down)`.
  - `Total ↓` = 256 KiB/s ±5 % and `↑` = 64 KiB/s ±5 %, i.e. unchanged from before the vifs were added; in every 50 ms poll from the step on, `Total ↓` ≤ 1.05 × 256 KiB/s.
- **SS2**: both monitor rates set to 0, steady:
  - Solid baseline: Pixel(x,31) = FF00FF for every x in 12-139, because wlan0mon is up although wlan1mon is down. Rows 16-30 for x 12-139 are T.
- **SS3**: wlan0mon flags 0x1002 (operstate stays `unknown`), steady:
  - Dotted baseline: on row 31, x 12-139, exactly 64 pixels are FF00FF, alternating. Both groups end with `, down)`.

**AC-77: Monitor vif removed while captured history is on screen** (R8, UD-a). Sandbox, S-T (qa-instructions §11.2). Added in v1.2.
- Given: S-D steady (wlan1 managed 512/128 KiB/s; wlan1mon type 803, phy1, operstate unknown, flags 0x1003, rx 512 KiB/s, 1000 pps), so the monitor history is full of FF00FF.
- When: at t0 wlan1mon is removed atomically (`del_iface`), and its rates and iw entry are removed.
- Then:
  - Within T1 (0.6 s) the tooltip has no `MONITOR ` line and shows `monitor ended HH:MM:SS` while the strip remains.
  - From t0 + 1.25 s, column x = 139 contains no FF00FF/FFA0FF. Older columns keep their captured history and scroll left.
  - The monitor strip is gone between t0 + 32 s and t0 + 34 s. The strip-count sequence is 2 → 1 exactly once (no flapping), after which `Pixel(139,6)` = FF4F00 in the single full-height managed strip.
  - In every 50 ms poll, `Total ↓` ≤ 1.05 × 512 KiB/s.
  - No "!" marker, and error.log is not created or changed.

**AC-78: Monitor-mode palette is pixel-exact** (UD-a, D-07, R5). Sandbox, every PNG recorded in S-B, S-B802, S-C, S-D, S-F, S-S, S-T and S-U. Added in v1.2.
- Every pixel of every recorded `net.png` is one of T, FF4F00, FFE500, FF00FF or FFA0FF. FF2020 is allowed only on frame pixels during an M2 alert. Helper: `palette_violations()` in qa-instructions §11.4.
- No pixel is partial alpha (`pixel()` never returns `Aaa:rrggbb`).
- FF00FF/FFA0FF pixels occur only in the monitor strip rows of the image's current layout, and only while the monitor strip is active.
- FF4F00/FFE500 never occur in the monitor strip rows of the current layout.

**AC-79: Monitor detection does not depend on the interface name; the phy comes from the fake tree** (R8, UD-a, D-14, F-02). Sandbox, S-U (qa-instructions §11.2). Added in v1.2.
- Given: S-A steady; then `mon0` (type 803, phy **phy5**, which exists only in the fake tree; operstate unknown; flags 0x1003; rx 256 KiB/s, 500 pps) and a decoy `wlan2mon` (type 1, device link, no phy, operstate up, rx 128 KiB/s) are added in one step.
- Then, steady:
  - Exactly 3 strips (rows 0-9 wlan1, 11-20 wlan2mon, 22-31 monitor). Pixel(139,26) = FF00FF, and no FF00FF/FFA0FF in rows 0-20.
  - The tooltip has `MONITOR mon0 (phy5, ch44 5220 MHz, up)` and `captured 256` (±5 %).
  - `wlan2mon` has a managed strip line and is **not** named in the MONITOR line.
  - `Total ↓` = 640 KiB/s ±5 % (512 + 128). In every 50 ms poll from the step on, `Total ↓` ≤ 1.05 × 640 KiB/s.
  - The phy shown is `phy5`. Any other phy, or `?`, means the phy name is not read through `SYSNET` (fails AC-22 too).

---

## NEW-MUST (v1.4, F-25 hover popup, F-26 private runtime dir)

Design: `requirements.md` §4.7, D-46 to D-58. Procedures and the virtual-X harness: `qa-instructions.md` §12. Rules for every AC here:
- X tests run only on a private virtual display (Xvfb `:99` or higher; Xephyr nested in it for multi-head). Every xdotool call asserts that `DISPLAY` is not `:0`.
- The sandbox always sets `PANELGRAPH_ADDRS`. Processes are stopped only through Popen handles or pid files after comm and cwd checks.
- "Helper" means a process with comm `panelgraph-pop` and cwd = the sandbox runtime dir (found by a /proc scan, never `pgrep -f`). "Mapped" means `xwininfo -name panelgraph-popup` reports `IsViewable`.
- "Stub helper" (content-only ACs, no X): `PANELGRAPH_POPUP_CMD` = an absolute script that lives until `PANELGRAPH_DAEMON_PID` exits (e.g. waits on its pidfd); `DISPLAY` set to any value.

**AC-80: Wrapper records its parent** (F-25, D-48, NFR-4). Sandbox.
- After one `panelgraph-show net` call from parent P, `net.host` holds P's pid followed by a newline. A `panelgraph-show mem` call does not create or change it.
- AC-02 still holds: stdout byte-identical to `net.txt`, rc 0, no stderr, `PATH=/nonexistent`.
- Cost: the per-call time of the new wrapper minus the v1.3 wrapper (dash, ≥ 3 × 4000 sourced calls, minimum of each) ≤ 50 µs. AC-01 to AC-06 are re-run.

**AC-81: popup.json content** (F-25, D-50). Sandbox, stub helper, polls every 50 ms.
- Every poll parses as compact UTF-8 JSON with `v` = 1.
- Rows mirror the strips in order and count; each value is within ±5 % of the fixture and equals the tooltip's strip value of the same tick.
- S-A: one table row `wlan1 ★`, `↓ ` FF4F00 512 KiB/s, `↑ ` FFE500 128 KiB/s.
- S-D: a second, free row `wlan1mon (monitor)` with `↓ captured` ±5 % (FF00FF) and no `injected` cell while the monitor tx is 0; with the S-F/AC-29 fixture the `↑ injected` cell (FFA0FF) is present.
- S-T: span row `monitor ended HH:MM:SS` within T1; overflow strip label `other: …`; no NIC at all: span row `No network interfaces`.
- M2 (S-J1): a bold first row equal to the tooltip's `!!` line, within TM2. It is present whenever `gw.line` is set, also with 3 strips (SEC-13).
- Colours only from {null, FF4F00, FFE500, FF00FF, FFA0FF}. No SSID or IP appears in popup.json.

**AC-82: popup.json write policy** (F-25, D-50, D-30). Sandbox, stub helper.
- With constant content (all rates 0, steady), popup.json's mtime is unchanged over 5 s.
- It is never created with `PANELGRAPH_POPUP=0`, without `DISPLAY`, or with a relative `PANELGRAPH_POPUP_CMD` (which logs `not an absolute path` once).
- `mkdir popup.json.tmp`: no "!" marker, `net.txt` keeps updating, one `net aux [popup]` error.log entry per 10 min.

**AC-83: Helper lifecycle** (F-25, D-54, NFR-2/3/4). Virtual X, real chain (fake wrapper → panelgraph-show → daemon → helper). *Timing amended by the tech lead (A5).*
- Exactly one helper (comm `panelgraph-pop`, cwd = runtime dir, `popup.pid` = its pid) ≤ 5.5 s after `net.host` first appears. None without `DISPLAY`, with `PANELGRAPH_POPUP=0`, or before `net.host` exists.
- A second instance exits with rc 2 within 1 s.
- `kill -9` of the helper: respawn between 30 s and 41 s later; never more than one spawn per 30 s (count spawns with a logging `PANELGRAPH_POPUP_CMD` wrapper that `exec`s the helper).
- `PANELGRAPH_POPUP_CMD` = a stub that exits 1 (a crash, Q1): each respawn comes 30 s to 41 s after the previous exit, never sooner; `helper exited rc=1` is in error.log.
- Dead display (`DISPLAY=:<unused>`): rc 3 is logged; at most one spawn per 300 s.
- Daemon SIGTERM, `kill -9` and idle exit (AC-07): the helper is gone within 1 s and `popup.pid` is removed; a /proc scan finds no helper for that dir.
- The daemon count by comm `panelgraph` is unchanged (AC-04/05/06).

**AC-84: Show and hide** (F-25, D-49). Virtual X, fake panel.
- Pointer moved onto the item: not mapped at +0.35 s, mapped by +0.9 s.
- Moving inside the item, over its plug and button child windows: 0 unmapped samples (≥ 50 samples).
- Unmapped ≤ 0.2 s after the pointer leaves; shown again after re-entering.
- Never mapped while the pointer is outside the item (10 s sweep over the screen).

**AC-85: Live update** (F-25). Virtual X. While shown, adding a strip (e.g. a monitor vif) makes the popup one line taller, and changed rates redraw it, within 0.75 s of the popup.json change.

**AC-86: Placement** (F-25, D-53). Virtual X.
- Top panel: popup top = item bottom + 4, horizontally centred on the item, clamped with a 4 px margin.
- Bottom panel: popup bottom = item top − 4.
- Vertical left panel: popup x = item right + 4; a right panel is symmetric (popup right = item left − 4).
- Xephyr with two 1280x800 heads (`+xinerama`), item at the right end of head 0: the popup lies inside head 0.
- `PANELGRAPH_POPUP_MONITORS` is honoured. The popup never overlaps the item.
- The item moves while hidden (a neighbour changes width): the next show is centred on its new place (±1 px). The item moves while shown: re-placed (±1 px) within 0.6 s (D-58).

**AC-87: Rediscovery** (F-25, D-48). Virtual X.
- The fake panel and wrapper are killed and restarted with the item at a new x, the pointer resting where the item appears: the popup is mapped at the new place within 2.5 s of the new wrapper's first poll (net.host = its pid). The helper pid is unchanged.
- With a second fake wrapper (another plugin id) running another command, `net.host` keeps the net wrapper's pid and the popup attaches to the net item.

**AC-88: No focus or click impact** (F-25, D-53, SEC-04). Virtual X.
- `xwininfo` shows Override Redirect State `yes`; `_NET_WM_WINDOW_TYPE_TOOLTIP` and `WM_CLASS "panelgraph-popup", "Panelgraph-popup"` are set.
- The popup's input shape has 0 rectangles, and a point inside the popup is not hit by `XTranslateCoordinates` on root (the window below receives the click).
- A click on the item logs exactly one click; the popup is unmapped within 0.3 s and stays hidden while the pointer stays inside; it comes back after leave and re-enter.
- `xdotool getwindowfocus` is the same before and after the popup shows.
- A test client sends a synthetic `EnterNotify` (`XSendEvent`) to the item while the pointer is outside: the popup is never mapped.

**AC-89: Look** (F-25, D-52). Virtual X screenshot of the shown popup.
- Background pixel exactly 1C1C1E, border pixel 3A3A3C, the corner pixel is not 1C1C1E (rounded by the shape).
- No FF2020 pixel. Glyph hues only from the four graph colours (grey anti-aliasing only).

**AC-90: Cost** (F-25, NFR-4, D-58).
- Helper attached and hidden, 60 s: ≤ 0.05 % CPU and ≤ 2 voluntary context switches. This holds with a still panel and also while a neighbour item changes width every 0.25 s, so the panel moves the item's socket 4 times/s (the fake panel's relayout storm, §12).
- Helper shown, content changing at 4 Hz, no relayout storm, 60 s: ≤ 1.0 % CPU and ≤ 12 voluntary context switches per second.
- Helper shown, content changing at 4 Hz, with the relayout storm, 60 s: ≤ 1.0 % CPU. No context-switch bound here: each item move is one ConfigureNotify.
- Helper VmRSS ≤ 40 MB, hidden and shown.
- The daemon with the helper running still meets AC-21 (≤ 2 % CPU, ≤ 40 MB).

**AC-91: Robustness** (F-25, NFR-1).
- While shown, popup.json replaced by garbage, by a file > 16 KiB or by `"v":2`: no crash (helper pid unchanged), the last good content stays mapped, never an empty window.
- Xvfb killed: the helper exits (rc 3 logged by the daemon) within 1 s; the daemon keeps writing `net.txt` with no "!".
- The item's wrapper exits, while hidden or shown (xfce4-panel keeps the socket and a respawned wrapper reuses its id): the helper deselects the socket, stays, goes DETACHED at once and retries every 2 s (D-58).
- Kept socket (the fake panel keeps it, as xfce4-panel does): the wrapper exits while SHOWN and `net.host` still names the dead pid. A 4 Hz relayout storm for 20 s while DETACHED: the helper makes ≤ 12 voluntary context switches in those 20 s (the 2 s retries only). Then a new wrapper with the same socket id writes `net.host`: the helper re-attaches within 2.5 s, shows on hover, and its pid is unchanged.

**AC-92: Regression and static gate** (F-25, SEC-04). Sandbox + static.
- Same deterministic fixture with `PANELGRAPH_POPUP=1` (stub helper) and `=0`: `net.png` bytes and the `<tool>` text are identical, and identical to the v1.3 daemon's. The `Graph`/mem code path is unchanged.
- The daemon is still one file; AC-01 to AC-79 are re-run.
- Static, comments stripped (docstrings count), on `bin/panelgraph-popup`: none of `XGrab`, `XUngrab`, `XSetInputFocus`, `XWarpPointer`, `XSendEvent`, `subprocess`, `os.system`, `os.exec`, `os.spawn`, `ButtonPressMask`, `ButtonReleaseMask`, `PointerMotionMask`, `KeyPressMask`, `KeyReleaseMask`, `SubstructureRedirectMask`, `ResizeRedirectMask`, `XI_RawKeyPress`, `XI_RawKeyRelease`, `XI_RawMotion`, `XI_KeyPress`, `XI_Motion`. `XSelectInput` only on the item xid; `XChangeProperty` and `XShapeCombine*` only on the helper's own window; `XISelectEvents` only on root and only with `XI_RawButtonPress`.
- Static on `bin/panelgraph-daemon`: no `ctypes` or `gi` import; exactly two `subprocess.Popen` sites (iw, helper); AC-22 still passes for both files.

**AC-94: Private runtime dir** (F-26, D-55, NFR-3). Sandbox + unit probe.
- `XDG_RUNTIME_DIR` unset, `''` or `rel/x`: `panelgraph-show net` prints `<txt>!</txt><tool>panelgraph: XDG_RUNTIME_DIR is not set</tool>` with rc 0, starts no daemon, and creates nothing in its cwd or under `/tmp`. The daemon run directly exits 1 and creates nothing; the helper exits 3.
- A pre-created `panelgraph` that is a symlink: daemon rc 1, helper rc 3, nothing written to the target.
- `$d` (`$XDG_RUNTIME_DIR/panelgraph`) is a symlink to a dir we own: `panelgraph-show net` and `panelgraph-show mem` print `<txt>!</txt><tool>panelgraph: runtime dir is not private</tool>` with rc 0, nothing is written through the link (`seen`, `net.host`), and no daemon starts. A dangling symlink is refused the same way.
- `$d` does not exist yet: the wrapper is not refused and starts the daemon (first start).
- A `$d` owned by another uid cannot be reproduced without a second uid; it is covered by code review of the wrapper's `[ -O "$d" ]` test.
- A pre-existing dir at 0775 is set to 0700 on daemon start.
- AC-02 is still byte-identical with `PATH=/nonexistent`.
- A dir owned by another uid: unit probe through `SourceFileLoader` with `os.getuid` patched → `secure_dir()` returns False.

**AC-95: Hostile text** (D-56, SEC-06). Sandbox.
- AC-42 extended (see AC-42).
- An interface whose name contains byte 0xff (and U+202E) gives valid UTF-8 popup.json; its label contains `?` or U+FFFD, no surrogate and no U+202E.
- Unit: `clean("y"*50, 40)` ends with `…` and has 40 code points; `decode_ssid` keeps exactly 32 without an ellipsis.

**AC-96: iw drain race** (D-57, CR-1). Unit probe through `SourceFileLoader`.
- `PANELGRAPH_IW` = a stub `sh -c 'printf …'`; start a link run; patch `runner.proc.poll` so its first call does `proc.wait()` and returns the code (an exit after the first drain).
- `Not connected.` stub: `results[("link", "wlan1")]` has `data == {}` and `failed` False.
- `Connected to aa:bb:cc:dd:ee:02` stub: `data["bssid"]` is present. (The v1.3 code loses it.)
- AC-40, AC-41 and the M2 ACs are re-run.

**AC-97: Markup invariant** (SEC-11). Sandbox, under the S-L hostile SSID fixture (AC-95 version) and the 0xff interface name: `net.txt` has exactly one `<click>` and its body is `xfce4-taskmanager`; `<txt>`/`<img>` contain no variable text; inside `<tool>` the only `<` are those of `<b>`, `</b>`, `<span foreground="#XXXXXX">` and `</span>`.

**AC-98: Helper input validation** (SEC-02, SEC-05). Virtual X + unit.
- `net.host` naming a non-genmon process of ours: the helper stays DETACHED (logs `panel item not found`), stays alive.
- `net.host` or `popup.json` as a symlink: not followed (no crash; the symlinked popup.json content is never shown).
- popup.json > 16 KiB: ignored, helper pid unchanged.
- `PANELGRAPH_DAEMON_PID` `abc`, `0`, `''`, `-5`, `1 2` or unset → rc 3; a dead pid or a pid that is not the parent → rc 0.
- `PANELGRAPH_POPUP_XID` invalid (`0xZZ`, out of range) and `PANELGRAPH_POPUP_MONITORS` malformed → ignored, no crash. Each malformed hook produces its own line in popup.log (`[env:xid]` and `[env:monitors]`), also when both are invalid in the same run.
- An unreachable display (`DISPLAY=:97`) → rc 3 and one `[x] cannot open display` line in popup.log; the daemon still records `helper exited rc=3` in error.log.
- popup.log is an append log (D-54): with an invalid `PANELGRAPH_POPUP_MONITORS` and no resolvable item, the `[env:monitors]` line is still present after `[attach] panel item not found`. A log storm over 30 distinct keys (unit, `log_once` with 4096-code-point messages) keeps the file ≤ 16384 B. A popup.log that is a symlink is not followed (the target is unchanged) and a FIFO does not block.
- Unit, `os.getuid` patched: `resolve_host(pid)` of another uid → None. `parse_xid`, `parse_monitors`, `parse_dpi` and `parse_doc` reject the malformed inputs listed in `requirements.md` §4.7.7 and §4.7.9.

**AC-99: A grab or screen locker hides the popup** (SEC-10). Virtual X. While the popup is shown, a test client maps a fullscreen override-redirect "locker" window and takes `XGrabPointer`: the popup is unmapped within 0.3 s and still unmapped 5 s later while the grab holds.

---

## NEW-SHOULD (SKIPPED if not built)

**AC-52: Sustained upload and Up 5 min** (R9, F-11). Sandbox. *Window revised in v1.3 (D-44).*
- Fixture: wlan1 at rx 512 KiB/s, tx 128 KiB/s for ≥ 30 s before t0; from t0, tx 300 KiB/s, rx 100 KiB/s.
- Expected time from the F-11 rule (last-60 s average tx > 256 KiB/s and Σtx60 > Σrx60): 128·(60 − t) + 300·t > 256·60 → t > 44.65 s; Σtx60 > Σrx60 already holds then. `Sustained upload` first appears between **t0 + 44 s and t0 + 50 s** (rule time + 1 s bucket granularity + tick and scan slack), showing `1m00s` at first appearance. It must not appear before t0 + 44 s.
- `Up 5 min` = the fake managed tx bytes over the last min(300 s, daemon uptime) ±5 %. QA computes the reference from its own rate timeline: 128 KiB/s before t0, 300 KiB/s after.
- With wlan0mon tx 300 KiB/s and managed tx 0: never appears.
- Rationale: the v1.2 window (t0 + 60-67 s) assumed the alert needs a full 60 s at the new rate, which contradicts the F-11 averaging rule. The rule stays as specified.

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
- Given: L1 steps done, with wlan0mon tuned to wlan1's full channel width (`set freq <ctrl> <width> <center1>` from `iw dev wlan1 info`, today `5220 80 5210`); guard passes.
- When: a 25 s curl download at `--limit-rate 500k` runs over wlan1.
- Then:
  - Within T1 + Tiw, net.txt has `MONITOR wlan0mon (phy0, ch<N> <F> MHz, up)` with N/F = wlan1's channel (today `ch44 5220 MHz`).
  - Screenshots show 2 strips: FF4F00 in the upper strip, FF00FF in the lower one.
  - **Capture is substantial:** in ≥ 8 of 10 AC-10 windows (2 s each, from t = 5 s), the mean `captured` rate is ≥ 50 % of the wlan1 sysfs rx rate.
  - **Not in Total:** in ≥ 8 of the same 10 windows, mean `Total ↓` is within ±10 % of the wlan1 sysfs rx rate (AC-10 2 s window method, not single 50 ms polls against an instantaneous rate).
  - **Vif counter vs tooltip** (v1.2): in ≥ 8 of the same 10 windows, Δ`/sys/class/net/wlan0mon/statistics/rx_bytes`/Δt is within ±10 % of the mean `captured` figure.
  - **Bar and marker on screen** (v1.2), in the 142x34 plugin-26 crop, where crop (x, y) = net.png (x+1, y+1):
    - the captured bar (crop x 2-5, y 17-32) is exactly FF00FF while `captured` > 0;
    - the baseline marker (crop row 32, x 13-140) is FF00FF in every column (solid: the vif is up);
    - no FFA0FF pixel appears (no injection).
  - The guard passes throughout.
- If the driver rejects the 80 MHz tuning, QA falls back to `set channel <N>`, records this, and reports the capture and not-in-Total parts as **INCONCLUSIVE**, never PASS (a 20 MHz monitor captures only beacons/management frames, a few KiB/s, which vanish inside the ±10 % tolerance).
- After rollback:
  - Within T1 the `MONITOR` line is replaced by `monitor ended HH:MM:SS`.
  - From t0 + 1.25 s, column 139 has no FF00FF.
  - The monitor strip is gone within 34 s, with no "!".
  - The guard passes; wlan0 flags are 0x1103 while netdiscover runs (0x1003 otherwise); NM shows wlan0 managed.

**AC-68: L2, in-place switch of wlan0** (R8). NEW-MUST, APPROVAL.
- Given: wlan0 switched in place and tuned to wlan1's full channel width (`set freq`, as in AC-67).
- Then:
  - The tooltip shows `MONITOR wlan0 (phy0` within T1.
  - During a 25 s `--limit-rate 500k` download over wlan1: captured ≥ 50 % of the wlan1 sysfs rx rate, and `Total ↓` within ±10 % of the wlan1 sysfs rx rate, each in ≥ 8 of 10 AC-10 windows (2 s). The 80 MHz fallback rule of AC-67 (INCONCLUSIVE) applies.
  - `rx_bytes` before and after the switch is recorded, answering "do counters survive?" (survive if after ≥ before).
- After rollback (`set type managed`):
  - Within T1 the `MONITOR wlan0` line is replaced by `monitor ended HH:MM:SS`.
  - The monitor strip is gone within 34 s.
  - `Total` never exceeds 1.1 × the wlan1 sysfs rate on the switch-back tick.
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
- `sudo aireplay-ng --test wlan0mon` (never `-0`/deauth) during L1 gives FFA0FF columns and an FFA0FF right bar in the monitor strip, and `Total ↑` is unchanged (±10 % of the wlan1 sysfs tx rate).
- phy0 only; never inject on phy1 (the uplink card). Injection exposes wlan0's permanent MAC aa:bb:cc:dd:ee:03. The user must accept this when deciding OQ-12.

**AC-93: Live hover popup** (R11, F-25). NEW-MUST (v1.4), APPROVAL (the user installs, restarts the daemon and hovers; agents never move the `:0` pointer).
- The user runs `./install.sh`, restarts the daemon through its pid file (README "Stopping the daemon"), then hovers over the network graph and confirms:
  - the popup appears about 0.5 s after the pointer rests on the item, just below it (or above/beside it for a bottom or vertical panel), inside the screen;
  - it lists the strip interfaces with plausible rates that change while it is shown;
  - a click still opens xfce4-taskmanager and hides the popup;
  - it disappears when the pointer leaves.
- QA read-only checks (no pointer action):
  - one `panelgraph-pop` runs with cwd `$XDG_RUNTIME_DIR/panelgraph`;
  - `net.host` holds the pid of the net item's genmon wrapper (argv[1] ends in `libgenmon.so`, its command is `panelgraph-show net`);
  - the window named `panelgraph-popup` exists, unmapped, override-redirect;
  - the runtime dir is mode 0700;
  - helper idle CPU and RSS meet AC-90.
- F-25 is "done" only after the user confirms; until then it is "ready for live acceptance".
