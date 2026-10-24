# Glint

A small, translucent to-do list that floats beside your work. Native SwiftUI + AppKit, macOS 15 or later. One list, automatic local saving, no account, no server, no dependencies.

## Open the app

Double-click **Glint.app** in this project folder. It starts near the upper-right corner of your main screen. Its checkmark icon appears in the menu bar; it has no Dock icon.

- Type in **Add a task…** and press Return to add a task.
- Click a circle to complete or reopen a task. Expand **Completed** to see finished tasks.
- Double-click task text, or use its options menu, to edit. Return saves; Escape cancels. Leaving the field also saves. Blank edits leave the original text intact.
- Drag task rows to reorder them, or choose **Move Up / Move Down** from a row’s menu. Dropping a row places it before the target row.
- Drag the header to move the card. Resize its edges or use the bottom-right grip.
- Click the capsule button in the header to shrink into a pill. Its full rounded background is clickable. Click the pill to expand; drag its center to move it.
- Drag any pill edge or corner to resize it horizontally or vertically. Resize cursors mark the border. Glint remembers the pill’s size separately from the expanded card, including across relaunches.
- **Control–Option–T** shows or hides Glint. Showing it expands the card and focuses task entry.
- The header menu has **Keep on top**, Undo/Redo, Settings, Hide, and Quit.
- Command-Z / Shift-Command-Z undo and redo. While editing text, the text field’s own undo history takes precedence; otherwise these act on task changes.
- The menu bar icon provides Show/Hide, Keep on Top, Settings, and Quit. Command-W hides the panel; Command-Q quits.

Settings contains a shortcut recorder, optional launch at login (off initially), and a panel-position reset. Shortcut conflicts are shown there. Launch at login uses Apple’s service-management API; macOS may request approval in System Settings → General → Login Items. Keep the app at a stable location when enabling it.

## Build and test

With Apple Command Line Tools installed:

```sh
./build.sh
./test.sh
```

The build produces **Glint.app** in this folder for the current Mac’s architecture. The included local build is for Apple silicon and is ad-hoc signed. It has not been notarized or signed for public distribution.

With full Xcode installed, open **Glint.xcodeproj**, select the **Glint** scheme and **My Mac**, then Run. Xcode uses the standard SwiftData `@Model` declaration. The command-line build uses its checked-in explicit model expansion because Apple’s Command Line Tools omit the SwiftData macro plugin. Both paths use the same SwiftData schema and store, with CloudKit disabled.

The macOS 15 SDK builds the frosted `NSVisualEffectView` appearance. Building with Xcode 26 / Swift 6.2 or newer enables the native Liquid Glass branch on macOS 26+. Older systems retain the frosted fallback. Reduce Transparency switches to an opaque system background; Reduce Motion removes the custom completion animation.

## Data and window behavior

Tasks live in `~/Library/Application Support/Glint/Tasks.store` and its SQLite companion files. Window geometry and settings live in the app’s UserDefaults domain, `com.glint.todo`. Undo history lasts for the current run. Completed tasks remain until explicitly deleted; there is no automatic cleanup.

The panel floats over ordinary windows by default and joins desktop Spaces on its current display. It does not opt into full-screen overlays. Turning **Keep on top** off uses normal window layering. Position, expanded size, and collapsed state survive relaunch. A disconnected display or changed screen bounds causes the panel to move back within an available display.

## Validation status

The command-line app compiles and its code signature verifies. The test runner passes 28 checks covering task normalization, completion/reopening, editing, deletion, reorder in both directions, undo/redo, stable identity and creation dates, invalid-operation handling, disk persistence after reopening, and edge/corner resize calculations and pill-size limits.

Live UI inspection was blocked by the agent environment’s lack of Computer Use permission and GUI launch access. The Xcode build path and native macOS 26 glass path could not be compiled here because only the macOS 15 Command Line Tools are installed. Before a release, run the checklist in **VALIDATION.md** on actual macOS 15 and 26 systems.

Later possibilities: a one-task focus view, multiple lists, optional Apple Reminders integration, and due dates. These are intentionally outside this version.
