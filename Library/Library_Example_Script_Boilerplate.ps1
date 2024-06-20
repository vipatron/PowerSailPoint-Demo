. $PSScriptRoot\..\Library\API.ps1
. $PSScriptRoot\..\Library\Logger.ps1
. $PSScriptRoot\..\Library\UtilityFunctions.ps1
. $PSScriptRoot\..\Library\IterationUtils.ps1


### CONSTANTS ###

$PRODUCTION = $true
$DEFAULT_CONTENT_TYPE = "application/json"
$PATCH_CONTENT_TYPE = "application/json-patch+json"

### LOAD CONFIG ###
$configPropertyToVarNameMap = @{
	orgname = "orgname"
	ClientID = "ClientID"
	ClientSecret = "ClientSecret"
}
$configFileName = (?: {$PRODUCTION} {""} {"dev_"}) + "config.json"
try{
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\$configFileName" -configPropertyToVarNameMap $configPropertyToVarNameMap
} catch {
	Write-Error ("PROBABLY MISSING $configFileName")
	exit 1;
}

### SCRIPT OBJECTS ###
$authorizer = [Authorizer]::new($orgname, $ClientID, $ClientSecret)
$log = [Logger]::new((($PSCommandPath -split '\\' | Select -Last 1) -replace "`.[^.]+$", ""), "trace", [LogStyleSet]::generateBoldLogStyles(), [Logger]::getLogFileNameMatchingCallingScript())
$API_BASE_URL = "https://$orgname.api.identitynow.com"

### MAIN CODE EXECUTION STARTS HERE ###

$log.debug("TEST LOGGER")