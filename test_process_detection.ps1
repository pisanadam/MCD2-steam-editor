#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Dogrulama-Ortak.ps1')

$Expected = @('Dungeons', 'Dungeons-Win64-Shipping', 'Dungeons2', 'Dungeons2-Win64-Shipping', 'MinecraftDungeonsII', 'MinecraftDungeons2-Win64-Shipping')
$Rejected = @('Dungeons-II-Forge', 'Dungeons-II-Forge-v2', 'Dungeons-Editor', 'Dungeons.Tools', 'Dungeons-Win64-Shipping-Editor', 'steam', 'powershell')
function Get-Process {
    param($ErrorAction)
    foreach ($Name in ($Expected + $Rejected)) { [PSCustomObject]@{ ProcessName = $Name } }
}
$Actual = @(Get-DFGameProcesses | Select-Object -ExpandProperty ProcessName)
if (@(Compare-Object $Expected $Actual).Count -ne 0) { throw ('Process detection regression: ' + ($Actual -join ', ')) }
Remove-Item Function:\Get-Process
Write-Output 'PASS: real game names detected; Forge/editor/helper names excluded.'
