# Surround Fill

A tray button for Windows users with a surround or Dolby Atmos soundbar setup.

Stereo audio like YouTube often plays only from the soundbar, and the surround speakers stay silent. Click the tray icon and that audio plays through your surrounds too. Click again to go back to normal. The volume stays the same either way.

## Setup

**Easy way:** download this repo, right-click `Setup.ps1` and choose **Run with PowerShell**. It walks you through everything below.

**Manual way:**

1. Install [Equalizer APO](https://sourceforge.net/projects/equalizerapo/). In its Device Selector, tick your soundbar under Playback devices, then restart your PC.
2. In Windows Sound settings, set your soundbar's speaker setup to **5.1** or **7.1**.
3. Add these two lines to the end of `C:\Program Files\EqualizerAPO\config\config.txt`, using your soundbar's name as it appears in Sound settings:
   ```
   Device: Your Soundbar Name
   Include: surround-fill.txt
   ```
4. Download this repo and double-click `SurroundFill.vbs`.

## Use

- **Left-click** the tray icon to turn it on or off. Green means on.
- **Right-click** to turn it off and close it.

Turn it off for movies and games that already have real surround sound.
