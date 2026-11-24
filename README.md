# Desktop Restore for Windows 11

Save the virtual desktop for each app window. After sign-in, move reopened
windows back to their saved desktops. This tool supports separate browser and
VS Code windows by matching their titles.

Requires Windows 11 22H2 (build 22621) or later, with current updates, and the
built-in Windows PowerShell 5.1. Older Windows 11 builds are rejected because
the bundled dependency has an incomplete interface definition for those builds.

**Windows integration has not been tested on this development host.** The host
runs Linux. Matching, file storage, script syntax and C# compilation are tested.
Use Preview and the manual check below before relying on automatic restoration.

## Setup

1. Extract the ZIP into a folder on your Windows laptop. Keep all files together.
2. Arrange your windows on the correct virtual desktops. Give desktops distinct
   names in Task View (`Win+Tab`), such as **Work**, **Personal**, and **Project Alpha**.
3. Double-click **Install.cmd**. Use your normal Windows account. No admin
   account or extra software is needed. The first installation saves the layout
   and adds a startup shortcut for your account.
4. Double-click **Preview.cmd**. Check the target desktop for each listed window.
5. Move one window to another desktop, then double-click **Restore now.cmd**.
   Check that the window returns to the saved desktop.

At the next sign-in, the tool waits 15 seconds and checks for reopened windows
for about three minutes. It exits after this period. It does not switch the
desktop you are viewing. Once it has restored a window, it leaves that window
alone for the rest of that run.

The installed copy is in `%LOCALAPPDATA%\DesktopRestore\app`. You can use the
CMD files there and delete the extracted download after installation.

If you change your arrangement, run **Save layout.cmd** again. This replaces
the saved layout and keeps its previous version as `layout.json.bak`.
Reinstalling the tool preserves an existing layout.

## Separate windows of the same app

The saved layout is in `%LOCALAPPDATA%\DesktopRestore\layout.json`.
Double-click **Edit rules.cmd** to open it in Notepad.

Each saved window has a `Title` and a `TitlePattern`. With an empty pattern,
matching uses the exact title. If an app has windows saved on only one desktop,
it can return there even when its title changes. This fallback is disabled for
shared Windows application hosts.

For VS Code, use the project or workspace name as a stable part of the title.
For example, change just the `TitlePattern` value on the relevant saved entry:

```json
"Title": "main.c - Project Alpha - Visual Studio Code",
"TitlePattern": "* - Project Alpha - Visual Studio Code"
```

Use a different pattern for each project. `*` matches any text; `?` matches one
character. These are PowerShell wildcard patterns, not regular expressions.
The executable path and window class must also match. After editing, run
**Preview.cmd** to check the rules. A new Save replaces manual title patterns,
so add them again after saving a changed arrangement.

Browser titles usually depend on the active tab. If the browser restores the
same title, exact matching works. If it restores a different active tab or
several windows titled `New Tab`, the tool cannot reliably identify them. Leave
a distinct tab active before saving, or supply a title pattern that uniquely
identifies each window. A browser window name is useful only if the browser
actually includes it in the native window title shown by Preview.

**Identical or overlapping title rules on different desktops are left in place.**
The report marks these windows as `Unmatched`. The tool cannot recover hidden
browser profile identity or tab history from a window title.

## Commands and flags

Run commands in **Windows PowerShell 5.1** (`powershell.exe`) from the extracted
or installed folder. Choose a command with `-Action`:

| Action | What it does | Double-click launcher |
| --- | --- | --- |
| `Install` | Copy the tool to the local app folder and enable startup restoration. Save the initial layout if none exists; keep an existing layout. | `Install.cmd` |
| `Save` | Replace the saved layout with the current window assignments. Keep the previous save as a backup. Manual title patterns must be added again. | `Save layout.cmd` |
| `Restore` | Move matching windows to their saved desktops. By default, scan once immediately and exit. | `Restore now.cmd` |
| `Preview` | Show proposed assignments and write a preview report without moving windows. | `Preview.cmd` |
| `Status` | Show the Windows build, startup status, layout path, saved window count and log path. This is the default action. | Run from PowerShell |
| `Edit` | Open the selected layout in Notepad to edit title rules. | `Edit rules.cmd` |
| `Uninstall` | Remove the startup shortcut. Keep the scripts, layout and reports. An active restore continues until it finishes. | `Uninstall.cmd` |

### Flags

| Flag | Default | Accepted values and effect |
| --- | --- | --- |
| `-Action` | `Status` | One of the seven actions listed above. |
| `-LayoutPath` | `%LOCALAPPDATA%\DesktopRestore\layout.json` | Path to a layout file. Used by `Save`, `Restore`, `Preview`, `Status` and `Edit`. Use an absolute path. `Install` requires the default path. `Uninstall` does not use this flag. |
| `-WaitSeconds` | `0` | Integer from `0` to `3600`. Used only by `Restore`. Zero means one immediate scan. A positive value starts restoring immediately, then checks about every three seconds for windows that open later. The final scan can finish after the stated period. |
| `-DelaySeconds` | `0` | Integer from `0` to `300`. Wait this long before starting `Save`, `Restore` or `Preview`. Other actions do not use this flag. |
| `-Verbose` | Off | Standard PowerShell switch. Show additional details, including windows that could not be inspected. |

`Restore` does not wait by default. Normal script loading and window enumeration
still take time. Startup restoration uses a separate wrapper: it waits 15
seconds, then runs `Restore -WaitSeconds 180`. Manual flags do not change these
startup settings.

### Examples

```powershell
# Install and enable restoration after sign-in.
.\DesktopRestore.ps1 -Action Install

# Save the current arrangement.
.\DesktopRestore.ps1 -Action Save

# Check assignments without moving any windows.
.\DesktopRestore.ps1 -Action Preview

# Restore open windows immediately, then exit.
.\DesktopRestore.ps1 -Action Restore

# Restore immediately and keep checking for ten minutes.
.\DesktopRestore.ps1 -Action Restore -WaitSeconds 600

# Wait ten seconds, then restore and check for three minutes.
.\DesktopRestore.ps1 -Action Restore -DelaySeconds 10 -WaitSeconds 180

# Show diagnostic details during a single restore.
.\DesktopRestore.ps1 -Action Restore -Verbose

# Show status. Omitting -Action has the same effect.
.\DesktopRestore.ps1 -Action Status
.\DesktopRestore.ps1

# Edit title rules in the default saved layout.
.\DesktopRestore.ps1 -Action Edit

# Remove the startup shortcut.
.\DesktopRestore.ps1 -Action Uninstall
```

Use a separate layout for a different arrangement:

```powershell
$layout = Join-Path $env:LOCALAPPDATA 'DesktopRestore\work-layout.json'
.\DesktopRestore.ps1 -Action Save -LayoutPath $layout
.\DesktopRestore.ps1 -Action Preview -LayoutPath $layout
.\DesktopRestore.ps1 -Action Restore -LayoutPath $layout
```

Automatic startup always uses the default layout. Only one Save, Preview or
Restore can run at a time per user and session. A timed restore holds that slot
until it finishes.

If script execution is blocked, use a supplied CMD launcher, or invoke the
script with a per-process override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\DesktopRestore.ps1 -Action Restore
```

This does not change the machine or user execution policy. Organisation policy
can still block scripts; use your organisation's approved method in that case.
PowerShell 7 (`pwsh.exe`) is for the development tests, not the Windows app.

## What this tool restores

It restores **virtual desktop assignments for windows that reopen**. It does
not start apps, restore browser tabs, reopen files, or restore window size,
monitor, position or maximized state. Enable each app's session recovery and
Windows' restartable-app setting as needed. Apps started after the three-minute
startup period can be restored with **Restore now.cmd**.

Pinned windows and apps shown on all desktops are skipped. Minimized windows
and windows on inactive virtual desktops are included. Some protected, elevated
or system windows cannot be read or moved from a normal account. The tool keeps
them in place. Keep normal apps at the same privilege level as the tool.

Desktops are matched by GUID, then by a unique exact name. A missing desktop is
not created and no desktop is selected solely by its old position. If you delete
or rename desktops and their IDs also change, arrange the windows and save again.

The Windows shell interfaces are version dependent. The bundled dependency
advertises support through Windows 11 24H2; newer builds need testing. A Windows
update may require a dependency update. See [THIRD-PARTY.md](THIRD-PARTY.md).

## Reports and removal

All state stays on the laptop in `%LOCALAPPDATA%\DesktopRestore`:

| File | Purpose |
| --- | --- |
| `layout.json` | Saved titles, executable paths and desktop assignments |
| `layout.json.bak` | Previous explicit save |
| `preview-report.json` | Proposed moves, without moving any window |
| `restore-report.json` | Latest restore results for observed apps in the saved layout |
| `restore.log` | Startup errors and move results |

Reports contain window titles. Nothing is sent over the network. Apps that did
not reopen do not appear as live windows in the report. Check `restore.log` if
nothing moves. `Failed` rows have error details in the JSON report. On an
unsupported Windows build, stop using startup restore until the dependency has
been checked for that build.

Double-click **Uninstall.cmd** to remove the startup shortcut. It does not stop
an already running restore; wait for its three-minute run to finish. The saved
layout and installed files remain. You can delete `%LOCALAPPDATA%\DesktopRestore`
when you no longer need them.

## Manual Windows test

1. Put two VS Code projects and two browser windows on distinct desktops.
2. Save, then use Preview to check their targets.
3. Move the windows elsewhere. Restore and check every window, including one
   minimized window and one window on an inactive desktop.
4. Give two browser windows the same title on different desktops, save, move
   them, then restore. They must be reported as unmatched.
5. Set distinct title patterns, run Preview, and repeat the move test.
6. Reboot. Let Windows and the apps reopen their windows. Check placement and
   the report after about four minutes.

Core development tests, which can also run on Linux with PowerShell:

```powershell
pwsh -NoProfile -File tests/Core.Tests.ps1
pwsh -NoProfile -File tests/Interop.Compile.ps1 -Build 26100
```

## Publishing the source

Publish the source files from this project folder. Do not include saved layouts,
reports, logs, screenshots, or local task notes. Runtime files can contain window
titles, document names, desktop names and account-specific application paths.

The included `.gitignore` excludes JSON runtime data (except the public dependency
provenance), backups, logs, archives and local settings. Ignore rules do not remove
files that Git already tracks, and they do not apply to browser uploads. Review
any files you add before publishing. Keep the dependency licence and attribution.

Git commits include an author name and email address. Use the identity you intend
to make public when you create commits.

## Sources

- [Microsoft virtual desktop API](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager)
- [PSVirtualDesktop upstream source and supported versions](https://github.com/MScholtes/PSVirtualDesktop)
