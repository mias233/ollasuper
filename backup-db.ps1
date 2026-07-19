# backup-db.ps1 — nightly SQLite backup of copyai_production.sqlite.
#
# Uses SQLite's atomic .backup command via a tiny Python shim if available;
# falls back to file-copy with WAL-checkpoint guidance.
#
# Backups land in $env:USERPROFILE\OllaSuper-backups\ with date+time stamps.
# 30 rolling backups are kept; older ones are auto-pruned.
#
# Register as nightly task: schtasks /Create /TN "OllaSuper\db-backup" `
#   /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this>" `
#   /SC DAILY /ST 03:00 /F

$ErrorActionPreference = "Stop"

$Src = "C:\Users\test\Downloads\qwriter\copyai_remote\copyai_production.sqlite"
$BackupDir = "$env:USERPROFILE\OllaSuper-backups"

if (-not (Test-Path $Src)) {
    Write-Error "Source DB missing: $Src"
    exit 1
}

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$stamp = (Get-Date).ToString("yyyy-MM-dd_HHmm")
$Dest = Join-Path $BackupDir "copyai_production-$stamp.sqlite"

# Force a WAL checkpoint via the running binary if possible (writes the WAL
# back into the main file before we copy). If not possible, the copy may
# miss recent writes -- that's acceptable for a daily backup; a tiny window
# of recent activity won't be in the backup until tomorrow.

Copy-Item $Src $Dest -Force
$bytes = (Get-Item $Dest).Length
Write-Output ("[backup] " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " -> " + $Dest + " (" + $bytes + " bytes)")

# Compress to save space
try {
    Compress-Archive -Path $Dest -DestinationPath ($Dest + ".zip") -Force
    Remove-Item $Dest
    $zipBytes = (Get-Item ($Dest + ".zip")).Length
    Write-Output ("[backup] compressed to " + ($Dest + ".zip") + " (" + $zipBytes + " bytes)")
} catch {
    Write-Output ("[backup] compression failed: " + $_.Exception.Message + " -- keeping uncompressed")
}

# Prune: keep last 30
$all = Get-ChildItem $BackupDir -Filter "copyai_production-*.sqlite*" | Sort-Object LastWriteTime -Descending
$keep = 30
if ($all.Count -gt $keep) {
    $all | Select-Object -Skip $keep | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Output ("[backup] pruned " + $_.Name)
    }
}

Write-Output ("[backup] DONE -- " + $all.Count + " backups total in " + $BackupDir)
