<#
.SYNOPSIS
Converts Remote Desktop app connection data to Windows App connection resources.

.DESCRIPTION
Reads Remote Desktop connection files from the source path and writes converted
Windows App connection resources to the destination path.

.PARAMETER SourcePath
Path to the Remote Desktop connection files.

.PARAMETER DestinationPath
Path where Windows App connection resources are written.

.PARAMETER TemplateModelPath
Optional path to a template model file or folder.

.PARAMETER Force
Overwrites existing Windows App connection files when needed (based on hostname).

.PARAMETER SkipExistingHostName
Skips conversion for entries that already have a host name.

.PARAMETER BackupDestination
Optional path for backups before conversion.

.PARAMETER PreviewOnly
Runs the conversion logic without writing changes.

.EXAMPLE
.\ConvertTo-WindowsAppConnection.ps1 -PreviewOnly
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
	[Parameter()]
	[string]$SourcePath = (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.RemoteDesktop_8wekyb3d8bbwe\LocalState\RemoteDesktopData\LocalWorkspace\connections"),

	[Parameter()]
	[string]$DestinationPath = (Join-Path $env:LOCALAPPDATA "Packages\MicrosoftCorporationII.Windows365_8wekyb3d8bbwe\LocalState\LocalResources"),

	[Parameter()]
	[string]$TemplateModelPath,

	[Parameter()]
	[switch]$Force,

	[Parameter()]
	[switch]$SkipExistingHostName,

	[Parameter()]
	[string]$BackupDestination,

	[Parameter()]
	[switch]$PreviewOnly
)

Set-StrictMode -Version Latest

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-ModelFiles {
	param(
		[Parameter(Mandatory)]
		[string]$Path
	)

	if (Test-Path -LiteralPath $Path -PathType Leaf) {
		return @(Get-Item -LiteralPath $Path -ErrorAction Stop)
	}

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		throw "Path not found: $Path"
	}

	return @(Get-ChildItem -LiteralPath $Path -Filter '*.model' -File -ErrorAction Stop | Sort-Object -Property Name)
}

function Get-XmlElementValue {
	param(
		[Parameter(Mandatory)]
		[xml]$XmlDocument,

		[Parameter(Mandatory)]
		[string]$LocalName
	)

	$node = $XmlDocument.SelectSingleNode("//*[local-name()='$LocalName']")
	if ($null -eq $node) {
		return $null
	}

	return $node.InnerText
}

function ConvertTo-ClipboardRedirectionValue {
	param(
		[Parameter()]
		[object]$Value
	)

	if ($null -eq $Value) {
		return $null
	}

	$text = ([string]$Value).Trim()
	if ([string]::IsNullOrWhiteSpace($text)) {
		return $null
	}

	switch ($text.ToLowerInvariant()) {
		'true' { return '1' }
		'false' { return '0' }
		'1' { return '1' }
		'0' { return '0' }
		default { return $null }
	}
}

function Copy-TemplateModel {
	param(
		[Parameter(Mandatory)]
		[object]$TemplateObject
	)

	return ($TemplateObject | ConvertTo-Json -Depth 10 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-ExistingHostIndex {
	param(
		[Parameter(Mandatory)]
		[string]$Path
	)

	$hostIndex = @{}

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		return $hostIndex
	}

	foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.model' -File -ErrorAction Stop) {
		try {
			$jsonText = [System.IO.File]::ReadAllText($file.FullName)
			$model = $jsonText | ConvertFrom-Json -ErrorAction Stop
			$hostName = [string]$model.host_name

			if (-not [string]::IsNullOrWhiteSpace($hostName)) {
				if (-not $hostIndex.ContainsKey($hostName)) {
					$hostIndex[$hostName] = $file.FullName
				}
				else {
					Write-Warning ("Multiple destination files already exist for hostname '{0}'. Keeping '{1}' as the overwrite target and ignoring '{2}'." -f $hostName, (Split-Path -Path $hostIndex[$hostName] -Leaf), $file.Name)
				}
			}
		}
		catch {
			Write-Warning ("Skipping destination file '{0}' while reading existing host index: {1}" -f $file.Name, $_.Exception.Message)
		}
	}

	return $hostIndex
}

function New-UniqueModelFileName {
	param(
		[Parameter(Mandatory)]
		[string]$DestinationPath
	)

	do {
		$fileName = ([guid]::NewGuid().ToString().ToUpperInvariant()) + '.model'
		$candidatePath = Join-Path $DestinationPath $fileName
	}
	while (Test-Path -LiteralPath $candidatePath)

	return $candidatePath
}

function Write-ModelFile {
	param(
		[Parameter(Mandatory)]
		[object]$ModelObject,

		[Parameter(Mandatory)]
		[string]$OutputPath
	)

	$json = $ModelObject | ConvertTo-Json -Depth 10
	[System.IO.Directory]::CreateDirectory((Split-Path -Path $OutputPath -Parent)) | Out-Null
	[System.IO.File]::WriteAllText($OutputPath, $json, $script:Utf8NoBom)
}

function New-DefaultTemplateModel {
	return [pscustomobject]@{
		host_name = ''
		display_name = ''
		settings = [pscustomobject]@{
			enable_rdp_multimon = 'true'
			smartcard_redirection = '0'
			workspace_display_settings = '{"configuration":"Single","useDefaultSettings":false,"fullScreen":false,"fitWindow":true,"dynamicResolution":true}'
			audio_mode = '2'
			port_redirection = '0'
			location_redirection = '0'
			audio_capture_mode = '0'
			clipboard_redirection = '1'
			printer_redirection = '0'
			webauthn_redirection = '0'
			keyboard_hook = '2'
			enable_rds_aad_auth = '0'
			device_to_redirection = ''
			drives_to_redirection = ''
			cameras_to_redirection = ''
			server_identity = ''
			server_identity_type = ''
		}
	}
}

function Resolve-TemplateModelObject {
	param(
		[Parameter()]
		[string]$RequestedTemplateModelPath
	)

	if (-not [string]::IsNullOrWhiteSpace($RequestedTemplateModelPath)) {
		$templatePath = (Resolve-Path -LiteralPath $RequestedTemplateModelPath -ErrorAction Stop).Path
		$templateJsonText = [System.IO.File]::ReadAllText($templatePath)

		try {
			$templateObject = $templateJsonText | ConvertFrom-Json -ErrorAction Stop
		}
		catch {
			throw "Failed to parse template JSON file '$templatePath': $($_.Exception.Message)"
		}

		return [pscustomobject]@{
			TemplateObject = $templateObject
			TemplateSource  = $templatePath
		}
	}

	return [pscustomobject]@{
		TemplateObject = (New-DefaultTemplateModel)
		TemplateSource  = '<embedded default template>'
	}
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
	throw "Source path does not exist: $SourcePath"
}

if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
	throw "Destination path must be a directory: $DestinationPath"
}

$templateResolution = Resolve-TemplateModelObject -RequestedTemplateModelPath $TemplateModelPath
$templateObject = $templateResolution.TemplateObject
$resolvedTemplateModelPath = $templateResolution.TemplateSource

foreach ($requiredProperty in @('host_name', 'display_name', 'settings')) {
	if ($null -eq $templateObject.PSObject.Properties[$requiredProperty]) {
		throw "Template JSON is missing required property '$requiredProperty'."
	}
}

$sourceFiles = Get-ModelFiles -Path $SourcePath
	Write-Verbose ("Source file count: {0}" -f (@($sourceFiles).Count))

$existingHostIndex = Get-ExistingHostIndex -Path $DestinationPath

if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container) -and -not $PreviewOnly) {
	if ($PSCmdlet.ShouldProcess($DestinationPath, 'Create destination directory')) {
		[System.IO.Directory]::CreateDirectory($DestinationPath) | Out-Null
	}
}

$backupPath = $null
if (-not $PreviewOnly) {
	$destinationFiles = @()
	if (Test-Path -LiteralPath $DestinationPath -PathType Container) {
		$destinationFiles = @(Get-ChildItem -LiteralPath $DestinationPath -Filter '*.model' -File -ErrorAction Stop)
	}

	if (@($destinationFiles).Count -gt 0) {
		if ($BackupDestination) {
			$backupPath = $BackupDestination
		}
		else {
			$destinationParent = Split-Path -Path $DestinationPath -Parent
			$destinationLeaf = Split-Path -Path $DestinationPath -Leaf
			$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
			$backupPath = Join-Path $destinationParent ("{0}-backup-{1}" -f $destinationLeaf, $timestamp)
		}

		if ($PSCmdlet.ShouldProcess($backupPath, 'Back up existing destination .model files')) {
			[System.IO.Directory]::CreateDirectory($backupPath) | Out-Null

			foreach ($destinationFile in $destinationFiles) {
				$backupFilePath = Join-Path $backupPath $destinationFile.Name
				Copy-Item -LiteralPath $destinationFile.FullName -Destination $backupFilePath -Force:$true -ErrorAction Stop
			}

			Write-Verbose ("Backed up {0} existing destination file(s) to '{1}'." -f (@($destinationFiles).Count), $backupPath)
		}
	}
}

$migratedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($sourceFile in $sourceFiles) {
	try {
		$xmlText = [System.IO.File]::ReadAllText($sourceFile.FullName)
		[xml]$sourceXml = $xmlText

		$hostName = [string](Get-XmlElementValue -XmlDocument $sourceXml -LocalName 'HostName')
		if ([string]::IsNullOrWhiteSpace($hostName)) {
			throw "Source file '$($sourceFile.Name)' does not contain a HostName value."
		}

		$friendlyName = [string](Get-XmlElementValue -XmlDocument $sourceXml -LocalName 'FriendlyName')
		if ([string]::IsNullOrWhiteSpace($friendlyName)) {
			$friendlyName = $hostName
		}

		$clipboardValue = Get-XmlElementValue -XmlDocument $sourceXml -LocalName 'RedirectClipboard'
		$clipboardRedirection = ConvertTo-ClipboardRedirectionValue -Value $clipboardValue

		$outputPath = $null
		$existingConnection = $existingHostIndex[$hostName]
		if ($null -ne $existingConnection) {
			if (-not $Force) {
				$skippedCount++
				if ($SkipExistingHostName) {
					Write-Verbose ("Skipping '{0}' because hostname '{1}' already exists in the destination set." -f $sourceFile.Name, $hostName)
				}
				else {
					Write-Warning ("Skipping '{0}' because hostname '{1}' already exists in the destination set." -f $sourceFile.Name, $hostName)
				}

				continue
			}

			$outputPath = $existingConnection
			Write-Verbose ("Overwriting existing target for hostname '{0}' at '{1}'." -f $hostName, (Split-Path -Path $outputPath -Leaf))
		}

		$modelObject = Copy-TemplateModel -TemplateObject $templateObject
		$modelObject.host_name = $hostName
		$modelObject.display_name = $friendlyName

		if ($null -ne $clipboardRedirection) {
			if ($null -eq $modelObject.settings) {
				throw "Template settings object is missing while applying clipboard mapping for '$($sourceFile.Name)'."
			}

			$modelObject.settings.clipboard_redirection = $clipboardRedirection
		}

		if ($null -eq $outputPath) {
			$outputPath = New-UniqueModelFileName -DestinationPath $DestinationPath
		}

		if ($PreviewOnly) {
			$migratedCount++
			Write-Verbose ("PreviewOnly: would migrate '{0}' -> host '{1}', display '{2}', target '{3}'." -f $sourceFile.Name, $hostName, $friendlyName, (Split-Path -Path $outputPath -Leaf))
			continue
		}

		if (-not $PSCmdlet.ShouldProcess($outputPath, ("Write migrated model for host '{0}'" -f $hostName))) {
			$skippedCount++
			Write-Verbose ("Skipped '{0}' because the operation was not approved by ShouldProcess." -f $sourceFile.Name)
			continue
		}

		Write-ModelFile -ModelObject $modelObject -OutputPath $outputPath
		$migratedCount++

		if (-not $existingHostIndex.ContainsKey($hostName)) {
			$existingHostIndex[$hostName] = $outputPath
		}

		Write-Verbose ("Migrated '{0}' | host '{1}' | display '{2}' | target '{3}'." -f $sourceFile.Name, $hostName, $friendlyName, (Split-Path -Path $outputPath -Leaf))
	}
	catch {
		$failedCount++
		Write-Warning ("Failed to migrate '{0}': {1}" -f $sourceFile.Name, $_.Exception.Message)
	}
}

Write-Verbose ("Migrated count: {0}" -f $migratedCount)
Write-Verbose ("Skipped count: {0}" -f $skippedCount)
Write-Verbose ("Failed count: {0}" -f $failedCount)

[pscustomobject]@{
	SourceCount       = @($sourceFiles).Count
	MigratedCount     = $migratedCount
	SkippedCount      = $skippedCount
	FailedCount       = $failedCount
	BackupPath        = $backupPath
	SourcePath        = $SourcePath
	DestinationPath   = $DestinationPath
	TemplateModelPath = $resolvedTemplateModelPath
	PreviewOnly       = [bool]$PreviewOnly
}
