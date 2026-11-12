# AOC Q27G2G4: black screen with white power light on DisplayPort

**Reproduction, a reset that needs no unplugging, and the evidence behind it**

Written 2026-11-11 from tests on one monitor and one PC. Everything under "Observed" was seen on that hardware on that day. Everything under "Interpretation" is a working explanation that has not been proven.

---

## 1. Summary

- The monitor goes black and stays black after its **power button is pressed off and on**, or after the **PC restarts**, while connected by DisplayPort.
- In this state the **power light is white** (the monitor believes it is on), the screen is black, and the **monitor's own menu does not appear**.
- Windows and the graphics driver report the monitor as connected, healthy and showing 2560x1440. Nothing is logged as an error.
- The monitor is **not broken**. It can be brought back every time, and a reset was found that does **not** require pulling the power plug (section 5).
- The hang only happens when the monitor starts up **while the PC is already sending it a signal**. When the PC is not sending a signal during start-up, the monitor starts and wakes normally.

## 2. Hardware and settings it was observed on

| Item | Value |
|---|---|
| Monitor | AOC, Windows name "Q27G2G4", device ID `DISPLAY\AOC2702`, 2560x1440 |
| Connection | DisplayPort, direct to the graphics card |
| Mode in use | 2560x1440 at 59.95 Hz |
| Monitor menu settings | Input Select: DP. DP Capability: 1.2. FreeSync: Off. Game Mode: Off. Overdrive: Off |
| Graphics card | NVIDIA GeForce RTX 5070 (ASUS), driver 621.14 (32.0.16.2114), video BIOS 98.05.28.00.65 |
| Operating system | Windows 11 Pro, build 10.0.26300 |
| Other monitors on the same card | AOC 24G2W1G4 (1920x1080, 60 Hz) and ARZOPA-315 (2560x1440, 60 Hz). Neither shows the fault |

## 3. The three states

| State | Screen | Power light | Monitor's own menu | Recovers by itself when the PC sends a signal? |
|---|---|---|---|---|
| Normal | Picture | White | Works | n/a |
| Clean power saving (PC stopped sending a signal) | Black | Power saving | n/a | **Yes** (observed once, 16:17) |
| **Hung** | Black | **White** | **Does not appear** | **No** |

The hung state and clean power saving look alike on the screen but are different. Clean power saving is harmless. The hung state needs the reset in section 5.

## 4. How to reproduce

**Method A, about 10 seconds:** with the PC running and showing a picture on the monitor, press the monitor's power button off, wait about 5 seconds, press it on.
Result: hung state. Observed 3 times out of 3 on 2026-11-11 (15:50, 16:20, and about 16:32 with Process Lasso stopped).

**Method B:** restart the PC.
Result: hung state. Reported by the owner as happening on every restart; not separately timed in these tests.

## 5. How to recover

### 5a. Reset without unplugging (new)

1. Make the PC **stop sending a signal** to the monitor.
   - In Windows: Settings > System > Display > select the monitor > "Disconnect this display".
   - Or run `Q27-reset.cmd` from this folder, which does steps 1 and 4 by itself with a 30 second gap.
2. Press the monitor's power button **off**.
3. Count to three and press it **on**.
4. Make the PC send a signal again: "Extend desktop to this display" (the script does this after 30 seconds).

Result: picture returns. Observed 2 times out of 2 using the script (16:23 to 16:24, and 16:33 to 16:34). The Windows Settings route for step 1 and 4 uses the same Windows function as the script, but has not yet been tested together with the button.

### 5b. Original reset (owner's method, used for weeks)

1. Settings > Display > select the monitor > "Disconnect this display".
2. Pull the monitor's power plug, plug it back in.
3. Wait about 10 seconds.
4. "Extend desktop to this display".

Result: picture returns. Observed at 15:28 to 15:29 and 15:53 to 15:54.

### What does not recover it (all tested)

| Attempt | Result |
|---|---|
| Stop the signal for 40 s, send it again, monitor not touched (16:21 to 16:22) | Still hung |
| Stop the signal 4 s after the button press, send it again 11 s later (automatic, 16:20) | Still hung |
| Press the monitor's menu button | No menu |
| Power off and on while the PC keeps sending a signal (owner's earlier tests) | Hangs again |
| "Disconnect" then "Extend" with no power off/on (owner's earlier tests) | Still hung |

## 6. Timeline of the tests (2026-11-11, local time)

| Time | Action | What Windows logged | Result |
|---|---|---|---|
| 15:50:42 | Button off/on, PC sending signal | Kernel-PnP event 1010: monitor "surprise removed, missing on the bus", then immediately present again | Hung. No menu |
| 15:53:05 | Power plug pulled (after "Disconnect") | Kernel-PnP event 1010 | |
| 15:54:10 to 15:54:17 | "Extend" | Six Display events 4107 (SetDisplayConfig) | Picture back |
| 16:16:47 | Script stops the signal, monitor not touched | Nothing | Monitor enters power saving |
| 16:17:31 | Script sends the signal again | Nothing | **Picture back by itself** |
| 16:20:40 | Button off/on, PC sending signal | Kernel-PnP event 1010 | Hung. White light |
| 16:20:44 to 16:20:55 | Automatic stop and resend of the signal | Nothing | Still hung |
| 16:21:31 to 16:22:14 | Script stops the signal 43 s, resends | Nothing | Still hung |
| 16:23:40 | Script stops the signal; **button off/on during the gap** | **No event 1010 at all** | |
| 16:24:12 | Script sends the signal again | Nothing | **Picture back** |
| 16:25:32 | A power-plan change on the PC (see section 8) | Power-plan switch event | Monitor unaffected |
| 16:31:25 | Button off/on, PC sending signal, Process Lasso stopped | Kernel-PnP event 1010 | Hung. White light |
| 16:33:48 | Script stops the signal; button off/on during the gap | No event 1010 | |
| 16:34:21 | Script sends the signal again | Nothing | **Picture back** |

Two details worth noting:

- When the button is pressed while the PC is sending a signal, Windows logs the monitor dropping off the bus (event 1010). When the button is pressed while the PC is **not** sending a signal, Windows logs nothing.
- In every hung case Windows continued to list the monitor as present, active and at 2560x1440. A full read of Event Viewer for a restart (3,328 events) found no display or graphics-driver error.

## 7. Interpretation (not proven)

The monitor hangs when its start-up coincides with a DisplayPort link that the PC is already driving or immediately re-establishing. If the link is idle while the monitor starts, and is brought up afterwards, the monitor accepts it. This would explain why both resets need the PC to stop sending a signal *before* the monitor is switched off and on, and why a power off/on alone hangs it again.

Not established:
- Whether the fault is in the monitor's firmware, in how this graphics driver re-establishes the link, or in the combination. No DisplayPort-level trace was captured.
- Whether another driver version, DP Capability 1.1, or a different graphics card behaves differently. None of these was tested.
- What exactly happens during a PC restart. Only the button case was tested step by step.

## 8. Other software checked

- **Process Lasso** (Bitsum): its background service was found changing the Windows power plan at every shutdown and about 10 seconds after every start-up (65 changes in 30 days). Stopping the service triggers the same change. The monitor stayed on through that change (16:25), so a power-plan change by itself does not cause the hang. With the service stopped and none of its programs running (confirmed 16:30:52), a button off/on still produced the hung state (black, white light). **Process Lasso is therefore not needed for the hang in the button case.** Its effect on the restart case has not been tested.
- **Razer** services: running at start-up; not yet tested.
- No AOC software (G-Menu, e-Saver) is installed.

## 9. Files in this folder

| File | What it is |
|---|---|
| `README.md` | This document |
| `Q27-reset.cmd` | Double-click reset. Stops the signal for 30 seconds, prompts for the button off/on, sends the signal again |
| `q27-path.ps1` | The tool the reset uses. A software version of "Disconnect this display" and "Extend" for one monitor |

### Using `q27-path.ps1` directly

```
powershell -NoProfile -ExecutionPolicy Bypass -File q27-path.ps1 -Action Show
powershell -NoProfile -ExecutionPolicy Bypass -File q27-path.ps1 -Action Cycle -Seconds 30
```

| Action | Effect |
|---|---|
| `Show` | Lists the displays Windows is driving. Changes nothing |
| `Validate` | Asks Windows whether Off and On would be accepted. Changes nothing |
| `Off` | Stops driving the matching monitor. Saves the current layout to `q27-layout.bin` first. Not stored as Windows' remembered layout |
| `On` | Puts back the exact layout saved by `Off` |
| `Cycle -Seconds N` | `Off`, wait N seconds, `On` |

- `-Match` chooses the monitor by a piece of its device ID. The default is `AOC2702`.
- It uses the standard Windows display functions (`QueryDisplayConfig`, `SetDisplayConfig`). It installs nothing and needs no administrator rights.
- The saved layout file is only valid until the next PC restart.
- Requires Windows PowerShell 5.1 and must run in the signed-in user's session.

## 10. Still open

1. **Prevention.** The reset recovers the monitor; it does not stop the hang happening. The aim is for the PC to hold back its signal automatically whenever the monitor is starting.
2. The PC-restart case, step by step.
3. Button test with the Razer services stopped. (Done for Process Lasso: it still hangs.)
4. An older graphics driver, and DP Capability 1.1, as comparisons.

---

## Status (2026-11-11)

This is a **reset, not a cure**. The hang still happens; this brings the picture back without pulling the power plug. It worked 2 times out of 2 on the hardware in section 2. Not yet tested: the route through Windows Settings alone, and whether disconnecting the display before a restart avoids the hang.

## Contributing

Pull requests are welcome, especially:

- results on other AOC models, cables or graphics cards (say what you tested and how many times it worked);
- the restart case;
- a hands-free version.

Please report what you observed on your own hardware. Forum posts are ideas to test, not evidence.

## Credit

Found and written by Claude (Anthropic's Claude Mythos 5.2, running in Claude Code) on the owner's PC on 2026-11-11, by testing on the real hardware. The owner ran every physical step and pushed for tests over forum reading.
