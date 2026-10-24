# Glint

A small, translucent to-do list that floats beside your work. Native SwiftUI + AppKit, macOS 15 or later. One list, automatic local saving, no account, no server, no dependencies.

## Open the app

Double-click **Glint.app** in this project folder. It starts near the upper-right corner of your main screen. Its checkmark icon appears in the menu bar; it has no Dock icon.

- Type in **Add a task…** and press Return to add a task.
- Click a circle to complete or reopen a task. Expand **Completed** to see finished tasks.
- Double-click task text, or use its options menu, to edit. Return saves; Escape cancels. Leaving the field also saves. Blank edits leave the original text intact.
- Drag task rows to reorder them, or choose **Move Up / Move Down** from a row’s menu. Dropping a row places it before the target row.
- Drag the header to move the card. Resize its edges or use the bottom-right grip.
- Click the capsule button in the header to shrink into a pill. Its full rounded background is clickable. The task-count pill expands when clicked; drag its center to move it. When a focus selection exists, collapsing shows the focus pill instead.
- Drag any pill edge or corner to resize it horizontally or vertically. Resize cursors mark the border. Glint remembers the pill’s size separately from the expanded card, including across relaunches.
- **Control–Option–T** shows or hides Glint. Showing it expands the card and focuses task entry.
- The header menu has **Keep on top**, Undo/Redo, Settings, Hide, and Quit.
- Command-Z / Shift-Command-Z undo and redo. While editing text, the text field’s own undo history takes precedence; otherwise these act on task changes.
- The menu bar icon provides Show/Hide, Keep on Top, Settings, and Quit. Command-W hides the panel; Command-Q quits.

Settings contains a shortcut recorder, a **Snap to screen edges** toggle, optional launch at login (off initially), and a panel-position reset. Shortcut conflicts are shown there. Launch at login uses Apple’s service-management API; macOS may request approval in System Settings → General → Login Items. Keep the app at a stable location when enabling it.

## Edge snapping

- Release Glint near a screen edge to snap it into place, leaving a 16-point gap from the usable screen boundary. The trigger distance is 18 points from that position. Corners attach both edges; snapping to one edge leaves the other coordinate unchanged.
- Snapping applies to the list, task-count pill, and focus pill and does not change their size. It happens only after a genuine window drag. Crossing between monitors remains unrestricted while dragging.
- Hold **Option when releasing** to bypass snapping and clear the previous attachment. Drag away normally to detach, without resistance.
- The selected display is the one containing most of the panel; pointer location resolves an equal-overlap tie. Placement accounts for the menu bar and Dock.
- Attached edges remain aligned when expanding/collapsing or switching focus views. Attachments and display identity survive app relaunch.
- Changing screen space, including moving the Dock, updates the attached position. If the attached display disappears, Glint moves within an available display and clears the old attachment.
- Grabbing a resize edge or corner clears attachment and follows normal resizing. Resizing never creates a snap. **Reset panel position** also clears attachment.
- Disable **Snap to screen edges** in Settings to leave Glint where it is and clear attachment. Enabling it again does not move Glint until another drag release.
- A brief 0.12-second motion settles the panel. Reduce Motion makes placement immediate. Clicks and task actions never create new attachments.

## Focus mode

Choose **Focus on This Task** from an incomplete task’s options menu or right-click menu. Glint becomes a glass pill showing just that task.

- Click the left checkbox to complete it. Glint returns to the task-count pill and does not pick another task. Command-Z restores the task without resuming focus automatically.
- Click the right list button to return to all tasks. A small scope icon marks the selected task. Choose **Resume Focus** or **Stop Focusing** from its menu or the header menu.
- Drag the text area to move the pill. Clicking the text does not expand it or complete the task. The checkbox, text region, list button, and resize border have separate hit areas.
- Resize from any edge or corner. The focus pill starts at 320 × 64 points, with a 240 × 48 minimum and 520 × 180 maximum. Text wraps as space permits and truncates overflow; hover to read the full task.
- Focus-pill size is remembered independently of the count pill and full list. Your selection and current presentation survive relaunch if the selected task is still incomplete.
- Editing a selected task through the list updates its focused text. Completing or deleting it from the list clears the selection. Changing the selection never reorders or modifies tasks.
- The global show/hide shortcut continues to open the full list and focus task entry, retaining the selected task for later. The focus pill’s right-click menu also offers **Stop Focusing** and **Return to All Tasks**.

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

The command-line app compiles and its code signature verifies. The test runner passes 92 checks covering tasks, undo/redo, persistence, resizing, focus mode, snapping thresholds and corners, negative display coordinates, display selection, Option bypass, attachment restoration, independent presentation sizes, and drag-versus-click detection.

Live UI inspection was blocked by the agent environment’s lack of Computer Use permission and GUI launch access. The Xcode build path and native macOS 26 glass path could not be compiled here because only the macOS 15 Command Line Tools are installed. Before a release, run the checklist in **VALIDATION.md** on actual macOS 15 and 26 systems.

Later possibilities: multiple lists, optional Apple Reminders integration, and due dates. These are intentionally outside this version.
