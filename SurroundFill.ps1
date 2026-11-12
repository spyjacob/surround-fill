# Tray app that plays stereo audio through the surround speakers via Equalizer APO.
# Left-click opens a small window with the on/off button and the surround volume.
# Closing the window puts it back in the tray. Right-click turns the fill off and exits.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\SurroundFill', [ref]$created)
if (-not $created) { return }

$fillFile = Join-Path (Get-ItemProperty HKLM:\SOFTWARE\EqualizerAPO).ConfigPath 'surround-fill.txt'
$iconOn  = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-on.ico')
$iconOff = New-Object Drawing.Icon (Join-Path $PSScriptRoot 'surround-off.ico')
$inv = [Globalization.CultureInfo]::InvariantCulture
$minDb = -12; $maxDb = 6   # surround volume range, relative to the fronts

# surround-fill.txt keeps the volume ("# level <dB>") and, when on, the Copy and Preamp lines
function Read-Fill {
    $text = if (Test-Path $fillFile) { [string](Get-Content $fillFile -Raw) } else { '' }
    $db = 0
    if ($text -match '#\s*level\s+(-?[\d.]+)') { $db = [double]::Parse($Matches[1], $inv) }
    elseif ($text -match 'SL=SL\+([\d.]+)\*L') { $db = 20 * [Math]::Log10([double]::Parse($Matches[1], $inv)) }  # older versions
    @{ On = $text -match 'Copy:'; Db = [int][Math]::Max($minDb, [Math]::Min($maxDb, [Math]::Round($db))) }
}

function Write-Fill {
    $gain = [Math]::Pow(10, $state.Db / 20)
    # Preamp offsets the added surrounds so overall loudness doesn't change
    $preamp = (10 * [Math]::Log10(2 / (2 + 2 * $gain * $gain))).ToString('0.0', $inv)
    $g = $gain.ToString('0.####', $inv)
    $lines = @("# level $($state.Db)")
    $lines += if ($state.On) { "Copy: SL=SL+$g*L SR=SR+$g*R", "Preamp: $preamp dB" } else { '# off' }
    Set-Content $fillFile $lines -Encoding ASCII
}

$state = Read-Fill

# Window, following the Windows light/dark setting
$dark  = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
$bg    = if ($dark) { [Drawing.Color]::FromArgb(32, 32, 32) } else { [Drawing.Color]::FromArgb(249, 249, 249) }
$fg    = if ($dark) { [Drawing.Color]::White } else { [Drawing.Color]::Black }
$dim   = if ($dark) { [Drawing.Color]::FromArgb(160, 160, 160) } else { [Drawing.Color]::FromArgb(96, 96, 96) }
$offBg = if ($dark) { [Drawing.Color]::FromArgb(55, 55, 55) } else { [Drawing.Color]::FromArgb(229, 229, 229) }
$onBg  = [Drawing.Color]::FromArgb(16, 124, 16)

$form = New-Object Windows.Forms.Form -Property @{
    Text = 'Surround Fill'; FormBorderStyle = 'FixedSingle'; MaximizeBox = $false; MinimizeBox = $false
    ShowInTaskbar = $false; StartPosition = 'Manual'; KeyPreview = $true
    ClientSize = New-Object Drawing.Size(300, 142); BackColor = $bg; ForeColor = $fg
    Font = New-Object Drawing.Font('Segoe UI', 10)
}
$power = New-Object Windows.Forms.CheckBox -Property @{
    Appearance = 'Button'; AutoCheck = $false; FlatStyle = 'Flat'; TextAlign = 'MiddleCenter'
    Bounds = New-Object Drawing.Rectangle(16, 16, 268, 40); Font = New-Object Drawing.Font('Segoe UI Semibold', 11)
}
$power.FlatAppearance.BorderSize = 0
$label = New-Object Windows.Forms.Label -Property @{
    Text = 'Surround volume'; Bounds = New-Object Drawing.Rectangle(16, 70, 180, 22); ForeColor = $fg
}
$value = New-Object Windows.Forms.Label -Property @{
    Bounds = New-Object Drawing.Rectangle(200, 70, 84, 22); TextAlign = 'TopRight'; ForeColor = $dim
}
$slider = New-Object Windows.Forms.TrackBar -Property @{
    TickFrequency = 3; SmallChange = 1; LargeChange = 3; Bounds = New-Object Drawing.Rectangle(8, 94, 284, 45); BackColor = $bg
}
$slider.Minimum = $minDb; $slider.Maximum = $maxDb; $slider.Value = $state.Db
$form.Controls.AddRange(@($power, $label, $value, $slider))
$form.ClientSize = New-Object Drawing.Size(300, 142)

if ($dark) {
    Add-Type -Namespace SurroundFill -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);'
    $form.Add_HandleCreated({ $v = 1; [void][SurroundFill.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4) })
}

$tray = New-Object Windows.Forms.NotifyIcon
function Show-State {
    $icon = if ($state.On) { $iconOn } else { $iconOff }
    $tray.Icon = $icon; $form.Icon = $icon
    $tray.Text = if ($state.On) { 'Surround Fill: ON' } else { 'Surround Fill: OFF' }
    $power.Checked = $state.On
    $power.Text = if ($state.On) { 'On' } else { 'Off' }
    $power.BackColor = if ($state.On) { $onBg } else { $offBg }
    $power.ForeColor = if ($state.On) { [Drawing.Color]::White } else { $fg }
    $power.FlatAppearance.MouseOverBackColor = $power.BackColor
    $power.FlatAppearance.CheckedBackColor = $power.BackColor
    $value.Text = if ($state.Db -gt 0) { "+$($state.Db) dB" } else { "$($state.Db) dB" }
}

$power.Add_Click({ $state.On = -not $state.On; Write-Fill; Show-State })

# Save the volume a moment after the slider stops moving, so Equalizer APO isn't reloaded on every step
$saveTimer = New-Object Windows.Forms.Timer -Property @{ Interval = 250 }
$saveTimer.Add_Tick({ $saveTimer.Stop(); Write-Fill })
$slider.Add_ValueChanged({ $state.Db = $slider.Value; Show-State; $saveTimer.Stop(); $saveTimer.Start() })

$form.Add_FormClosing({ param($s, $e) if ($e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $form.Hide() } })
$form.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $form.Hide() } })

$tray.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq 'Left') {
        # Open just above the tray, on the screen the mouse is on
        $area = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
        $form.Location = New-Object Drawing.Point(($area.Right - $form.Width - 12), ($area.Bottom - $form.Height - 12))
        $form.Show(); $form.Activate()
    } elseif ($e.Button -eq 'Right') {
        $saveTimer.Stop()
        $state.On = $false; Write-Fill
        $tray.Visible = $false
        [Windows.Forms.Application]::Exit()
    }
})

Show-State
$tray.Visible = $true
[Windows.Forms.Application]::Run()
$tray.Dispose()
