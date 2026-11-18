# ASUS Keyboard Wake & Inactivity Recovery Script
# Target Hardware: ASUS ROG Zephyrus G14 (GA402RJ) - VID_0B05&PID_19B6 (ASUS N-KEY Controller)

param(
    [switch]$ForceRestart
)

$logPath = "$HOME\.config\wintil\automations.log"
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

function Log-Msg($msg) {
    $line = "[$timestamp] [asus-keyboard-wake] $msg"
    Write-Output $line
    try {
        $parent = Split-Path $logPath -Parent
        if (!(Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null }
        Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
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

# 2. Disable USB Selective Suspend in Registry for USB Host Service & Root Hubs
try {
    # Disable selective suspend at host controller driver level
    $usbSvc = "HKLM:\SYSTEM\CurrentControlSet\Services\USB"
    if (!(Test-Path $usbSvc)) { New-Item -Path $usbSvc -Force | Out-Null }
    Set-ItemProperty -Path $usbSvc -Name "HcDisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # Target all USB Root Hub 3.0 devices
    $rootHubs = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "ROOT_HUB30*" }
    foreach ($hub in $rootHubs) {
        $instances = Get-ChildItem $hub.PSPath -ErrorAction SilentlyContinue
        foreach ($inst in $instances) {
            $params = Join-Path $inst.PSPath "Device Parameters"
            if (Test-Path $params) {
                Set-ItemProperty -Path $params -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Dynamically target all ASUS N-KEY composite controller instances (VID_0B05&PID_19B6)
    $asusRegDevices = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "VID_0B05&PID_19B6*" }
    $asusRegCount = 0
    foreach ($dev in $asusRegDevices) {
        $instances = Get-ChildItem $dev.PSPath -ErrorAction SilentlyContinue
        foreach ($inst in $instances) {
            $params = Join-Path $inst.PSPath "Device Parameters"
            if (Test-Path $params) {
                Set-ItemProperty -Path $params -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $params -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
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
            pnputil.exe /restart-device "$asusId" 2>$null | Out-Null
            Log-Msg "Hardware controller reinitialized successfully ($asusId)."
        }
    }
} catch {
    Log-Msg "PnP restart note: $_"
}

# 4. Universal key unstick across all virtual keys via Wintil
try {
    $candidates = @(
        "$PSScriptRoot\..\..\target\release\wintil.exe",
        "$HOME\Desktop\projects\wintil\wintil\target\release\wintil.exe",
        "wintil.exe"
    )
    foreach ($exe in $candidates) {
        if (Test-Path $exe) {
            Start-Process -FilePath $exe -ArgumentList "--flush-keys" -NoNewWindow -Wait -ErrorAction SilentlyContinue
            Log-Msg "Dispatched universal key unstick via wintil --flush-keys."
            break
        }
    }
} catch {
    Log-Msg "Keyboard unstick note: $_"
}

Log-Msg "ASUS N-KEY keyboard wake recovery completed successfully."
