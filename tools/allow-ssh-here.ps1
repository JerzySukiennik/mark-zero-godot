# Let the Mac reach this laptop on the network you are on right now.
#
# Why this is ever needed: Windows classifies each network as Public or Private. On a
# Public one it blocks every inbound connection, including SSH - which is why the laptop
# went silent when it moved from the flat to Gzowo even though nothing on it changed.
#
# This marks the CURRENT network as Private and makes sure the SSH server is running and
# starts with Windows. It touches only the network you are on now.
#
# Needs administrator rights: right-click PowerShell, "Run as administrator", then
#   irm https://raw.githubusercontent.com/JerzySukiennik/mark-zero-godot/main/tools/allow-ssh-here.ps1 | iex

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Run PowerShell as administrator and try again." -ForegroundColor Yellow
    return
}

Get-NetConnectionProfile | ForEach-Object {
    if ($_.NetworkCategory -ne 'Private') {
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
        Write-Host "  '$($_.Name)' is now a Private network" -ForegroundColor Green
    } else {
        Write-Host "  '$($_.Name)' was already Private" -ForegroundColor Green
    }
}

$svc = Get-Service sshd -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Host "  The OpenSSH server is not installed. Installing..." -ForegroundColor Cyan
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    $svc = Get-Service sshd
}
Set-Service -Name sshd -StartupType Automatic
if ($svc.Status -ne 'Running') { Start-Service sshd }
Write-Host "  SSH server running, and set to start with Windows" -ForegroundColor Green

if (-not (Get-NetFirewallRule -Name 'MarkZero-SSH' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'MarkZero-SSH' -DisplayName 'SSH (Mark Zero)' `
        -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
}
Write-Host "  Firewall allows SSH on port 22" -ForegroundColor Green

Write-Host ""
Write-Host "  This machine is now reachable at:" -ForegroundColor White
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    ForEach-Object { Write-Host "    ssh $env:USERNAME@$($_.IPAddress)" -ForegroundColor White }
Write-Host ""
