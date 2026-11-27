# v1.0.0 release checklist

Status as of 2026-11-27. The repo is public at
https://github.com/danilchernyshev/xfce4-genmon-netgraph. `main` holds the code, README,
LICENSE (MIT), CLAUDE.md and the spec in `docs/`. There is no tag, no release and no
screenshot yet. The remaining steps need a real **Kali/XFCE** desktop: the repo was published
from Linux Mint (Cinnamon), where genmon can't run.

Tick each box when it's done and commit this file with it.

## 1. Git identity (once per OS)

- [ ] Check `git config --global user.email`. It must be the GitHub noreply address, so no
      personal or hostname-derived email ends up in public history:
  ```bash
  git config --global user.name "Danil Chernyshev"
  git config --global user.email "5802166+danilchernyshev@users.noreply.github.com"
  ```

## 2. Reconcile with the copy deployed on Kali

The daemon was developed and deployed on Kali (`~/.local/bin`) before this repo existed.

- [ ] Clone the repo (or `git pull`) and compare:
  ```bash
  cmp bin/panelgraph-daemon ~/.local/bin/panelgraph-daemon
  cmp bin/panelgraph-show   ~/.local/bin/panelgraph-show
  ```
- [ ] If they differ, diff them and find out which is newer before running `install.sh`, which
      overwrites the deployed copy. Commit any newer Kali-side changes first.

## 3. Verify the README install steps on XFCE

- [ ] `sudo apt install xfce4-genmon-plugin python3-cairo iw xfce4-taskmanager`, then `./install.sh`.
- [ ] Add a Generic Monitor exactly as the README says. Confirm that:
  - the command needs a full path (genmon does not expand `~`): README already says so;
  - period `0.25` is accepted and gives about 4 updates/s (unverified so far);
  - the "Label: untick" step is right.
- [ ] Fix the README where reality differs.
- [ ] Stop the daemon with the README's "Stopping the daemon" snippet (never `pkill -f`). Confirm
      the panel restarts it on the next poll.

## 4. Screenshot

- [ ] Capture the panel graph with the tooltip open: `xfce4-screenshooter -r`.
- [ ] **Redact real SSID, MACs, IPs and gateway** in the tooltip before committing: blur them, or
      use the sandbox from `docs/qa-instructions.md` §5 with fake values (`HomeNet`,
      `aa:bb:cc:dd:ee:01`, `192.168.1.x`).
- [ ] Save as `docs/screenshot.png` and add `![panel](docs/screenshot.png)` right under the README title.

## 5. Tag and release

- [ ] Commit, push, tag and create the release:
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

## Later

- [ ] A `.deb` package. This is a prerequisite for a Kali "New Tool Request" on
      bugs.kali.org (https://www.kali.org/docs/tools/submitting-tools/), which also wants
      license, dependencies, similar tools and proof of activity. Realistic only once the
      project has users.
