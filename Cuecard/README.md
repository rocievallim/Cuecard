# Cuecard

Cuecard is a macOS menu bar teleprompter. The single floating panel stays visible when you work in another app. Reading and presentation controls can be used without taking keyboard focus from that app. Edit and Rename let the panel receive keyboard input.

## Install and run

1. On macOS 13 Ventura or later, extract the ZIP in Finder.
2. Open **install-cuecard.command**. This installs **Cuecard.app** in your home folder under **Applications** and launches it. The installer includes the compiled app for Apple Silicon and Intel.
3. Click the lined icon in the menu bar to open or hide Cuecard. Drag the header to move the panel and drag an edge or corner to resize it.

If Finder says the installer lacks execute privileges, open Terminal, type `/bin/bash ` with a trailing space, drag **install-cuecard.command** into Terminal, and press Return. The app can also be opened directly from **Cuecard.app** in this folder.

Cuecard requires no Accessibility, Input Monitoring, Screen Recording, or Automation permissions. The bundled app is signed ad hoc. Full-screen availability depends on the presentation app and display mode. If an app's full-screen slideshow covers Cuecard, try its windowed presentation mode or place Cuecard on your presenter display.

## Use during a presentation

- Click the script title to switch scripts. Use **⋯ → New Script** to add one, **Edit** to change the name or body, and **⋯ → Delete Script** to remove one. Click **Done** to go back to reading.
- Type headings such as `# Introduction` or `## Closing`. Use **Jump to section** to move to a heading. Markdown mode renders headings, emphasis, lists, and code. Turn off **Markdown** in the editor to show the original text. Headings still work as jump markers.
- Use **A−** and **A+** to set the reading size. **Auto-scroll** starts scrolling, and the slider controls speed. The progress line shows your position. Manual scrolling, switching sections, editing, or hiding the panel pauses it. Press **Auto-scroll** again after the last line to start over. When the entire script is visible, the panel shows **Script fits on screen**.
- Start, pause, resume, or reset the presenter timer. A running timer keeps counting while the panel is hidden.
- Scripts and reading preferences are saved automatically at `~/Library/Application Support/Cuecard/scripts.json`. Quit from **⋯ → Quit Cuecard**.

## Build from source

1. If `xcrun --find swiftc` reports that a compiler is missing, run `xcode-select --install` and complete the macOS installation prompt.
2. In Terminal, type `cd ` and drag this project folder in, then press Return.
3. Run `/bin/bash build.sh`. It builds and verifies an ad-hoc-signed universal bundle at `build/Cuecard.app`.
4. Run `open build/Cuecard.app` to launch your build. Quit any existing Cuecard instance before testing another copy.
5. Run `/bin/bash package.sh` to regenerate the standalone `build/install-cuecard.command`.

## Source layout

```text
Cuecard/
├── Info.plist                 Agent app and bundle metadata
├── Sources/
│   ├── App.swift               App entry point
│   ├── Cuecard.swift           Panel, script editing, timer, and auto-scroll
│   ├── PanelViews.swift        Reader geometry and visual controls
│   └── Scripts.swift           Local storage, Markdown, and section indexing
├── Tools/
│   ├── DrawIcon.swift          App icon generator
│   └── installer.template     Installer before the app is embedded
├── build.sh
├── package.sh
├── install-cuecard.command     Standalone installer with the bundled app
└── Cuecard.app                 Prebuilt universal app
```
