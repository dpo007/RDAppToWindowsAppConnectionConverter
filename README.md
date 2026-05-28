# ConvertTo-WindowsAppConnection

Convert legacy Microsoft Store Remote Desktop app connection data into Windows App connection resources.

This script takes the old `.model` connection files used by the legacy UWP Remote Desktop app from the Microsoft Store, translates the data into the Windows App format, and writes the results into a destination folder. It does not target the built-in `mstsc.exe` Remote Desktop Connection client. In practice, it is a tidy little migration tool: the old connections get a fresh coat of paint, and the new ones show up where Windows App expects them.

## Overview

`ConvertTo-WindowsAppConnection.ps1` reads connection definitions from the legacy UWP Remote Desktop Local Workspace, maps the source XML fields into Windows App `.model` files, and writes the converted output to the destination path.

It supports:

- Migrating one file or many files from a source folder.
- Preserving an existing destination set with optional backups.
- Previewing changes without writing output.
- Reusing a template model so you can keep your preferred Windows App defaults.
- Replacing existing destination entries by host name when requested.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+.
- Access to the Remote Desktop connection source folder.
- Access to the Windows App Local Resources destination folder.
- A template `.model` file or folder, if you want to override the embedded defaults.

## Default Paths

If you do not specify parameters, the script uses the following locations:

- Source: `%LOCALAPPDATA%\Packages\Microsoft.RemoteDesktop_8wekyb3d8bbwe\LocalState\RemoteDesktopData\LocalWorkspace\connections`
- Destination: `%LOCALAPPDATA%\Packages\MicrosoftCorporationII.Windows365_8wekyb3d8bbwe\LocalState\LocalResources`

## What The Script Does

For each source `.model` file, the script:

1. Reads the file as XML.
2. Extracts the `HostName` value.
3. Uses `FriendlyName` as the display name, or falls back to the host name if no friendly name is present.
4. Maps clipboard redirection values from the old format to the Windows App model.
5. Copies a template model object.
6. Writes a new `.model` file into the destination folder.

When destination files already exist for the same host name, the script can skip or overwrite them depending on the parameters you choose.

## Parameters

### `SourcePath`

Path to the Remote Desktop connection files. This can be either a folder containing `.model` files or a single `.model` file.

### `DestinationPath`

Path where converted Windows App connection files are written.

### `TemplateModelPath`

Optional path to a template `.model` file or folder. When not supplied, the script uses an embedded default template.

### `Force`

Overwrites existing destination files when a matching host name is found.

### `SkipExistingHostName`

Skips conversion for source items whose host name already exists in the destination set.

### `BackupDestination`

Optional backup folder path. If omitted and the destination already contains `.model` files, the script creates a timestamped backup folder next to the destination.

### `PreviewOnly`

Runs the migration logic without writing files. This is the safest way to see what would happen before making changes.

## Examples

### Preview the migration

```powershell
.\ConvertTo-WindowsAppConnection.ps1 -PreviewOnly -Verbose
```

### Run with the default source and destination paths

```powershell
.\ConvertTo-WindowsAppConnection.ps1 -Verbose
```

### Use a custom source and destination

```powershell
.\ConvertTo-WindowsAppConnection.ps1 `
  -SourcePath "C:\Temp\RemoteDesktopConnections" `
  -DestinationPath "C:\Temp\WindowsAppConnections" `
  -Verbose
```

### Use a custom template model

```powershell
.\ConvertTo-WindowsAppConnection.ps1 `
  -TemplateModelPath "C:\Templates\WindowsAppTemplate.model" `
  -Verbose
```

### Overwrite existing destination entries

```powershell
.\ConvertTo-WindowsAppConnection.ps1 -Force -Verbose
```

### Create backups in a specific folder

```powershell
.\ConvertTo-WindowsAppConnection.ps1 `
  -BackupDestination "C:\Backups\WindowsAppConnections" `
  -Verbose
```

## Output

The script returns a summary object with these properties:

- `SourceCount`
- `MigratedCount`
- `SkippedCount`
- `FailedCount`
- `BackupPath`
- `SourcePath`
- `DestinationPath`
- `TemplateModelPath`
- `PreviewOnly`

This makes it easy to inspect results from the console or capture them in another script.

## Backup Behavior

If the destination folder already contains `.model` files and you are not running in preview mode, the script backs up the existing files before writing new ones.

- If `-BackupDestination` is provided, that path is used.
- If not, the script creates a timestamped backup folder beside the destination directory.

## Notes

- The script requires a valid `HostName` in each source file.
- If `FriendlyName` is missing, the host name is used as the display name.
- Clipboard redirection values are normalized to Windows App values of `1` or `0` when possible.
- Preview mode is useful when you want to confirm the migration before touching the destination folder.

## Troubleshooting

- If the source path is wrong, the script stops immediately with a path-not-found error.
- If the destination path points to a file instead of a directory, the script throws an error.
- If a template file cannot be parsed as JSON, the script reports the parse failure and stops.
- If a source file does not contain `HostName`, that file is skipped and counted as a failure.

## Supporting Tool: AHK RDP Window Resizer

- <https://github.com/dpo007/AHK-RDP-Window-Resizer>

That script has been updated to support Windows App Remote Desktop windows as well (including sessions whose titles are host-only).

Why you might want it: after migrating connections, it helps quickly normalize RDP window size and placement so multi-session workflows are easier to manage and compare on screen.
