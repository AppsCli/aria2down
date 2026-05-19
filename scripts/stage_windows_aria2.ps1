# 将 aria2c.exe 复制到 Flutter Windows Release 目录（与 package_desktop / CI 一致）。
param(
  [string]$Aria2cSource = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$rel = "build\windows\x64\runner\Release"
if (-not (Test-Path $rel)) {
  Write-Error "Release folder not found: $rel (run flutter build windows --release first)"
}

if (-not $Aria2cSource) {
  if (Test-Path "C:\ProgramData\chocolatey\bin\aria2c.exe") {
    $Aria2cSource = "C:\ProgramData\chocolatey\bin\aria2c.exe"
  } elseif (Get-Command aria2c -ErrorAction SilentlyContinue) {
    $Aria2cSource = (Get-Command aria2c).Source
  }
}

if (-not $Aria2cSource -or -not (Test-Path $Aria2cSource)) {
  Write-Warning "aria2c.exe not found; skip staging."
  exit 0
}

Copy-Item -Force $Aria2cSource "$rel\aria2c.exe"
Write-Host "Staged $Aria2cSource -> $rel\aria2c.exe"
Get-Item "$rel\aria2c.exe" | Format-List Name, Length
