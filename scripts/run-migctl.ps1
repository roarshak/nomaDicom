[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$RemoteHost = "10.240.24.226",
  [string]$RemoteUser = "medsrv",
  [int]$Port = 22,
  [string]$RemotePath = "~/migctl",
  [string]$KeyPath = "C:\Users\BOOTHJ\My Applications\SSH Clients\Keypairs\openSSH_key",
  [string]$ConfigDir = "/home/medsrv/migctl/config",
  [switch]$IncludeConfig,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$MigctlArgs
)

$syncArgs = @{
  RemoteHost = $RemoteHost
  RemoteUser = $RemoteUser
  Port       = $Port
  RemotePath = $RemotePath
  KeyPath    = $KeyPath
}
if ($IncludeConfig) { $syncArgs.IncludeConfig = $true }

& "$PSScriptRoot\sync-to-pacs.ps1" @syncArgs

$runArgs = @{
  RemoteHost = $RemoteHost
  RemoteUser = $RemoteUser
  Port       = $Port
  RemotePath = $RemotePath
  KeyPath    = $KeyPath
  ConfigDir  = $ConfigDir
}

& "$PSScriptRoot\run-remote-migctl.ps1" @runArgs @MigctlArgs
