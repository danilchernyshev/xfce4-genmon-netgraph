# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**xfce4-genmon-netgraph** (internal name **panelgraph**): a cpugraph-style network (and RAM) graph for the XFCE panel, shown through
`xfce4-genmon-plugin`. There are two executables in `bin/` and no build step, package
manager or test suite in the repo. Runtime deps: `python3-cairo`, `xfce4-genmon-plugin`, `iw`.

```bash
./install.sh                              # copies bin/* to ~/.local/bin (copies, not symlinks: re-run after every edit)
python3 -m py_compile bin/panelgraph-daemon   # quick syntax check
cat $XDG_RUNTIME_DIR/panelgraph/error.log     # last daemon error
```

The genmon panel item runs `~/.local/bin/panelgraph-show net` (`mem` for RAM). `panelgraph-show`
always starts the daemon from `~/.local/bin`, never from the repo. So a change only takes
effect after `install.sh` and a daemon restart (stop it via its pid file, see Safety).

## Architecture

- **`bin/panelgraph-show`** (POSIX sh) is the genmon command. It runs about 8 times a second, so it
  uses **shell builtins only** on the hot path. It prints `$XDG_RUNTIME_DIR/panelgraph/<name>.txt`,
  touches `seen`, and starts the daemon with `setsid -f` when the pid file is stale. Stale means
  `/proc/$pid/comm != panelgraph` or `/proc/$pid/cwd` is not the runtime dir, and it only starts
  one while the `lock` flock is free.
- **`bin/panelgraph-daemon`** (one Python file, kept single-file so deploys stay atomic) is the
  core. `main()` closes inherited fds (genmon waits for EOF on every pipe), chdirs into the
  runtime dir, takes `flock` and sets `/proc/self/comm = panelgraph`. `run()` then ticks every
  `INTERVAL` (0.25 s):
  - `Graph("mem")` draws the RAM graph. It is the legacy generic renderer; leave it unchanged.
  - `NetMonitor.tick()` returns `(layout, markup)` and `NetGraph` renders the layout.
    - Per tick: `sample()` reads `/sys/class/net/*/statistics` for candidates only (interfaces
      with a `device` or `phy80211` link). It classifies each one as managed or monitor
      (ARPHRD 801–803), smooths over `NET_SMOOTH` samples and keeps a 128-column history per key.
    - Every `SLOW_EVERY` ticks (about 5 s), the slow scan runs: route/arp/wireless, the `iw`
      results (`IwRunner`, async, at most one spawn per 5 s), `GwWatch` (gateway MAC alert with a
      `gw.json` baseline), uploads, PROMISC, VPN and ip_forward. Each item sits in its own
      try/except with `log_once`. Auxiliary failures must never put the graph into its "!" error state.
  - The PNG is re-rendered only when the pixel-key tuple changes. The txt is rewritten only when
    the text changes. Both are written atomically (`.tmp` + `os.replace`; QA relies on the name
    `net.png.tmp`).
  - The daemon exits when `seen` has not changed for `IDLE_EXIT` s (checked on the monotonic
    clock). After a fatal error it stays alive for `FATAL_HOLD` s while holding the lock, so
    genmon does not respawn it 8 times a second.
- **Image layout**: 140×32. Down/up bars come first, then 128 history columns, cut into up to
  `MAX_STRIPS` horizontal strips: one per managed card, an `other` sum strip, and the monitor
  strip last. An alert frame means the content box shrinks by 1 px. The exact geometry, colours
  and paint order are in `docs/requirements.md` §4.1 / `docs/dev-instructions.md` §4. QA checks
  them pixel by pixel, so treat them as binding.

## Specs are binding

`docs/requirements.md` (spec v1.3, decision log D-xx, features F-xx),
`docs/acceptance-criteria.md` (AC-01…AC-79) and `docs/dev-instructions.md` define the behaviour.
Before changing behaviour, read the relevant section. If code and spec conflict, ask rather than
improvise. `docs/backup/` holds earlier versions of the docs and daemon. Don't edit it.

Invariants that are easy to break:
- **Cost (NFR-4):** no process spawn per tick, and never `nmcli`/`ip`/`ss`/`subprocess.run`. Every
  subprocess uses `stdin/stderr=DEVNULL, close_fds=True, start_new_session=True`. Target ≤ 2 % of
  one core and RSS ≤ 40 MB.
- **Monitor traffic is never added to the managed total.** Read `rx_packets` for every candidate
  on every tick (D-31). Read `type` *after* the counters. When the kind changes, drop the delta
  (rebaseline).
- No anti-aliasing (`ANTIALIAS_NONE`) and no colour outside the defined palette. `#FF2020` is
  used only for the alert frame.
- Hard-coded `/sys/class/net`, `/proc/net`, `/proc/sys/net` and `/sys/class/ieee80211` may appear
  only as defaults of the `PANELGRAPH_*` env constants (static gate AC-22).

## Testing: sandbox only

The repo has no automated tests. QA runs a copy of the daemon in a fake sysfs/proc tree, using
the `PANELGRAPH_SYSNET`, `PANELGRAPH_PROCNET`, `PANELGRAPH_IPFORWARD`, `PANELGRAPH_ADDRS`,
`PANELGRAPH_IW` (stub) and `PANELGRAPH_ALERT_HOLD` env vars and a separate `XDG_RUNTIME_DIR`.
The reference harness `sbx.py` (fixture builder, traffic engine, pixel reader) and the scenarios
are in `docs/qa-instructions.md` §5–§6 and §11. Its hard-coded scratch paths are stale; point
`QA` at the current scratchpad. **Always set `PANELGRAPH_ADDRS`**: without it the daemon calls
ioctl on the real interfaces and shows live IPs.

## Safety (from the dev/QA docs; this is a pentest box)

- **Never `pkill -f panelgraph` / `pgrep -f`**: the pattern matches your own shell. Stop a daemon
  only via its pid file, after checking `/proc/$pid/comm == panelgraph` and its cwd.
- Do not change interface state (no airmon-ng, `iw … set`, `ip link set`, nmcli, macchanger,
  firewall). Monitor mode, promisc and gateway changes are tested only in the sandbox. Live
  variants (`qa-instructions.md` §8) need the user's explicit approval, and the user runs the sudo.
- Do not touch xfconf, panel settings or panel items, and do not restart xfce4-panel.
- No foreground `sleep`. Wait with `timeout N tail -f /dev/null`. Test traffic is limited to rate-limited
  `curl` downloads to `/dev/null` from `deb.debian.org`, each under 30 s.
