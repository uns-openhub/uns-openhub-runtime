param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("uns", "infisical-rotator")]
  [string]$Tool
)

$ErrorActionPreference = "Stop"
$RuntimeDir = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $RuntimeDir "VERSION") -Raw).Trim()
$Repository = (Get-Content (Join-Path $RuntimeDir "release/repository") -Raw).Trim()
$Tag = (Get-Content (Join-Path $RuntimeDir "release/tag") -Raw).Trim()

$Architecture = switch ($env:PROCESSOR_ARCHITECTURE.ToUpperInvariant()) {
  "ARM64" { "arm64" }
  "AMD64" { "amd64" }
  default { throw "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$Asset = "$Tool-$Version-windows-$Architecture.exe"
$ChecksumPath = Join-Path $RuntimeDir "release/SHA256SUMS"
$ChecksumLine = Get-Content $ChecksumPath |
  Where-Object { $_ -match "^[0-9a-f]{64}  $([regex]::Escape($Asset))$" } |
  Select-Object -First 1
if (-not $ChecksumLine) {
  throw "Release checksum not found for $Asset"
}
$Expected = ($ChecksumLine -split "\s+")[0]

function Test-Asset([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Expected
}

$LocalAsset = Join-Path $RuntimeDir ".release/$Version/$Asset"
if (Test-Asset $LocalAsset) {
  Write-Output $LocalAsset
  exit 0
}

$CacheDir = if ($env:UNS_RUNTIME_CACHE_DIR) {
  $env:UNS_RUNTIME_CACHE_DIR
} else {
  Join-Path $RuntimeDir ".cache/bin"
}
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
$CachedAsset = Join-Path $CacheDir $Asset
if (Test-Asset $CachedAsset) {
  Write-Output $CachedAsset
  exit 0
}

$TempAsset = Join-Path $CacheDir ".$Asset.$([guid]::NewGuid().ToString('N'))"
try {
  $PublicUrl = "https://github.com/$Repository/releases/download/$Tag/$Asset"
  try {
    Invoke-WebRequest -Uri $PublicUrl -OutFile $TempAsset -UseBasicParsing
    if (-not (Test-Asset $TempAsset)) {
      throw "SHA-256 verification failed"
    }
  } catch {
    Remove-Item -LiteralPath $TempAsset -Force -ErrorAction SilentlyContinue
    $Token = if ($env:UNS_GITHUB_TOKEN) {
      $env:UNS_GITHUB_TOKEN
    } elseif ($env:GH_TOKEN) {
      $env:GH_TOKEN
    } else {
      $SecureToken = Read-Host "GitHub read-only token" -AsSecureString
      [System.Net.NetworkCredential]::new("", $SecureToken).Password
    }
    if (-not $Token) {
      throw "GitHub token must not be empty"
    }
    $Headers = @{
      Accept = "application/vnd.github+json"
      Authorization = "Bearer $Token"
      "X-GitHub-Api-Version" = "2022-11-28"
    }
    $Release = Invoke-RestMethod `
      -Uri "https://api.github.com/repos/$Repository/releases/tags/$Tag" `
      -Headers $Headers
    $ReleaseAsset = $Release.assets | Where-Object { $_.name -eq $Asset } |
      Select-Object -First 1
    if (-not $ReleaseAsset) {
      throw "Release asset $Asset was not found in $Repository@$Tag"
    }
    $Headers.Accept = "application/octet-stream"
    Invoke-WebRequest -Uri $ReleaseAsset.url -Headers $Headers `
      -OutFile $TempAsset -UseBasicParsing
    if (-not (Test-Asset $TempAsset)) {
      throw "SHA-256 verification failed for downloaded asset $Asset"
    }
    $Token = $null
  }
  Move-Item -LiteralPath $TempAsset -Destination $CachedAsset -Force
  Write-Output $CachedAsset
} finally {
  Remove-Item -LiteralPath $TempAsset -Force -ErrorAction SilentlyContinue
}
