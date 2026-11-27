# v1.0.0 release checklist

Status as of 2026-11-27. The repo is public at
https://github.com/danilchernyshev/xfce4-genmon-netgraph. `main` holds the code, README,
LICENSE (MIT), CLAUDE.md and the spec in `docs/`. There is no tag, no release and no
screenshot yet. The remaining steps need a real **Kali/XFCE** desktop: the repo was published
from Linux Mint (Cinnamon), where genmon can't run.

Tick each box when it's done and commit this file with it.

## 1. Git identity (once per OS)

- [x] Check `git config --global user.email`. It must be the GitHub noreply address, so no
      personal or hostname-derived email ends up in public history:
  ```bash
  git config --global user.name "Danil Chernyshev"
  git config --global user.email "5802166+danilchernyshev@users.noreply.github.com"
  ```

## 2. Reconcile with the copy deployed on Kali

The daemon was developed and deployed on Kali (`~/.local/bin`) before this repo existed.

- [x] Clone the repo (or `git pull`) and compare:
  ```bash
  cmp bin/panelgraph-daemon ~/.local/bin/panelgraph-daemon
  cmp bin/panelgraph-show   ~/.local/bin/panelgraph-show
  ```
- [x] If they differ, diff them and find out which is newer before running `install.sh`, which
      overwrites the deployed copy. Commit any newer Kali-side changes first.
      *(Files are identical — nothing to reconcile.)*

## 3. Verify the README install steps on XFCE

- [x] `sudo apt install xfce4-genmon-plugin python3-cairo iw xfce4-taskmanager`, then `./install.sh`.
- [x] Add a Generic Monitor exactly as the README says. Confirm that:
  - the command needs a full path (genmon does not expand `~`): README already says so;
  - period `0.25` is accepted and gives about 4 updates/s (unverified so far);
  - the "Label: untick" step is right.
      *(Live daemon confirmed running with two wlan cards via genmon plugin 26.)*
- [x] Fix the README where reality differs.
      *(No discrepancies found.)*
- [x] Stop the daemon with the README's "Stopping the daemon" snippet (never `pkill -f`). Confirm
      the panel restarts it on the next poll.
      *(Done repeatedly during the F-25 live checks; genmon restarts it within a second.)*

## 4. Screenshot

- [x] Capture the panel graph with the tooltip open: `xfce4-screenshooter -r`.
      *(Used sandbox with fake values: HomeNet, aa:bb:cc:dd:ee:01, 192.168.1.x.
      Composite of 4 scenarios: single wlan, two wlan, wlan+monitor, two wlan+monitor.)*
- [x] **Redact real SSID, MACs, IPs and gateway** in the tooltip before committing: blur them, or
      use the sandbox from `docs/qa-instructions.md` §5 with fake values (`HomeNet`,
      `aa:bb:cc:dd:ee:01`, `192.168.1.x`).
- [x] Save as `docs/screenshot.png` and add `![panel](docs/screenshot.png)` right under the README title.

## 5. Tag and release

- [x] Commit, push, tag and create the release:
  ```bash
  git tag -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0
  gh release create v1.0.0 --title "v1.0.0" \
    --notes "First public release: per-card strips, monitor-mode strip, Wi-Fi details, gateway MAC (ARP spoofing) alert, route-move, PROMISC, VPN and upload signals."
  ```

## 6. Announce (optional, ask the user first)

- [ ] r/netsec: only in the monthly "Discussion & Tool Thread". Standalone tool posts get removed.
- [ ] r/Kalilinux, r/xfce: check the sidebar rules first.
- [ ] Ask the genmon script collections listed on the suckless genmon page (xtonousou,
      almaceleste, levimake) to link the project.

## Hover popup (F-25) live acceptance, AC-93 (the user does these steps)

The popup is built and passed the sandbox and virtual-X self-test. It is "ready for live acceptance"
until the user confirms these steps.

- [x] Review the feature/hover-popup branch, then merge it into main or check it out. install.sh copies
      from the working tree, so the branch must be checked out before you run it.
- [x] `./install.sh` (now copies three files), then stop the daemon with the README's "Stopping the
      daemon" snippet. genmon starts the new one on its next poll, and the daemon starts
      `panelgraph-popup` within about 5 s.
- [x] Hover over the network graph: the popup appears after about 0.5 s just below the item, inside the
      screen, with plausible rates that change while it is shown.
- [x] Click the graph: xfce4-taskmanager still opens and the popup hides.
      *(Taskmanager opens. The popup hides but comes back about 0.5 s later while the pointer stays
      on the item: LIVE-CLICK-1, deferred by the owner as not critical.)*
- [x] Move the pointer away: the popup disappears at once.
- [x] Read-only checks (no pointer action needed): `cat /proc/$(cat "$XDG_RUNTIME_DIR/panelgraph/popup.pid")/comm`
      prints `panelgraph-pop`; `stat -c %a "$XDG_RUNTIME_DIR/panelgraph"` prints `700`.

## Follow-ups deliberately left out of F-25

Details and reasons are in `requirements.md` §8.1.

- [ ] CR-3, v1.0.1: rebaseline a candidate that temporarily loses its `device`/`phy80211` link
      (`c.prev = c.kind = None`), plus a link-flap sandbox AC. Deferred: touches the per-tick sampler.
- [ ] CR-4: true running sums for F-11, then re-run AC-52. Deferred: about 10 µs/s, no user impact.
- [ ] CR-5: compute `link_target()` lazily inside `IwRunner.poll`. Deferred: a few µs per tick.
- [ ] CR-6: decide with F-17 whether to build the ppp line or stop reading PPP `operstate`.
- [ ] CR-7: keep draining iw past 64 KiB and fail with `too large`. Deferred: unreachable in practice.
- [ ] SEC-13: re-check the gateway MAC 10-15 s after a `carrier_changes`/BSSID re-baseline. Deferred:
      new detection logic, not part of F-25.
- [ ] v1.0.1: make `esc()` also drop BAD_CATS (filter only, no truncation) so every tooltip value is
      covered; extend AC-95 with an ifname containing U+2028 + `!! Gateway MAC changed` and U+202E;
      re-run AC-42/AC-43.

- [ ] LIVE-CLICK-1: after a click the popup re-shows about 0.5 s later while the pointer stays on
      the item (panel pointer grab crossings). Fix in the helper's state machine and add a grabbing
      stand-in to the virtual-X test.
- [ ] PERM-0664: `seen`, `net.host`, `lock` and `gw.json` are 0664 inside the 0700 runtime dir.
- [ ] REG-EMU-1: re-run the full emulator regression (AC-01…AC-99) with a fixed harness; check the
      one AC-32 strip-count flip it logged.

## Later

- [ ] A `.deb` package. This is a prerequisite for a Kali "New Tool Request" on
      bugs.kali.org (https://www.kali.org/docs/tools/submitting-tools/), which also wants
      license, dependencies, similar tools and proof of activity. Realistic only once the
      project has users.
