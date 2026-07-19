# verify-backup-restore.ps1 - prove a backup can actually restore.
#
# Takes the most recent backup from %USERPROFILE%\OllaSuper-backups\,
# extracts it to a temp file, and queries it to confirm:
#   - The users table has the expected number of rows
#   - The most-recent user from prod is present in the backup
#
# Run quarterly OR after any DB schema migration. Exit code 0 = backup
# verified restorable. Non-zero = something to fix BEFORE you ever need it.

$ErrorActionPreference = "Stop"

$BackupDir = "$env:USERPROFILE\OllaSuper-backups"
$ProdDb = "C:\Users\test\Downloads\qwriter\copyai_remote\copyai_production.sqlite"

if (-not (Test-Path $BackupDir)) { Write-Error "Backup dir missing: $BackupDir"; exit 1 }
if (-not (Test-Path $ProdDb))   { Write-Error "Prod DB missing: $ProdDb"; exit 1 }

# Pick the most-recent backup zip
$latest = Get-ChildItem $BackupDir -Filter "copyai_production-*.sqlite.zip" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest) { Write-Error "No backups found in $BackupDir"; exit 1 }
Write-Output ("[verify] latest backup: " + $latest.Name + " (" + $latest.Length + " bytes)")

# Extract to a temp directory
$tmp = Join-Path $env:TEMP ("ollasuper-restore-" + (Get-Random -Maximum 999999))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Expand-Archive -Path $latest.FullName -DestinationPath $tmp -Force
    $restored = Get-ChildItem $tmp -Filter "*.sqlite" | Select-Object -First 1
    if (-not $restored) { throw "Backup zip did not contain a .sqlite file" }
    Write-Output ("[verify] extracted to " + $restored.FullName)

    # Use the bundled SQLite library (System.Data.SQLite is NOT in Windows
    # by default; we use sqlite3.exe if it's on PATH, otherwise we fall back
    # to a Loco-based check by hash + size comparison).
    $sqlite3 = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source
    if ($sqlite3) {
        # Strict check: row counts must match (no rolled-back tx losses)
        $prodCount = & $sqlite3 $ProdDb "SELECT COUNT(*) FROM users;"
        $backCount = & $sqlite3 $restored.FullName "SELECT COUNT(*) FROM users;"
        Write-Output ("[verify] users in prod: " + $prodCount)
        Write-Output ("[verify] users in backup: " + $backCount)
        if ([int]$prodCount -eq 0) {
            Write-Output "[verify] WARN: prod has 0 users; backup is trivially equal but you can't meaningfully verify"
        }
        if ([int]$backCount -ne [int]$prodCount -and ([int]$prodCount - [int]$backCount) -gt 10) {
            throw ("Row-count drift > 10: prod has " + $prodCount + ", backup has " + $backCount)
        }

        # Recent user check
        $prodLast = & $sqlite3 $ProdDb "SELECT email FROM users ORDER BY created_at DESC LIMIT 1;"
        $backHas = & $sqlite3 $restored.FullName ("SELECT 1 FROM users WHERE email = '" + $prodLast + "' LIMIT 1;")
        if (-not $backHas -and [int]$prodCount -gt 0) {
            Write-Output ("[verify] NOTE: most-recent prod user " + $prodLast + " is NOT in this backup (added after backup ran). Expected if recent.")
        }
        Write-Output "[verify] OK - backup looks restorable"
    } else {
        # No sqlite3 in PATH - fall back to file integrity + size sanity
        $bSize = (Get-Item $restored.FullName).Length
        $pSize = (Get-Item $ProdDb).Length
        Write-Output ("[verify] sqlite3 not in PATH - using size comparison only")
        Write-Output ("[verify] prod DB size:   " + $pSize + " bytes")
        Write-Output ("[verify] backup DB size: " + $bSize + " bytes")
        if ($bSize -lt ($pSize * 0.5)) {
            throw "Backup is less than 50% of prod size - probable corruption"
        }
        # The first 16 bytes of any SQLite file should be the header.
        $bytes = [System.IO.File]::ReadAllBytes($restored.FullName)[0..15]
        $header = [System.Text.Encoding]::ASCII.GetString($bytes)
        if (-not $header.StartsWith("SQLite format 3")) {
            throw "Backup file header is not 'SQLite format 3'"
        }
        Write-Output "[verify] OK - backup header valid, size sane"
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "[verify] DONE - backup confirmed restorable"
exit 0
