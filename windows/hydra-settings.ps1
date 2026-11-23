# The settings of Hydra Launcher: the theme (from hydrathemes.shop or made in
# the app), the language, the download folder and the other preferences.
#
# Hydra keeps them in a LevelDB (%APPDATA%\hydralauncher\hydra-db), next to the
# login and the library, so they are read and written with windows\hydra\hydra-db.js
# (Node and the classic-level package, installed once in %LOCALAPPDATA%\envsetup\hydra-tool).
# The login and the library are never touched. Keys and tokens of the preferences
# (the RetroAchievements key) are left out of git and kept in the store, next to
# the Playnite secrets.
#
#   hydra-settings.ps1 -Save      write the settings of this machine to windows\hydra\settings.json
#   hydra-settings.ps1 -Check     exit 1 when the saved theme is not the active one here
#   hydra-settings.ps1 -Install   put the saved settings in Hydra (closes it first)
param(
  [switch]$Save,
  [switch]$Check,
  [switch]$Install,
  [string]$Settings = (Join-Path $PSScriptRoot 'hydra\settings.json')
)
$ErrorActionPreference = 'Stop'
$db = Join-Path $env:APPDATA 'hydralauncher\hydra-db'
$js = Join-Path $PSScriptRoot 'hydra\hydra-db.js'
$tool = Join-Path $env:LOCALAPPDATA 'envsetup\hydra-tool'

# The store of config/playnite.yaml holds the secrets of the backups.
function Get-SecretsFile {
  $yaml = Join-Path $PSScriptRoot '..\config\playnite.yaml'
  $store = $null
  if (Test-Path -LiteralPath $yaml) {
    $m = Select-String -LiteralPath $yaml -Pattern '^store:\s*(.+?)\s*$' | Select-Object -First 1
    if ($m) { $store = $m.Matches[0].Groups[1].Value.Trim('"', "'") }
  }
  if (-not $store -or -not (Test-Path -LiteralPath $store)) { return $null }
  return Join-Path $store 'envsetup-hydra-secrets.json'
}

function Initialize-Tool {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is needed to read the Hydra settings (install it with: winget install OpenJS.NodeJS.LTS)' }
  if (Test-Path -LiteralPath (Join-Path $tool 'node_modules\classic-level')) { return }
  New-Item -ItemType Directory -Force -Path $tool | Out-Null
  Push-Location $tool
  try {
    if (-not (Test-Path 'package.json')) { '{"name":"envsetup-hydra-tool","private":true}' | Set-Content -Encoding ascii 'package.json' }
    & npm install --silent --no-audit --no-fund classic-level@1 | Out-Null
    if ($LASTEXITCODE) { throw "npm install classic-level failed (code $LASTEXITCODE)" }
  } finally { Pop-Location }
}

function Invoke-HydraDb([string[]]$Arguments) {
  $env:NODE_PATH = Join-Path $tool 'node_modules'
  & node $js @Arguments | ForEach-Object { Write-Host $_ }
  return $LASTEXITCODE
}

# Hydra holds a lock on its database while it runs: read a copy instead.
function Copy-Db {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("hydra-db-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Get-ChildItem -LiteralPath $db -File | Where-Object Name -ne 'LOCK' | Copy-Item -Destination $tmp
  return $tmp
}

if ($Save) {
  if (-not (Test-Path -LiteralPath $db)) { throw "Hydra has no settings on this machine ($db)" }
  Initialize-Tool
  $copy = Copy-Db
  $secretsOut = Join-Path $copy 'secrets.json'
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path $Settings) | Out-Null
    $code = Invoke-HydraDb @('export', $copy, $Settings, $secretsOut)
    if ($code) { throw "reading the Hydra settings failed (code $code)" }
    $secrets = Get-SecretsFile
    if ($secrets) { Copy-Item -LiteralPath $secretsOut -Destination $secrets -Force; Write-Host "secrets kept in $secrets" }
    else { Write-Warning 'the store is not reachable: the secrets of the preferences were not kept' }
    Write-Host "saved to $Settings"
  } finally { Remove-Item -Recurse -Force -LiteralPath $copy -ErrorAction SilentlyContinue }
  exit 0
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $Settings)) { exit 0 }
  if (-not (Test-Path -LiteralPath $db)) { exit 1 }
  if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Test-Path -LiteralPath (Join-Path $tool 'node_modules\classic-level'))) { exit 1 }
  $copy = Copy-Db
  try { $code = Invoke-HydraDb @('check', $copy, $Settings) } finally { Remove-Item -Recurse -Force -LiteralPath $copy -ErrorAction SilentlyContinue }
  exit $code
}

if ($Install) {
  if (-not (Test-Path -LiteralPath $Settings)) { throw "no saved settings ($Settings)" }
  Initialize-Tool
  $running = Get-Process -Name 'Hydra' -ErrorAction SilentlyContinue
  if ($running) {
    Write-Host 'closing Hydra'
    $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 3
    Get-Process -Name 'Hydra' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
  }
  New-Item -ItemType Directory -Force -Path $db | Out-Null
  $nodeArgs = @('import', $db, $Settings)
  $secrets = Get-SecretsFile
  if ($secrets -and (Test-Path -LiteralPath $secrets)) { $nodeArgs += $secrets }
  $code = Invoke-HydraDb $nodeArgs
  if ($code) { throw "writing the Hydra settings failed (code $code)" }
  exit 0
}

Write-Host 'use -Save, -Check or -Install'
exit 2
