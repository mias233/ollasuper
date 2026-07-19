# deploy-vm.ps1 -- ship the dashboard from this Windows box to the prod VM.
#
# Pipeline:
#   1. git archive HEAD copyai_remote -> tar (tracked files only, no target/)
#   2. scp the tar to /tmp on 172.16.70.25
#   3. ssh: extract, cargo build --release, install binary, restart systemd unit
#   4. health-check: curl https://app.ollasuper.com/auth, expect 200
#
# Run from anywhere (script resolves repo root from its own path):
#   .\deploy-vm.ps1                # full deploy
#   .\deploy-vm.ps1 -SkipBuild     # ship source + restart only (binary must already exist)
#   .\deploy-vm.ps1 -SkipHealth    # skip post-deploy curl check
#   .\deploy-vm.ps1 -DryRun        # print what it would do, change nothing
#
# Requirements (already satisfied per Phase 0-6 migration on 2026-06-21):
#   - ssh + scp on PATH (Windows OpenSSH)
#   - SSH key trust to root@172.16.70.25
#   - VM has /root/.cargo/bin/cargo + systemd unit ollasuper-dashboard

param(
    [switch]$SkipBuild,
    [switch]$SkipHealth,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$VM        = "root@172.16.70.25"
$REPO      = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$TAR       = Join-Path $env:TEMP "qwriter-handoff.tar"
$VM_TAR    = "/tmp/qwriter-handoff.tar"
$VM_SRC    = "/opt/ollasuper/src"
$VM_BIN    = "/opt/ollasuper/copyai-cli"
$VM_UNIT   = "ollasuper-dashboard"
$PUBLIC    = "https://app.ollasuper.com/auth"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

# --- 0. preflight: must be inside the qwriter repo ---
if (-not (Test-Path (Join-Path $REPO ".git"))) {
    Die "no .git at $REPO -- script must live inside the qwriter repo"
}
Push-Location $REPO

$sha = (git rev-parse HEAD).Trim()
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$dirty = [bool](git status --porcelain -- copyai_remote)

Step "deploy plan"
Write-Host "    repo:      $REPO"
Write-Host "    branch:    $branch"
Write-Host "    HEAD:      $sha"
if ($dirty) {
    Warn "uncommitted changes in copyai_remote/ -- git archive ships HEAD, NOT your worktree"
    Warn "either commit first, or accept that local edits will not be deployed"
}
Write-Host "    target:    $VM ($VM_BIN, $VM_UNIT.service)"
Write-Host "    flags:     SkipBuild=$SkipBuild SkipHealth=$SkipHealth DryRun=$DryRun"
Write-Host ""

if ($DryRun) {
    Step "DRY-RUN -- would now: tar | scp | extract | build | install | restart | health-check"
    Pop-Location
    exit 0
}

# --- 1. tar HEAD ---
Step "creating tar from git HEAD"
if (Test-Path $TAR) { Remove-Item $TAR -Force }
git archive --format=tar -o $TAR HEAD copyai_remote
if (-not (Test-Path $TAR)) { Die "git archive produced no file" }
$tarMB = "{0:N2} MB" -f ((Get-Item $TAR).Length / 1MB)
OK "$TAR ($tarMB)"

# --- 2. scp ---
Step "shipping tar to $VM"
scp -o BatchMode=yes -q $TAR "${VM}:${VM_TAR}"
if ($LASTEXITCODE -ne 0) { Die "scp failed (exit $LASTEXITCODE)" }
OK "scp done"

# --- 3. remote script (extract, build, install, restart) ---
$buildBlock = if ($SkipBuild) {
    'echo skip-build: using existing binary at /opt/ollasuper/copyai-cli'
} else {
@'
cd /opt/ollasuper/src/copyai_remote
export PATH=/root/.cargo/bin:$PATH
echo "==> cargo build --release"
# Capture full build output to a file so we can show context on failure,
# AND so the pipe to tail doesn't swallow cargo's non-zero exit code.
# (Earlier bug: `cargo build … | tail -40` only checked tail's exit;
#  build could fail and the script kept going, reinstalling the OLD
#  binary because target/release/copyai-cli still existed.)
build_log=/tmp/qwriter-cargo-build.log
if ! cargo build --release --bin copyai-cli > "$build_log" 2>&1; then
  echo "==> BUILD FAILED — last 60 lines of $build_log:"
  tail -60 "$build_log"
  exit 1
fi
tail -8 "$build_log"
# Sanity: binary must have been touched in this build run (not just exist
# from a prior build).
test -x target/release/copyai-cli || { echo "FAIL: build produced no binary"; exit 1; }
binary_mtime=$(stat -c %Y target/release/copyai-cli)
now=$(date +%s)
if (( now - binary_mtime > 600 )); then
  echo "FAIL: target/release/copyai-cli was not rebuilt in the last 10 min (mtime $binary_mtime, now $now)"
  exit 1
fi
install -m 0755 target/release/copyai-cli /opt/ollasuper/copyai-cli
'@
}

$remote = @"
set -e
echo "==> extract source"
tar -xf $VM_TAR -C $VM_SRC
echo "$sha" > $VM_SRC/.commit-handoff.txt
rm -f $VM_TAR
$buildBlock
echo "==> restart $VM_UNIT (pre-restart DB snapshot taken by systemd ExecStartPre)"
systemctl restart $VM_UNIT
sleep 4
systemctl is-active $VM_UNIT
echo "==> local health"
curl -s -o /dev/null -w 'localhost:5150/auth -> %{http_code}\n' --max-time 5 http://127.0.0.1:5150/auth
echo "==> deployed commit"
cat $VM_SRC/.commit-handoff.txt
"@

Step "remote: extract + build + install + restart"
# Write the remote script to a local temp file with LF-only line endings, then
# scp it to the VM and execute. Piping via PS stdin re-introduces CRLF which
# bash treats as part of paths/arguments. .NET's WriteAllText with UTF8NoBOM
# + manual LF preserves byte-for-byte exactly what we wrote.
$remoteScript = Join-Path $env:TEMP "qwriter-deploy-remote.sh"
$remoteLf = $remote -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($remoteScript, $remoteLf, [System.Text.UTF8Encoding]::new($false))
scp -o BatchMode=yes -q $remoteScript "${VM}:/tmp/qwriter-deploy-remote.sh"
if ($LASTEXITCODE -ne 0) { Die "scp of remote script failed (exit $LASTEXITCODE)" }
ssh -o BatchMode=yes $VM "bash /tmp/qwriter-deploy-remote.sh; rc=`$?; rm -f /tmp/qwriter-deploy-remote.sh; exit `$rc"
if ($LASTEXITCODE -ne 0) { Die "remote pipeline failed (exit $LASTEXITCODE)" }
OK "remote pipeline green"

# --- 4. public health check ---
if ($SkipHealth) {
    Step "skipping public health check (-SkipHealth)"
} else {
    Step "public health: $PUBLIC"
    $ok = 0
    $fail = 0
    for ($i = 1; $i -le 5; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $PUBLIC -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0 -ErrorAction Stop
            $code = $r.StatusCode
        } catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        }
        if ($code -eq 200) {
            Write-Host "    req $i -> $code" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "    req $i -> $code" -ForegroundColor Red
            $fail++
        }
    }
    if ($fail -gt 0) {
        Die "$fail / 5 public requests failed -- investigate before assuming deploy is good"
    }
    OK "5/5 public requests = 200"
}

Pop-Location
Step "DONE -- $sha live on $VM"
