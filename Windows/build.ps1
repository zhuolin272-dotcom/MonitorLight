[CmdletBinding()]
param([string]$Dotnet = 'dotnet')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'dist'
$publish = Join-Path $output 'windows-x64'
$zip = Join-Path $output 'MonitorLight-Windows-x64.zip'
$dotnetPath = (Get-Command $Dotnet -CommandType Application).Source
$dotnetDirectory = Split-Path -Parent $dotnetPath

& $dotnetPath run --project (Join-Path $PSScriptRoot 'MonitorLight.Tests') -c Release
if ($LASTEXITCODE -ne 0) { throw 'MonitorLight Windows tests failed.' }

& $dotnetPath publish (Join-Path $PSScriptRoot 'MonitorLight') -c Release -r win-x64 `
    --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $publish
if ($LASTEXITCODE -ne 0) { throw 'MonitorLight publish failed.' }

$files = @((Join-Path $publish 'MonitorLight.exe'),
           (Join-Path $dotnetDirectory 'LICENSE.txt'),
           (Join-Path $dotnetDirectory 'ThirdPartyNotices.txt'))
Compress-Archive -LiteralPath $files -DestinationPath $zip -Force
Write-Output $zip
