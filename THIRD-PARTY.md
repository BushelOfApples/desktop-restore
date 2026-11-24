# Third-party code

`vendor/VirtualDesktop.psm1` comes from Markus Scholtes' PSVirtualDesktop,
module version 1.5.11, MIT licensed. The upstream file header uses script
version 2.22. The full license is in `vendor/LICENSE.txt`.

- Repository: https://github.com/MScholtes/PSVirtualDesktop
- Commit: `175367d111f86b465fcf54e46a3cbcb96163521f` (2025-08-25)
- Source: https://github.com/MScholtes/PSVirtualDesktop/blob/175367d111f86b465fcf54e46a3cbcb96163521f/Module/VirtualDesktop.ps1
- Original SHA-256: `108ba45ccbe1b077a79c36953535dbdd2920e1aa03a51f935bbd06b6fb61747c`

Local changes: normalized line endings, saved as UTF-8 with BOM for Windows
PowerShell, and added two members to `VirtualDesktop.Desktop`:

1. `Id` exposes the desktop GUID through the existing COM object.
2. `MoveExactWindow` moves only the supplied window handle. Unlike the upstream
   `MoveWindow`, it does not retry with the process main window after a failure.

The application calls `MoveExactWindow`. Upstream functions remain in the
vendored source but are not used to move windows.

The dependency uses undocumented Windows shell interfaces. Upstream advertises
Windows 11 support through 24H2. Later builds and changes from Windows updates
require a compatibility check on the target computer. No dependency is
downloaded or installed when this tool runs.
