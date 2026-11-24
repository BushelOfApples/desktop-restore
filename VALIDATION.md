# Validation

Development host: Linux. Test runtime: official PowerShell 7.7.0 for Linux.

- 30 checks pass in `tests/Core.Tests.ps1`: window matching, title ambiguity,
  overlapping patterns, shared application hosts, Unicode JSON, backup storage,
  desktop mapping, invalid data, script parsing and native bridge compilation.
- The Windows interface C# branches compile for builds 22621, 22631, 26100 and 26200.
  Reflection confirms the added `Id` and `MoveExactWindow` members.
- The build 22000 branch fails to compile in the upstream dependency. The
  application therefore requires build 22621 or later. No unverified older COM
  layout has been patched into the dependency.
- A separate read-only review found encoding, wildcard validation, shared-host
  matching and startup retry issues. These were fixed before packaging.

Not tested: Windows PowerShell 5.1 execution, live COM interface compatibility,
desktop movement, pinned-window detection, shortcut installation, or reboot
restoration on Windows. Successful C# compilation does not establish runtime
compatibility. Follow the manual Windows test in README.md.
