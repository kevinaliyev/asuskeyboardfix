# Registers (or removes) a Windows Scheduled Task that runs fix.ps1 on startup and system wake.
# Must be run as Administrator.

#Requires -RunAsAdministrator

param(
    [string]$TaskName = "AsusKeyboardWakeFix",
    [string]$ScriptPath = (Join-Path $PSScriptRoot "fix.ps1"),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Output "Removed scheduled task '$TaskName'."
    } else {
        Write-Output "Scheduled task '$TaskName' was not found."
    }
    exit 0
}

if (!(Test-Path $ScriptPath)) {
    throw "Could not find fix script at '$ScriptPath'. Place schedule-task.ps1 in the same folder as fix.ps1 or pass -ScriptPath."
}

$resolvedScriptPath = (Resolve-Path $ScriptPath).Path
$escapedScriptPath = [System.Security.SecurityElement]::Escape($resolvedScriptPath)
$escapedArgs = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$escapedScriptPath`""

# Triggers:
# 1. BootTrigger: runs at Windows startup
# 2. EventTrigger: runs on wake from sleep (Power-Troubleshooter Event 1, Kernel-Power Event 107)
#    and exit from Modern Standby / S0 Low Power Idle (Kernel-Power Event 507)
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Runs ASUS N-KEY keyboard wake recovery (fix.ps1) at startup and on system wake.</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[(Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1) or (Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107 or EventID=507))]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnWake>false</DisallowStartOnWake>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$escapedArgs</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -Force | Out-Null

Write-Output "Scheduled task '$TaskName' registered successfully."
Write-Output "  Script:   $resolvedScriptPath"
Write-Output "  Run as:   NT AUTHORITY\SYSTEM (Highest privileges)"
Write-Output "  Triggers: System startup + Wake (Power-Troubleshooter ID 1, Kernel-Power IDs 107 & 507)"
Write-Output "  Remove:   .\schedule-task.ps1 -Uninstall"
