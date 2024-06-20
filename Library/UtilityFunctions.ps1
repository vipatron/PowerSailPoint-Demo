using namespace System.Management.Automation.Host # to get [ChoiceDescription]

function Deepcopy-Object([PSObject] $objectToCopy){
	return [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($objectToCopy))
}

function FancyWrite-Message ([String] $message){
		$delimiter = $message -replace '.','='
		Write-Host -ForegroundColor Yellow -BackgroundColor DarkCyan "$delimiter`n$message`n$delimiter"
}

#Code from https://devblogs.microsoft.com/powershell/diy-ternary-operator/
set-alias ?: Invoke-Ternary -Option AllScope -Description "PSCX filter alias"
filter Invoke-Ternary ([scriptblock]$decider, [scriptblock]$ifTrue, [scriptblock]$ifFalse)
{
	if (&$decider) { 
		&$ifTrue
	} else { 
		&$ifFalse 
	}
}

### WINDOWS TIME CODE (USED IN AD ATTRIBUTES)
function getReadableTime ([String] $winTimeCode){
    w32tm.exe /ntte "$winTimeCode"
}

### TIME ZONE ABBREVIATION - OPTIONAL PARAM
# Good tests:
### EDT [UTC -5]:  (no-arg for creator)
### GMT [UTC +0]: (Get-TimeZone -Name GMT*)
### IST [UTC +5:30]: (Get-TimeZone -name "India*")
function getTimeZoneAndOffset([TimeZoneInfo] $timeZone){
	if (!$timeZone) { $timeZone = Get-TimeZone }
	$timeZoneAbbreviation = (($timeZone.id -split " ") |% {$_[0]}) -join ''
	$offsetTimeValues = $timeZone.BaseUtcOffset -split ":" | % {[int] $_}
	if ($offsetTimeValues[1]) { # if there's a non-zero minutes value to the offset
		$simplifiedOffsetString = "{0:+#;-#; +0}:{1:d2}" -f $offsetTimeValues
	} else {
		$simplifiedOffsetString = "{0:+#;-#;+0}" -f $offsetTimeValues
	}
	return "$timeZoneAbbreviation [UTC $simplifiedOffsetString]"
}

# Adapted from https://adamtheautomator.com/powershell-menu/

<# EXAMPLE USAGE
	[ChoiceDescription[]]$envtChoices = @(
		[ChoiceDescription]::new("&Production", "orgname.identitynow.com")
		[ChoiceDescription]::new("&Development", "orgname-dev.identitynow.com")
	)
	$choiceIndex = New-Menu `
		-Title "ENVIRONMENT SELECTION" `
		-Question "Please select an IDN Instance from which to generate the report" `
		-Options $envtChoices `
		-DefaultChoice 0

	$PRODUCTION = ( -Not $choiceIndex )
#>
function New-Menu {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Title,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Question,
		
		[Parameter(Mandatory)]
		[ChoiceDescription[]]$Options, #[array]
		# NOTE: [ChoiceDescription] is a built-in class whose constructor takes two strings:
		# 	1 - a button label where the ampersand precedes the letter of the button shortcut key
		# 	2 - an optional help messages


		[int32]$DefaultChoice #[array]
	)
		
	$indexOfChosenOption = $host.ui.PromptForChoice(
		$Title,
		$Question,
		$Options,
		(?: {$DefaultChoice -ne $null} {$DefaultChoice} {-1}) # -1 means no default choice
	)
	return $indexOfChosenOption
}