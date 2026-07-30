param(
    [string]$Runtime = "win-x64",
    [string]$Configuration = "Release",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot "dist"
}
$PublishDirectory = Join-Path $OutputDirectory "MiaoXinxin-$Runtime"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

dotnet publish (Join-Path $PSScriptRoot "WindowsPet.csproj") `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $PublishDirectory

$Archive = Join-Path $OutputDirectory "MiaoXinxin-Windows-$Runtime.zip"
Compress-Archive -Path (Join-Path $PublishDirectory "*") -DestinationPath $Archive -Force
Write-Output $Archive
