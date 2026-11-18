# ASUS Keyboard Wake & Inactivity Recovery Script (Standalone)
# Target Hardware: ASUS ROG Zephyrus G14 (GA402RJ) - VID_0B05&PID_19B6 (ASUS N-KEY Controller)

param(
    [switch]$ForceRestart,
    [string]$LogPath
)

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:ProgramData "AsusKeyboardWake" }
    $LogPath = Join-Path $baseDir "fix.log"
}

function Log-Msg {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [asus-keyboard-wake] $Message"
    Write-Output $line
    try {
        $parent = Split-Path $LogPath -Parent
        if ($parent -and !(Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Log-Msg "WARNING: Not running as Administrator. Power plan, registry, and PnP device restart steps require elevation."
}

Log-Msg "Executing ASUS N-KEY keyboard wake recovery..."

# 1. Disable Windows USB Selective Suspend in Power Plan (AC and DC / Battery)
try {
    # System subgroup: 2a737441-1930-4402-8d77-b2bebba308a3 (USB settings)
    # Setting GUID:    48e6b7a6-50f5-4782-a5d4-53bb8f07e226 (USB selective suspend setting)
    powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
    powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
    powercfg.exe /SETACTIVE SCHEME_CURRENT 2>$null
    Log-Msg "Disabled global USB selective suspend in active Windows power plan."
} catch {
    Log-Msg "Powercfg note: $_"
}

# 2. Disable USB Selective Suspend in Registry for USB Host Service, Root Hubs, and ASUS N-KEY Controller
function Set-UsbPowerPolicy {
    param([string]$DeviceParamsPath)
    if (Test-Path $DeviceParamsPath) {
        Set-ItemProperty -Path $DeviceParamsPath -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $DeviceParamsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $DeviceParamsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $DeviceParamsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}

try {
    # Disable selective suspend at host controller driver level
    $usbSvc = "HKLM:\SYSTEM\CurrentControlSet\Services\USB"
    if (!(Test-Path $usbSvc)) { New-Item -Path $usbSvc -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $usbSvc -Name "HcDisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    $usbEnumRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"

    # Target all USB Root Hub 3.0 devices
    $rootHubs = Get-ChildItem $usbEnumRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "ROOT_HUB30*" }
    foreach ($hub in $rootHubs) {
        $instances = Get-ChildItem $hub.PSPath -ErrorAction SilentlyContinue
        foreach ($inst in $instances) {
            $null = Set-UsbPowerPolicy (Join-Path $inst.PSPath "Device Parameters")
        }
    }

    # Dynamically target all ASUS N-KEY composite controller instances (VID_0B05&PID_19B6)
    $asusRegDevices = Get-ChildItem $usbEnumRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "VID_0B05&PID_19B6*" }
    $asusRegCount = 0
    foreach ($dev in $asusRegDevices) {
        $instances = Get-ChildItem $dev.PSPath -ErrorAction SilentlyContinue
        foreach ($inst in $instances) {
            if (Set-UsbPowerPolicy (Join-Path $inst.PSPath "Device Parameters")) {
                $asusRegCount++
            }
        }
    }

    Log-Msg "Configured registry power policies for USB service, root hubs, and $asusRegCount ASUS N-KEY controller instance(s)."
} catch {
    Log-Msg "Registry update note: $_"
}

# 3. Hardware Controller Re-initialization & Driver Stack Refresh
try {
    $instanceIds = @()

    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        $pnpDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId -like "USB\VID_0B05&PID_19B6*"
        }
        if ($pnpDevices) {
            $instanceIds = @($pnpDevices | Select-Object -ExpandProperty InstanceId -Unique)
        }
    }

    # Fallback to registry enumeration if Get-PnpDevice is unavailable or returned nothing
    if ($instanceIds.Count -eq 0) {
        $asusRegDevices = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -like "VID_0B05&PID_19B6*"
        }
        foreach ($dev in $asusRegDevices) {
            $instances = Get-ChildItem $dev.PSPath -ErrorAction SilentlyContinue
            foreach ($inst in $instances) {
                $instanceIds += "USB\$($dev.PSChildName)\$($inst.PSChildName)"
            }
        }
    }

    if ($instanceIds.Count -eq 0) {
        Log-Msg "No ASUS N-KEY controller (VID_0B05&PID_19B6) instances found to restart."
    } else {
        foreach ($asusId in $instanceIds) {
            Log-Msg "Restarting ASUS N-KEY composite device ($asusId)..."
            $pnpOut = & pnputil.exe /restart-device "$asusId" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Log-Msg "Hardware controller reinitialized successfully ($asusId)."
            } else {
                Log-Msg "PnP restart exited with code $LASTEXITCODE for ${asusId}: $($pnpOut -join ' ')"
            }
        }
    }
} catch {
    Log-Msg "PnP restart note: $_"
}

# 4. Standalone Virtual Key Unstick (releases any keys/modifiers stuck in software state)
try {
    if (-not ([System.Management.Automation.PSTypeName]'KeyboardWakeHelper').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KeyboardWakeHelper {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const uint KEYEVENTF_KEYUP = 0x0002;
}
'@
    }

    # Release any key currently reporting pressed state, plus common modifier keys
    $released = 0
    for ($vk = 0x08; $vk -le 0xFE; $vk++) {
        $state = [KeyboardWakeHelper]::GetAsyncKeyState($vk)
        if (($state -band 0x8000) -ne 0) {
            [KeyboardWakeHelper]::keybd_event([byte]$vk, 0, [KeyboardWakeHelper]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
            $released++
        }
    }

    $modifiers = @(0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C) # L/R Shift, Ctrl, Alt, Win
    foreach ($mod in $modifiers) {
        [KeyboardWakeHelper]::keybd_event([byte]$mod, 0, [KeyboardWakeHelper]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    }

    Log-Msg "Flushed stuck virtual key states ($released active key(s) released)."
} catch {
    Log-Msg "Keyboard unstick note: $_"
}

Log-Msg "ASUS N-KEY keyboard wake recovery completed."
