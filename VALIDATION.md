# Glint acceptance checklist

Automated checks: run `./test.sh`. Compile/package with `./build.sh`; validate the bundle with `codesign --verify --deep --strict Glint.app`. Xcode project metadata can be linted with `plutil -lint Glint.xcodeproj/project.pbxproj`.

Manual checks still required:

- Launch the app on macOS 15; verify the empty state, rounded translucent surface, readable text, menu bar icon, and absence of a Dock icon.
- Add several tasks, a long wrapping task, and whitespace-only input. Verify Return keeps task entry focused.
- Edit by double-click and options menu. Verify Return saves, Escape cancels, focus loss saves, and blank edits preserve the original.
- Complete/reopen tasks; expand Completed; delete from both sections. Verify Undo/Redo for completion, edits, deletion, and reorder.
- Drag a task upward and downward; verify Move Up / Move Down reaches every position without losing tasks.
- Click the capsule collapse button at its center and near each edge of its rounded background; verify the entire button responds.
- Drag the header; resize using edges and grip; scroll a long list. Collapse, drag the pill by its center, and resize it from every edge and corner. Verify horizontal, vertical, and diagonal cursors and that resizing does not expand the pill.
- Verify minimum/maximum pill sizes, collapse/expand size preservation, and relaunch while collapsed after resizing. The expanded card and pill should each retain their own dimensions.
- Use other apps while pinned; verify Glint remains visible without stealing typing focus. Disable Keep on Top and verify normal layering.
- Switch Spaces and displays, disconnect an external display, and change resolution. Verify the header always remains reachable. Enter another app’s full-screen mode and verify Glint does not overlay it.
- Hide/show through menu bar and global shortcut. Verify shortcut-show expands and focuses entry. Record a new shortcut; create a conflict with another registered shortcut and check the error in Settings.
- Close Settings with Command-W; verify Glint remains. Hide the panel with Command-W; restore it from the menu bar. Quit and relaunch; verify tasks, completion state, ordering, position, size, pin state, and collapsed state.
- Enable launch at login from a stable app location, approve it in System Settings if required, and check after login. Disable it afterward if not wanted.
- Check light/dark appearance over light, dark, and busy backgrounds. Enable Reduce Transparency, Reduce Motion, Full Keyboard Access, and VoiceOver. Verify task actions and options menus remain accessible.
- On macOS 26+, build with Xcode 26+ and repeat the appearance and interaction checks with native Liquid Glass enabled.

Distribution is separate: select a signing team, sign and notarize, validate both supported architectures as needed, and test the distributed artifact on a clean Mac.
