# Tray toggle that plays stereo audio through the surround speakers via Equalizer APO.
# Left-click toggles; right-click turns it off and exits.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\SurroundFill', [ref]$created)
if (-not $created) { return }

$rearGain = 1.0   # surround level relative to the fronts
$fillFile = Join-Path (Get-ItemProperty HKLM:\SOFTWARE\EqualizerAPO).ConfigPath 'surround-fill.txt'
$iconOn  = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-on.ico')
$iconOff = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-off.ico')

function Get-Fill { (Test-Path $fillFile) -and ([string](Get-Content $fillFile -Raw) -match 'Copy:') }

function Set-Fill([bool]$on) {
    # Preamp offsets the added rears so overall loudness doesn't change
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $preamp = (10 * [Math]::Log10(2 / (2 + 2 * $rearGain * $rearGain))).ToString('0.0', $inv)
    $g = $rearGain.ToString($inv)
    $lines = if ($on) { "Copy: SL=SL+$g*L SR=SR+$g*R", "Preamp: $preamp dB" } else { '# off' }
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
