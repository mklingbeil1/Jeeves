# Jeeves (native Swift)

A free, keyboard-driven launcher for macOS, written in Swift with AppKit and SwiftUI. Press **Option+Space**.

Not affiliated with Alfred or Running with Crayons Ltd.

## Build

Needs macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```
./build.sh
```

This makes `build/Jeeves.app` and `build/Jeeves.dmg`. Drag the app into Applications. An app you build yourself runs without any Gatekeeper warning.

## What it does

Launches apps, runs web searches with keywords (`g`, `yt`, `gh`, `w`…), calculates (`24 * (7 + 3)`), keeps clipboard history (`clip`), snippets (`snip`), bookmarks (`bm`), timers (`timer 10m`), small tools (`uuid`, `pass`, `now`, `b64`, `enc`, `upper`, `lower`, `#ff8800`) and `sleep` / `lock`.

Keys: ↑ ↓ move, Enter run, Tab complete, Alt+1–9 pick, Esc clear or hide.

## License

MIT
