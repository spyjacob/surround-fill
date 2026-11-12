# Surround Fill

A tray button for Windows users with a surround or Dolby Atmos soundbar setup.

Stereo audio like YouTube often plays only from the soundbar, and the surround speakers stay silent. Click the tray icon and that audio plays through your surrounds too. Click again to go back to normal. The volume stays the same either way.

## Setup

**Easy way:** download this repo, right-click `Setup.ps1` and choose **Run with PowerShell**. It walks you through everything below. Already set up from an older version? Download the new one and run `Setup.ps1` again.

**Manual way:**

1. Install [Equalizer APO](https://sourceforge.net/projects/equalizerapo/). In its Device Selector, tick your soundbar under Playback devices, then restart your PC.
2. In Windows Sound settings, set your soundbar's speaker setup to **5.1** or **7.1**.
3. Add these two lines to the end of `C:\Program Files\EqualizerAPO\config\config.txt`, using your soundbar's name as it appears in Sound settings:
   ```
   Device: Your Soundbar Name
   Include: surround-fill.txt
   ```
4. Download this repo and double-click `SurroundFill.vbs`.
5. Optional but recommended: in an admin PowerShell in the repo folder, run `powershell -ExecutionPolicy Bypass -File .\KeepAttached.ps1 -Install` (see below).

## Use

- **Left-click** the tray icon to open the Surround Fill window. Click **On/Off** to switch it, and drag **Surround volume** to set how loud the surrounds are compared with the front speakers. Close the window and it goes back to the tray.
- **Right-click** the tray icon to turn it off and close it.
- The tray icon is green when it's on.

Turn it off for movies and games that already have real surround sound.

## If it stops doing anything

Windows sometimes replaces your soundbar with a fresh copy of the device, for example after an audio driver update. The copy doesn't have Equalizer APO, so the button stops making a difference. Setup installs a small background task (`KeepAttached.ps1`) that notices this at startup and whenever Windows adds an audio device, then re-attaches Equalizer APO. It only touches the soundbar Surround Fill uses, and only if Equalizer APO was attached to it before.

If you skipped it, run Equalizer APO's Device Selector, tick your soundbar again and restart. You can also run `Setup.ps1` again.

## Remove

In an admin PowerShell in the repo folder, run `powershell -ExecutionPolicy Bypass -File .\KeepAttached.ps1 -Uninstall`. Then delete the Surround Fill shortcuts and remove the two lines you added to `config.txt`.
