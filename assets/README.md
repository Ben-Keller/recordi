# Recordi icons

MenuRecorder.png is the user-supplied audio-recorder.png, copied without modification. The app loads it as a 15.3-point monochrome template so macOS handles light/dark appearance. Recording adds red tint and the elapsed timer.

The colorful app icon uses original AppKit artwork in app/Recordi/IconArt.swift. Regenerate that icon with scripts/icons.sh. The build bundles both Recordi.icns and MenuRecorder.png; runtime does not depend on Downloads.
