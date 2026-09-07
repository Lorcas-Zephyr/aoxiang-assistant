[CmdletBinding()]
param(
    [switch]$CoreOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$swiftRoot = Join-Path $env:LOCALAPPDATA "Programs\Swift"
$swift = Get-ChildItem (Join-Path $swiftRoot "Toolchains") -Recurse -Filter swift.exe |
    Where-Object { $_.FullName -match "\\usr\\bin\\swift\.exe$" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if ($null -eq $swift) {
    throw "Swift for Windows is not installed. Install the Swift.Toolchain package first."
}

$toolchainBin = $swift.Directory.FullName
$toolchainRoot = (Resolve-Path (Join-Path $toolchainBin "..\..")).Path
$toolchainName = Split-Path $toolchainRoot -Leaf
$swiftVersion = $toolchainName -replace "\+.*$", ""
$runtimeBin = Join-Path $swiftRoot "Runtimes\$swiftVersion\usr\bin"
$sdkRoot = Join-Path $swiftRoot "Platforms\$swiftVersion\Windows.platform\Developer\SDKs\Windows.sdk"
$vsDevCmd = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio" -Recurse -Filter VsDevCmd.bat |
    Select-Object -First 1

if (-not (Test-Path $runtimeBin) -or -not (Test-Path $sdkRoot)) {
    throw "Swift runtime or Windows SDK is incomplete for $swiftVersion. Reinstall Swift.Toolchain."
}
if ($null -eq $vsDevCmd) {
    throw "Visual Studio Build Tools with the C++ workload is required for link.exe."
}

$packages = @("ios\AoxiangCore")
if (-not $CoreOnly) {
    $packages += "ios\AoxiangApp"
}

foreach ($package in $packages) {
    $command = @(
        "call `"$($vsDevCmd.FullName)`" -arch=x64 -host_arch=x64 >nul",
        "set `"PATH=$toolchainBin;$runtimeBin;%PATH%`"",
        "set `"SDKROOT=$sdkRoot`"",
        "`"$($swift.FullName)`" test --package-path `"$package`" --disable-sandbox"
    ) -join " && "

    Push-Location $repoRoot
    try {
        & cmd.exe /d /s /c $command
        if ($LASTEXITCODE -ne 0) {
            throw "Swift tests failed for $package with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}
