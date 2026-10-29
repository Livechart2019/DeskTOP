<p align="center">
  <img src="icon.png" width="160" alt="DeskTOP icon">
</p>

<h1 align="center">DeskTOP</h1>

<p align="center">
  Your desktop folders (and the Dock) follow you to whichever display you click on.
</p>

---

## What is it?

If you use several displays with a Mac, you know the problem: the folders on your desktop always seem to be on the display you're *not* looking at.

**DeskTOP** is a tiny menu bar app. Click an empty spot on the desktop of any display and

- all desktop icons move to the top-right corner of that display,
- the Dock moves to that display *(experimental, see below)*.

Clicks on windows, the Dock or the menu bar are ignored.

## Requirements

- macOS 11 (Big Sur) or later
- Xcode Command Line Tools (`xcode-select --install`)
- For the Dock: **System Settings → Desktop & Dock → "Displays have separate Spaces"** must be turned on

## Installation

```bash
git clone https://github.com/<your-name>/DeskTOP.git
cd DeskTOP
./build.sh
open DeskTOP.app
```

`build.sh` compiles the Swift source, builds the app icon from `DeskTOP.iconset` and signs the app locally (ad-hoc).
Afterwards you can move `DeskTOP.app` into your Applications folder.

The app has no Dock icon, only a small 🖥 in the menu bar, which you can also use to quit it.

## Permissions

On first launch macOS asks for several permissions. All of them are needed:

| Permission | Used for | Where |
|---|---|---|
| **Accessibility** | Moving the Dock to another display | Privacy & Security → Accessibility |
| **Automation → Finder** | Moving the desktop icons | Privacy & Security → Automation |
| **Automation → System Events** | Reading/changing the Dock auto-hide setting | Privacy & Security → Automation |

> **Important:** Because the app is only ad-hoc signed, macOS treats it as a "new" app after every `./build.sh`.
> Reset the old permissions and grant them again:
> ```bash
> tccutil reset Accessibility local.DeskTOP
> tccutil reset AppleEvents local.DeskTOP
> ```

## How it works

- **Detecting the click:** A global mouse monitor (`NSEvent.addGlobalMonitorForEvents`) uses `CGWindowListCopyWindowInfo` to check whether a window is under the cursor. If not, the click was on the desktop.
- **Moving the folders:** An AppleScript sent to Finder shifts all desktop icons by the same offset onto the clicked display, so their arrangement is preserved.
- **Moving the Dock:** macOS has no API for this. The Dock only switches displays when the cursor "pushes" against the bottom edge of a display. After you release the mouse button, DeskTOP briefly simulates that push (max. ~1 s) and then puts the cursor back.
- **Dock auto-hide:** If "Automatically hide and show the Dock" is on, DeskTOP turns it off so the Dock stays visible, and turns it back on when you quit.

## Known limitations

- Moving the Dock is **experimental**. Whether macOS reacts to the simulated mouse movement may vary between systems, and you will see the cursor jump briefly.
- The Dock is supported at the bottom, left or right edge (depending on your Dock position).
- Without the Accessibility permission the Dock won't move. Moving the folders still works.
- Log messages and the menu item are currently in German.

## Troubleshooting

DeskTOP writes a log file **`DeskTOP.log` next to the app**. Among other things it records:

- whether Accessibility is granted,
- whether "Displays have separate Spaces" is on,
- which display the Dock is on and whether moving it worked,
- AppleScript errors. `-1743` means an Automation permission is missing.

You can also follow it live in Terminal:

```bash
log stream --predicate 'process == "DeskTOP"'
```

## Uninstall

1. Quit DeskTOP from its menu bar icon
2. Delete `DeskTOP.app`
3. Remove the permissions:
   ```bash
   tccutil reset Accessibility local.DeskTOP
   tccutil reset AppleEvents local.DeskTOP
   ```

## Project structure

```
DeskTOP.swift      App source code
Info.plist         App metadata and permission descriptions
build.sh           Builds, bundles and signs the app
DeskTOP.iconset/   Icon in all sizes
icon.png           Icon source image
```

## License

See [LICENSE](LICENSE).
