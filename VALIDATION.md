# Glint acceptance checklist

Automated checks: run `./test.sh`. Compile/package with `./build.sh`; validate the bundle with `codesign --verify --deep --strict Glint.app`. Xcode project metadata can be linted with `plutil -lint Glint.xcodeproj/project.pbxproj`.

Manual checks still required:

- Launch the app on macOS 15; verify the empty-state pixel spark, stepped translucent surface, pixel font, pixel menu bar icon, and absence of a Dock icon.
- Add several tasks, a long wrapping task, and whitespace-only input. Verify Return keeps task entry focused.
- Edit by double-click and options menu. Verify Return saves, Escape cancels, focus loss saves, and blank edits preserve the original.
- Complete/reopen tasks; expand Completed; delete from both sections. Verify Undo/Redo for completion, edits, deletion, and reorder.
- Drag a task upward and downward; verify Move Up / Move Down reaches every position without losing tasks.
- Click the pixel capsule collapse button at its center and near each edge of its background; verify the entire button responds.
- Verify the header X and both header/task-row ellipsis icons are visible. Check Quit in header options, task-row right-click, full-panel header/background, task-count bar, focus text area, and the resize border; also check Control-click. Quit through the native compact menu and through X, relaunch, and verify tasks are preserved. Check Command-Q while Glint has keyboard focus.
- Drag the header; resize using edges and grip; scroll a long list. Collapse, drag the pill by its center, and resize it from every edge and corner. Verify horizontal, vertical, and diagonal cursors and that resizing does not expand the pill.
- Verify minimum/maximum pill sizes, collapse/expand size preservation, and relaunch while collapsed after resizing. The expanded card and pill should each retain their own dimensions.
- Choose **Focus on This Task** from both task menus. Verify only that task appears, with a checkbox and list button, and that selecting another task replaces it without changing list order.
- In focus mode, click every part of both 32-point buttons; drag the text area; resize every edge/corner. Verify completing, moving, returning to the list, and resizing never trigger each other. Check text wrapping at larger heights and truncation/full-text tooltip at smaller sizes.
- Complete a focused task and verify the count pill appears without selecting another task. Undo and verify the task returns while focus stays cleared.
- Return to the list and check the focus marker, Resume Focus, Stop Focusing, and collapse-to-resume behavior. Edit the task, resume, and verify updated text. Complete/delete the selected task in the list and verify its marker and selection clear.
- Resize the focus pill, count pill, and list differently; move between all three and relaunch in each. Verify their independent saved sizes. Relaunch with a valid selected task in focus mode and in list mode; verify both selection and presentation restore.
- Use the show/hide shortcut from focus mode; verify show opens the list with task entry focused, while preserving the selection for later resumption. Check VoiceOver labels and keyboard access for the focus checkbox, list button, and task menu actions.
- Use other apps while pinned; verify Glint remains visible without stealing typing focus. Disable Keep on Top and verify normal layering.
- Drag and release near every screen edge and corner in all three presentations. Verify the 16-point inset from usable bounds, the 18-point trigger distance, preserved size, and single-edge alignment without unwanted movement on the other axis.
- Verify there is no snapping while dragging between monitors, including shared boundaries and monitors above or left of the main screen. Release near edges on each display and check display choice.
- Hold Option on release and verify placement stays free. Disable **Snap to screen edges**, drag near edges, and confirm no snap. Reenable and confirm the panel stays still until another drag.
- While snapped, expand/collapse, enter/leave focus, complete the focused task, and relaunch. Verify attached edges remain aligned and each presentation keeps its own dimensions.
- Drag away, or grab any resize edge/corner, and verify attachment clears without resistance. Drag away and back to the initial position before releasing; verify the count pill does not mistakenly expand.
- Move the Dock between screen edges or change menu-bar/screen configuration while attached; verify placement updates within about a second. Disconnect the attached screen and verify Glint remains reachable and its attachment clears.
- Test a simple click, task completion, and list-button click near screen edges; none should create a new snap. Enable Reduce Motion and verify snap placement is immediate. Start another drag or resize during the short settling animation and verify normal interaction.
- Switch Spaces and displays, disconnect an external display, and change resolution. Verify the header always remains reachable. Enter another app’s full-screen mode and verify Glint does not overlay it.
- Hide/show through menu bar and global shortcut. Verify shortcut-show expands and focuses entry. Record a new shortcut; create a conflict with another registered shortcut and check the error in Settings.
- Close Settings with Command-W; verify Glint remains. Hide the panel with Command-W; restore it from the menu bar. Quit and relaunch; verify tasks, completion state, ordering, position, size, pin state, and collapsed state.
- Enable launch at login from a stable app location, approve it in System Settings if required, and check after login. Disable it afterward if not wanted.
- Check light/dark appearance over light, dark, and busy backgrounds. Enable Reduce Transparency, Reduce Motion, Full Keyboard Access, and VoiceOver. Verify task actions and options menus remain accessible.
- Check both light and dark cozy palettes over busy wallpapers. Enable Reduce Transparency and verify an opaque surface; enable Reduce Motion and verify completion/snap feedback has no movement or changing sparkle frames.
- Launch offline and verify Pixelify Sans is loaded. Edit long tasks and confirm font metrics match the display state; check accented text, emoji, and non-Latin text for usable fallback glyphs.
- Toggle **Readable text** in Settings and verify the list, input, both compact views, and Settings update immediately. Relaunch and verify the choice persists.
- At minimum list, count-bar, and focus-bar sizes, verify text wraps/truncates without overlapping the controls. Repeat at 1× and Retina display scales and after moving between displays. Pixel icon cells and stepped borders should stay crisp.
- Verify square task checkboxes and pixel menu/collapse/list buttons retain their full click areas and are reachable by keyboard. Check VoiceOver labels for all icon-only actions and for the Completed disclosure. Native menus and alerts should remain legible.
- Complete a task from both list and focus mode; verify brief check/spark feedback, successful undo, and no celebratory feedback on a failed save or reopened task.
- On a newer macOS version, build with its Xcode SDK and repeat appearance and interaction checks. There is no Liquid Glass branch in this pixel-themed version.

Distribution is separate: select a signing team, sign and notarize, validate both supported architectures as needed, and test the distributed artifact on a clean Mac.
