# Tray toggle that plays stereo audio through the surround speakers via Equalizer APO.
# Left-click toggles; right-click turns it off and exits.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\SurroundFill', [ref]$created)
if (-not $created) { return }

$fillFile = Join-Path (Get-ItemProperty HKLM:\SOFTWARE\EqualizerAPO).ConfigPath 'surround-fill.txt'
$iconOn  = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-on.ico')
$iconOff = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-off.ico')

function Get-Fill { (Test-Path $fillFile) -and ([string](Get-Content $fillFile -Raw) -match 'Copy:') }

function Set-Fill([bool]$on) {
    # -3.5 dB offsets the added rears + center so overall loudness doesn't change
    $lines = if ($on) { 'Copy: RL=RL+L RR=RR+R C=C+0.5*L+0.5*R', 'Preamp: -3.5 dB' } else { '# off' }
    Set-Content $fillFile $lines -Encoding ASCII
}

$tray = New-Object Windows.Forms.NotifyIcon
function Show-State {
    if (Get-Fill) { $tray.Icon = $iconOn;  $tray.Text = 'Surround Fill: ON' }
    else          { $tray.Icon = $iconOff; $tray.Text = 'Surround Fill: OFF' }
}

$tray.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq 'Left') {
        Set-Fill (-not (Get-Fill))
        Show-State
    } elseif ($e.Button -eq 'Right') {
        Set-Fill $false
        $tray.Visible = $false
        [Windows.Forms.Application]::Exit()
    }
})

Show-State
$tray.Visible = $true
[Windows.Forms.Application]::Run()
$tray.Dispose()
