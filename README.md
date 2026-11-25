# GenshinUltraSlimmer

GenshinUltraSlimmer is a Windows launcher for dnullptr's original GenshinSlimmer
and a multilingual audio-language stubber maintained by **Rueben Gill**.
The original tools remain credited to dnullptr; the launcher updates the GUI
from dnullptr's upstream repository and the audio tool from this fork.

## Project files

| File | Purpose and attribution |
| --- | --- |
| `GenshinUltraSlimmer.bat` | GenshinUltraSlimmer launcher. Requests administrator access once, automatically checks both script sources at startup, and lets you retry updates from the menu. |
| `GenshinSlimmer.ps1` | dnullptr's original command-line interface, retained to match the fork's file structure. The BAT launcher opens the GUI instead. |
| `GenshinSlimmer_GUI.ps1` | dnullptr's original GenshinSlimmer GUI. The launcher refreshes this file from dnullptr's upstream `main` branch at startup. |
| `GenshinUltraSlimmer_Audio.ps1` | Rueben Gill's language-only audio stubber, adapted to the GenshinSlimmer GUI style. It supports installed language folders and locale-specific manifest updates, and updates from this fork. |
| `GenshinUltraSlimmer_FindGame.ps1` | Launcher helper that reuses a saved location, checks common HoYoPlay folders, then scans fixed drives with a time limit. |
| `path.ini` | Game-folder setting shared by the tools; created or updated when a game path is selected. |

`path.ini` is created at runtime and is intentionally excluded from version
control because it contains a machine-specific game path.

## Use

1. Keep the BAT and PowerShell scripts together in the same folder.
2. Run `GenshinUltraSlimmer.bat`. Windows will request administrator access so the
   tools can modify game files; if already elevated, no prompt is needed.
3. The launcher checks for updates to dnullptr's GUI and the audio stubber,
   each from its respective GitHub repository. If an update is unavailable,
   it keeps and uses the packaged copy when possible.
4. It reuses the saved game path or searches common locations and fixed drives.
   If it cannot find the game, choose **Browse** in either tool once; the
   selected location is saved for future launches.
5. Choose an option:
   - **Original GenshinSlimmer** launches dnullptr's upstream tool. The launcher
     checks for its latest script at startup.
   - **Audio language stubber** opens Rueben Gill's language-only tool. It
     checks this fork for an updated audio script at startup, then detects
     installed voice-over folders. Extra languages appear disabled until
     their folders are installed in-game; rescan after installing one.   
   - **Check for script updates again** retries both downloads after startup.
   - **Exit** closes the launcher.

After either GUI closes, the launcher returns to its menu. An internet
connection is needed to check for script updates and fetch the live revision.

## Original GenshinSlimmer features

The features below belong to **dnullptr's original tool**. GenshinUltraSlimmer
ships both its GUI and command-line scripts, although the launcher opens the
GUI. For full upstream documentation, see
[dnullptr/GenshinSlimmer](https://github.com/dnullptr/GenshinSlimmer).

- Select cutscene videos by region, event, or Traveler variant. Supported
  content includes Mondstadt, Liyue, Inazuma, Sumeru, Fontaine, Natlan,
  Nod-Krai, Snezhnaya, and BeyondUGC cache assets.
- Use bulk presets to stub supported content while keeping the newest
  Snezhnaya Archon Quest videos separate; finish that quest before selecting
  its dedicated category.
- Synchronize game manifests with selected zero-byte stubs, and restore
  removed files and manifest entries when you want the game to download them
  again.
- Inspect local resource revisions and fetch the current server revision.
  The tool can also recover from certain interrupted manifest updates.
- Optionally update HoYoPlay's `pkg_version` entries to reflect stubs. This
  feature is experimental and reversible; see dnullptr's documentation before
  using it.
- Remove legacy file-lock permissions and optionally apply Windows NTFS LZX
  compression to the game files.

### Upstream release highlights

The bundled dnullptr scripts identify as v14. The launcher checks the GUI
against dnullptr's `main` branch on startup, so the version may change as
upstream releases updates.

- **v14:** Added live revision fetching and recovery for silent manifest
  updates, expanded the regional cutscene categories, and improved handling
  of newer manifest formats.
- **v13:** Introduced the dark GUI, split Snezhnaya content into pre-7.2 and
  7.2 categories, added safer presets, and introduced experimental launcher
  `pkg_version` synchronization.
- **v12:** Expanded manifest discovery and updated empty-file metadata handling
  for newer game versions.
- **v11:** Added direct manifest synchronization and revision management,
  replacing the older file-lock approach for preventing in-game redownloads.

## Audio language stubber

The audio tool can stub selected installed voice-over files, synchronize
matching entries in the game's already-installed manifests, and restore
stubbed files using the current streaming manifests. Manifest matching
includes the exact locale path, so a filename shared by different language
packs does not cause another locale's entry to be changed.

The revision manager reads or updates the local resource revision and can
fetch the current revision. It does not download game assets or perform a
game update. The game launcher remains responsible for installing game
updates and their manifests.

## Important notes

- Close Genshin Impact before making changes. Stubbing changes local game files
  and manifests; keep backups and use the tool's restore feature when you want
  to download a voice pack again.
- The original GenshinSlimmer's video/resource features and behavior belong to
  its upstream project. Consult its own documentation for details.
- A game update, repair, or file verification can replace modified files or
  manifests. Recheck the game after updates.
- This project is an unofficial community tool and is not affiliated with
  HoYoverse.

## Credits and project history

- **dnullptr** created the original [GenshinSlimmer](https://github.com/dnullptr/GenshinSlimmer).
  GenshinUltraSlimmer incorporates and launches that work; the original script keeps
  its own attribution and is downloaded directly from dnullptr's repository.
- **Rueben Gill** created the multilingual language-stubbing work and the
  locale-specific audio manifest handling in `GenshinUltraSlimmer_Audio.ps1`.
  The audio GUI follows the style of dnullptr's original GUI.

### Heads-up

- The language-stubbing contribution was discussed in
  [dnullptr/GenshinSlimmer PR #22](https://github.com/dnullptr/GenshinSlimmer/pull/22).
  That PR proposed Japanese voice-over stubbing and exact locale-specific
  manifest handling. In the PR discussion, dnullptr explained that they chose
  not to merge Asian-language stubbing because of prior Terms of Service
  concerns involving regional voice data, while encouraging a separate fork
  and cautioning users about the risks. This project documents that history;
  it does not claim that the technique is approved or provide legal advice.
  Review the current game terms and make your own informed decision before
  using language-stubbing features.
