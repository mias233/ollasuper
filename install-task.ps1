# install-task.ps1 -- register copyai-cli as a Scheduled Task at user logon.
#
# This is the NSSM-equivalent without needing to install NSSM. The task:
#   - Triggers when the current user logs on (same time as Cloudflare Tunnel)
#   - Runs as the current user (NO admin elevation required to install)
#   - Restarts on failure (3 retries, 1 minute apart)
#   - Streams stdout/stderr to %TEMP%\copyai-stdout.log / -stderr.log
#
# Run from a normal PowerShell prompt (no admin):
#   powershell -ExecutionPolicy Bypass -File .\install-task.ps1
#
# To uninstall: Unregister-ScheduledTask -TaskName 'OllaSuper\copyai-cli' -Confirm:$false

param([string]$TaskName = "OllaSuper\copyai-cli")

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$LauncherPath = Join-Path $ScriptDir "start.ps1"

if (-not (Test-Path $LauncherPath)) {
    throw "Missing $LauncherPath -- clone the repo and run cargo build first."
}

# Define the action: launch the start.ps1 launcher in -Background mode, prod env.
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Env production' -f $LauncherPath) `
    -WorkingDirectory $ScriptDir

# Trigger: at the current user's logon (matches Cloudflare Tunnel pattern)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Settings: restart on failure 3×, no time limit
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

# Run as the current user (no UAC needed to install)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# Remove any existing version
$existing = Get-ScheduledTask -TaskName $TaskName.Split('\')[-1] -TaskPath ($TaskName.Substring(0, $TaskName.LastIndexOf('\') + 1) -replace '\\$', '\') -ErrorAction SilentlyContinue
if ($existing) {
    Write-Output "Removing existing task $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$null = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OllaSuper dashboard -- copyai-cli prod-mode binary. Auto-restart on failure. See start.ps1 for env-var loading."

Write-Output "OK: Registered $TaskName"
Write-Output ""
Write-Output "Verify with: Get-ScheduledTaskInfo -TaskName '$TaskName' | Format-List"
Write-Output "Trigger now with: Start-ScheduledTask -TaskName '$TaskName'"
Write-Output "Uninstall with: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
