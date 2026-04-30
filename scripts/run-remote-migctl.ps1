[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$RemoteHost = "10.240.24.226",
  [string]$RemoteUser = "medsrv",
  [int]$Port = 22,
  [string]$RemotePath = "~/migctl",
  [string]$KeyPath = "",
  [string]$ConfigDir = "/home/medsrv/migctl/config",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$MigctlArgs
)

function Require-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $Name"
  }
}

function Escape-BashArg([string]$Value) {
  $replacement = "'" + "`"" + "'" + "`"" + "'"
  return "'" + ($Value -replace "'", $replacement) + "'"
}

function Escape-Path([string]$Value) {
  if ($Value -match '^~' -and $Value -notmatch '\s') {
    return $Value
  }
  return Escape-BashArg $Value
}

Require-Cmd "ssh"

$sshArgs = @("-p", $Port, "-o", "BatchMode=yes")
if ($KeyPath) {
  $sshArgs += @("-i", $KeyPath)
}

$cmd = "cd $(Escape-Path $RemotePath) && bash ./migctl.sh"
if ($ConfigDir) {
  $cmd += " --config-dir $(Escape-Path $ConfigDir)"
}
if ($MigctlArgs) {
  foreach ($arg in $MigctlArgs) {
    $cmd += " $(Escape-BashArg $arg)"
  }
}

& ssh @sshArgs "$RemoteUser@$RemoteHost" $cmd
if ($LASTEXITCODE -ne 0) {
  throw "Remote migctl failed (exit $LASTEXITCODE)."
}
