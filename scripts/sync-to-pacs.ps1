[CmdletBinding()]
param(
  [string]$RemoteHost = "10.240.24.226",
  [string]$RemoteUser = "medsrv",
  [int]$Port = 22,
  [string]$RemotePath = "~/migctl",
  [string]$LocalRoot = (Resolve-Path "$PSScriptRoot\..\migctl").Path,
  [string]$KeyPath = "",
  [switch]$IncludeConfig,
  [switch]$DryRun
)

function Require-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $Name"
  }
}

Require-Cmd "ssh"
Require-Cmd "scp"

$localRootResolved = (Resolve-Path $LocalRoot).Path
$remotePath = $RemotePath

$sshArgs = @("-p", $Port, "-o", "BatchMode=yes")
$scpArgs = @("-P", $Port, "-r", "-C", "-o", "BatchMode=yes")

if ($KeyPath) {
  $sshArgs += @("-i", $KeyPath)
  $scpArgs += @("-i", $KeyPath)
}

$mkdirCmd = "mkdir -p $remotePath"
if ($DryRun) {
  Write-Host ("ssh " + ($sshArgs -join " ") + " $RemoteUser@$RemoteHost $mkdirCmd")
} else {
  & ssh @sshArgs "$RemoteUser@$RemoteHost" $mkdirCmd | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Remote mkdir failed (exit $LASTEXITCODE)."
  }
}

$syncItems = @(
  "migctl.sh",
  "config",
  "lib",
  "schema"
)

# IncludeConfig is kept for backward compatibility; config is always synced.
$syncSources = @()
foreach ($item in $syncItems) {
  $path = Join-Path $localRootResolved $item
  if (Test-Path $path) {
    $syncSources += $path
  } else {
    Write-Host "Warning: sync item not found: $path"
  }
}

if ($syncSources.Count -eq 0) {
  throw "No sync sources found under $localRootResolved"
}

$scpTarget = "${RemoteUser}@${RemoteHost}:$remotePath/"
if ($DryRun) {
  Write-Host ("scp " + ($scpArgs -join " ") + " " + ($syncSources -join " ") + " " + $scpTarget)
} else {
  & scp @scpArgs @syncSources $scpTarget
  if ($LASTEXITCODE -ne 0) {
    throw "SCP sync failed (exit $LASTEXITCODE)."
  }
}

Write-Host ("Synced " + ($syncSources -join ", ") + " -> " + $scpTarget)

$fixCmd = "find $remotePath -type f \( -name '*.sh' -o -name '*.cfg' \) -print0 | xargs -0 sed -i 's/\r$//'; chmod +x $remotePath/migctl.sh $remotePath/lib/*.sh"
if ($DryRun) {
  Write-Host ("ssh " + ($sshArgs -join " ") + " $RemoteUser@$RemoteHost $fixCmd")
} else {
  & ssh @sshArgs "$RemoteUser@$RemoteHost" $fixCmd | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Remote fix (line endings/perms) failed (exit $LASTEXITCODE)."
  }
}
