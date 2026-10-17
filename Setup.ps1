# Guided setup for Surround Fill. Run: right-click > Run with PowerShell.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    return
}
$apoKey = 'HKLM:\SOFTWARE\EqualizerAPO'

function Step($text) { Write-Host "`n$text" -ForegroundColor Cyan }

# 1. Equalizer APO
if (-not (Test-Path $apoKey)) {
    Step '1. Install Equalizer APO'
    Write-Host 'Opening the download page. Install it, skip its Device Selector for now, then come back here.'
    Start-Process 'https://sourceforge.net/projects/equalizerapo/'
    while (-not (Test-Path $apoKey)) { Read-Host 'Press Enter once Equalizer APO is installed' | Out-Null }
}
$apo = (Get-ItemProperty $apoKey).InstallPath
$configDir = (Get-ItemProperty $apoKey).ConfigPath

# 2. Pick the soundbar
Step '2. Pick your soundbar'
$render = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$devices = @(Get-ChildItem $render | Where-Object { (Get-ItemProperty $_.PSPath).DeviceState -eq 1 } | ForEach-Object {
    $p = Get-ItemProperty "$($_.PSPath)\Properties"
    [pscustomobject]@{
        Id       = $_.PSChildName
        Name     = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
        Adapter  = $p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
        Channels = if ($f = $p.'{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0') { [BitConverter]::ToUInt16($f, 10) } else { 0 }
    }
})
for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host "  [$($i + 1)] $($devices[$i].Name) ($($devices[$i].Adapter))" }
do { $n = (Read-Host 'Number') -as [int] } until ($n -ge 1 -and $n -le $devices.Count)
$dev = $devices[$n - 1]

# 3. Speaker setup must be 5.1 or 7.1
if ($dev.Channels -lt 6) {
    Step '3. Set speaker setup to 5.1 or 7.1'
    Write-Host "Sound settings will open. Select '$($dev.Name)' > Configure > pick 5.1 or 7.1 Surround."
    Start-Process control mmsys.cpl
    Read-Host 'Press Enter when done' | Out-Null
}

# 4. Attach Equalizer APO to the soundbar
if (-not (Test-Path "$apoKey\Child APOs\$($dev.Id)")) {
    Step '4. Attach Equalizer APO'
    Write-Host "Device Selector will open. Tick '$($dev.Name)' under Playback devices, click OK, then close it."
    Start-Process (Join-Path $apo 'DeviceSelector.exe') -Wait
    $needsRestart = $true
}

# 5. Config + shortcuts
$config = Join-Path $configDir 'config.txt'
if (-not (Select-String -Path $config -Pattern 'surround-fill\.txt' -Quiet)) {
    Add-Content $config "`r`nDevice: $($dev.Name)`r`nInclude: surround-fill.txt"
}
$shell = New-Object -ComObject WScript.Shell
$targets = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
if ((Read-Host "`nStart Surround Fill with Windows? (y/n)") -eq 'y') { $targets += [Environment]::GetFolderPath('Startup') }
foreach ($dir in $targets) {
    $lnk = $shell.CreateShortcut((Join-Path $dir 'Surround Fill.lnk'))
    $lnk.TargetPath = 'wscript.exe'
    $lnk.Arguments = "`"$PSScriptRoot\SurroundFill.vbs`""
    $lnk.IconLocation = "$PSScriptRoot\surround-on.ico,0"
    $lnk.Save()
}

Step 'Done.'
if ($needsRestart) {
    if ((Read-Host 'Restart now to finish? (y/n)') -eq 'y') { Restart-Computer }
    else { Write-Host 'Restart later, then open Surround Fill from the desktop.' }
} else {
    Start-Process wscript.exe "`"$PSScriptRoot\SurroundFill.vbs`""
    Write-Host 'Surround Fill is in your tray.'
    Read-Host 'Press Enter to close' | Out-Null
}
