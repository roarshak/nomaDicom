[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$RemoteHost = "10.240.24.226",
  [string]$RemoteUser = "medsrv",
  [int]$Port = 22,
  [string]$RemotePath = "~/migctl",
  [string]$LocalRoot = (Resolve-Path "$PSScriptRoot\..\migctl").Path,
  [string]$KeyPath = "",
  [string]$ConfigDir = "/home/medsrv/migctl/config",
  [switch]$IncludeConfig,
  [switch]$DryRun,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$MigctlArgs
)

$syncArgs = @{
  RemoteHost = $RemoteHost
  RemoteUser = $RemoteUser
  Port       = $Port
  RemotePath = $RemotePath
  LocalRoot  = $LocalRoot
}
if ($KeyPath) { $syncArgs.KeyPath = $KeyPath }
if ($IncludeConfig) { $syncArgs.IncludeConfig = $true }
if ($DryRun) { $syncArgs.DryRun = $true }

& "$PSScriptRoot\sync-to-pacs.ps1" @syncArgs

if ($DryRun) { return }

$runArgs = @{
  RemoteHost = $RemoteHost
  RemoteUser = $RemoteUser
  Port       = $Port
  RemotePath = $RemotePath
}
if ($KeyPath) { $runArgs.KeyPath = $KeyPath }
if ($ConfigDir) { $runArgs.ConfigDir = $ConfigDir }

& "$PSScriptRoot\run-remote-migctl.ps1" @runArgs @MigctlArgs
