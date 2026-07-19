# start.ps1 -- launch copyai-cli with the env vars Phase 5 needs.
# Source these from gitignored files; never commit secrets here.
#
# Usage (from this directory):
#   .\start.ps1                       # dev  - foreground - debug binary
#   .\start.ps1 -Env production       # prod - foreground - release binary
#   .\start.ps1 -Background           # detached
#   .\start.ps1 -Release              # force release binary regardless of env
#   .\start.ps1 -SkipBackup           # ESCAPE HATCH - Phase 14.5 backup-before-
#                                       migrate is otherwise mandatory.
#
# Required files (gitignored):
#   C:\Users\test\.openrouter\key       OpenRouter API key (Experts + openfang)
#   C:\Users\test\.openfang.key         Bearer token for openfang sidecar
#
# Env vars set here:
#   OPENROUTER_API_KEY   Expert chat uses it via local LLM calls
#   OPENFANG_API_KEY     copyai-cli->openfang bridge auth
#   OPENFANG_BASE_URL    defaults to http://172.16.70.25:4201 (the .25 sidecar)
#   OLLAGRAPH_API_KEY    for Expert-side ollagraph integration
#
# Phase 14.5 / FIX6 - pre-migrate backup
#
# auto_migrate is true in production.yaml. Every binary startup runs any
# pending migrations against the live DB. To make that safe, this launcher
# takes a fresh SQLite snapshot to $env:USERPROFILE\OllaSuper-backups\
# BEFORE handing off to the binary. If the backup fails, we ABORT - a
# server that won't start is safer than a corrupted DB you can't roll back.
# The rolling pool keeps the 30 most recent pre-migrate snapshots.

param(
    [switch]$Background,
    [switch]$Release,
    [switch]$SkipBackup,
    [string]$Env = "development"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# Env loading
# ---------------------------------------------------------------------

$openrouterKeyFile = "C:\Users\test\.openrouter\key"
$openfangKeyFile   = "C:\Users\test\.openfang.key"
$cfLocalEnvFile    = Join-Path $PSScriptRoot "..\.cf.local.env"

if (-not (Test-Path $openrouterKeyFile)) { throw "Missing $openrouterKeyFile" }
if (-not (Test-Path $openfangKeyFile))   { throw "Missing $openfangKeyFile"   }

$env:OPENROUTER_API_KEY = (Get-Content $openrouterKeyFile -Raw).Trim()
$env:OPENFANG_API_KEY   = (Get-Content $openfangKeyFile -Raw).Trim()
if (-not $env:OPENFANG_BASE_URL) { $env:OPENFANG_BASE_URL = "http://172.16.70.25:4201" }

if (Test-Path $cfLocalEnvFile) {
    Get-Content $cfLocalEnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $idx = $line.IndexOf("=")
            $k = $line.Substring(0, $idx).Trim()
            $v = $line.Substring($idx + 1).Trim()
            if (-not [string]::IsNullOrEmpty($k) -and -not [Environment]::GetEnvironmentVariable($k, "Process")) {
                [Environment]::SetEnvironmentVariable($k, $v, "Process")
            }
        }
    }
}

# ---------------------------------------------------------------------
# Phase 14.5 - pre-migrate backup (FIX6 production-grade guardrail)
# ---------------------------------------------------------------------

function Get-SqliteDbPath {
    # Resolve the SQLite file from DATABASE_URL. Supports the two shapes
    # we use: sqlite://<path>?mode=rwc  and  sqlite:<path>.
    $url = $env:DATABASE_URL
    if (-not $url) {
        # Dev fallback - what config/development.yaml templates against.
        return (Join-Path $PSScriptRoot "qwriter_dev.sqlite")
    }
    if ($url -match "^sqlite://(?<p>[^?]+)") {
        $p = $Matches.p
    } elseif ($url -match "^sqlite:(?<p>[^?]+)") {
        $p = $Matches.p
    } else {
        # Non-sqlite (e.g. Postgres) - no file-level backup possible.
        return $null
    }
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        $p = Join-Path $PSScriptRoot $p
    }
    return $p
}

function Invoke-PreMigrateBackup {
    param([string]$DbPath)

    if (-not (Test-Path $DbPath)) {
        Write-Output "[backup] no DB at $DbPath yet - first-run skip"
        return $true
    }

    $backupDir = Join-Path $env:USERPROFILE "OllaSuper-backups"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($DbPath)
    $dest = Join-Path $backupDir "$dbName-pre-migrate-$stamp.sqlite"

    try {
        Copy-Item $DbPath $dest -Force
        # Also copy WAL + SHM if they exist so the snapshot is complete.
        foreach ($suffix in @("-wal","-shm")) {
            $src = $DbPath + $suffix
            if (Test-Path $src) { Copy-Item $src ($dest + $suffix) -Force }
        }
        $bytes = (Get-Item $dest).Length
        $auditLog = Join-Path $backupDir "audit.log"
        $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ'
        # Single-quoted format strings avoid PowerShell's double-quote
        # parsing of `{2}` followed by a paren which it misreads.
        $line = '{0} backup -> {1} ({2} bytes) before env={3}' -f $now, $dest, $bytes, $Env
        Add-Content -Path $auditLog -Value $line
        Write-Output ('[backup] {0} ({1} bytes)' -f $dest, $bytes)
    } catch {
        $msg = $_.Exception.Message
        Write-Error ('[backup] FAILED: {0}' -f $msg)
        return $false
    }

    # Rotate - keep the 30 most recent pre-migrate snapshots for this DB.
    try {
        $glob = "$dbName-pre-migrate-*.sqlite"
        $all = Get-ChildItem -Path $backupDir -Filter $glob | Sort-Object LastWriteTime -Descending
        if ($all.Count -gt 30) {
            $all | Select-Object -Skip 30 | ForEach-Object {
                foreach ($suffix in @("","-wal","-shm")) {
                    $rm = $_.FullName + $suffix
                    if (Test-Path $rm) { Remove-Item $rm -Force }
                }
                Write-Output "[backup] pruned $($_.Name)"
            }
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Output ('[backup] prune warning: {0}' -f $msg)
    }

    return $true
}

if (-not $SkipBackup) {
    $dbPath = Get-SqliteDbPath
    if ($null -eq $dbPath) {
        Write-Output "[backup] DATABASE_URL is non-sqlite - skipping file-level backup. Use a Postgres-side backup before deploy."
    } else {
        $ok = Invoke-PreMigrateBackup -DbPath $dbPath
        if (-not $ok) {
            throw "[backup] aborting startup - refusing to run migrations without a fresh snapshot. To override, re-run with -SkipBackup. Restore from $env:USERPROFILE\OllaSuper-backups if needed."
        }
    }
} else {
    Write-Output "[backup] -SkipBackup set - proceeding WITHOUT pre-migrate snapshot. You own this."
}

# ---------------------------------------------------------------------
# Echo loaded env (key lengths only - never the value itself)
# ---------------------------------------------------------------------

Write-Output "OPENROUTER_API_KEY:         $($env:OPENROUTER_API_KEY.Length) chars"
Write-Output "OPENFANG_API_KEY:           $($env:OPENFANG_API_KEY.Length) chars"
Write-Output "OPENFANG_BASE_URL:          $($env:OPENFANG_BASE_URL)"
if ($env:OLLAGRAPH_API_KEY) {
    Write-Output "OLLAGRAPH_API_KEY:          $($env:OLLAGRAPH_API_KEY.Length) chars"
} else {
    Write-Output "OLLAGRAPH_API_KEY:          NOT SET"
}
if ($env:GOOGLE_OAUTH_CLIENT_ID) {
    Write-Output "GOOGLE_OAUTH_CLIENT_ID:     $($env:GOOGLE_OAUTH_CLIENT_ID.Length) chars"
} else {
    Write-Output "GOOGLE_OAUTH_CLIENT_ID:     NOT SET"
}
if ($env:GOOGLE_OAUTH_CLIENT_SECRET) {
    Write-Output "GOOGLE_OAUTH_CLIENT_SECRET: $($env:GOOGLE_OAUTH_CLIENT_SECRET.Length) chars"
} else {
    Write-Output "GOOGLE_OAUTH_CLIENT_SECRET: NOT SET"
}
Write-Output "GOOGLE_OAUTH_REDIRECT_URI:  $($env:GOOGLE_OAUTH_REDIRECT_URI)"
Write-Output "Environment:                $Env"

# ---------------------------------------------------------------------
# Binary selection
# ---------------------------------------------------------------------
#
# Production mode always uses the release binary. Dev defaults to debug
# unless -Release is passed explicitly. Phase 14.5 fix - earlier this
# always used debug, which meant the Scheduled Task ran the slow path in
# prod.

$useRelease = $Release.IsPresent -or ($Env -eq "production")
if ($useRelease) { $buildDir = "release" } else { $buildDir = "debug" }
$exe = Join-Path $PSScriptRoot "target\$buildDir\copyai-cli.exe"
if (-not (Test-Path $exe)) {
    if ($useRelease) {
        throw "Missing $exe - run: cargo build --release"
    } else {
        throw "Missing $exe - run: cargo build"
    }
}
Write-Output "Binary:                     $exe"

# ---------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------

if ($Background) {
    $stdout = "C:\Users\test\AppData\Local\Temp\copyai-stdout.log"
    $stderr = "C:\Users\test\AppData\Local\Temp\copyai-stderr.log"
    $proc = Start-Process -FilePath $exe -ArgumentList "start","-e",$Env `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Start-Sleep -Seconds 8
    if ($proc.HasExited) {
        Write-Error "copyai-cli crashed (exit $($proc.ExitCode)). Tail of stderr:"
        Get-Content $stderr -Tail 20
        exit 1
    }
    Write-Output "copyai-cli PID $($proc.Id) detached"
    Write-Output "stdout: $stdout"
    Write-Output "stderr: $stderr"
} else {
    & $exe start -e $Env
}
