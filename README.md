
# Script fix(s) for the ASUS N-KEY USB Device driver turning unresponsive.

This bug appears at random intervals, generally after wake from sleep and manifests as: held down modkeys, stuck/repeating characters, and arbitrary input buffer corrosion.

I have noticed this issue on my G14 model GA402RJ, however this device driver is used across a range of models so consider trying this fix if you have matching hardware and / or symptoms.

--------

I **highly recommend** to manage this fix using [wintil](https://www.github.com/kevinaliyev/wintil) with the included automation, or you can use the standalone fix set to run as a scheduled task using one of the included scripts so you can apply a persistent fix!

## Files

- `fix.ps1` — Applies USB power-saving fixes, restarts the ASUS N-KEY USB device, and flushes stuck keys.
- `schedule-task.ps1` — Registers (or removes) a Windows Scheduled Task (`AsusKeyboardWakeFix`) to run `fix.ps1` on startup and wake. **(run in an elevated shell)**
- `run-fix.cmd` — Double-click launcher for `fix.ps1` (prompts for Admin).
- `install-task.cmd` — Double-click launcher for `schedule-task.ps1` (prompts for Admin).

## Usage

### Option 1: CLI (Fastest)

Open **PowerShell as Administrator**.

```powershell
#Navigate to where you've saved the repo

# Register the scheduled task (runs on startup and wake, on AC or battery)
.\schedule-task.ps1

# Or run the fix once immediately
.\fix.ps1
```

To remove the scheduled task later if you dont want to (you can also just use the task scheduler gui)

```powershell
.\schedule-task.ps1 -Uninstall
```

### Option 2: File Explorer (Easiest)

- Double-click **`install-task.cmd`** to install the startup/wake scheduled task.
- Double-click **`run-fix.cmd`** to run the fix once immediately.

### Option 3: Wintil Automation (Best)

If you utilize my windows utility project [wintil](https://www.github.com/kevinaliyev/wintil)
the included automation can be installed by simply placing it into your wintil config.

if wintil is set to run on startup, this fix will also run according to its set triggers (wake, idle, startup).

```powershell
# Navigate to where you've saved the repo
mkdir "$HOME\.config\wintil\automations" -Force | Out-Null
cp -r ".\wintil\automations\asus-keyboard-wake" "$HOME\.config\wintil\automations" -Force
```
