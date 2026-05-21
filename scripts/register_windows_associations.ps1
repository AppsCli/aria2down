<#
.SYNOPSIS
  为 portable / zip 安装的 aria2down.exe 在 Windows 注册表里写入
  协议（aria2down:// magnet:）与文件（.torrent .metalink .meta4）关联。

.DESCRIPTION
  MSIX 安装会自动声明这些关联（见 pubspec.yaml#msix_config），
  但解压 zip 直接运行的 portable 版不会，导致浏览器点击 magnet:
  / 文件管理器双击 .torrent 都不会路由到 aria2down。

  本脚本以「当前用户」（HKCU）方式注册，不需要管理员权限，
  也不会污染其它账户。卸载用 -Unregister。

  注册后 Windows 仍可能弹「选择默认应用」让用户确认；这是 OS 行为。

.PARAMETER ExePath
  aria2down.exe 的绝对路径。默认使用脚本所在目录的 aria2down.exe，
  方便和 portable zip 解压后放在一起直接 .\register_windows_associations.ps1。

.PARAMETER Unregister
  反向操作：移除本工具写入的全部 HKCU 项。

.EXAMPLE
  PS> .\register_windows_associations.ps1
  PS> .\register_windows_associations.ps1 -ExePath "D:\Apps\aria2down\aria2down.exe"
  PS> .\register_windows_associations.ps1 -Unregister
#>
[CmdletBinding()]
param(
  [string]$ExePath,
  [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

function Resolve-Aria2DownExe {
  param([string]$Hint)
  if ($Hint) {
    $p = (Resolve-Path -LiteralPath $Hint).Path
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
      throw "可执行文件不存在: $p"
    }
    return $p
  }
  $here = Split-Path -Parent $MyInvocation.PSCommandPath
  foreach ($candidate in @(
      (Join-Path $here 'aria2down.exe'),
      (Join-Path (Split-Path -Parent $here) 'aria2down.exe'))) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "未指定 -ExePath，且未在脚本同级目录找到 aria2down.exe"
}

# 注册表根：HKCU\Software\Classes（当前用户，无需管理员）。
$ClassesRoot = 'HKCU:\Software\Classes'

# ProgIds（自定义键，避免和其它应用冲突）。
$ProgIds = @{
  Torrent  = 'aria2down.torrent.1'
  Metalink = 'aria2down.metalink.1'
  Meta4    = 'aria2down.meta4.1'
}

# 文件扩展 → ProgId。
$FileExts = @{
  '.torrent'  = $ProgIds.Torrent
  '.metalink' = $ProgIds.Metalink
  '.meta4'    = $ProgIds.Meta4
}

# 自定义协议（URL Protocol）。
$Schemes = @('aria2down', 'magnet')

function Ensure-Key([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -Path $Path -Force | Out-Null
  }
}

function Register-ProgId {
  param([string]$ProgId, [string]$FriendlyName, [string]$Exe)
  $base = Join-Path $ClassesRoot $ProgId
  Ensure-Key $base
  Set-ItemProperty -LiteralPath $base -Name '(default)' -Value $FriendlyName
  Ensure-Key (Join-Path $base 'DefaultIcon')
  Set-ItemProperty -LiteralPath (Join-Path $base 'DefaultIcon') -Name '(default)' -Value "`"$Exe`",0"
  Ensure-Key (Join-Path $base 'shell\open\command')
  Set-ItemProperty -LiteralPath (Join-Path $base 'shell\open\command') -Name '(default)' -Value "`"$Exe`" `"%1`""
}

function Register-Extension {
  param([string]$Ext, [string]$ProgId)
  $extKey = Join-Path $ClassesRoot $Ext
  Ensure-Key $extKey
  # 不强写默认 ProgId（避免抢系统首选）；写 OpenWithProgids 让「打开方式」里出现 aria2down。
  $owp = Join-Path $extKey 'OpenWithProgids'
  Ensure-Key $owp
  New-ItemProperty -LiteralPath $owp -Name $ProgId -Value ([byte[]]@()) -PropertyType Binary -Force | Out-Null
}

function Register-Scheme {
  param([string]$Scheme, [string]$Exe)
  $base = Join-Path $ClassesRoot $Scheme
  Ensure-Key $base
  Set-ItemProperty -LiteralPath $base -Name '(default)' -Value "URL:$Scheme Protocol"
  Set-ItemProperty -LiteralPath $base -Name 'URL Protocol' -Value ''
  Ensure-Key (Join-Path $base 'DefaultIcon')
  Set-ItemProperty -LiteralPath (Join-Path $base 'DefaultIcon') -Name '(default)' -Value "`"$Exe`",0"
  Ensure-Key (Join-Path $base 'shell\open\command')
  Set-ItemProperty -LiteralPath (Join-Path $base 'shell\open\command') -Name '(default)' -Value "`"$Exe`" `"%1`""
}

function Unregister-All {
  foreach ($p in $ProgIds.Values) {
    $k = Join-Path $ClassesRoot $p
    if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force }
  }
  foreach ($ext in $FileExts.Keys) {
    $owp = Join-Path (Join-Path $ClassesRoot $ext) 'OpenWithProgids'
    if (Test-Path -LiteralPath $owp) {
      foreach ($p in $ProgIds.Values) {
        if (Get-ItemProperty -LiteralPath $owp -Name $p -ErrorAction SilentlyContinue) {
          Remove-ItemProperty -LiteralPath $owp -Name $p -ErrorAction SilentlyContinue
        }
      }
    }
  }
  foreach ($s in $Schemes) {
    $k = Join-Path $ClassesRoot $s
    if (Test-Path -LiteralPath $k) {
      $owner = (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'(default)'
      # 只移除我们自己写的 URL Protocol 条目，避免误删用户其它客户端。
      if ($owner -like "URL:$s Protocol") {
        Remove-Item -LiteralPath $k -Recurse -Force
      }
    }
  }
  Write-Host "已移除 aria2down 在 HKCU\Software\Classes 下的关联。" -ForegroundColor Yellow
}

if ($Unregister) {
  Unregister-All
  return
}

$exe = Resolve-Aria2DownExe -Hint $ExePath
Write-Host "注册 aria2down 关联到: $exe" -ForegroundColor Cyan

Register-ProgId -ProgId $ProgIds.Torrent  -FriendlyName 'BitTorrent file (aria2down)' -Exe $exe
Register-ProgId -ProgId $ProgIds.Metalink -FriendlyName 'Metalink (aria2down)'        -Exe $exe
Register-ProgId -ProgId $ProgIds.Meta4    -FriendlyName 'Metalink 4 (aria2down)'      -Exe $exe

foreach ($ext in $FileExts.Keys) {
  Register-Extension -Ext $ext -ProgId $FileExts[$ext]
}

foreach ($s in $Schemes) {
  Register-Scheme -Scheme $s -Exe $exe
}

Write-Host @"

完成。请测试：
  - 浏览器地址栏粘贴: aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip
  - 文件管理器右键 .torrent → 打开方式 → aria2down
  - 任意页面点击 magnet: 链接

如果 Windows 仍未让 aria2down 出现在「打开方式」里，可以注销再重新登录；
或在系统设置 → 应用 → 默认应用 → 按文件类型选择默认应用 里手动指派。

卸载本工具写入的关联：
  .\$($MyInvocation.MyCommand.Name) -Unregister
"@ -ForegroundColor Green
