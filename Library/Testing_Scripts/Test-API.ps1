$initialVars = ((Get-Variable -Scope script) | Where-object {$_.description -eq ""}).name


. $PSScriptRoot\..\API.ps1
. $PSScriptRoot\..\Logger.ps1
. $PSScriptRoot\..\UtilityFunctions.ps1

$log = [Logger]::new("Test-API", "trace", [LogStyleSet]::generateBoldLogStyles(), [Logger]::getLogFileNameMatchingCallingScript())

# TODO: test multiple invocations of this function - something isn't right.
<# TESTING Function Load-ConfigJSONIntoScriptVariables
$log.warning("TESTING Function Load-ConfigJSONIntoScriptVariables")

	$currentVars = ((Get-Variable -Scope script) | Where-object {$_.description -eq "" -and $_.name -notin $initialVars})
	$log.debug("# currentVars: $($currentVars.count)")
	$log.debug(($currentVars | ft -wrap -Property Name, Value | Out-String))

	$configPropertyToVarNameMap = @{
		orgname = "orgname"
		testingflag = "testingflag"
		ClientID = "ClientID"
		ClientSecret = "ClientSecret"
		localOutputDir = "dirToPlaceLogs"
	}

	$log.warning("LOADING MAPPED VARS FROM CONFIG")
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\config.json" -configPropertyToVarNameMap $configPropertyToVarNameMap

	$currentVars = ((Get-Variable -Scope script) | Where-object {$_.description -eq "" -and $_.name -notin $initialVars})
	$log.info("# currentVars: $($currentVars.count)")
	$log.info(($currentVars | ft -wrap -Property Name, Value | Out-String))


	$log.warning("LOADING ALL VARS IN CONFIG - NoClobber")
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\config.json" -overwriteExistingValues $false

	$currentVars = ((Get-Variable -Scope script) | Where-object {$_.description -eq "" -and $_.name -notin $initialVars})
	$log.info("# currentVars: $($currentVars.count)")
	$log.info(($currentVars | ft -wrap -Property Name, Value | Out-String))


	$log.warning("LOADING ALL VARS IN CONFIG - Clobber")
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\config.json"

	$currentVars = ((Get-Variable -Scope script) | Where-object {$_.description -eq "" -and $_.name -notin $initialVars})
	$log.info("# currentVars: $($currentVars.count)")
	$log.info(($currentVars | ft -wrap -Property Name, Value | Out-String))
<##>

<# TESTING class Authorizer
	$log.warning("TESTING class Authorizer")

	$configPropertyToVarNameMap = @{
		orgname = "orgname"
		ClientID = "ClientID"
		ClientSecret = "ClientSecret"
	}

	$log.warning("LOADING MAPPED VARS FROM CONFIG FOR TESTING ")
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\config.json" -configPropertyToVarNameMap $configPropertyToVarNameMap

	$log.warning("TESTING INITIAL CALL")	
	$auther = [Authorizer]::new($orgname, $ClientID, $ClientSecret)
	$log.debug("auther:$auther")
	$header = $auther.getHeader()
	$log.info("received header: $($header | fl | Out-String)")
	$log.debug("auther after getHeader Call:$auther")
	
	$log.warning("TESTING REPEAT CALL")
	$repeatedCallHeader = $auther.getHeader()
	$log.info("received header from repeat call: Still the same object? $($repeatedCallHeader -eq $header) $($repeatedCallHeader | fl | Out-String)")
	$log.debug("auther after repeat getHeader Call:$auther")

	$log.warning("TESTING CALL WITH EXPIRING PREVIOUS HEADER INFO")
	$auther.expirationDate = $auther.expirationDate.AddMinutes(-12)
	$log.warning("subtracted 12 minutes from expiration time. Current Authorizer state: $auther")
	$log.warning("current time: $(Get-Date)")
	$newHeader = $auther.getHeader()
	$log.info("new header: $($newHeader | fl | Out-String)")
	$log.debug("auther after getHeader Call resulting in new header:$auther")
	
<##>

<# TESTING class ObjectEndpointQuery 
	$log.warning("TESTING class ObjectEndpointQuery")
	$url = "https://myOrg.api.identitynow.com/v3/sources?limit=250&offset=0&count=true&sorters=name&filters=name%20eq%20%22Workday%22"
	$log.info("Original url: $url")

	<# TESTING STATIC METHODS
		<# TESTING urlDecode and parseQuery
			$decodedUrl = [ObjectEndpointQuery]::urlDecode($url)
			$log.info("Decoded url:  $decodedUrl")
			$queryObjectOutput = [ObjectEndpointQuery]::parseQuery($decodedUrl)
			# $queryObjectOutput
			$log.debug(($queryObjectOutput | fl | Out-String))
			$queryObjectOutput.paramTable
			$queryObjectOutput.paramTable.GetType().name
			
			
			$decodedUrlNoParams = $decodedUrl -replace "\?.*",""
			$log.info("Decoded url Without Query Params: $decodedUrlNoParams")
			$queryObjectNoParamsOutput = [ObjectEndpointQuery]::parseQuery($decodedUrlNoParams)
			# $queryObjectNoParamsOutput
			$log.debug(($queryObjectNoParamsOutput | fl | Out-String))

			$doublydecodedUrl = [ObjectEndpointQuery]::urlDecode($decodedUrl)
			$log.info("Singly-Decoded url: $decodedUrl")
			$log.info("Double-Decoded url: $doublydecodedUrl")
		#>
		
		<# TESTING constructors
			$log.warning("Validation should fail on empty string")
			$failureUrl = ""
			$log.info("failureUrl: $failureUrl")
			try {
				[ObjectEndpointQuery]::new($failureUrl)
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

			$log.warning("Validation should fail on single path component (objectType)")
			$failureUrl = "https://myOrg.api.identitynow.com/v3/"
			$log.info("failureUrl: $failureUrl")
			try {
				[ObjectEndpointQuery]::new($failureUrl)
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

			$log.warning("Validation should SUCCEED: full query")
			$fullQueryUrl = [ObjectEndpointQuery]::urlDecode($url)
			$log.info("fullQueryUrl: $fullQueryUrl")
			try {
				$objQuery = [ObjectEndpointQuery]::new($fullQueryUrl)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			$log.warning("Using the last object query, excluding some parameters")
			# $paramsToExclude = @('offset', 'sorters')
			# $log.trace("getQueryUrlExcludingParams($paramsToExclude): $($objQuery.getQueryUrlExcludingParams($paramsToExclude))")

			$log.warning("Validation should SUCCEED: no query params")
			$objectEndpointUrl = [ObjectEndpointQuery]::urlDecode($url) -replace "\?.*",""
			$log.info("objectEndpointUrl: $objectEndpointUrl")
			try {
				$objQuery = [ObjectEndpointQuery]::new($objectEndpointUrl)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

			$log.warning("Validation should SUCCEED: separate objectEndpointUrl and queryParams strings")
			[ObjectEndpointQuery]::urlDecode($url) -match "(.*)\?(.*)"
			$objectEndpointUrl = $matches[1]
			$queryParamString = $matches[2]
			$log.info("objectEndpointUrl: $objectEndpointUrl")
			$log.info("queryParamString: $queryParamString")
			try {
				$objQuery = [ObjectEndpointQuery]::new($objectEndpointUrl, $queryParamString)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			$log.warning("Testing replacing previous objQuery.cloneWithDifferentParams")
			$paramNamesToRemove = @("offset","sorters")
			$paramNamesToAddOrReplace =  @{limit=1;count="false"}
			$log.debug("paramNamesToRemove: $paramNamesToRemove")
			$log.debug("paramNamesToAddOrReplace: $(($paramNamesToAddOrReplace | fl | Out-String).TrimEnd())")
			$newObjQuery = $objQuery.cloneWithDifferentParams($paramNamesToRemove,$paramNamesToAddOrReplace)
			$log.debug("newObjQuery: $newObjQuery")
			$log.trace("getQueryUrl(): $($newObjQuery.getQueryUrl())")

			$log.warning("Validation should SUCCEED: separate objectEndpointUrl and queryParams Hashtable")
			$objectEndpointUrl = [ObjectEndpointQuery]::urlDecode($url) -replace "\?.*",""
			$queryParamHT = @{
				sorters = "name"
				filters = 'name eq "Workday"'
			}
			$log.info("objectEndpointUrl: $objectEndpointUrl")
			$log.info("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
			try {
				$objQuery = [ObjectEndpointQuery]::new($objectEndpointUrl, $queryParamHT)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

			$log.warning("Validation should SUCCEED: separate orgname, versionPathSegment, objectEndpointPathSegment and queryParams Strings")
			$orgname = "myOrg"
			$versionPathSegment = "v3"
			$objectEndpointPathSegment = "sources"
			$queryParamString = 'sorters=name&filters=name eq "Workday"'
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			$log.info("queryParamString: $queryParamString")
			try {
				$objQuery = [ObjectEndpointQuery]::new($orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamString)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}


			$log.warning("Validation should SUCCEED: separate orgname, versionPathSegment, objectEndpointPathSegment strings and queryParams HashTable")
			$orgname = "myOrg"
			$versionPathSegment = "v3"
			$objectEndpointPathSegment = "sources"
			$queryParamHT = @{
				sorters = "name"
				filters = 'name eq "Workday"'
			}
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			$log.debug("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
			try {
				$objQuery = [ObjectEndpointQuery]::new($orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamHT)
				$log.debug("objQuery: $objQuery")
				$log.trace("getQueryUrl(): $($objQuery.getQueryUrl())")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

		#>

#>

<# TESTING class ObjectEndpointIterator #>
	$log.warning("TESTING class ObjectEndpointIterator")
	
	$configPropertyToVarNameMap = @{
		orgname = "orgname"
		ClientID = "ClientID"
		ClientSecret = "ClientSecret"
	}
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\dev_config.json" -configPropertyToVarNameMap $configPropertyToVarNameMap

	$authorizer = [Authorizer]::new($orgname, $ClientID, $ClientSecret)

	<# TESTING constructors - implicitly tests static methods validateAndUpdateQueryPageLimit and determinePageSizeForObjectType

		$log.warning("Validation should FAIL on limit=0")
		$failureUrl = "https://$orgname.api.identitynow.com/v3/sources?limit=0"
		$log.info("failureUrl: $failureUrl")
		try {
			[ObjectEndpointIterator]::new($authorizer, $failureUrl)
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}

		$log.warning("Validation should FAIL on limit=300")
		$failureUrl = "https://$orgname.api.identitynow.com/v3/sources?limit=300"
		$log.info("failureUrl: $failureUrl")
		try {
			[ObjectEndpointIterator]::new($authorizer, $failureUrl)
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}


		$log.warning("Validation should SUCCEED via default limit lookup for an endpoint with a known limit")
		$log.debug("NOTE: This is also a test of the 'no query params' constructor")
		$defaultLimitUrL = "https://$orgname.api.identitynow.com/v3/sources"
		$log.info("defaultLimitUrL: $defaultLimitUrL")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $defaultLimitUrL)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}

		# TESTING NOTE 1: Because SP has been secretly raising the documented limit of 50 on most v3 and beta to 250, the only way to test the limit-acquisition quote in determinePageSizeForObjectType is to comment out the SPO name in [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS, which forces the code to make an API call to look it up, and to raise the [ObjectEndpointIterator]::COMMON_HIGH_LIMIT from 250 to 251.
		# WARNING: If you make these changes, you MUST reverse them for production
		# PROGRAMMER NOTE: If one day, SP announces default limits of 250 for all endpoints, the determinePageSizeForObjectType function will still work, but that and DEFAULT_API_PAGE_LIMITS should be stripped from the API.ps1
		$log.warning("Validation should SUCCEED via dynamic limit lookup for an endpoint with a unknown limit")
		$log.fatal("[SEE TESTING NOTE IN THE CODE FOR TEMPORARY MODIFICATIONS TO API.ps1 NEEDED TO ENSURE THIS TEST WORKS]")
		$log.debug("NOTE: If those modifications aren't done, this serves as a test of fact-checking low page limits")
		$dynamicLimitUrL = "https://$orgname.api.identitynow.com/v3/access-profiles"
		$log.info("dynamicLimitUrL: $dynamicLimitUrL")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $dynamicLimitUrL)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}
		
		# TESTS OF CONSTRUCTOR OVERLOADS
		# Base URL for the overload tests
		$url = "https://$orgname.api.identitynow.com/beta/sources?filters=name%20eq%20%22Workday%22"
		
		$log.warning("Validation should SUCCEED: full query")
		$fullQueryUrl = [ObjectEndpointQuery]::urlDecode($url)
		$log.info("fullQueryUrl: $fullQueryUrl")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $fullQueryUrl)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}

		$log.warning("Validation should SUCCEED: separate objectEndpointUrl and queryParams strings")
		[ObjectEndpointQuery]::urlDecode($url) -match "(.*)\?(.*)"
		$objectEndpointUrl = $matches[1]
		$queryParamString = $matches[2]
		$log.info("objectEndpointUrl: $objectEndpointUrl")
		$log.info("queryParamString: $queryParamString")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $objectEndpointUrl, $queryParamString)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}

		$log.warning("Validation should SUCCEED: separate objectEndpointUrl and queryParams Hashtable")
		$objectEndpointUrl = [ObjectEndpointQuery]::urlDecode($url) -replace "\?.*",""
		$queryParamHT = @{
			sorters = "name"
			filters = 'name eq "Workday"'
		}
		$log.info("objectEndpointUrl: $objectEndpointUrl")
		$log.info("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $objectEndpointUrl, $queryParamHT)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}

		$log.warning("Validation should SUCCEED: separate orgname, versionPathSegment, objectEndpointPathSegment and queryParams Strings")
		$versionPathSegment = "v3"
		$objectEndpointPathSegment = "sources"
		$queryParamString = 'sorters=name&filters=name eq "Workday"'
		$log.info("orgname: $orgname")
		$log.info("versionPathSegment: $versionPathSegment")
		$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
		$log.info("queryParamString: $queryParamString")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamString)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}


		$log.warning("Validation should SUCCEED: separate orgname, versionPathSegment, objectEndpointPathSegment strings and queryParams HashTable")
		$versionPathSegment = "beta"
		$objectEndpointPathSegment = "accounts"
		$queryParamHT = @{
			sorters = "name"
			filters = 'uncorrelated eq true'
		}
		$log.info("orgname: $orgname")
		$log.info("versionPathSegment: $versionPathSegment")
		$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
		$log.debug("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
		try {
			$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamHT)
			$log.trace("objEndpointIterator: $objEndpointIterator")
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}
	#>
	<# TESTING INSTANCE METHODS #>
		<# TESTING SINGLE PAGE AND METHODS
			$log.warning("TESTING Execution of single page and executeQuery overloads - implicitly tests flush")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "sources"
			$queryParamHT = @{
				sorters = "name"
				filters = 'name co "AD"'
			}
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			$log.debug("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
			try {
				$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamHT)
				$log.trace("objEndpointIterator: $objEndpointIterator")

				$log.info("Testing executing previous Iterator [4 total]")

				$log.debug("executing no params")
				$objEndpointIterator.executeQuery()

				$log.debug("executing bool only (false) - no progress indicator")
				$objEndpointIterator.executeQuery($false)

				$log.debug("executing progressBarActivityName only")
				$objEndpointIterator.executeQuery("String only: Getting Sources containing 'AD'")

				$log.debug("executing while explicitly setting both params: showProgressIndicators=true & progressBarActivityName")
				$objEndpointIterator.executeQuery($true, "Both Params:Getting Sources containing 'AD'")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$log.warning("TESTING Execution of iteration methods")
			
			$log.info("TESTING count()")
			$count = $objEndpointIterator.count()
			$log.debug("count(): $count")
			
			$log.info("TESTING random-access methods getObjectById and getObjectByIndex")
			$firstId = $objEndpointIterator.ids[0]
			$log.trace("first id in arrayList: $firstId")
			$objById = $objEndpointIterator.getObjectById($firstId)
			$log.debug("objById(firstId): $objById")
			$objByIndex = $objEndpointIterator.getObjectByIndex(0)
			$log.debug("objByIndex(0): $objByIndex")
			$log.trace("First objById and First objByIndex are the same? $(-Not [bool] (Compare-Object $objById $objByIndex))")

			$log.warning("TESTING hasNext and next")
			$log.debug("Iterating the whole iterator")
			$allObjects = [System.Collections.ArrayList]::new()
			while ($objEndpointIterator.hasNext()){
				[void] $allObjects.add($objEndpointIterator.next())
			}
			$log.trace("allObjects: $($allObjects | ft | Out-string)")
			$log.debug("allObjects.count: $($allObjects.count)")
			
			$log.warning("TESTING iteration reset")
			$log.debug("EXHAUSTED - objEndpointIterator.index out of count: $($objEndpointIterator.index) out of $($objEndpointIterator.count())")
			$log.trace("resetting...")
			$objEndpointIterator.reset()
			$log.debug("    RESET - objEndpointIterator.index out of count: $($objEndpointIterator.index) out of $($objEndpointIterator.count())")
		#>
		
		<# TESTING Execution of multiple pages
			$log.warning("TESTING Execution of multiple pages")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "accounts"
			$queryParamHT = @{
				sorters = "id"
				filters = 'uncorrelated eq true'
			}
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			$log.debug("queryParam HashTable: $((($queryParamHT | fl | Out-String)-replace "`n","`n`t").TrimEnd())")
			try {
				$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamHT)
				$log.trace("objEndpointIterator: $objEndpointIterator")
				$log.info("executing previous Iterator")
$performance = Measure-Command -Expression {
				$objEndpointIterator.executeQuery("Uncorrelated Accounts")
}
$log.trace("Process took $($performance.Minutes) minutes and $($performance.Seconds) seconds to run.")
$log.trace(($performance | fl | out-string))

$objEndpointIterator | export-clixml -path C:\Users\u730339\Documents\TEMP_DUMP\Library\Testing_Scripts\objEndpointIterator.xml

			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$uncorrelatedAccountList = [System.Collections.ArrayList]::new()
			while ($objEndpointIterator.hasNext()){
				[void] $uncorrelatedAccountList.add($objEndpointIterator.next())
			}
			$log.debug("uncorrelatedAccountList.count: $($uncorrelatedAccountList.count)")
		#>

		<# TESTING Post-execution filter methods
			$log.warning("TESTING Post-execution filter methods")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "sources"
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			try {
				$objEndpointIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment,"")
				$log.trace("objEndpointIterator PRE FILTER: $objEndpointIterator")
				$log.info("executing previous Iterator")
				$objEndpointIterator.executeQuery()
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$log.debug("Total number of sources: $($objEndpointIterator.count())")
			$adSourceFilter = {$_.type -eq "Active Directory - Direct"}
			$objEndpointIterator.filterResults($adSourceFilter)
			$log.trace("objEndpointIterator POST FILTER: $objEndpointIterator")
			$log.debug("Total number of AD direct sources: $($objEndpointIterator.count())")
			
			while($objEndpointIterator.hasNext()){
				$source = $objEndpointIterator.next()
				Write-Host "$($source.id): $($source.type)"
			}
		#>

		<# TESTING MergedObjectEndpointIterator
			$log.warning("TESTING Post-execution merging using MergedObjectEndpointIterator")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "sources"
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			try {
				$adSourceIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment,"")
				$log.trace("adSourceIterator: $adSourceIterator")
				$log.info("executing previous Iterator")
				$adSourceIterator.executeQuery()
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$log.debug("Total number of sources: $($adSourceIterator.count())")
			$adSourceFilter = {$_.type -eq "Active Directory - Direct"}
			$adSourceIterator.filterResults($adSourceFilter)
			$log.debug("Total number of AD direct Sources: $($adSourceIterator.count())")

			# while($adSourceIterator.hasNext()){
				# $source = $adSourceIterator.next()
				# Write-Host "$($source.id): $($source.type)"
			# }


			$log.warning("TESTING Post-execution merging")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "sources"
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")
			try {
				$azureSourceIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment,"")
				$log.trace("azureSourceIterator: $azureSourceIterator")
				$log.info("executing previous Iterator")
				$azureSourceIterator.executeQuery()
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$log.debug("Total number of sources: $($azureSourceIterator.count())")
			$adSourceFilter = {$_.type -eq "Azure Active Directory"}
			$azureSourceIterator.filterResults($adSourceFilter)
			$log.debug("Total number of Azure direct Sources: $($azureSourceIterator.count())")

			# while($azureSourceIterator.hasNext()){
				# $source = $azureSourceIterator.next()
				# Write-Host "$($source.id): $($source.type)"
			# }

			
			$mergedIteratorsArr = @($adSourceIterator, $azureSourceIterator)
			$log.info("TESTING constructor using array")
			$mergedArrIterator = [MergedObjectEndpointIterator]::new($mergedIteratorsArr)

			$log.info("TESTING count()")
			$log.debug("Total number of Sources in mergedArrIterator: $($mergedIteratorsArr.count())")

			$log.info("TESTING iteration methods hasNext() and next()")
			$counts = @{}
			while ($mergedArrIterator.hasNext()){
				$source = $mergedArrIterator.next()
				if ($counts.ContainsKey($source.type)){
					$counts[$source.type]++
				} else {
					$counts[$source.type] = 1
				}
			}
			$log.debug("COUNTS USING ARRAY: $([PSCustomObject] $counts | fl | Out-String)")
			
			
			$log.info("TESTING reset")
			$log.debug("BEFORE reset(), index = $($mergedArrIterator.index)")
			$mergedArrIterator.reset()
			$log.debug("AFTER reset(), index = $($mergedArrIterator.index)")


			$log.info("TESTING random-access methods getObjectById and getObjectByIndex")
			$firstId = $mergedArrIterator.ids[0]
			$log.trace("first id in arrayList: $firstId")
			$objById = $mergedArrIterator.getObjectById($firstId)
			$log.debug("objById(firstId): $objById")
			$objByIndex = $mergedArrIterator.getObjectByIndex(0)
			$log.debug("objByIndex(0): $objByIndex")
			$log.trace("First objById and First objByIndex are the same? $(-Not [bool] (Compare-Object $objById $objByIndex))")



			$log.info("TESTING constructor using ArrayList")


			$mergedIteratorsArrList = [System.Collections.ArrayList]::new()
			$mergedIteratorsArrList.addRange($mergedIteratorsArr)
			$mergedArrListIterator = [MergedObjectEndpointIterator]::new($mergedIteratorsArrList)
			$log.debug("Total number of Sources in mergedArrListIterator: $($mergedArrListIterator.count())")

			$counts = @{}
			while ($mergedArrListIterator.hasNext()){
				$source = $mergedArrListIterator.next()
				if ($counts.ContainsKey($source.type)){
					$counts[$source.type]++
				} else {
					$counts[$source.type] = 1
				}
			}
			$log.debug("COUNTS USING ARRAYLIST: $([PSCustomObject] $counts | fl | Out-String)")
			
			Write-Host $mergedArrListIterator
			
		#>

		<# TESTING ObjectIterator baseClass methods
			$log.warning("TESTING ObjectIterator baseClass methods")
			$log.warning("test of generateObjectArray Method using `$_")
			$versionPathSegment = "beta"
			$objectEndpointPathSegment = "sources"
			$queryParamHT = @{
				sorters = "name"
			}
			$Global:objectTransformFilterTable = [PSCustomObject]@{
				name = {$_.name}
				BU = {if ($_.description -match "BU: ([^\|]+) \|") {$matches[1]}}
				# BU = { $_.description }
				owner = {$_.owner.name}
				type = {$_.type}
				connectionType = {$_.connectorAttributes.connectionType}
				cloudExternalId = {$_.connectorAttributes.cloudExternalId}
				domainUser = {$_.connectorAttributes.domainSettings.user}
				DCs = {$_.connectorAttributes.domainSettings.servers -join " | "}
				iqServiceHost = {$_.connectorAttributes.IQServiceHost}
				iqServicePort = {$_.connectorAttributes.IQServicePort}
				iqServiceUser = {$_.connectorAttributes.IQServiceUser }
			}
			$log.info("orgname: $orgname")
			$log.info("versionPathSegment: $versionPathSegment")
			$log.info("objectEndpointPathSegment: $objectEndpointPathSegment")				
			$log.info("queryParamHT: $queryParamHT")				
			$log.info("objectTransformFilterTable: $($objectTransformFilterTable | fl | Out-String)")
			try {
				$sourceIterator = [ObjectEndpointIterator]::new($authorizer, $orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParamHT)
				$log.trace("sourceIterator: $sourceIterator")
				$log.info("executing previous Iterator")
				$sourceIterator.executeQuery()
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			
			$Global:objectArray = $sourceIterator.generateObjectArray($objectTransformFilterTable)
			$log.debug("objectArray type: $($objectArray.getType().Name)")
			$log.debug("objectArray[0] type: $($objectArray[0].getType().Name)")
			$log.debug("objectArray count: $($objectArray.count)")
			$log.trace("objectArray: $($objectArray | ft -wrap | Out-string)")
			$log.debug("objectArray[0]: $($objectArray[0])")

			$log.warning("test of generateObjectArrayUsingInputVariable Method using `$Input")
			$Global:inputObjectTransformFilterTable = [PSCustomObject]@{
				name = {$Input.name}
				provisioningFeatures = { ($Input.features | Where-Object {$_ -like "*PROVISIONING*"}) -join " | " }
			}
			$log.info("inputObjectTransformFilterTable: $($inputObjectTransformFilterTable | fl | Out-String)")

			$Global:objectArrayUsingComplexFilters = $sourceIterator.generateObjectArrayUsingInputVariable($inputObjectTransformFilterTable)
			$log.debug("objectArrayUsingComplexFilters type: $($objectArrayUsingComplexFilters.getType().Name)")
			$log.debug("objectArrayUsingComplexFilters[0] type: $($objectArrayUsingComplexFilters[0].getType().Name)")
			$log.debug("objectArrayUsingComplexFilters count: $($objectArrayUsingComplexFilters.count)")
			$log.fatal("objectArrayUsingComplexFilters: $($objectArrayUsingComplexFilters | ft -wrap | Out-string)")
			$log.debug("objectArrayUsingComplexFilters[0]: $($objectArrayUsingComplexFilters[0])")
			
			$mixedObjectAttributeArrayWillFail = @("id", 321, "name")
			$log.warning("TESTING [String[]] validation for generateObjectArray - FAIL")
			try {
				$failedObjectArray = $sourceIterator.generateObjectArray($mixedObjectAttributeArrayWillFail)
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}

			$stringObjectAttributeArray = @("id", "name")
			$log.warning("TESTING [String[]] validation for generateObjectArray - SUCCESS")
			try {
				$global:objectArrayOfSourceIdsAndNames = $sourceIterator.generateObjectArray($stringObjectAttributeArray) # implicitly calls the [String[]] version
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
			}
			$log.debug("objectArrayOfSourceIdsAndNames type: $($objectArrayOfSourceIdsAndNames.getType().Name)")
			$log.debug("objectArrayOfSourceIdsAndNames[0] type: $($objectArrayOfSourceIdsAndNames[0].getType().Name)")
			$log.debug("objectArrayOfSourceIdsAndNames count: $($objectArrayOfSourceIdsAndNames.count)")
			$log.fatal("objectArrayOfSourceIdsAndNames: $($objectArrayOfSourceIdsAndNames | ft -wrap | Out-string)")
			$log.debug("objectArrayOfSourceIdsAndNames[0]: $($objectArrayOfSourceIdsAndNames[0])")
			


		#>
		
	#>
	

# TODO: formalize and sanitize this hackish debugging.
	<# TESTING workgroups issue (getting 400 bad request during sizing calls) #>
		$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["workgroups"]
		$log.debug("pageSize null? $($pageSize -eq $null)")
		$log.debug("DefaultContent: $([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE)")

	# $url = "https://myOrg.api.identitynow.com/beta/workgroups?limit=50"
	# try{
		# # Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType [ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE -UseBasicParsing
		# # Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType "application/json" -UseBasicParsing
		# Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
	# } catch {
		# $global:lastError = $_
		# $log.error([Logger]::getLoggableMultilineErrorString($_))		
	# }
# exit;
	
	
	
		# $workgroupsUrl = "https://$orgname.api.identitynow.com/beta/workgroups"
		$API_BASE_URL = "https://$($orgname).api.identitynow.com"
		$workgroupsUrl = "https://$orgname.api.identitynow.com/beta/workgroups?filters=name eq `"IDNPrivADNotifications`""
		
		try {
			$workgroupIterator = [ObjectEndpointIterator]::new($authorizer, $workgroupsUrl)
			$log.trace("workgroupIterator: $workgroupIterator")
			$log.info("executing previous Iterator")
			$workgroupIterator.executeQuery("Running workgroup query")
			$workgroupIterator.generateObjectArray(@("id", "name", "owner.name")) | ft
		} catch {
			$log.error([Logger]::getLoggableMultilineErrorString($_))
		}


		$NEW_ACCESS_PROFILE_OWNER_NAME = "$($orgname -replace '-dev','')_admin"
$log.debug("NEW_ACCESS_PROFILE_OWNER_NAME: $NEW_ACCESS_PROFILE_OWNER_NAME")
		$APOwnerUrl = "$API_BASE_URL/beta/identities?filters=alias eq `"$NEW_ACCESS_PROFILE_OWNER_NAME`"&sorters=alias"
		try{
			$global:APOwnerIterator = [ObjectEndpointIterator]::new($authorizer,$APOwnerUrl)
$log.debug("APOwnerIterator: $APOwnerIterator")
			$script:APOwnerIdentityObj = $APOwnerIterator.executeQueryForSingleObject("Looking up Identity '$NEW_ACCESS_PROFILE_OWNER_NAME'")
			$log.trace("Proof of execution - APOwnerIterator.lastQueryDescription: $($APOwnerIterator.lastQueryDescription)")
		} catch {
			$log.fatal("Error getting Access Profile-owning Identity '$NEW_ACCESS_PROFILE_OWNER_NAME': " + [Logger]::getLoggableMultilineErrorString($_))
			exit
		}



exit;
	#>
#>

<# TESTING class SearchQueryResultObjectStructure 

	$log.warning("TESTING class SearchQueryResultObjectStructure")

	$includeNested = $false
	$includeAttributesInDotNotation = @("*Name", "id")
	$excludeAttributesInDotNotation = @("name")
	
	$log.info("includeNested: $includeNested")
	$log.info("includeAttributesInDotNotation: $includeAttributesInDotNotation")
	$log.info("excludeAttributesInDotNotation: $excludeAttributesInDotNotation")

	$queryResultFilterAllParams = [SearchQueryResultObjectStructure]::new($includeNested, $includeAttributesInDotNotation, $excludeAttributesInDotNotation)
	$log.debug("queryResultFilterAllParams: $($queryResultFilterAllParams -replace "`n","`n`t")")

	$queryResultFilterBothIncludeNestedAndSomeAttributes = [SearchQueryResultObjectStructure]::new($includeNested, $includeAttributesInDotNotation)
	$log.debug("queryResultFilterBothIncludeNestedAndSomeAttributes: $($queryResultFilterBothIncludeNestedAndSomeAttributes -replace "`n","`n`t")")

	$queryResultFilterIncludeNestedOnly = [SearchQueryResultObjectStructure]::new($includeNested)
	$log.debug("queryResultFilterIncludeNestedOnly: $($queryResultFilterIncludeNestedOnly -replace "`n","`n`t")")
	
	$queryResultFilterDefault = [SearchQueryResultObjectStructure]::new()
	$log.debug("queryResultFilterDefault: $($queryResultFilterDefault -replace "`n","`n`t")")

#>

<# TESTING class SearchQueryIteratory
	$log.warning("TESTING class SearchQueryIteratory")
	
	$configPropertyToVarNameMap = @{
		orgname = "orgname"
		ClientID = "ClientID"
		ClientSecret = "ClientSecret"
	}
	Load-ConfigJSONIntoScriptVariables -path "${PSScriptRoot}\config.json" -configPropertyToVarNameMap $configPropertyToVarNameMap

	$authorizer = [Authorizer]::new($orgname, $ClientID, $ClientSecret)

		<# GENERATE COMMON VALUES 
			$log.warning("Generating common values")
			$searchQuery = "lastName:sand*"
			# $searchQuery = "attributes.sourceName: `"Active Directory`""
			$objectType = [SearchQueryIndex]::identities
			$sorters = @("lastName", "firstName", "id")
			$includeNested = $false
			$includeAttributesInDotNotation = @("id", "name", "*Name")
			$excludeAttributesInDotNotation = @("*displayName")
			$queryResultStructure = [SearchQueryResultObjectStructure]::new($includeNested, $includeAttributesInDotNotation, $excludeAttributesInDotNotation)
			$log.info("includeNested: $includeNested") # default value is true, so false is a useful initialization test value.
			$log.info("includeAttributesInDotNotation: $includeAttributesInDotNotation")
			$log.info("excludeAttributesInDotNotation: $excludeAttributesInDotNotation")
			$log.debug("queryResultStructure: [$($queryResultStructure.getType())]`n`t$((($queryResultStructure | fl | Out-String)-replace "`n","`n`t").Trim())")


			<# TESTING CONSTRUCTOR FAILURES
				$log.warning("TESTING Constructor - EXPECT FAILURES")
				# $searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQuery, $objectType, $sorters, $queryResultStructure)

				$log.info("This should fail based on lacking minimum params: authorizer")
				try {
					$searchQueryIterator = [SearchQueryIterator]::new($null, $searchQuery)
					$log.trace("searchQueryIterator: $searchQueryIterator")
				} catch {
					$log.error([Logger]::getLoggableMultilineErrorString($_))
				}

				$log.info("This should fail based on lacking minimum params: searchQuery")
				try {
					$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $null)
					$log.trace("searchQueryIterator: $searchQueryIterator")
				} catch {
					$log.error([Logger]::getLoggableMultilineErrorString($_))
				}

				$log.info("This should fail based on sorters array not containing only strings")
				try {
					$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQuery, @("lastName", "firstName", 999))
					$log.trace("searchQueryIterator: $searchQueryIterator")
				} catch {
					$log.error([Logger]::getLoggableMultilineErrorString($_))
				}

				$log.info("This should fail GRACEFULLY based on empty sorters array to default sorter")
				try {
					$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQuery, @())
					$log.trace("searchQueryIterator: $searchQueryIterator")
				} catch {
					$log.error([Logger]::getLoggableMultilineErrorString($_))
				}
			#>

			
			<# TESTING CONSTRUCTOR SUCCESS - ALL OVERLOAD SIGNATURES
				$log.warning("TESTING All Constructor Overloads - EXPECT SUCCESS")
				$constructorInvocationPrefix = '$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQuery'
				foreach ($optionalParamPresenceFlagSums in 7..0) {
					# $log.info("optionalParamPresenceFlagSums: $optionalParamPresenceFlagSums")
					$binaryString = [convert]::ToString($optionalParamPresenceFlagSums,2).PadLeft(3, "0")
					# $log.debug("binaryString: $binaryString")
					$optionalParamPresenceFlags = $binaryString -split '' | Select -index (1..$binaryString.Length) | ForEach-Object { [bool] ([int] $_) }
					# $log.debug("optionalParamPresenceFlags: $optionalParamPresenceFlagSums, [$optionalParamPresenceFlags]")
					
					$optionalParamString = ( @(
						(?: {$optionalParamPresenceFlags[0]} {"objectType"} {$null}),
						(?: {$optionalParamPresenceFlags[1]} {"sorters"} {$null}),
						(?: {$optionalParamPresenceFlags[2]} {"queryResultStructure"} {$null})
					) | Where-Object { $_ -ne $null }) -join ', $'
					
					$constructorCommand = $constructorInvocationPrefix + (?: {$optionalParamString} {', $' + $optionalParamString} {''} ) + ")"
					
					$log.info("searchQuery: $searchQuery")
					$log.info("objectType: $objectType")
					$log.info("sorters: $sorters")
					$log.debug("queryResultStructure: [$($queryResultStructure.getType())]`n`t$((($queryResultStructure | fl | Out-String)-replace "`n","`n`t").Trim())")

					$log.warning("binaryString: $binaryString")
					$log.warning("constructorCommand: $constructorCommand")
					try {
						Invoke-Expression $constructorCommand
$global:iterator = $searchQueryIterator
						$log.trace("searchQueryIterator: $searchQueryIterator")
						$queryBody = $searchQueryIterator.generateSearchQueryBody()
						$log.debug("QUERY BODY:`n${queryBody}")
					} catch {
						$log.error([Logger]::getLoggableMultilineErrorString($_))
						continue;
					}
					
				}
			#>
				
				
			<# TESTING EXECUTION OVERLOADS
				$log.warning("TESTING executeQuery method for all-params Iterator [4 overloads]")

				$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQuery, $objectType, $sorters, $queryResultStructure)
				
				try{
					$log.debug("executing no params")
					$searchQueryIterator.executeQuery()
					$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")

					$log.debug("executing bool only (false) - no progress indicator")
					$searchQueryIterator.executeQuery($false)
					$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")

					$log.debug("executing progressBarActivityName only")
					$searchQueryIterator.executeQuery("String only: Searching Identities | lastName:sand*")
					$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")

					$log.debug("executing while explicitly setting both params: showProgressIndicators=true & progressBarActivityName")
					$searchQueryIterator.executeQuery($true, "Both Params: Searching Identities | lastName:sand*")
					$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")
				} catch {
					$log.error([Logger]::getLoggableMultilineErrorString($_))
					continue;
				}
			#>
		<# TESTING SEARCH QUERY DIFFERENCES #>

<#
			$log.warning("TESTING Different nested vs non-nested Search Query - ALL IDENTITIES ")
			$searchQueryAll = "*"
			
			$log.info("Testing non-nested")
			try {
				$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQueryAll, $objectType, $sorters, $queryResultStructure)
				$searchQueryIterator.executeQuery("Getting NON-nested identities. PAGE SIZE: $($searchQueryIterator.pageSize)")
				$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
				continue;
			}
			
			$log.info("Testing nested")
			$queryResultStructureWithNesting = [SearchQueryResultObjectStructure]::new($true, $includeAttributesInDotNotation, $excludeAttributesInDotNotation)
			try {
				$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQueryAll, $objectType, $sorters, $queryResultStructureWithNesting)
				$searchQueryIterator.executeQuery("Getting NESTED identities. PAGE SIZE: $($searchQueryIterator.pageSize)")
				$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
				continue;
			}
#>
			$includeAttributesInDotNotationForAccessOwners = @("id", "name", "*Name", "acc*ame")
			$searchQueryAccessCount = "accessCount:>0"
<#			
			$log.warning("TESTING Different nested vs non-nested Search Query - IDENTITIES WITH ACCESS ITEMS")
			
			$log.info("Testing non-nested")
			$queryResultStructureAccessItemsNonNested = [SearchQueryResultObjectStructure]::new($false, $includeAttributesInDotNotationForAccessOwners)
			try {
				$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQueryAccessCount, $objectType, $sorters, $queryResultStructureAccessItemsNonNested)
				$searchQueryIterator.executeQuery("Getting NON-nested identities. PAGE SIZE: $($searchQueryIterator.pageSize)")
				$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
				continue;
			}
	#>		
			$log.info("Testing nested")
			$queryResultStructureAccessItemsNested = [SearchQueryResultObjectStructure]::new($true, $includeAttributesInDotNotationForAccessOwners)
			try {
				$searchQueryIterator = [SearchQueryIterator]::new($authorizer, $searchQueryAccessCount, $objectType, $sorters, $queryResultStructureAccessItemsNested)
# $global:iterator = $searchQueryIterator
				$searchQueryIterator.executeQuery("Getting NESTED identities. PAGE SIZE: $($searchQueryIterator.pageSize)")
				$log.trace("searchQueryIterator [$($searchQueryIterator.count())]: $searchQueryIterator")
			} catch {
				$log.error([Logger]::getLoggableMultilineErrorString($_))
				continue;
			}
			
			# $al = [System.Collections.ArrayList]::new($searchQueryIterator.count());
			# $sum = 0; while($searchQueryIterator.hasNext()){ [void] $al.add($searchQueryIterator.next()); $sum++ }
			$identitiesWithAccess = $searchQueryIterator.generateObjectArray(@("lastName", "firstname", "manager.displayName", "access.name"))
			$log.debug("identitiesWithAccess: [$($identitiesWithAccess.count)]`n$($identitiesWithAccess | select -first 3 -last 3 | ft | out-string)")
#>