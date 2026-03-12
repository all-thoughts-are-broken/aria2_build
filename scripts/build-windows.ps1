[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageVersion,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$MileAria2Ref = "main",

    [string]$Configuration = "Release",

    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

$mileAria2RepoUrl = if ($env:MILE_ARIA2_REPO_URL) {
    $env:MILE_ARIA2_REPO_URL
} else {
    "https://github.com/ProjectMile/Mile.Aria2.git"
}

$mileAria2LocalSource = if ($env:MILE_ARIA2_SOURCE_DIR) {
    $env:MILE_ARIA2_SOURCE_DIR
} else {
    Join-Path $repoRoot "Mile.Aria2"
}

$sourceOrigin = $mileAria2RepoUrl
$isLocalSource = $false
if (Test-Path (Join-Path $mileAria2LocalSource ".git")) {
    $sourceOrigin = $mileAria2LocalSource
    $isLocalSource = $true
}

$sourceDir = Join-Path $WorkDir "Mile.Aria2-source"
$packageDir = Join-Path $OutputDir "package"

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (Test-Path $sourceDir) {
    Remove-Item -Recurse -Force $sourceDir
}
if (Test-Path $packageDir) {
    Remove-Item -Recurse -Force $packageDir
}

Write-Host "Cloning Mile.Aria2 from $sourceOrigin ($MileAria2Ref)"
if ($isLocalSource) {
    git clone --branch $MileAria2Ref $sourceOrigin $sourceDir
}
else {
    git clone --depth 1 --branch $MileAria2Ref $sourceOrigin $sourceDir
}

$configPath = Join-Path $sourceDir "Mile.Aria2.Library\config.h"
$configContent = Get-Content -Raw $configPath
$configReplacements = [ordered]@{
    "#define ENABLE_BITTORRENT 1" = "/* #undef ENABLE_BITTORRENT */"
    "#define ENABLE_METALINK 1" = "/* #undef ENABLE_METALINK */"
    "#define ENABLE_WEBSOCKET 1" = "/* #undef ENABLE_WEBSOCKET */"
    "#define ENABLE_XML_RPC 1" = "/* #undef ENABLE_XML_RPC */"
    "#define HAVE_LIBEXPAT 1" = "/* #undef HAVE_LIBEXPAT */"
    "#define HAVE_LIBSSH2 1" = "/* #undef HAVE_LIBSSH2 */"
    "#define HAVE_SQLITE3 1" = "/* #undef HAVE_SQLITE3 */"
    "#define HAVE_SQLITE3_OPEN_V2 1" = "/* #undef HAVE_SQLITE3_OPEN_V2 */"
}
foreach ($entry in $configReplacements.GetEnumerator()) {
    $configContent = $configContent.Replace($entry.Key, $entry.Value)
}
[System.IO.File]::WriteAllText($configPath, $configContent, [System.Text.UTF8Encoding]::new($false))

$dependenciesPropsPath = Join-Path $sourceDir "Mile.Aria2.Dependencies\Mile.Aria2.Dependencies.props"
$dependenciesContent = Get-Content -Raw $dependenciesPropsPath
$dependenciesContent = $dependenciesContent.Replace(
    "libexpatMT.lib;libssh2.lib;sqlite3.lib;zlib.lib;%(AdditionalDependencies)",
    "zlib.lib;%(AdditionalDependencies)")
[System.IO.File]::WriteAllText($dependenciesPropsPath, $dependenciesContent, [System.Text.UTF8Encoding]::new($false))

$vcxprojPath = Join-Path $sourceDir "Mile.Aria2.Library\Mile.Aria2.Library.vcxproj"
[xml]$vcxprojXml = Get-Content $vcxprojPath
$wslayImports = $vcxprojXml.SelectNodes('/*[local-name()="Project"]/*[local-name()="Import"]') | Where-Object {
    $_.Project -eq "..\Mile.Aria2.Wslay\Mile.Aria2.Wslay.props"
}
foreach ($wslayImport in $wslayImports) {
    [void]$wslayImport.ParentNode.RemoveChild($wslayImport)
}

$excludedCompilePatterns = @(
    "AbstractBtMessage.cc",
    "ActivePeerConnectionCommand.cc",
    "AnnounceList.cc",
    "AnnounceTier.cc",
    "bittorrent_helper.cc",
    "Bt*.cc",
    "DefaultBt*.cc",
    "DHT*.cc",
    "ExpatXmlParser.cc",
    "HandshakeExtensionMessage.cc",
    "IndexBtMessage*.cc",
    "InitiatorMSEHandshakeCommand.cc",
    "Lpd*.cc",
    "magnet.cc",
    "main.cc",
    "metalink_helper.cc",
    "Metalink*.cc",
    "MSEHandshake.cc",
    "NameResolveCommand.cc",
    "PeerInteractionCommand.cc",
    "PeerReceiveHandshakeCommand.cc",
    "ReceiverMSEHandshakeCommand.cc",
    "Sftp*.cc",
    "SSHSession.cc",
    "TorrentAttribute.cc",
    "TrackerWatcherCommand.cc",
    "UTMetadata*.cc",
    "UTPexExtensionMessage.cc",
    "WebSocket*.cc",
    "Xml*.cc",
    "ZeroBtMessage.cc"
)

$compileNodes = @(
    $vcxprojXml.SelectNodes(
        '/*[local-name()="Project"]/*[local-name()="ItemGroup"]/*[local-name()="ClCompile" and @Include]'
    )
)
foreach ($node in $compileNodes) {
    $includePath = [string]$node.Include
    foreach ($pattern in $excludedCompilePatterns) {
        if ($includePath -like $pattern) {
            [void]$node.ParentNode.RemoveChild($node)
            break
        }
    }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$streamWriter = [System.IO.StreamWriter]::new($vcxprojPath, $false, $utf8NoBom)
try {
    $vcxprojXml.Save($streamWriter)
}
finally {
    $streamWriter.Dispose()
}

$projectPath = Join-Path $sourceDir "Mile.Aria2.Library\Mile.Aria2.Library.vcxproj"
Write-Host "Building $projectPath"
msbuild $projectPath /m /restore /p:Configuration=$Configuration /p:Platform=$Platform /p:PreferredToolArchitecture=x64

$builtLibraryPath = Join-Path $sourceDir "Output\Binaries\$Configuration\$Platform\Mile.Aria2.Library.lib"
if (-not (Test-Path $builtLibraryPath)) {
    throw "Mile.Aria2.Library.lib was not produced at $builtLibraryPath."
}

$zlibPath = Join-Path $sourceDir "Mile.Aria2.Dependencies\Lib\$Platform\zlib.lib"
if (-not (Test-Path $zlibPath)) {
    throw "Expected bundled zlib at $zlibPath."
}

New-Item -ItemType Directory -Force -Path (Join-Path $packageDir "include\aria2") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageDir "lib") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageDir "cmake") | Out-Null

Copy-Item (Join-Path $sourceDir "Mile.Aria2.Library\Include\aria2\aria2.h") (Join-Path $packageDir "include\aria2\aria2.h")
Copy-Item $builtLibraryPath (Join-Path $packageDir "lib\aria2.lib")
Copy-Item $zlibPath (Join-Path $packageDir "lib\zlib.lib")
Copy-Item (Join-Path $sourceDir "License.md") (Join-Path $packageDir "LICENSE.Mile.Aria2.md")

$configFilePath = Join-Path $packageDir "cmake\Aria2Config.cmake"
$configVersionFilePath = Join-Path $packageDir "cmake\Aria2ConfigVersion.cmake"

$configFileContent = @'
get_filename_component(_ARIA2_PREFIX "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

if(NOT TARGET Aria2::aria2)
  add_library(Aria2::aria2 STATIC IMPORTED)
  set_target_properties(Aria2::aria2 PROPERTIES
    IMPORTED_LOCATION "${_ARIA2_PREFIX}/lib/aria2.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${_ARIA2_PREFIX}/include"
    INTERFACE_LINK_LIBRARIES
      "${_ARIA2_PREFIX}/lib/zlib.lib;Advapi32;Crypt32;Iphlpapi;Secur32;Ws2_32"
  )
endif()

unset(_ARIA2_PREFIX)
'@

$configVersionFileContent = @"
set(PACKAGE_VERSION "$PackageVersion")

if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
"@

[System.IO.File]::WriteAllText($configFilePath, $configFileContent, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($configVersionFilePath, $configVersionFileContent, [System.Text.UTF8Encoding]::new($false))

Write-Host "Package created at $packageDir"
