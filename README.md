# xfce4-genmon-netgraph

A cpugraph-style live network graph for the **XFCE panel**, with security signals for
pentesters: one strip per network card, monitor-mode traffic in its own colour, Wi-Fi
details, gateway-MAC (ARP spoofing) alerts, PROMISC and VPN detection.

Built for Kali Linux (XFCE) and Debian. It runs inside
[`xfce4-genmon-plugin`](https://docs.xfce.org/panel-plugins/xfce4-genmon-plugin), needs no
root and no packet capture, and only reads `/sys` and `/proc`.

![XFCE panel](https://img.shields.io/badge/XFCE-genmon-blue) ![Python 3](https://img.shields.io/badge/Python-3.10%2B-green) ![License](https://img.shields.io/badge/license-MIT-brightgreen)

## Features

- **Per-card strips.** Each active managed interface (Ethernet, Wi-Fi, WWAN) gets its own
  horizontal strip, up to 3. Extra cards are summed into an `other` strip.
- **Monitor-mode awareness.** Traffic on monitor interfaces (`wlan0mon`, or an in-place
  switched `wlan0`) is drawn in magenta in a separate bottom strip with its own scale. It is
  **never** added to the managed total. Detection uses the interface type, not the name.
- **Wi-Fi details in the tooltip:** SSID, signal (dBm), channel, frequency, width, bitrates
  and AP/mesh/IBSS flags, via `iw`.
- **Gateway MAC alert.** A red frame and a `!!` tooltip line appear when the default
  gateway's MAC changes on the same link (in-session ARP poisoning).
- **Default route moved.** The tooltip notes when the default route switches interface.
- **PROMISC detection.** The tooltip shows interfaces in promiscuous mode, e.g. a running sniffer.
- **VPN visibility.** Active tun/WireGuard interfaces are listed (`VPN wg0 up`).
- **Upload tracking.** A sustained-upload warning and a 5-minute upload total.
- **Forwarding note.** Shown when IP forwarding is on and two or more managed NICs are up.
- **Cheap to run.** Samples every 250 ms, spawns at most one `iw` per 5 s, and targets ≤ 2 % of
  one core and ≤ 40 MB RSS. The daemon exits by itself 30 s after the panel stops asking.

## Requirements

- XFCE panel with `xfce4-genmon-plugin`. Other desktops (Cinnamon, GNOME, KDE) are not
  supported: genmon is an XFCE panel plugin.
- Python 3.10+ with pycairo (`python3-cairo`)
- `iw` (optional, for Wi-Fi details)
- `xfce4-taskmanager` (optional, opened when you click the graph)

## Installation

```bash
sudo apt install xfce4-genmon-plugin python3-cairo iw xfce4-taskmanager

git clone https://github.com/danilchernyshev/xfce4-genmon-netgraph.git
cd xfce4-genmon-netgraph
./install.sh            # copies bin/panelgraph-daemon and bin/panelgraph-show to ~/.local/bin
```

Then add the panel item:

1. Right-click the panel → **Panel** → **Add New Items…** → **Generic Monitor** → **Add**.
2. Right-click the new item → **Properties**:
   - **Command:** the full path printed by `echo ~/.local/bin/panelgraph-show`, followed by
     ` net`. For example: `/home/kali/.local/bin/panelgraph-show net`
   - **Label:** untick
   - **Period (s):** `0.25`
3. Close the dialog. The graph appears within a second. The daemon starts on demand: no autostart
   entry and no systemd unit are needed.

Optional RAM graph: add a second Generic Monitor with the same command, but ending in `mem` instead of `net`.

### Verify

```bash
d="$XDG_RUNTIME_DIR/panelgraph"
cat "/proc/$(cat "$d/pid")/comm"   # -> panelgraph
cat "$d/net.txt"                   # what genmon displays
cat "$d/error.log"                 # last error, if any
```

### Update

```bash
git pull && ./install.sh
```

Then stop the running daemon (see [Stopping the daemon](#stopping-the-daemon)). genmon starts
the new version on its next poll.

### Uninstall

Remove the Generic Monitor item from the panel, stop the daemon, then:

```bash
rm -f ~/.local/bin/panelgraph-daemon ~/.local/bin/panelgraph-show
rm -rf "$XDG_RUNTIME_DIR/panelgraph"
```

## Reading the graph

The image is 140×32 px: two current-value bars on the left, then 128 history columns
(newest on the right, one column per 250 ms ≈ 32 s of history).

| Colour | Meaning |
|---|---|
| `#FF4F00` orange | managed download (same colour as the netload plugin) |
| `#FFE500` yellow | managed upload |
| `#FF00FF` magenta | monitor mode: captured frames (rx), plus a baseline marker: solid if the monitor interface is up, dotted if down |
| `#FFA0FF` pink | monitor mode: injected frames (tx) |
| `#FF2020` red frame | gateway MAC alert |
| `!` | the graph itself failed. See `error.log`, retried every 5 s |

Strips are stacked top to bottom: managed cards sorted by name, then `other`, then the
monitor strip. All managed strips share one scale (minimum 64 KiB/s). The monitor strip has its own.

Hover for the tooltip (up to 10 lines):

```
!! Gateway MAC changed 14:02 aa:bb:cc:dd:ee:01 → de:ad:be:ef:00:01 via wlan1
■■ Total ↓ 512.0 KiB/s ↑ 128.0 KiB/s   Scale 512.0 KiB/s
top  wlan1 ★ HomeNet -27 dBm ch44 5220 MHz/80  rx 780/tx 867 Mbit/s  ↓ 10.9 KiB/s ↑ 10.0 KiB/s
bottom  ■ MONITOR wlan0mon (phy0, ch6 2437 MHz, up)  ■ captured 1.2 MiB/s  ■ injected 0 B/s  1.2k fr/s · not in total
Gateway 192.168.1.1 aa:bb:cc:dd:ee:01 via wlan1, IP 192.168.1.25
PROMISC wlan0 (packet capture running)
VPN wg0 up · Up 5 min 12.3 MiB
Idle: eth0 no carrier
```

`★` marks the default-route interface. The SSID is attacker-controlled input, so it is
sanitised and escaped before it reaches the panel markup.

## Gateway MAC alert

Every 5 s the daemon reads the default route and the gateway's entry in `/proc/net/arp`, and
compares the MAC with a baseline stored in `$XDG_RUNTIME_DIR/panelgraph/gw.json`. A changed
MAC on the same interface, gateway IP and BSSID turns on the red frame. The frame stays 10 min
after the MAC returns to normal. The `!!` line stays until the daemon exits.

If the router really changed (new hardware), accept the new MAC:

```bash
rm -f "$XDG_RUNTIME_DIR/panelgraph/gw.json"
```

Limitations, so you don't overrate it:
- The baseline is silently re-taken on a reconnect or a BSSID change (roaming). A
  deauth-forced reconnect to an evil twin, or poisoning right after a reconnect, is not detected.
- A cache that was already poisoned when the baseline was taken is not detected.
- IPv4 only. IPv6 NDP spoofing and rogue router advertisements are not covered.
- Your own `bettercap`/`arpspoof` poisons other hosts, not this machine, so it won't trigger the alert.

## Configuration

All tunables are constants at the top of `bin/panelgraph-daemon`. Edit them, re-run
`./install.sh` and stop the daemon so the new copy starts.

| Constant | Default | Description |
|---|---|---|
| `INTERVAL` | `0.25` | Sample interval, seconds |
| `HISTORY` | `128` | Graph width in px (1 px per sample) |
| `HEIGHT` | `32` | Graph height in px (panel size 34 minus genmon padding) |
| `NET_FLOOR` | `64 KiB/s` | Minimum full scale |
| `NET_SMOOTH` | `4` | Samples averaged (1 s window) |
| `MAX_STRIPS` | `3` | Maximum strips in the graph |
| `IDLE_EXIT` | `30` | Seconds without a genmon poll before the daemon exits |
| `CLICK` | `xfce4-taskmanager` | Command run on click |

## Stopping the daemon

The daemon exits by itself 30 s after the panel item is removed. To stop it now:

```bash
d="$XDG_RUNTIME_DIR/panelgraph"; pid=$(cat "$d/pid")
[ "$(cat /proc/$pid/comm)" = panelgraph ] && kill "$pid"
```

Don't use `pkill -f panelgraph`: the pattern also matches the shell running it.

## How it works

```
xfce4-genmon-plugin (panel item, every 0.25 s)
    └── panelgraph-show net          POSIX sh, builtins only
            ├── prints $XDG_RUNTIME_DIR/panelgraph/net.txt  (<img>, <tool>, <click> markup)
            ├── touches "seen" (keeps the daemon alive)
            └── starts panelgraph-daemon if it isn't running (flock-guarded, single instance)
                    ├── every 250 ms: /sys/class/net/*/statistics + type → per-card and monitor rates
                    ├── every 5 s: /proc/net/route, arp, wireless, flags, ip_forward, iw (async)
                    ├── renders net.png with pycairo (no anti-aliasing, only when pixels change)
                    └── writes net.png / net.txt atomically (tmp + rename)
```

Runtime files in `$XDG_RUNTIME_DIR/panelgraph/`:

| File | Purpose |
|---|---|
| `net.png`, `net.txt` | graph image and genmon markup |
| `mem.png`, `mem.txt` | RAM graph |
| `pid`, `lock` | daemon pid, single-instance flock |
| `seen` | touched on every poll, used for idle exit |
| `gw.json` | gateway MAC baseline (delete it to accept a new MAC) |
| `error.log` | last error |

## Testing

There are no automated tests in the repo. Behaviour is specified in `docs/` and verified in a
sandbox. The sandbox runs the daemon against a fake sysfs/procfs tree, so monitor mode, PROMISC
and ARP spoofing can be tested without root and without touching real interfaces:

| Variable | Overrides |
|---|---|
| `PANELGRAPH_SYSNET` | `/sys/class/net` |
| `PANELGRAPH_PROCNET` | `/proc/net` |
| `PANELGRAPH_IPFORWARD` | `/proc/sys/net/ipv4/ip_forward` |
| `PANELGRAPH_ADDRS` | file of `ifname ip` lines instead of the `SIOCGIFADDR` ioctl (always set it in a sandbox) |
| `PANELGRAPH_IW` | path to `iw` (point it at a stub) |
| `PANELGRAPH_ALERT_HOLD` | gateway alert hold time, seconds (default 600) |
| `XDG_RUNTIME_DIR` | output directory (use a separate one so the sandbox gets its own lock and pid) |

Documentation:
- `docs/requirements.md`: specification v1.3, including the decision log and traceability.
- `docs/acceptance-criteria.md`: acceptance criteria AC-01 to AC-79.
- `docs/dev-instructions.md`: implementation guide and the constraints to keep.
- `docs/qa-instructions.md`: QA procedures and the sandbox harness `sbx.py`.

## License

MIT, see [LICENSE](LICENSE).
