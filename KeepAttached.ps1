# Keeps Equalizer APO attached to the soundbar Surround Fill uses.
# Windows sometimes swaps an audio device for a fresh copy (driver updates, some restarts). The copy
# comes without Equalizer APO, so the tray button stops doing anything. This finds that copy and
# attaches Equalizer APO the same way its Device Selector does, then restarts Windows audio.
# It runs as a scheduled task at startup and whenever Windows adds an audio device.
#   -Install    (admin) copy to Program Files, create the task, fix anything now. Setup.ps1 does this.
#   -Uninstall  (admin) remove the task and the copy.
#   -Check      only report what it would do. No admin needed.
param([switch]$Check, [switch]$Install, [switch]$Uninstall)

if ($Install -or $Uninstall) {
    $taskName = 'Surround Fill'
    $installDir = Join-Path $env:ProgramFiles 'Surround Fill'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if ($Uninstall) { Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue; return }
    New-Item $installDir -ItemType Directory -Force | Out-Null
    Copy-Item $PSCommandPath "$installDir\KeepAttached.ps1" -Force
    # Kernel-PnP event 400 for the audio endpoint class = Windows just created an audio device
    $query = "<QueryList><Query Id='0' Path='Microsoft-Windows-Kernel-PnP/Configuration'><Select Path='Microsoft-Windows-Kernel-PnP/Configuration'>" +
        "*[System[EventID=400]] and *[EventData[Data[@Name='ClassGuid']='{c166523c-fe0c-4a94-a586-f1a80cfbbf3e}']]</Select></Query></QueryList>"
    $xml = @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Re-attaches Equalizer APO to the Surround Fill soundbar when Windows replaces the audio device.</Description></RegistrationInfo>
  <Triggers>
    <BootTrigger><Delay>PT30S</Delay></BootTrigger>
    <EventTrigger><Delay>PT30S</Delay><Subscription>$([Security.SecurityElement]::Escape($query))</Subscription></EventTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$installDir\KeepAttached.ps1"</Arguments></Exec></Actions>
</Task>
"@
    Register-ScheduledTask -TaskName $taskName -Xml $xml | Out-Null
    & "$installDir\KeepAttached.ps1"
    return
}

$apoKey  = 'HKLM:\SOFTWARE\EqualizerAPO'
$render  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$fx      = '{d04e05a6-594b-4fb6-a80d-01af5eed7d1d}'   # effect slots: 1 LFX, 2 GFX, 5 SFX, 6 MFX, 7 EFX
$modes   = '{d3993a3f-99c2-4402-b5ec-a92a0367664b}'   # processing modes, same slot numbers
$preMix  = '{EACD2258-FCAC-4FF4-B36D-419E924A6D79}'   # Equalizer APO
$postMix = '{EC1CC9CE-FAED-4822-828A-82A81A6F018F}'
$slots   = 1, 2, 5, 6, 7
$logFile = Join-Path $PSScriptRoot 'KeepAttached.log'

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Write-Host $line
    if (-not $Check) { Add-Content $logFile $line -ErrorAction SilentlyContinue }
}

# The soundbar is the Device: line in config.txt that applies to "Include: surround-fill.txt"
function Get-FillDevices {
    $cfg = (Get-ItemProperty $apoKey -ErrorAction SilentlyContinue).ConfigPath
    if (-not $cfg -or -not (Test-Path "$cfg\config.txt")) { return }
    $device = 'all'
    foreach ($line in Get-Content "$cfg\config.txt") {
        if ($line -match '^\s*Device:\s*(.*?)\s*$') { $device = $Matches[1] }
        elseif ($line -match '^\s*Include:.*surround-fill\.txt') {
            return $device -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'all' }
        }
    }
}

function Get-Endpoints {
    foreach ($key in Get-ChildItem $render) {
        $props = Get-ItemProperty "$($key.PSPath)\Properties" -ErrorAction SilentlyContinue
        $fxKey = Get-Item "$($key.PSPath)\FxProperties" -ErrorAction SilentlyContinue
        $vals = $null
        if ($fxKey) { $vals = @{}; foreach ($n in $fxKey.GetValueNames()) { $vals[$n] = $fxKey.GetValue($n) } }
        $child = $null
        if ($c = Get-Item "$apoKey\Child APOs\$($key.PSChildName)" -ErrorAction SilentlyContinue) {
            $child = @{}; foreach ($n in $c.GetValueNames()) { $child[$n] = [string]$c.GetValue($n) }
        }
        [pscustomobject]@{
            Id       = $key.PSChildName
            Present  = ((Get-ItemProperty $key.PSPath).DeviceState -band 0xF) -in 1, 8   # active or unplugged
            Dev      = $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
            Conn     = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
            Combined = $null -ne $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},41'
            Fx       = $vals
            Child    = $child
        }
    }
}

function Get-ApoSlots($ep) { if ($ep -and $ep.Fx) { $slots | Where-Object { $ep.Fx["$fx,$_"] -in $preMix, $postMix } } }

# Install mode: copy it from the older copy, otherwise choose it the way Device Selector does
function Get-Mode($ep, $ref) {
    $s = @(Get-ApoSlots $ref)
    if ($s -contains 1 -or $s -contains 2) { return 'LFX_GFX' }
    if ($s -contains 6) { return 'SFX_MFX' }
    if ($s -contains 7) { return 'SFX_EFX' }
    $has = @(1, 2, 5, 6, 7, 13, 14, 15 | Where-Object { $ep.Fx.ContainsKey("$fx,$_") })
    if (($has -contains 1 -or $has -contains 2) -and -not ($has | Where-Object { $_ -ge 5 })) { return 'LFX_GFX' }
    if ($ep.Combined) { return 'SFX_MFX' }
    'SFX_EFX'
}

# The driver effect Equalizer APO passes audio on to (Device Selector's getOriginalAPOPreMix/PostMix)
function Get-Original($orig, $mode, [int]$post) {
    $nv = '!VALUE'
    $g = switch ($mode) {
        'LFX_GFX' { if ($orig[1] -eq $nv -and $orig[2] -eq $nv) { $orig[(5, 6)[$post]] } else { $orig[(1, 2)[$post]] } }
        'SFX_MFX' { if ($orig[5] -eq $nv -and $orig[6] -eq $nv) { $orig[(1, 2)[$post]] } else { $orig[(5, 6)[$post]] } }
        'SFX_EFX' { if ($orig[5] -eq $nv -and $orig[7] -eq $nv) { $orig[(1, 2)[$post]] } else { $orig[(5, 7)[$post]] } }
    }
    if ($g -in '!VALUE', '!KEY') { '' } else { [string]$g }
}

function Attach($ep, $ref) {
    $mode = Get-Mode $ep $ref
    # Reuse the choices made in Device Selector for this soundbar
    $opt = if ($ep.Child) { $ep.Child } else { $ref.Child }
    $installPre = $installPost = $true
    if ($ref) {
        $refVals = $slots | ForEach-Object { $ref.Fx["$fx,$_"] }
        $installPre = $refVals -contains $preMix
        $installPost = $refVals -contains $postMix
    }
    $optOrig = @{}; foreach ($n in $slots) { $optOrig[$n] = $opt["$fx,$n"] }
    $usePre  = $opt['PreMixChild'] -or -not (Get-Original $optOrig $mode 0)
    $usePost = $opt['PostMixChild'] -or -not (Get-Original $optOrig $mode 1)

    # 1. Back up the device's own effects where Equalizer APO looks for them
    $orig = @{}
    foreach ($n in $slots) { $orig[$n] = if ($ep.Fx.ContainsKey("$fx,$n")) { [string]$ep.Fx["$fx,$n"] } else { '!VALUE' } }
    $child = "$apoKey\Child APOs\$($ep.Id)"
    if (-not (Test-Path $child)) { New-Item $child -Force | Out-Null }
    $values = [ordered]@{}
    foreach ($n in $slots) { $values["$fx,$n"] = $orig[$n] }
    $values.PreMixChild = if ($usePre) { Get-Original $orig $mode 0 } else { '' }
    $values.PostMixChild = if ($usePost) { Get-Original $orig $mode 1 } else { '' }
    $values.AllowSilentBufferModification = if ($opt['AllowSilentBufferModification']) { $opt['AllowSilentBufferModification'] } else { 'false' }
    if ($opt['DisableAutomaticAdjustment'] -eq 'true') { $values.DisableAutomaticAdjustment = 'true' }
    $values.Version = '2'
    foreach ($v in $values.GetEnumerator()) { New-ItemProperty $child -Name $v.Key -Value $v.Value -PropertyType String -Force | Out-Null }

    # 2. Put Equalizer APO in the effect slots.
    # Administrators may only set values here, so open the key with exactly those rights.
    $sub = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\$($ep.Id)\FxProperties"
    $w = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [Security.AccessControl.RegistryRights]'SetValue, ReadKey')
    if (-not $w) { throw "Could not open $sub" }
    try {
        $put = { param($n, $guid)
            $w.SetValue("$fx,$n", $guid, 'String')
            if ($n -ge 5 -and $null -eq $w.GetValue("$modes,$n")) {
                $w.SetValue("$modes,$n", [string[]]'{C18E2F7E-933D-4965-B7D1-1EEF228D2AF3}', 'MultiString')
            }
        }
        $drop = { param($n) $w.DeleteValue("$fx,$n", $false) }
        switch ($mode) {
            'LFX_GFX' { if ($installPre) { & $put 1 $preMix }; if ($installPost) { & $put 2 $postMix }; 5, 6, 7 | ForEach-Object { & $drop $_ } }
            'SFX_MFX' { 1, 2 | ForEach-Object { & $drop $_ }; if ($installPre) { & $put 5 $preMix }; if ($installPost) { & $put 6 $postMix } }
            'SFX_EFX' { 1, 2 | ForEach-Object { & $drop $_ }; if ($installPre) { & $put 5 $preMix }; if ($installPost) { & $put 7 $postMix } }
        }
        $w.DeleteValue('{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5', $false)   # turn audio enhancements back on
    } finally { $w.Close() }
    Log "Attached Equalizer APO to $($ep.Conn) $($ep.Id) ($mode)"
}

$patterns = @(Get-FillDevices)
if (-not $patterns) { Log 'No soundbar set for surround-fill.txt in config.txt. Nothing to do.'; exit 0 }
$eps = @(Get-Endpoints)
$todo = 0; $done = 0
foreach ($ep in $eps) {
    if (-not $ep.Present -or (Get-ApoSlots $ep)) { continue }
    $str = "$($ep.Dev) $($ep.Conn) $($ep.Id)".ToLower()
    if (-not ($patterns | Where-Object { $str.Contains($_.ToLower()) })) { continue }
    # Only where Equalizer APO was attached before: on this device (Windows reset it) or an older copy of it
    $ref = $eps | Where-Object { $_.Id -ne $ep.Id -and $_.Dev -eq $ep.Dev -and $_.Conn -eq $ep.Conn -and $_.Child -and (Get-ApoSlots $_) } |
        Select-Object -First 1
    if (-not $ep.Child -and -not $ref) { continue }
    $todo++
    if (-not $ep.Fx) { Log "$($ep.Conn) $($ep.Id) has no effect settings yet. Use Equalizer APO's Device Selector."; continue }
    if ($Check) { Log "Would attach Equalizer APO to $($ep.Conn) $($ep.Id) ($(Get-Mode $ep $ref))"; continue }
    try { Attach $ep $ref; $done++ } catch { Log "Failed on $($ep.Conn) $($ep.Id): $_" }
}

if ($done) { Restart-Service Audiosrv -Force; Log 'Restarted Windows audio.' }
elseif (-not $todo) { Log "Nothing to fix for $($patterns -join '; ')." }
if (-not $Check -and (Test-Path $logFile) -and (Get-Item $logFile).Length -gt 64KB) {
    (Get-Content $logFile -Tail 300) | Set-Content $logFile
}
if ($Check -and $todo) { exit 1 }
exit 0
