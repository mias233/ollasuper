# Restore-LastBackup.ps1 -- roll the SQLite DB back to the most recent
# pre-migrate snapshot. Use this when a bad migration auto-applied at
# startup (auto_migrate=true in production.yaml).
#
# Usage:
#   .\Restore-LastBackup.ps1                          # restore most recent
#   .\Restore-LastBackup.ps1 -List                    # show available
#   .\Restore-LastBackup.ps1 -Stamp 20260613-034417Z  # restore specific snapshot
#   .\Restore-LastBackup.ps1 -DryRun                  # show what would happen
#
# What it does:
#   1. Stops copyai-cli.exe if running (DB must be released before swap).
#   2. Moves the current live DB aside as <name>-before-restore-<stamp>.sqlite
#      so a botched restore is itself reversible.
#   3. Copies the chosen pre-migrate snapshot + WAL/SHM siblings back
#      to the live DB location.
#   4. Prints the next command to start the binary back up.
#
# All operations log to OllaSuper-backups\audit.log.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$DryRun,
    [string]$Stamp
)

$ErrorActionPreference = "Stop"

$BackupDir = Join-Path $env:USERPROFILE "OllaSuper-backups"
if (-not (Test-Path $BackupDir)) {
    throw "No backups directory at $BackupDir - nothing to restore."
}

function Get-LiveDbPath {
    $cfLocalEnvFile = Join-Path $PSScriptRoot "..\.cf.local.env"
    $url = $null
    if (Test-Path $cfLocalEnvFile) {
        $m = Select-String -Path $cfLocalEnvFile -Pattern "^DATABASE_URL=(.+)$" | Select-Object -First 1
        if ($m) { $url = $m.Matches[0].Groups[1].Value.Trim() }
    }
    if (-not $url) { $url = $env:DATABASE_URL }
    if (-not $url) {
        return (Join-Path $PSScriptRoot "qwriter_dev.sqlite")
    }
    if ($url -match "^sqlite://(?<p>[^?]+)") {
        $p = $Matches.p
    } elseif ($url -match "^sqlite:(?<p>[^?]+)") {
        $p = $Matches.p
    } else {
        throw "DATABASE_URL is non-sqlite - file-level restore impossible: $url"
    }
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        $p = Join-Path $PSScriptRoot $p
    }
    return $p
}

$liveDb = Get-LiveDbPath
$dbName = [System.IO.Path]::GetFileNameWithoutExtension($liveDb)
$glob = "$dbName-pre-migrate-*.sqlite"

$snapshots = Get-ChildItem -Path $BackupDir -Filter $glob -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($List) {
    if (-not $snapshots) {
        Write-Output "No snapshots for $dbName in $BackupDir."
        exit 0
    }
    Write-Output "Snapshots for $dbName (most recent first):"
    foreach ($s in $snapshots) {
        $bytes = $s.Length
        Write-Output ('  {0}  {1,12:N0} bytes  {2}' -f $s.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $bytes, $s.Name)
    }
    exit 0
}

if (-not $snapshots) {
    throw "No snapshots for $dbName found in $BackupDir. Run start.ps1 at least once to create one."
}

if ($Stamp) {
    $pick = $snapshots | Where-Object { $_.Name -like "*$Stamp*" } | Select-Object -First 1
    if (-not $pick) {
        throw "No snapshot matches stamp '$Stamp'. Use -List to see options."
    }
} else {
    $pick = $snapshots | Select-Object -First 1
}

Write-Output "Live DB:          $liveDb"
Write-Output "Restoring from:   $($pick.FullName)"
Write-Output "Snapshot taken:   $($pick.LastWriteTime)"

if ($DryRun) {
    Write-Output ""
    Write-Output "DryRun: no changes made."
    exit 0
}

# Step 1 - stop the binary so it releases the file handle.
$running = Get-Process copyai-cli -ErrorAction SilentlyContinue
if ($running) {
    Write-Output "Stopping copyai-cli (PID $($running.Id))..."
    Stop-Process -Id $running.Id -Force
    Start-Sleep -Seconds 2
}

# Step 2 - move the current live DB aside so the restore is itself reversible.
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
if (Test-Path $liveDb) {
    $aside = Join-Path $BackupDir "$dbName-before-restore-$ts.sqlite"
    Copy-Item $liveDb $aside -Force
    foreach ($suffix in @("-wal","-shm")) {
        $s = $liveDb + $suffix
        if (Test-Path $s) { Copy-Item $s ($aside + $suffix) -Force }
    }
    Write-Output "Live DB preserved at: $aside"
}

# Step 3 - restore. Also restore matching WAL/SHM siblings.
Copy-Item $pick.FullName $liveDb -Force
foreach ($suffix in @("-wal","-shm")) {
    $sb = $pick.FullName + $suffix
    $lt = $liveDb + $suffix
    if (Test-Path $sb) {
        Copy-Item $sb $lt -Force
    } elseif (Test-Path $lt) {
        Remove-Item $lt -Force
    }
}

# Step 4 - audit log entry.
$auditLog = Join-Path $BackupDir "audit.log"
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ'
$entry = '{0} restore -> {1} from {2}' -f $now, $liveDb, $pick.Name
Add-Content -Path $auditLog -Value $entry

Write-Output ""
Write-Output "Restored. Restart with: .\start.ps1 -Background -Env production"
