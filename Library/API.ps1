# This line is critical to HTTPS functionality, so we include it in the API library
[void] [Net.SecurityProtocolType]::Tls12

# This statement provides access to Where-ObjectFast
. $PSScriptRoot\IterationUtils.ps1

<## @function Load-ConfigJSONIntoScriptVariables
	# @description - This loads properties from the first JSON object in a file containing an array of JSON objects.
	# @param path - a string pointing to the config JSON file - validated for existence
	# @param overwriteExistingValues [optional: default true] - whether or not to clobber existing variable values
	# @param configPropertyToVarNameMap [optional] - a hashtable where the property names are the property names in the JSON object, and the values are what the variable names in the script should be.
	# @returns - [void]
	#>
function Load-ConfigJSONIntoScriptVariables(
	[Parameter(Mandatory)]
	[ValidateScript({Test-Path -Path $_})]
	[String] $path,
	
	[bool] $overwriteExistingValues = $true, # 'clobber' by default
	
	[ValidateNotNull()]
	[Hashtable] $configPropertyToVarNameMap	
)
{
	$config = (Get-Content -Path $path | ConvertFrom-Json)[0]
	
	# determine which properties to load from the config object
	if ($configPropertyToVarNameMap){
		$propertiesToLoad = $configPropertyToVarNameMap.keys
	} else {
		$propertiesToLoad = $config.psobject.properties.name
	}
	
	foreach ($propertyName in $propertiesToLoad){
		# determine what the variable should be called
		if ($configPropertyToVarNameMap){
			$varName = $configPropertyToVarNameMap.$propertyName
		} else {
			$varName = $propertyName
		}
		
		$alreadyLoaded = [bool](get-variable $propertyName -ErrorAction SilentlyContinue)
		if ($overwriteExistingValues -or -not $alreadyLoaded){ # load the config property
			if ($overwriteExistingValues -and $alreadyLoaded){
				# clear variable name first to avoid an error when invoking new-variable.
				Remove-Variable -Name $varName -Scope Script				
			}
			New-Variable -Name $varName -Value $config.$propertyName -Scope Script
		}
	}
}

function getUsefulErrorCodes([System.Management.Automation.ErrorRecord] $apiError){
	$messageObj = $apiError.ErrorDetails.Message | ConvertFrom-Json
	if ($messageObj.DetailCode){ # Detail Code == HTTP Code
		$usefulErrorCode = $messageObj.DetailCode
		$usefulMessages = $messageObj.messages | Select-Object -ExpandProperty text -Unique
		if ($usefulMessages){ $usefulErrorCode += " - $usefulMessages" }
	} elseif ($messageObj.errorName) {
		$usefulErrorCode = $messageObj.errorName + " - " + $messageObj.errorMessage
	}
	return $usefulErrorCode
}


<## @class Authorizer
	# @description - simple class that generates a Header Hashtable and manages the expiration state
	#>
class Authorizer{
	
	### HIDDEN INSTANCE PROPERTIES ###
	
	hidden [String] $orgName
	hidden [String] $clientID
	hidden [String] $clientSecret
	hidden [DateTime] $expirationDate # defaults to midnight NYD 2001.
	hidden [Hashtable] $header
	hidden [bool] $silent = $false
	
	
	### CONSTRUCTORS ###
	
	<## @constructor Authorizer
		# @description - instantiates an [Authorizer] object for use with the SailPoint API which keeps track of the Header hashtable for use with Invoke-RestMethod and the v3token's expiration time. 2 overloads.
		# @param orgName - the tenant subdomain for your org, i.e.: <orgname>.api.identitynow.com
		# @param clientID - the ClientID from your API token
		# @param clientSecret - the clientSecret from your API token
		# @param silent [optional: default true] - Whether to report on the status of Authorizer's actions via Write-Host
		#>
	
	Authorizer(
		[String] $orgName,
		[String] $clientID,
		[String] $clientSecret
	){
    foreach ($paramName in @("orgName","clientID", "clientSecret")){
			$param = Get-Variable -name $paramName
			if ($param.Value -eq $null -or $param.Value -eq ""){
				throw "[Authorizer]::Authorizer() - Parameter '$paramName' must have be a non-empty string"
			}
			$this.$paramName = $param.value
    }
	}	
	
	Authorizer(
		[String] $orgName,
		[String] $clientID,
		[String] $clientSecret,
		[bool] $silent
	){
    foreach ($paramName in @("orgName","clientID", "clientSecret")){
			$param = Get-Variable -name $paramName
			if ($param.Value -eq $null -or $param.Value -eq ""){
				throw "[Authorizer]::Authorizer() - Parameter '$paramName' must have be a non-empty string"
			}
			$this.$paramName = $param.value
    }
		if ($silent -is [bool]){
			$this.silent = $silent
		} else {
			throw "[Authorizer]::Authorizer() - Optional parameter 'silent' must be a boolean"
		}
	}
	
	### INSTANCE METHODS ###
	
	<## @method getHeader
		# @returns - [HashTable] - this can be passed to the -Headers flag of Invoke-WebRequest and Invoke-RestMethod
		#>
	[Hashtable] getHeader(){
		if ($this.header -ne $null){ # this has been called before.
		
			# If there's a minute or more left, return the same Header
			if ([Math]::round(($this.expirationDate - (Get-Date)).totalMinutes) -ge 1){
				return $this.header # don't have to null-check this, as it will be guaranteed to exist during any call in which $expirationDate is not null.
			} elseif ( -Not $this.silent ) {
				Write-Host -ForegroundColor Black -BackgroundColor Red "In [Authorizer].getHeader: Token will expire in less than a minute. Will reacquire."
			}
		}
		
		$TokenBody = "grant_type=client_credentials&client_id=$($this.clientID)&client_secret=$($this.clientSecret)"
		$oAuthURI = "https://$($this.orgname).api.identitynow.com/oauth/token?$TokenBody"

		$tokenAcquistionTime = Get-Date
		try {
			if ( -Not $this.silent ) {
				Write-Host -ForegroundColor Green -NoNewLine "In [Authorizer].getHeader: Obtaining JWT ..."
			}
			$v3Token = Invoke-RestMethod -Uri $oAuthURI -Method POST -Body $TokenBody
			$this.header = @{Authorization = "Bearer $($v3Token.access_token)"}
			if ( -Not $this.silent ) {
				Write-Host -ForegroundColor Green " complete."
			}
			$this.expirationDate = $tokenAcquistionTime.AddSeconds($v3Token.expires_in)
		} catch { Write-Error $_ }
		
		return $this.header
	}
	
	
	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		return ([PSCustomObject]@{
			orgName =  $this.orgName
			clientID =  $this.clientID
			clientSecret =  $(if ($this.clientSecret -eq $null) {"NULL"} else {"<NON-NULL SECRET>"})
			expirationDate =  $this.expirationDate
			header =  $this.header
			silent =  $this.silent
		} | fl | Out-String).Trim() -replace "^","`r`n"
	}
}


<## @class ObjectEndpointQuery
	# @description - Container class that holds a representation of the details of the an Object endpoint query, used in [ObjectEndpointIterator]
	#>
class ObjectEndpointQuery {

	### HIDDEN STATIC PROPERTIES ###
	
	hidden static [String[]] $MINIMUM_REQUIRED_URL_COMPONENTS = @("orgName", "version", "objectType") # matches named groups in the regex used in parseQuery method
	
	### INSTANCE PROPERTIES ###
	
	[String] $orgName
	[String] $version
	[String] $objectType
	[PSCustomObject] $paramTable # can be null
	
	### STATIC METHODS ###

	<## @method urlDecode
		# @static
		# @description - decodes URL-encoded characters from a string. This method is safe to use on already-decoded URLs
		# @param - url - a url (encoded or decoded)
		# @returns - [String] - decoded url string
		#>
	static [String] urlDecode ([String] $url){
		return [System.Net.WebUtility]::UrlDecode($url)
	}

	### HIDDEN STATIC METHODS ###
	
	<## @method parseQuery
		# @static
		# @hidden
		# @description - called by [ObjectEndpointQuery] constructors. Turns an IdentityNow API query URL into a [PSCustomObject], letting the constructor put any finishing touches on it. (Usually, adding [Hashtable] queryParams).
		# @param - decodedUrl - a plaintext query URL against the IdentityNow API
		# @returns - [PSCustomObject] - a vanilla object representing the decoded query URL
		#>
	hidden static [PSCustomObject] parseQuery ([String] $decodedQueryUrl){
		$queryObject = $null # return value
# Write-Host -BackgroundColor DarkGreen "ObjectEndpointQuery(): decodedQueryUrl: $decodedQueryUrl"
		
		# $decodedQueryUrl -match "https://(?<orgname>[\w-]+).api.identitynow.com(\/(?<version>\w+)(\/(?<objectType>[\w-]+)(\?(?<queryParams>.+)|)|)|)"
		$decodedQueryUrl -match "https://(?<orgname>[\w-]+).api.identitynow.com(\/(?<version>\w+)(\/(?<objectType>[^?]+)(\?(?<queryParams>.+)|)|)|)"
		if ($matches){
			$queryObject = [PSCustomObject] $matches | Select-Object -Property ([ObjectEndpointQuery]::MINIMUM_REQUIRED_URL_COMPONENTS)
			
			if ($matches.queryParams){
				[ObjectEndpointQuery]::parseQueryParamsAndAddToQueryObject($matches.queryParams, $queryObject)
			}
		}
		return $queryObject
	}	


	<## @method parseQueryParamsAndAddToQueryObject
		# @static
		# @hidden
		# @description - parses a string containing the query params part of the URL and turns in into a param table PSCustomObject which gets added to the provided queryObject param. This code is split off from parseQuery because some of the constructor overloads add a [HashTable] paramTable themselves.
		# @param - queryParams - should be everything after but not including the "?" (the query symbol in the URL). Example: 'sorters=name&filters=name eq "Workday"'
		# @param - queryObject - the [PSCustomObject] being generated in parseQuery
		# @throws - this function runs no validation on queryParams, so an error will result if the queryParams string is malformed.
		# @returns - [PSCustomObject] - the queryObject with a paramTable property added.
		#>
	hidden static [PSCustomObject] parseQueryParamsAndAddToQueryObject ([String] $queryParams, [PSCustomObject] $queryObject){
		$local:paramTable = @{}
		$paramStrings = $queryParams -split "&"
		foreach ($paramString in $paramStrings) {
			if ($paramString -match "(?<param>[\w-]+)=(?<value>.*)") {
				$paramTable[$matches.param] = $matches.value
			}
		}

		[ObjectEndpointQuery]::addParamTableToQueryObject($paramTable, $queryObject)

		return $queryObject
	}
	
	<## @method addParamTableToQueryObject
		# @static
		# @hidden
		# @description - takes a paramTable as a Hashtable, turns it into a PSCustomObject and adds it to the queryObject PSCustomObject. Called by parseQueryParamsAndAddToQueryObject and constructors that take a [HashTable]
		# @param - paramTable - a HashTable that represents the query params as key: value pairs.
		# @param - queryObject - a [PSCustomObject] either being generated by parseQuery or passed to this method by a constructor.
		# @returns - [PSCustomObject] - the queryObject with a paramTable property added.
		#>
	hidden static [void] addParamTableToQueryObject ([Hashtable] $paramTable, [PSCustomObject] $queryObject){
		$queryObject | Add-Member -MemberType NoteProperty -Name 'paramTable' -Value ([PSCustomObject] $paramTable) # This guarantees a paramTable, even if it contains no properties
	}

	<## @method validate
		# @static
		# @hidden
		# @description - validates that a queryObject, once constructed, has non-empty values for the keys in the static property [ObjectEndpointQuery]::MINIMUM_REQUIRED_URL_COMPONENTS
		# @param - queryObject - the [PSCustomObject] being generated by a constructor
		# @throws - [System.Management.Automation.RuntimeException] - Throws an error if validation fails
		# @returns - [bool] - whether validation passed. Note, if this method returns anything, it will be $true, because otherwise an exception would have been thrown already.
		#>
	hidden static [bool] validate([PSCustomObject] $queryObject){
# Write-Host -ForegroundColor Cyan "validate(): queryObject null? $($queryObject -eq $null)"
# Write-Host -ForegroundColor Magenta "validate(): $queryObject"
		$componentsFailingValidation = @()
		foreach ($component in [ObjectEndpointQuery]::MINIMUM_REQUIRED_URL_COMPONENTS){
			if ($queryObject.$component -eq $null -or $queryObject.$component -eq ""){
				$componentsFailingValidation += $component
			}
		}
		
		# Conjugate the verb 'to be' and decline the suffixes for the exception message.
		if ($componentsFailingValidation.count){
			if ($componentsFailingValidation.count -gt 1) { # pluralize
				$componentWordSuffix = "s"
				$toBeConjugated = "were"
			} else { # singularize
				$componentWordSuffix = ""
				$toBeConjugated = "was"
			}
			
			throw ("The following required query URL component{0} {1} null or empty: '{2}'." `
				-f $componentWordSuffix, $toBeConjugated, ($componentsFailingValidation -join ' | ')
				)
		}
		return $true;
	}

	### CONSTRUCTORS ###

	<## @constructor ObjectEndpointQuery
		# @description - instantiates an [ObjectEndpointQuery] object which represents a query against the SailPoint API. 5 overloads with different signatures.
		# @param fullQueryUrl - the complete query URL, URL-encoded or not.
		# @param objectEndpointUrl - the complete query URL, URL-encoded or not. Must contain the [ObjectEndpointQuery]::MINIMUM_REQUIRED_URL_COMPONENTS.
		# @param orgName - the tenant subdomain for your org, i.e.: <orgname>.api.identitynow.com
		# @param versionPathSegment - the path segment representing the version (e.g.: v3, beta, etc)
		# @param objectEndpointPathSegment - the path segment representing the objects being queried (e.g.: sources, access-profiles, etc.)
		# @param queryParams - two formats: [String] should be everything after but not including the "?" (the query symbol in the URL). Example: 'sorters=name&filters=name eq "Workday"' or [HashTable] representing the same information contained in the "key=value" pairs.
		#>

	ObjectEndpointQuery([String] $fullQueryUrl){
		$parseableUrl = [ObjectEndpointQuery]::urlDecode($fullQueryUrl)
# Write-Host -ForegroundColor Green "ObjectEndpointQuery(): fullQueryUrl: $fullQueryUrl"
# Write-Host -ForegroundColor Green "ObjectEndpointQuery(): parseableUrl: $parseableUrl"
		$queryObject = [ObjectEndpointQuery]::parseQuery($parseableUrl)
# Write-Host -ForegroundColor Cyan "ObjectEndpointQuery(): queryObject null? $($queryObject -eq $null)"
# Write-Host -ForegroundColor Magenta "ObjectEndpointQuery(): $queryObject"
		
		if ([ObjectEndpointQuery]::validate($queryObject)){
			foreach ($propertyName in ($queryObject.psobject.Properties.name)){
				$this.$propertyName = $queryObject.$propertyName
			}
		}
	}
	
	ObjectEndpointQuery([String] $objectEndpointUrl, [String] $queryParams){
		$parseableUrl = [ObjectEndpointQuery]::urlDecode("${objectEndpointUrl}?$queryParams")
		$queryObject = [ObjectEndpointQuery]::parseQuery($parseableUrl)
		
		if ([ObjectEndpointQuery]::validate($queryObject)){
			foreach ($propertyName in ($queryObject.psobject.Properties.name)){
				$this.$propertyName = $queryObject.$propertyName
			}
		}
	}

	ObjectEndpointQuery([String] $objectEndpointUrl, [Hashtable] $queryParams){
		$parseableUrl = [ObjectEndpointQuery]::urlDecode($objectEndpointUrl)
		$queryObject = [ObjectEndpointQuery]::parseQuery($parseableUrl)

		[ObjectEndpointQuery]::addParamTableToQueryObject($queryParams, $queryObject)
		
		if ([ObjectEndpointQuery]::validate($queryObject)){
			foreach ($propertyName in ($queryObject.psobject.Properties.name)){
				$this.$propertyName = $queryObject.$propertyName
			}
		}		
	}

	ObjectEndpointQuery([String] $orgname, [String] $versionPathSegment, [String] $objectEndpointPathSegment, [String] $queryParams){
		$fullQueryUrl = "https://$orgName.api.identitynow.com/$versionPathSegment/${objectEndpointPathSegment}?$queryParams"
		$parseableUrl = [ObjectEndpointQuery]::urlDecode($fullQueryUrl)
		$queryObject = [ObjectEndpointQuery]::parseQuery($parseableUrl)
		
		if ([ObjectEndpointQuery]::validate($queryObject)){
			foreach ($propertyName in ($queryObject.psobject.Properties.name)){
				$this.$propertyName = $queryObject.$propertyName
			}
		}
	}

	ObjectEndpointQuery([String] $orgname, [String] $versionPathSegment, [String] $objectEndpointPathSegment, [Hashtable] $queryParams){
		$objectEndpointUrl = "https://$orgName.api.identitynow.com/$versionPathSegment/${objectEndpointPathSegment}"
		$parseableUrl = [ObjectEndpointQuery]::urlDecode($objectEndpointUrl)
		$queryObject = [ObjectEndpointQuery]::parseQuery($parseableUrl)

		[ObjectEndpointQuery]::addParamTableToQueryObject($queryParams, $queryObject)
		
		if ([ObjectEndpointQuery]::validate($queryObject)){
			foreach ($propertyName in ($queryObject.psobject.Properties.name)){
				$this.$propertyName = $queryObject.$propertyName
			}
		}		
	}

	### INSTANCE METHODS ###
	
	<## @method getObjectEndpointUrl
		# @description - returns the URL of the object endpoint part of the query represented by this [ObjectEndpointQuery]
		# @returns - [String] - the URL of the object endpoint query (EXCLUDING the query parameters)
		#>
	[String] getObjectEndpointUrl(){
		return "https://$($this.orgName).api.identitynow.com/$($this.version)/$($this.objectType)"
	}
	
	<## @method getQueryUrl
		# @description - returns the full URL of the query represented by this [ObjectEndpointQuery]
		# @returns - [String] - the URL of the query (INCLUDING the query parameters)
		#>
	[String] getQueryUrl(){
		$url = $this.getObjectEndpointUrl()

		$paramCount = ($this.paramTable | Get-Member -MemberType NoteProperty).count
		if ($paramCount){
			$paramStrings = [System.Collections.ArrayList]::new($paramCount)
			foreach ($propertyName in ($this.paramTable.psobject.Properties.name)){
				$paramStrings.add(("{0}={1}" -f $propertyName, $this.paramTable.$propertyName))
			}
			$url += "?{0}" -f ($paramStrings -join "&")
		}
		
		return $url
	}

	<## @method cloneWithDifferentParams
		# @description - shallow-copies this [ObjectEndpointQuery] with some differences in the parameters and returns a new [ObjectEndpointQuery]
		# @param - paramNamesToRemove - [String[]] of the names of the parameters to EXCLUDE from the query
		# @param - paramsToAddOrReplace - [Hashtable] of the new values for query params. If a param key wasn't including in the original query, it will be added in the copy.
		# @returns - [ObjectEndpointQuery] - a new query with the same objectEndpointUrl and potentially-different query params.
		#>
	[ObjectEndpointQuery] cloneWithDifferentParams([String[]] $paramNamesToRemove, [Hashtable] $paramsToAddOrReplace){
		$endpointUrl = $this.getObjectEndpointUrl()
		
		$newParamTable = @{}
		if ($this.paramTable -ne $null){
			foreach ($paramName in ($this.paramTable.psobject.Properties.name)){
				$newParamTable.$paramName = $this.paramTable.$paramName
			}
		}
		
		foreach ($paramName in $paramNamesToRemove){
			if ($newParamTable.ContainsKey($paramName)){
				$newParamTable.remove($paramName)
			}
		}
		
		foreach ($paramName in $paramsToAddOrReplace.Keys){
			$newParamTable.$paramName =  $paramsToAddOrReplace.$paramName
		}
		
		return [ObjectEndpointQuery]::new($endpointUrl, $newParamTable)
	}

	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		if ($this.paramTable -eq $null) {
			$paramTableRepresentation = "NULL"
		} else {
			$paramTableRepresentation = ($this.paramTable | fl | Out-String) -replace "^`r`n",""
		}

		$ObjectEndpointQueryRepresentation = [PSCustomObject]@{
			orgName = $this.orgName
			version = $this.version
			objectType = $this.objectType
			paramTable = $paramTableRepresentation
		}

		return ($ObjectEndpointQueryRepresentation | fl | Out-String).Trim() -replace "^","`r`n"
	}

}


# SEARCH DOCUMENT

<## @class ObjectIterator
	# @description -  unopinionated class that serves as a class Interface to iterate the results of an /object endpoint in the IDN API. No constructors are defined, so the only one that exists is a no-arg constructor. You should never directly instantiate this class, but instead instances
	# @subclasses - ObjectEndpointIterator, MergedObjectEndpointIterator
	#>
class ObjectIterator {

	### HIDDEN STATIC METHODS ###
	
	<## @method convertFilterFromPSItemToInputVariable
		# @static
		# @hidden
		# @description - Replaces all instances of '$_' with '$Input' so that it can be used with the Invoke-Command cmdlet. CAUTION: this replaces ALL instances, so if the transformFilter has nested cmdlets, they should not use generateObjectArray, and use the generateObjectArrayWithInputTransforms
		# @param - filter - a [ScriptBlock] using the $_ automatic variable.
		# @returns - [ScriptBlock] - the modified $filter argument
		#>
	hidden static [ScriptBlock] convertFilterFromPSItemToInputVariable([ScriptBlock] $filter){
		return [ScriptBlock]::Create($filter.ToString().replace('$_','$Input'))
	}

	<## @method convertFilterTableForUseWithInvokeCommand
		# @static
		# @hidden
		# @description - Replaces all instances of '$_' with '$Input' in a [PSCustomObject] made up of [ScriptBlock] members, so that it can be used with the Invoke-Command cmdlet. CAUTION: this replaces ALL instances, so if the transformFilter has nested cmdlets, they should not use generateObjectArray, and use the generateObjectArrayWithInputTransforms
		# @param - filterTable - a [PSCustomObject] whose member properties are all [ScriptBlock]s using the $_ automatic variable.
		# @returns - [PSCustomObject] - a copy of the $filterTable argument with the members modified
		#>
	hidden static [PSCustomObject] convertFilterTableForUseWithInvokeCommand([PSCustomObject] $filterTable){
		$invokeCommandFilterTable = $filterTable | Select-Object *
		foreach ($propertyName in ($invokeCommandFilterTable.psobject.Properties.name)){
			$invokeCommandFilterTable.$propertyName = [ObjectIterator]::convertFilterFromPSItemToInputVariable($filterTable.$propertyName)
		}
		return $invokeCommandFilterTable
	}
	
	<## @method generateFilterTableFromObjectAttributesInDotNotation
		# @static
		# @hidden
		# @description - A convenience function for when all the properties you want to pull can be described in simple dot notation. Creates a Filter table whose properties are all camel-cased version of the object attribute. Example: source.name creates a filter {$_.source.name} whose property name in the resulting [PSCustomObject] is 'sourceName'.
		# @param - objectAttributesInDotNotation - [String[]] which define which object attributes to pull into the filterTable. Example: @("id", "name", "source.id", "source.name").
		# @returns - [PSCustomObject] - a simple Filter table in '$_' form which can be passed to the generateObjectArray method
		#>
	hidden static [PSCustomObject] generateFilterTableFromObjectAttributesInDotNotation([String[]] $objectAttributesInDotNotation){
		$filterTable = [ordered]@{} # return value (in ordered HashTable form)

		foreach ($objectAttribute in $objectAttributesInDotNotation){
			$pathComponents = $objectAttribute.ToLower() -split "\."
			for ($i=1; $i -lt $pathComponents.count; $i++){ # skip the first path component when capitalizing
				$pathComponents[$i] = $pathComponents[$i].Substring(0,1).toUpper() + $pathComponents[$i].Substring(1)
			}
			$propertyName = $pathComponents -join ""
			$filterTable.$propertyName = [ScriptBlock]::Create("`$_.$objectAttribute")
		}
		return [PSCustomObject]$filterTable
	}	
	
	### INSTANCE PROPERTIES ###
	
	[System.Collections.ArrayList] $ids = [System.Collections.ArrayList]::new()
	[Hashtable] $objects = @{}
	[int] $index = 0 # used by the iteration method next()
	[ScriptBlock] $postQueryFilter
	
	### INSTANCE METHODS ###

	<## @method getObjectById
		# @description - allows for random access by the id (guid)of the object
		# @param - id - [String] id (guid) of the object
		# @throws - throws error for invalid ID (key in $this.objects [Hashtable])
		# @returns - [PSCustomObject] - the SailPoint Object
		#>
	[PSCustomObject] getObjectById([String] $id){
		# need to validate that id is valid (if obj is null, check whether ids[] contains it.
		return $this.objects[$id]
	}
	
	<## @method getObjectByIndex
		# @description - allows for random access by the index of the object in the ids member
		# @param - index - [int] index of the object in the ids member
		# @throws - throws error for invalid index (in $this.ids [ArrayList])
		# @returns - [PSCustomObject] - the SailPoint Object
		#>
	[PSCustomObject] getObjectByIndex([int] $index){
		return $this.objects[$this.ids[$index]]
	}

	<## @method getObjectsAsArray
		# @description - Convenience method to get untransformed objects back in an easily-iterable fashion
		# @returns - [Object[]] - array of objects transformed according to the $invokeCommandFilterTable argument.
		#>
	[Object[]] getObjectsAsArray(){
		return $this.ids | ForEach-ObjectFast { $this.getObjectById($_) }
	}

	<## @method count
		# @description - gets the number of objects returned by the last call to executeQuery 
		# @returns - [int] - the number of objects
		#>
	[int] count(){
		return $this.ids.count
	}

	<## @method reset
		# @description - sets the index member property back to zero so iteration can begin again without making more network calls.
		# @returns - [void]
		#>
	[void] reset(){
		$this.index = 0
	}

	<## @method hasNext
		# @description - Whether iteration is complete
		# @returns - [bool] - whether a call to next() will return a SailPoint Object (true) or a RuntimeException (false)
		#>
	[bool] hasNext(){
		return $this.index -lt $this.ids.count
	}	
	
	<## @method next
		# @description - The next object in the iterator
		# @throws - [System.Management.Automation.RuntimeException] - throws after the count()-th call, when hasNext returns false
		# @returns - [bool] - whether a call to next() will return a SailPoint Object (true) or a RuntimeException (false)
		#>
	[PSCustomObject] next(){
		if ($this.index -ge $this.ids.count){
			throw "Iterator exhausted. Please use hasNext() to check exhaustion or reset() before reiterating."
		}		
		return $this.getObjectByIndex($this.index++)
	}

	<## @method filterResults
		# @description - lets you apply a filter to the results, where $_ represents the object. This permanently mutates the stored results to speed iteration, and populates the postQueryFilter member property. Useful when the pre-built filters don't provide enough specificity. To undo, just executeQuery on the relevant subclass instance again.
		# @param - filter - [ScriptBlock] the Powershell filter to apply.
		# @returns - [void]
		#>
	[void] filterResults([ScriptBlock] $filter){
		$filteredIds = ($this.ids | Foreach-ObjectFast {$this.objects[$_]} | where-objectfast $filter).id
		$filteredIdList = [System.Collections.ArrayList]::new()
		if ($filteredIds -ne $null){
			if ($filteredIds -is [Array]){
				$filteredIdList.addRange($filteredIds)
			} else {
				$filteredIdList.add($filteredIds)
			}
		}
		$newObjectTable = @{}
		foreach ($id in $filteredIdList){
			$newObjectTable.$id = $this.objects[$id]
		}
		$this.ids = $filteredIdList
		$this.objects = $newObjectTable
		$this.postQueryFilter = $filter
	}
	
	<## @method generateObjectArray
		# @description - Transforms the objects represented by this iterator (in query results order) into an array of Objects specified by the filter member properties in the $filterTable argument which all use the '$_' automatic variable. CAUTION: if the transformFilter has nested cmdlets, where '$_' can mean multiple things during code execution, they should not use generateObjectArray, and use the generateObjectArrayUsingInputVariable instead.
		# @param - filterTable - a [PSCustomObject] whose member properties are all [ScriptBlock]s using the $_ automatic variable.
		# @returns - [Object[]] - array of objects transformed according to the $filterTable argument.
		#>
	[Object[]] generateObjectArray ([PSCustomObject] $filterTable){
		$invokeCommandFilterTable = [ObjectIterator]::convertFilterTableForUseWithInvokeCommand($filterTable)
		
		return $this.generateObjectArrayUsingInputVariable($invokeCommandFilterTable)
	}

	### QUICK HACK for generateObjectArray: If you want to create an array of PSCustomObjects, but not all the properties are immediately derivable from the query results, include a property name that does not exist on the result objects. Powershell won't complain, it will just create a property on the returned objects with that name and set it to $null, which is much easier than using Add-Member later.


	# # # # <## @method generateObjectArray
		# # # # # @description - a convenience overload for generateObjectArray([PSCustomObject $filterTable) that turns an array of strings into a simple filter table using the generateFilterTableFromObjectAttributesInDotNotation static method.
		# # # # # @param - objectAttributesInDotNotation - [String[]] which define which object attributes to pull into the filterTable. Example: @("id", "name", "source.id", "source.name") NOTE: to force the parser to pick this overload, you need to cast the argument as [String[]], or it will pick the above method.
		# # # # # @returns - [Object[]] - array of objects transformed according to the filterTable generated according to the $objectAttributesInDotNotation argument.
		# # # # #>
	# # # # [Object[]] generateObjectArray ([String[]] $objectAttributesInDotNotation){
# # # # Write-Host -ForegroundColor Green ("objectAttributesInDotNotation:`n$($objectAttributesInDotNotation | fl | Out-string)")
		# # # # $simpleFilterTable = [ObjectIterator]::generateFilterTableFromObjectAttributesInDotNotation($objectAttributesInDotNotation)
# # # # Write-Host -ForegroundColor Magenta ("simpleFilterTable:`n$($simpleFilterTable | fl | Out-string)")
		
		# # # # return $this.generateObjectArray($simpleFilterTable)
	# # # # }

	<## @method generateObjectArray
		# @description - a convenience overload for generateObjectArray([PSCustomObject] $filterTable) that first checks whether all the members of the array argument are Strings, and then calls the other method.
		# @param - objectAttributesInDotNotation - [String[]] which define which object attributes to pull into the filterTable. Example: @("id", "name", "source.id", "source.name")
		# @throws - exception if the [Object[]] argument isn't a [String[]]
		# @returns - [Object[]] - array of objects transformed according to the filterTable generated according to the $objectAttributesInDotNotation argument.
		#>
	[Object[]] generateObjectArray ([Object[]] $objectAttributesInDotNotation){
		foreach ($objAttr in $objectAttributesInDotNotation){
			if ($objAttr -isNot [String] ) {
				throw "$objAttr is not a [String]. Please ensure all elements of the passed `$objectAttributesInDotNotation array are Strings."
			}
		}
		$simpleFilterTable = [ObjectIterator]::generateFilterTableFromObjectAttributesInDotNotation($objectAttributesInDotNotation)
		return $this.generateObjectArray($simpleFilterTable)
	}

	<## @method generateObjectArrayUsingInputVariable
		# @description - Transforms the objects represented by this iterator (in query results order) into an array of Objects specified by the filter member properties in the $invokeCommandFilterTable argument which all use the '$Input' automatic variable. USE CASE: complex filters, where '$_' can mean multiple things during code execution, so the InputObject should be called "$Input"
		# @param - invokeCommandFilterTable - a [PSCustomObject] whose member properties are all [ScriptBlock]s using the $Input automatic variable.
		# @returns - [Object[]] - array of objects transformed according to the $invokeCommandFilterTable argument.
		#>
	[Object[]] generateObjectArrayUsingInputVariable ([PSCustomObject] $invokeCommandFilterTable){
		return $this.ids | ForEach-ObjectFast { $this.getObjectById($_) } | ForEach-ObjectFast {
			$objectElement = [ordered]@{}

			foreach ($key in ($invokeCommandFilterTable.psobject.Properties.name)){
				$objectElement.$key = Invoke-Command -InputObject $_ -ScriptBlock $invokeCommandFilterTable.$key
			}

			return [PSCustomObject] $objectElement
		}
	}

}


# FUTURE IDEAS FOR [ObjectEndpointIterator]:
# 1. Parse the IDN API docs to get information on valid filters (might be useful, but leans into being opinionated)

<## @class ObjectEndpointIterator
	# @description -  unopinionated class to iterate an /object endpoint in the IDN API. The constructor takes a query and runs it until the API response is exhausted. It maintains an ArrayList of objectIds and a hashtable of objects keyed on those ids. The URLs provided to its constructors can be URL-encoded or not, this class will take care of that.
	#>
class ObjectEndpointIterator : ObjectIterator {

	### HIDDEN STATIC PROPERTIES ###
	
	# Some common endpoints and their documented API page limits, as of August 2023. Used for speedy lookup to avoid an Invoke-WebRequest call to get the size when not equal to COMMON_LOW_LIMIT
	hidden static [Hashtable] $DEFAULT_API_PAGE_LIMITS = @{
		"access-profiles" = 50 # See "TESTING NOTE 1" in Test-Api.ps1 - comment this out
		"access-request-approvals" = 250
		accounts = 250
		entitlements = 250
		identities = 250
		roles = 50
		sources = 250
		workgroups = 50
		COMMON_HIGH_LIMIT = 250 # See "TESTING NOTE 1" in Test-Api.ps1 - change to 251
		COMMON_LOW_LIMIT = 50
	}
	# To guarantee complete and unique results, there must be a sorter. If not supplied, this defaults to id, which can be used by all object types
	hidden static [Hashtable] $DEFAULT_SORTERS = @{
		certifications = "name"
		campaigns = "name"
		default = "id"
	}
	hidden static $DEFAULT_CONTENT_TYPE = "application/json" # common to GET operations in the IDN API

	### INSTANCE PROPERTIES ###
	
	[ObjectEndpointQuery] $queryObject
	[Authorizer] $authorizer
	[String] $lastQueryDescription
	
	### HIDDEN STATIC METHODS ###
	
	# PROGRAMMER NOTE: If one day, SP announces default limits of 250 for all endpoints, the determinePageSizeForObjectType function will still work, but that static method and the static property DEFAULT_API_PAGE_LIMITS should be stripped from this API.ps1 library
	
	<## @method validateAndUpdateQueryPageLimit
		# @static
		# @hidden
		# @description - Validates that the passed $queryObject has a limit query param. If not, it determines the most performant one for that that objectType and mutates the passed queryObject.
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# throws - [System.Management.Automation.RuntimeException] - if validation of the limit query param fails, if one is provided. Validity means that 0 < limit <= DEFAULT_API_PAGE_LIMITS[$objectType]
		# @returns - [ObjectEndpointQuery] - the possibly-modified $queryObject argument
		#>
	hidden static [ObjectEndpointQuery] validateAndUpdateQueryPageLimit ([Authorizer] $authorizer, [ObjectEndpointQuery] $queryObject){
		if ($queryObject.paramTable -eq $null){ # We must guarantee that the queryObject has paramTable for the below logic to work, even if empty.
			$queryObject.paramTable = [PSCustomObject] @{}
		}
		$params = $queryObject.paramTable

		$maxPageSizeForObject = [ObjectEndpointIterator]::determinePageSizeForObjectType($authorizer, $queryObject)

		if ($params.limit -ne $null){
			if ($params.limit -lt 1 -or $params.limit -gt $maxPageSizeForObject) {
				throw "the limit you provided [$($params.limit)] must be between 1 and the maximum (default) limit of $maxPageSizeForObject, inclusive."
			}
			# At this point in the code, we know a limit param was provided, and is valid. Next line is the return statement.
		} else { # if no limit was provided, we should set the limit to the maxPageSizeForObject
			$params | Add-Member -MemberType NoteProperty -Name 'limit' -Value $maxPageSizeForObject
		}
		return $queryObject
	}

	<## @method determinePageSizeForObjectType
		# @static
		# @hidden
		# @description - By default, all SPO endpoints use the documented limit for that endpoint. Experimentally, some of the API endpoints using COMMON_LOW_LIMIT as the default don't obey their documented limits. For example, /access-profiles will default to limit=50 (COMMON_LOW_LIMIT), accept values up to 250 (COMMON_HIGH_LIMIT), and error out on 251. This method first looks up the documented value for common objects. If it doesn't find one in DEFAULT_API_PAGE_LIMITS or finds out that it is equal to the COMMON_LOW_LIMIT, it tries to GET one page using the COMMON_HIGH_LIMIT. If that doesn't work, it fails gracefully to the COMMON_LOW_LIMIT. This can 5x the performance of fetching objects with a documented COMMON_LOW_LIMIT. This function only gets called if no limit is provided, so it won't override behavior determined by a consumer of this library.
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# throws - Exception (unknown type, likely [System.Net.Exception] if neither COMMON_HIGH_LIMIT or COMMON_LOW_LIMIT work when facing an objectType that is not accounted-for in DEFAULT_API_PAGE_LIMITS or has a COMMON_LOW_LIMIT value.
		# @returns - [int] - the largest page size that will work for the queryObject
		#>
	hidden static [int] determinePageSizeForObjectType([Authorizer] $authorizer, [ObjectEndpointQuery] $queryObject){
		$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS[$queryObject.objectType]

		# Since SP is sneakily doing a good thing and raising their low Page limits to 250, check all documented low page limits to see whether they still apply. If not, update it.
		if ( `
			$pageSize -eq $null -or `
			$pageSize -eq [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_LOW_LIMIT"] `
		){ # Then the DEFAULT_API_PAGE_LIMITS doesn't contain the objectType as a key
		
			# First try the high limit. If that errors out, try the low limit.
			$url = $queryObject.getObjectEndpointUrl() + "?limit="+[ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_HIGH_LIMIT"]
# Write-Host -ForegroundColor Red "url: $url"
# Write-Host -ForegroundColor Green "authorizer: $authorizer"
# Write-Host -ForegroundColor Red "header: $($authorizer.getHeader() | fl | out-string)"
# Write-Host -ForegroundColor Green "queryObject: $($queryObject | fl | out-string)"
			try {
				$apiResponse = Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
				
				# In case of unpublished higher page limits or unknown limits, we should reach this code without having thrown an exception, so update to the return value.
				$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_HIGH_LIMIT"]
			} catch [System.Net.WebException] { # High limit didn't work, fail gracefully to trying the low limit.
				if ([int]$_.Exception.Response.StatusCode -eq 400){ # 400.1 = Bad Request Error
					$url = $queryObject.getObjectEndpointUrl() + "?limit="+[ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_LOW_LIMIT"]
					$apiResponse = Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
					# If we reach this line of code without having thrown an exception, the HIGH limit failed, but the LOW limit succeeded, so update the return value.
					$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_HIGH_LIMIT"]
				} else { # Something unexpected happened trying the low limit
					# throw $_.Exception
# $global:lastError = $_
					throw ("Error determining page size using low limit:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
				}
			} catch { # Something unexpected happened trying the high limit
				# throw $_.Exception
				throw ("Error determining page size using high limit:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
			}
		}
		return $pageSize
	}

	# PROGRAMMER NOTE: Since this method is only called after validating the Page Limit in a constructor, we know the queryObject has a paramTable, but if that changes, add code similar to the first 3 lines of validateAndUpdateQueryPageLimit

	<## @method addSortersAndOffsetToQueryIfNeeded
		# @static
		# @hidden
		# @description - validates that the query object has 'sorters' and 'offset' parameter in its paramTables, and mutates the passed $queryObject, adding  them if they don't exist
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# @throws - [System.Management.Automation.RuntimeException] - if there are sorters and/or offset parameters, but they are null.
		# @returns - [void]
		#>
	hidden static [void] addSortersAndOffsetToQueryIfNeeded ([ObjectEndpointQuery] $queryObject){
# Write-Host -ForegroundColor Magenta "In addSortersAndOffsetToQueryIfNeeded() queryObject: $queryObject"
		if ($queryObject.paramTable.sorters -eq $null){
			if( $queryObject.paramTable.psobject.properties.match('sorters').Count ){
				throw "A null value was passed for the 'sorters' parameter. Either don't pass one, or pass a valid one."
			}
			$defaultSorter = [ObjectEndpointIterator]::DEFAULT_SORTERS[$queryObject.objectType]
			if ($defaultSorter -eq $null) { $defaultSorter = [ObjectEndpointIterator]::DEFAULT_SORTERS["default"] }
			$queryObject.paramTable | Add-Member -MemberType NoteProperty -Name 'sorters' -Value $defaultSorter -Force
		}
		if ($queryObject.paramTable.offset -eq $null){
			if( $queryObject.paramTable.psobject.properties.match('offset').Count ){
				throw "A null value was passed for the 'offset' parameter. Either don't pass one, or pass a valid one."
			}
			$queryObject.paramTable | Add-Member -MemberType NoteProperty -Name 'offset' -Value 0 -Force
		}
	}

	<## @method processApiResponseContent
		# @static
		# @hidden
		# @description - deals with a quirk discovered in Azure account responses, with both "ImmutableId" and "immutableId" keys that Powershell views as the same. This method analyzes the error, and adds a leading underscore to the key for the second key in the DuplicateKeysInJsonString PS error. If passing the results of Invoke-WebRequest, pass the output's .content member. You can pass the results Invoke-RestMethod directly.
		# @param - apiResponseContent - a [System.Object] because this could either be a [String] or [Object[]]
		# @throws - any error that is not a DuplicateKeysInJsonString error so it can be dealt with by the developer of the calling script
		# @returns - [Object[]]
		#>
	hidden static [Object[]] processApiResponseContent([System.Object] $apiResponseContent){
		if ($apiResponseContent.GetType().name -eq "String") {
			$allDuplicateKeysFound = $false
			do{
				try{
					$apiResponseContent = $apiResponseContent | ConvertFrom-JSON
					$allDuplicateKeysFound = $true
				} catch [System.InvalidOperationException] {
					if ( `
						$_.FullyQualifiedErrorId -eq "DuplicateKeysInJsonString,Microsoft.PowerShell.Commands.ConvertFromJsonCommand" -and `
						$_.Exception.Message -match "Cannot convert the JSON string because a dictionary that was converted from the string contains the duplicated keys '(?<key1>.*)' and '(?<key2>.*)'." `
					){
						$apiResponseContent = $apiResponseContent -creplace $matches.key2, "_$($matches.key2)"
					} else { # some other issue
						throw $_.Exception.Message
					}
				}
			} while (!$allDuplicateKeysFound)
		}
		return $apiResponseContent
	}	


	### CONSTRUCTORS ###

	<## @constructor ObjectEndpointIterator
		# @description - instantiates an [ObjectEndpointIterator] object which represents a query against the SailPoint API. 5 overloads with different signatures, similar to the ObjectEndpointQuery constructors, except they all require an [Authorizer] first, because they generate a [ObjectEndpointQuery] then ensure that at least the DEFAULT_SORTERS is applied and that the DEFAULT_API_PAGE_LIMITS are respected by examining the paramTable after creating the ObjectEndpointQuery. NOTE: the offset, if provided, only determines the beginning of the first page of query results.
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param fullQueryUrl - the complete query URL, URL-encoded or not.
		# @param objectEndpointUrl - the complete query URL, URL-encoded or not. Must contain the [ObjectEndpointQuery]::MINIMUM_REQUIRED_URL_COMPONENTS.
		# @param orgName - the tenant subdomain for your org, i.e.: <orgname>.api.identitynow.com
		# @param versionPathSegment - the path segment representing the version (e.g.: v3, beta, etc)
		# @param objectEndpointPathSegment - the path segment representing the objects being queried (e.g.: sources, access-profiles, etc.)
		# @param queryParams - two formats: [String] should be everything after but not including the "?" (the query symbol in the URL). Example: 'sorters=name&filters=name eq "Workday"' or [HashTable] representing the same information contained in the "key=value" pairs.
		# @throws - [System.Management.Automation.RuntimeException] - if validation of an optional limit query param fails. Validity means that 0 < limit <= [ObjectEndpointQuery]::DEFAULT_API_PAGE_LIMITS[$objectType]
		#>
	
	ObjectEndpointIterator(){
		Write-Host -BackgroundColor DarkRed "Inside of OEI constructor"
	} #only used by subclasses.
	
	ObjectEndpointIterator([Authorizer] $authorizer, [String] $fullQueryUrl){
		$this.authorizer = $authorizer
		$this.queryObject = [ObjectEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($fullQueryUrl))
		[ObjectEndpointIterator]::addSortersAndOffsetToQueryIfNeeded($this.queryObject)
	}
	
	ObjectEndpointIterator([Authorizer] $authorizer, [String] $objectEndpointUrl, [String] $queryParams){
		$this.authorizer = $authorizer
		$this.queryObject = [ObjectEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($objectEndpointUrl, $queryParams))
		[ObjectEndpointIterator]::addSortersAndOffsetToQueryIfNeeded($this.queryObject)
	}

	ObjectEndpointIterator([Authorizer] $authorizer, [String] $objectEndpointUrl, [Hashtable] $queryParams){
		$this.authorizer = $authorizer
		$this.queryObject = [ObjectEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($objectEndpointUrl, $queryParams))
		[ObjectEndpointIterator]::addSortersAndOffsetToQueryIfNeeded($this.queryObject)
	}

	ObjectEndpointIterator([Authorizer] $authorizer, [String] $orgname, [String] $versionPathSegment, [String] $objectEndpointPathSegment, [String] $queryParams){
		$this.authorizer = $authorizer
		$this.queryObject = [ObjectEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParams))
		[ObjectEndpointIterator]::addSortersAndOffsetToQueryIfNeeded($this.queryObject)
	}

	ObjectEndpointIterator([Authorizer] $authorizer, [String] $orgname, [String] $versionPathSegment, [String] $objectEndpointPathSegment, [Hashtable] $queryParams){
		$this.authorizer = $authorizer
		$this.queryObject = [ObjectEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($orgname, $versionPathSegment, $objectEndpointPathSegment, $queryParams))
		[ObjectEndpointIterator]::addSortersAndOffsetToQueryIfNeeded($this.queryObject)
	}
	
	### INSTANCE METHODS ###

	<## @method flush
		# @description - empties the results of previous calls to execute(), forcing a call to the garbage collector
		# @returns - [void]
		#>
	[void] flush(){
		$this.ids.Clear()
		$this.objects.Clear()
		$this.index = 0

		[System.GC]::Collect()
		[System.GC]::WaitForPendingFinalizers()
	}

<# executeQuery notes #>
	# Run the query to get the Iterator ready for iteration
	# throws an exception if a problem arises with the REST call.

	<## @method executeQuery
		# @description - simplest overload for executeQuery that shows a progress indicator with the default activity name  "<objectType> Query", "e.g.: 'sources Query'"
		# @returns - [void]
		#>
	[void] executeQuery(){
		$this.executeQuery($true, "$($this.queryObject.objectType) Query")
	}

	<## @method executeQuery
		# @description - overload for executeQuery that allows the caller to decide whether to show a progress indicator with the default activity name  "<objectType> Query", e.g.: "sources Query"
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @returns - [void]
		#>
	[void] executeQuery([bool] $showProgressIndicators){
		$this.executeQuery($showProgressIndicators, "$($this.queryObject.objectType) Query")
	}

	<## @method executeQuery
		# @description - overload for executeQuery that shows a progress indicator with the passed $progressBarActivityName
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - if progressBarActivityName is null or empty $progressBarActivityName
		# @returns - [void]
		#>
	[void] executeQuery([String] $progressBarActivityName){
		$this.executeQuery($true, $progressBarActivityName)
	}

	<## @method executeQuery
		# @description - Executes the the query specified by the queryObject member property and populates the ids and objects members.
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - [System.Management.Automation.RuntimeException] - if $progressBarActivityName is null or empty when $showProgressIndicators is true. Technically, you COULD not showProgressIndicators and pass a progressBarActivityName, but it wouldn't matter.
		# @returns - [void]
		#>
	[void] executeQuery([bool] $showProgressIndicators, [String] $progressBarActivityName){
		# calls flush prior to action to ensure we don't have leftover state from the last execution
		$this.flush()
		
		# pageNum & numPages only defined up here to deal with scopes bug (blocks in classes seem to define new child scopes
		$pageNum = 1 
		$numPages = 1
		
		# If we are going to showProgressIndicators, we need to fetch one object and use the X-Total-Count header to get the denominator for calculating the progress bar state.
		if ($showProgressIndicators){
			if ($progressBarActivityName -eq $null -or $progressBarActivityName -eq ""){
				throw "[ObjectEndpointIterator] method 'executeQuery': Must provide a non-empty string value for $progressBarActivityName if $showProgressIndicators is true"
			}
			$this.lastQueryDescription = $progressBarActivityName
			
			# Get count of objects by cloning this.queryObject with a few different params. NOTE: this is the only reason to use the count parameter, so its not necessary in the queryObject
			$paramNamesToRemove = @()
			$paramNamesToAddOrReplace = @{limit=1;count="true";offset=0}
			$newQueryObject = $this.queryObject.cloneWithDifferentParams($paramNamesToRemove,$paramNamesToAddOrReplace)
			$countingUrl = $newQueryObject.getQueryUrl()

			try{
# Write-Host -ForegroundColor Magenta "countingUrl: $countingUrl"
# Write-Host -ForegroundColor Magenta "authorizer: $($this.authorizer)"
				$apiResponse = Invoke-WebRequest -Method GET -URI $countingUrl -Headers $this.authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
				$numObjects= $apiResponse.Headers.'X-Total-Count'
				$numPages = [Math]::Ceiling($apiResponse.Headers.'X-Total-Count'/$this.queryObject.paramTable.limit)
			} catch {
# Write-Host -ForegroundColor Magenta "countingUrl: $countingUrl"
# Write-Host -ForegroundColor Cyan "authorizer: $($this.authorizer)"
# Write-Host -ForegroundColor Magenta "header: $($this.authorizer.header | fl | out-string)"
				throw ("Error counting objects:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
			}
		}

		if ($numPages){ # Don't need to hit an endpoint if there are no objects to fetch
			$originalOffset = $this.queryObject.paramTable.offset
			$numObjectsInResponse = 0
			do{ # until all objects have been iterated
				if ($showProgressIndicators){
					Write-Progress -Activity $progressBarActivityName -Status "Obtaining page $pageNum of $numPages. Page size: $($this.queryObject.paramTable.limit)" -PercentComplete ($pageNum/$numPages*100)
				}
				$apiResponse = Invoke-RestMethod -Uri $this.queryObject.getQueryUrl() -Method GET -Headers $this.authorizer.getHeader()
				$apiResponse = [ObjectEndpointIterator]::processApiResponseContent($apiResponse)
				$numObjectsInResponse = $apiResponse.count

				foreach ($object in $apiResponse){
					$this.ids.add($object.id)
					$this.objects[$object.id] = $object
				}

				$this.queryObject.paramTable.offset += $this.queryObject.paramTable.limit
				if ($showProgressIndicators) {$pageNum++}
			} while ($numObjectsInResponse -eq $this.queryObject.paramTable.limit)
			if ($showProgressIndicators) {Write-Progress -Activity $progressBarActivityName -Status "Done" -Completed}
			$this.queryObject.paramTable.offset = $originalOffset
		}
	}

<# executeQueryForSingleObject notes #>
	# Run the query and return a single object - Convenience method for a common use case.
	# throws an exception if a problem arises with the REST call.
	# throws an exception if the query did not return exactly one result.

	<## @method executeQueryForSingleObject
		# @description - simplest overload for executeQueryForSingleObject that shows a progress indicator with the default activity name  "<objectType> Query", "e.g.: 'sources Query'"
		# @throws - [System.Management.Automation.RuntimeException] - if the query did not return exactly one result.
		# @returns - [PSCustomObject]
		#>
	[PSCustomObject] executeQueryForSingleObjectFor(){
		return $this.executeQueryForSingleObject($true, "$($this.queryObject.objectType) Query")
	}

	<## @method executeQueryForSingleObject
		# @description - overload for executeQueryForSingleObject that allows the caller to decide whether to show a progress indicator with the default activity name  "<objectType> Query", e.g.: "sources Query"
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @throws - [System.Management.Automation.RuntimeException] - if the query did not return exactly one result.
		# @returns - [PSCustomObject]
		#>
	[PSCustomObject] executeQueryForSingleObject([bool] $showProgressIndicators){
		return $this.executeQueryForSingleObject($showProgressIndicators, "$($this.queryObject.objectType) Query")
	}

	<## @method executeQueryForSingleObject
		# @description - overload for executeQueryForSingleObject that shows a progress indicator with the passed $progressBarActivityName
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - if progressBarActivityName is null or empty $progressBarActivityName
		# @throws - [System.Management.Automation.RuntimeException] - if the query did not return exactly one result.
		# @returns - [PSCustomObject]
		#>
	[PSCustomObject] executeQueryForSingleObject([String] $progressBarActivityName){
		return $this.executeQueryForSingleObject($true, $progressBarActivityName)
	}

	<## @method executeQueryForSingleObject
		# @description - Executes the the query specified by the queryObject member property and populates the ids and objects members.
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - [System.Management.Automation.RuntimeException] - if $progressBarActivityName is null or empty when $showProgressIndicators is true. Technically, you COULD not showProgressIndicators and pass a progressBarActivityName, but it wouldn't matter.
		# @throws - [System.Management.Automation.RuntimeException] - if the query did not return exactly one result.
		# @returns - [PSCustomObject]
		#>
	[PSCustomObject] executeQueryForSingleObject([bool] $showProgressIndicators, [String] $progressBarActivityName){
		
		$this.executeQuery($showProgressIndicators, $progressBarActivityName)

		if ($this.count() -ne 1) {
			throw "Expecting a single object to be returned, but received $($this.count())"
		}
		
		return $this.getObjectByIndex(0)
	}




	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		return ($this | fl | Out-String).Trim() -replace "^","`r`n"
	}
	
}


<## @class GenericEndpointIterator
	# @description - This class is a hack: to use all the code of [ObjectEndpointIterator] when there is no guarantee of a top-level 'id' attribute, as there would be with SailPointObject(SPO)-type iterators.
	#>
class GenericEndpointIterator : ObjectEndpointIterator {

	<## @method validateAndUpdateQueryPageLimit
		# @static
		# @hidden
		# @description - Validates that the passed $queryObject has a limit query param. If not, it determines the most performant one for that that objectType and mutates the passed queryObject.
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# throws - [System.Management.Automation.RuntimeException] - if validation of the limit query param fails, if one is provided. Validity means that 0 < limit <= DEFAULT_API_PAGE_LIMITS[$objectType]
		# @returns - [ObjectEndpointQuery] - the possibly-modified $queryObject argument
		#>
	hidden static [ObjectEndpointQuery] validateAndUpdateQueryPageLimit ([Authorizer] $authorizer, [ObjectEndpointQuery] $queryObject){
		if ($queryObject.paramTable -eq $null){ # We must guarantee that the queryObject has paramTable for the below logic to work, even if empty.
			$queryObject.paramTable = [PSCustomObject] @{}
		}
		$params = $queryObject.paramTable

		$maxPageSizeForObject = [GenericEndpointIterator]::determinePageSizeForObjectType($authorizer, $queryObject)
# Write-Host -ForegroundColor Red "queryObject: $($queryObject | fl | out-string)"
# Write-Host -ForegroundColor Magenta "maxPageSizeForObject: $maxPageSizeForObject"

		if ($params.limit -ne $null){
			if ($params.limit -lt 1 -or $params.limit -gt $maxPageSizeForObject) {
				throw "the limit you provided [$($params.limit)] must be between 1 and the maximum (default) limit of $maxPageSizeForObject, inclusive."
			}
			# At this point in the code, we know a limit param was provided, and is valid. Next line is the return statement.
		} else { # if no limit was provided, we should set the limit to the maxPageSizeForObject
			$params | Add-Member -MemberType NoteProperty -Name 'limit' -Value $maxPageSizeForObject
		}
# Write-Host -ForegroundColor Green "queryObject: $($queryObject | fl | out-string)"
		return $queryObject
	}

	<## @method determinePageSizeForObjectType
		# @static
		# @hidden
		# @description - By default, all SPO endpoints use the documented limit for that endpoint. Experimentally, some of the API endpoints using COMMON_LOW_LIMIT as the default don't obey their documented limits. For example, /access-profiles will default to limit=50 (COMMON_LOW_LIMIT), accept values up to 250 (COMMON_HIGH_LIMIT), and error out on 251. This method first looks up the documented value for common objects. If it doesn't find one in DEFAULT_API_PAGE_LIMITS or finds out that it is equal to the COMMON_LOW_LIMIT, it tries to GET one page using the COMMON_HIGH_LIMIT. If that doesn't work, it fails gracefully to the COMMON_LOW_LIMIT. This can 5x the performance of fetching objects with a documented COMMON_LOW_LIMIT. This function only gets called if no limit is provided, so it won't override behavior determined by a consumer of this library.
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# throws - Exception (unknown type, likely [System.Net.Exception] if neither COMMON_HIGH_LIMIT or COMMON_LOW_LIMIT work when facing an objectType that is not accounted-for in DEFAULT_API_PAGE_LIMITS or has a COMMON_LOW_LIMIT value.
		# @returns - [int] - the largest page size that will work for the queryObject
		#>
	hidden static [int] determinePageSizeForObjectType([Authorizer] $authorizer, [ObjectEndpointQuery] $queryObject){
		$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_HIGH_LIMIT"]
		# Since SP is sneakily doing a good thing and raising their low Page limits to 250, we need to test 250 and 50.
		
		# First try the high limit. If that errors out, try the low limit.
		$queryObjectToTest = $queryObject.cloneWithDifferentParams(@(), @{"limit" = $pageSize})
		$url = $queryObjectToTest.getQueryUrl()

# Write-Host -ForegroundColor Red "url: $url"
# Write-Host -ForegroundColor Green "authorizer: $authorizer"
# Write-Host -ForegroundColor Red "header: $($authorizer.getHeader() | fl | out-string)"
# Write-Host -ForegroundColor Green "queryObject: $($queryObject | fl | out-string)"
		try {
			$apiResponse = Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
		} catch [System.Net.WebException] { # High limit didn't work, fail gracefully to trying the low limit.
			if ([int]$_.Exception.Response.StatusCode -eq 400){ # 400.1 = Bad Request Error
				$pageSize = [ObjectEndpointIterator]::DEFAULT_API_PAGE_LIMITS["COMMON_HIGH_LIMIT"]
				$queryObjectToTest = $queryObject.cloneWithDifferentParams(@(), @{"limit" = $pageSize})
				$url = $queryObjectToTest.getQueryUrl()

				$apiResponse = Invoke-WebRequest -Method GET -URI $url -Headers $authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
			} else { # Something unexpected happened trying the low limit
# $global:lastError = $_
				throw ("Error determining page size using low limit:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
			}
		} catch { # Something unexpected happened trying the high limit
			throw ("Error determining page size using high limit:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
		}
# Write-Host -ForegroundColor Magenta "pageSize: $pageSize"

		return $pageSize
	}

	# PROGRAMMER NOTE: Since this method is only called after validating the Page Limit in a constructor, we know the queryObject has a paramTable, but if that changes, add code similar to the first 3 lines of validateAndUpdateQueryPageLimit

	<## @method addOffsetToQueryIfNeeded
		# @static
		# @hidden
		# @description - validates that the query object has 'sorters' and 'offset' parameter in its paramTables, and mutates the passed $queryObject, adding  them if they don't exist
		# @param - queryObject - a [ObjectEndpointQuery] representing the query
		# @throws - [System.Management.Automation.RuntimeException] - if there are sorters and/or offset parameters, but they are null.
		# @returns - [void]
		#>
	hidden static [void] addOffsetToQueryIfNeeded ([ObjectEndpointQuery] $queryObject){
		if ($queryObject.paramTable.offset -eq $null){
			if( $queryObject.paramTable.psobject.properties.match('offset').Count ){
				throw "A null value was passed for the 'offset' parameter. Either don't pass one, or pass a valid one."
			}
			$queryObject.paramTable | Add-Member -MemberType NoteProperty -Name 'offset' -Value 0 -Force
		}
	}

	
	GenericEndpointIterator([Authorizer] $authorizer, [String] $fullQueryUrl){
		$this.authorizer = $authorizer
		# $this.queryObject = [ObjectEndpointQuery]::new($fullQueryUrl)
		$this.queryObject = [GenericEndpointIterator]::validateAndUpdateQueryPageLimit($authorizer, [ObjectEndpointQuery]::new($fullQueryUrl))
# Write-Host -ForegroundColor Magenta "this.queryObject: $this.queryObject"
		[GenericEndpointIterator]::addOffsetToQueryIfNeeded($this.queryObject)		
Write-Host -BackgroundColor DarkGreen "End of GEI constructor"
	}

	
		<## @method executeQuery
		# @description - Executes the the query specified by the queryObject member property and populates the ids and objects members. There are no overloads, since we must have a string, so for this hack class's single override method, you must specify all three params.
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @param - topLevelAttributeToUseAsId - the [String] used as the top-level property name in the object elements of the JSON array returned by the endpoint.
		# @throws - [System.Management.Automation.RuntimeException] - if $progressBarActivityName is null or empty when $showProgressIndicators is true. Technically, you COULD not showProgressIndicators and pass a progressBarActivityName, but it wouldn't matter.
		# @throws - [System.Management.Automation.RuntimeException] - if $topLevelAttributeToUseAsId doesn't exist on the object. Message: "Index operation failed; the array index evaluated to null"
		# @returns - [void]
		#>
	[void] executeQuery([bool] $showProgressIndicators, [String] $progressBarActivityName, [String] $topLevelAttributeToUseAsId){
		# calls flush prior to action to ensure we don't have leftover state from the last execution
		$this.flush()
		
		# pageNum & numPages only defined up here to deal with scopes bug (blocks in classes seem to define new child scopes
		$pageNum = 1 
		$numPages = 1
		
		# If we are going to showProgressIndicators, we need to fetch one object and use the X-Total-Count header to get the denominator for calculating the progress bar state.
		if ($showProgressIndicators){
			if ($progressBarActivityName -eq $null -or $progressBarActivityName -eq ""){
				throw "[GenericEndpointIterator] method 'executeQuery': Must provide a non-empty string value for $progressBarActivityName if $showProgressIndicators is true"
			}
			$this.lastQueryDescription = $progressBarActivityName
			
			# Get count of objects by cloning this.queryObject with a few different params. NOTE: this is the only reason to use the count parameter, so its not necessary in the queryObject
			$paramNamesToRemove = @()
			$paramNamesToAddOrReplace = @{limit=1;count="true";offset=0}
			$newQueryObject = $this.queryObject.cloneWithDifferentParams($paramNamesToRemove,$paramNamesToAddOrReplace)
			$countingUrl = $newQueryObject.getQueryUrl()
# Write-Host -ForegroundColor Magenta "countingUrl: $countingUrl"

			try{
				$apiResponse = Invoke-WebRequest -Method GET -URI $countingUrl -Headers $this.authorizer.getHeader() -ContentType ([ObjectEndpointIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
				$numObjects= $apiResponse.Headers.'X-Total-Count'
# Write-Host -ForegroundColor Magenta "numObjects: $numObjects"
# Write-Host -ForegroundColor Magenta "numObjects: $numObjects; null? $($numObjects -eq $null)"
				$numPages = [Math]::Ceiling($apiResponse.Headers.'X-Total-Count'/$this.queryObject.paramTable.limit)
# Write-Host -ForegroundColor Magenta "numPages: $numPages; null? $($numPages -eq $null)"
			} catch [System.Net.WebException] {
				throw "Error counting objects:$($_.Exception.message) - $(getUsefulErrorCodes($_))`n$($_.InvocationInfo.PositionMessage)"
			} catch {
# $global:LastError = $_
				throw "Error counting objects:$($_.Exception.message)`n$($_.InvocationInfo.PositionMessage)"
			}
		}

		if ($numPages){ # Don't need to hit an endpoint if there are no objects to fetch
			$originalOffset = $this.queryObject.paramTable.offset
			$numObjectsInResponse = 0
# Write-Host -ForegroundColor Magenta "this.queryObject.url: $($this.queryObject.getQueryUrl())"
# Write-Host -ForegroundColor Magenta "this.auth: $($this.authorizer.getHeader() | fl | out-string)"
			try{
				do{ # until all objects have been iterated
					if ($showProgressIndicators){
						Write-Progress -Activity $progressBarActivityName -Status "Obtaining page $pageNum of $numPages. Page size: $($this.queryObject.paramTable.limit)" -PercentComplete ($pageNum/$numPages*100)
					}
					$apiResponse = Invoke-RestMethod -Uri $this.queryObject.getQueryUrl() -Method GET -Headers $this.authorizer.getHeader()
					$apiResponse = [ObjectEndpointIterator]::processApiResponseContent($apiResponse)
					$numObjectsInResponse = $apiResponse.count

					foreach ($object in $apiResponse){
						$this.ids.add($object.$topLevelAttributeToUseAsId)
						$this.objects[$object.$topLevelAttributeToUseAsId] = $object
					}

# Write-Host -ForegroundColor Green "numObjectsInResponse: $numObjectsInResponse"
# Write-Host -ForegroundColor Red "numObjectsInResponse: $($this.queryObject.paramTable | fl | out-string)"
					$this.queryObject.paramTable.offset += $this.queryObject.paramTable.limit
					if ($showProgressIndicators) {$pageNum++}
				} while ($numObjectsInResponse -eq $this.queryObject.paramTable.limit)
			} catch [System.Net.WebException]{
# $global:LastError = $_
				throw ("Error executing query '$($this.lastQueryDescription)' :$($_.Exception.message) - $(getUsefulErrorCodes($_))")
			}

			if ($showProgressIndicators) {Write-Progress -Activity $progressBarActivityName -Status "Done" -Completed}
			$this.queryObject.paramTable.offset = $originalOffset
		}
	}


	# For endpoints where count=true doesn't work as a parameter - 2 overloads: no-arg, and an alternative unique attribute to use as the id. The latter is better to use, and the former creates a simple integer index beginning at 0.
	[void] executeNonCountableQuery(){
		# calls flush prior to action to ensure we don't have leftover state from the last execution
		$this.flush()
		
		$originalOffset = $this.queryObject.paramTable.offset
		$numObjectsInResponse = 0
		$index = 0
		do{ # until all objects have been iterated
			$apiResponse = Invoke-RestMethod -Uri $this.queryObject.getQueryUrl() -Method GET -Headers $this.authorizer.getHeader()
			$apiResponse = [ObjectEndpointIterator]::processApiResponseContent($apiResponse)
			$numObjectsInResponse = $apiResponse.count

			foreach ($object in $apiResponse){
				$this.ids.add([String] $index)
				$this.objects[[String] $index] = $object
				$index++
			}

			$this.queryObject.paramTable.offset += $this.queryObject.paramTable.limit
		} while ($numObjectsInResponse -eq $this.queryObject.paramTable.limit)
		$this.queryObject.paramTable.offset = $originalOffset
	}

	[void] executeNonCountableQuery([String] $topLevelAttributeToUseAsId){
		# calls flush prior to action to ensure we don't have leftover state from the last execution
		$this.flush()
		
		$originalOffset = $this.queryObject.paramTable.offset
		$numObjectsInResponse = 0
		do{ # until all objects have been iterated
# Write-Host -ForegroundColor Magenta "url: $($this.queryObject.getQueryUrl())"
			$apiResponse = Invoke-RestMethod -Uri $this.queryObject.getQueryUrl() -Method GET -Headers $this.authorizer.getHeader()
			$apiResponse = [ObjectEndpointIterator]::processApiResponseContent($apiResponse)
			$numObjectsInResponse = $apiResponse.count
# Write-Host -ForegroundColor Magenta "numObjectsInResponse: $numObjectsInResponse"

			foreach ($object in $apiResponse){
				$this.ids.add($object.$topLevelAttributeToUseAsId)
				$this.objects[$object.$topLevelAttributeToUseAsId] = $object
			}

			$this.queryObject.paramTable.offset += $this.queryObject.paramTable.limit
		} while ($numObjectsInResponse -eq $this.queryObject.paramTable.limit)
		$this.queryObject.paramTable.offset = $originalOffset
	}


	
}

<## @class MergedObjectEndpointIterator
	# @description -  Creates an interface for keeping track of and iterating the results of separate [ObjectEndpointIterator]s for the same objectType. The use case here is when polling the same objectEndpointPathSegment multiple times with different filters for performance reasons.
	#>
class MergedObjectEndpointIterator : ObjectIterator {

	### INSTANCE PROPERTIES ###
	
	[ObjectEndpointIterator[]] $componentIterators

	### CONSTRUCTORS ###

	<## @constructor MergedObjectEndpointIterator
		# @description - instantiates a [MergedObjectEndpointIterator], which keeps tracks of the component iterators and merges the results of the ids and objects members of each. If identical objects (same id) are found, they are only added to the results once. Safety is up to the caller to keep object types the same.
		# @param - iteratorsToMerge - [ObjectEndpointIterator[]] - a collection of executed iterators.
		#>
	MergedObjectEndpointIterator([ObjectEndpointIterator[]] $iteratorsToMerge){
		$this.componentIterators =  $iteratorsToMerge
		
		foreach ($iterator in $iteratorsToMerge){
			foreach ($id in $iterator.ids){
				if (-not $this.objects.ContainsKey($id)){
					$this.ids.add($id)
					$this.objects.$id = $iterator.objects.$id
				}
			}
		}
	}
	
	### INSTANCE METHODS ###
	
	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		return ([PSCustomObject]@{
			componentIterators =  ($this.componentIterators | Foreach-ObjectFast -Begin {$i=-1} {$i++; "`nIterator [$i]:" + ($_.ToString() -replace "`n","`n`t").TrimEnd() + "`n"})
			ids =  $this.ids
			objects =  $this.objects
			index =  $this.index
		} | fl | Out-String).Trim() -replace "^","`r`n"
	}	
}



# TODO - Improve / Error-check Documentation comments for the below Search-related classes.


<# DOCUMENTATION ON SEARCH 
+indices Index[]
	Possible values: [accessprofiles, accountactivities, entitlements, events, identities, roles, *]

	The names of the Elasticsearch indices in which to search. If none are provided, then all indices will be searched.

+includeNested boolean
	Default value: true

	Indicates whether nested objects from returned search results should be included.

+queryResultFilter object
	Allows the query results to be filtered by specifying a list of fields to include and/or exclude from the result documents.

		includes string[]
		The list of field names to include in the result documents.

		excludes string[]
		The list of field names to exclude from the result documents.

+searchAfter string[]
	Used to begin the search window at the values specified. This parameter consists of the last values of the sorted fields in the current record set. This is used to expand the Elasticsearch limit of 10K records by shifting the 10K window to begin at this value. It is recommended that you always include the ID of the object in addition to any other fields on this parameter in order to ensure you dont get duplicate results while paging. For example, when searching for identities, if you are sorting by displayName you will also want to include ID, for example ["displayName", "id"]. If the last identity ID in the search result is 2c91808375d8e80a0175e1f88a575221 and the last displayName is "John Doe", then using that displayName and ID will start a new search after this identity. The searchAfter value will look like ["John Doe","2c91808375d8e80a0175e1f88a575221"]

+sort string[]
	The fields to be used to sort the search results. Use + or - to specify the sort direction.
	VIP's Note: Experiments show that sorting can be done on non top-level properties, like [ "manager.displayName", "id" ]
	
#>

enum SearchQueryIndex {
	ALL = 0
	accessprofiles = 1
	accountactivities = 2
	entitlements = 3
	events = 4
	identities = 5
	roles = 6
}

# example for identities [includes / $true] - @("name","lastName", "firstName", "id","source.name")
# example for identities [excludes / $false] - @("*Count", "attributes")
# attribute filters do not affect hidden attributes in the search result object - namely: 'type', '_type', and '_version'
<#
 # NOTE: exclusion overrides inclusion, but ONLY if the excluded attribute would have been included by the inclusion attributes (i.e.: the same attribute appears in both lists, or the inclusion filter had a wildcard that includes the attribute in the exclude list:
 # e.g.: this can get all the top-level and nested attributes ending with the string 'name' except the top-level identity name.
	"includeNested": true,
	"queryResultFilter": {
        "includes": ["*Name", "source.name"],
        "excludes": ["name"]
    }
#>
class SearchQueryResultObjectStructure{
	[bool] $includeNested = $true
	[String[]] $includedAttributesInDotNotation
	[String[]] $excludedAttributesInDotNotation
	
	### CONSTRUCTORS ###
	# 2 overloads.
	SearchQueryResultObjectStructure([bool] $includeNested, [String[]] $includedAttributesInDotNotation, [String[]] $excludedAttributesInDotNotation){
		$this.includeNested = $includeNested
		$this.includedAttributesInDotNotation = $includedAttributesInDotNotation
		$this.excludedAttributesInDotNotation = $excludedAttributesInDotNotation
	}

	SearchQueryResultObjectStructure([bool] $includeNested, [String[]] $includedAttributesInDotNotation){
		$this.includeNested = $includeNested
		$this.includedAttributesInDotNotation = $includedAttributesInDotNotation
	}

	SearchQueryResultObjectStructure([bool] $includeNested){
		$this.includeNested = $includeNested
	}
		
	SearchQueryResultObjectStructure(){}

	
	### INSTANCE METHODS ###

	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		return ($this | fl | Out-String).Trim() -replace "^","`r`n"
	}
	
}


# TODOS: must deal with guaranteeing that the (returned properties) && (sorters) each include, at a minimum, the id.
<## @class SearchQueryIterator
	# @description -  unopinionated class to iterate the results of /search endpoint in the IDN API. The constructor takes a query and runs it until the API response is exhausted. It maintains an ArrayList of objectIds and a hashtable of objects keyed on those ids. The URLs provided to its constructors can be URL-encoded or not, this class will take care of that.
	#>
class SearchQueryIterator : ObjectIterator {

	### HIDDEN STATIC PROPERTIES ###
		
	hidden static [String] $DEFAULT_SORT = "id" # To guarantee complete and unique results, there must be a sorter. If not supplied, this defaults to id, which can be used by all object types
	hidden static [String] $DEFAULT_CONTENT_TYPE = "application/json" # common to GET operations in the IDN API
	hidden static [String] $DEFAULT_API_VERSION = "v3" # This is a slowly-mutating value (Latest stable release)
	hidden static [int] $SEARCH_NESTED_RESULTS_MAX_PAGE_SIZE = 1000 # Experiments on nested identities results shows that > 1010 gives a '500.1.503 Downstream service unavailable' error, so 10 is a safety buffer.
	hidden static [int] $SEARCH_RESULTS_MAX_PAGE_SIZE = 10000 # Max value as of v3 (not in documentation) - only usable without nesting.
	
	### INSTANCE PROPERTIES ###
	
	# MANDATORY AT CONSTRUCTION
	[Authorizer] $authorizer
	[String] $searchQuery
	# OPTIONAL AT CONSTRUCTION
	[SearchQueryIndex] $objectType = [SearchQueryIndex]::ALL
	[String[]] $sorters = @([SearchQueryIterator]::DEFAULT_SORT)
	[SearchQueryResultObjectStructure] $queryResultStructure = [SearchQueryResultObjectStructure]::new()
	# SETTABLE SHOULD DEFAULT NOT BE DESIRED - Not hidden so the caller knows these are Settable
	[String] $idnApiVersion = [SearchQueryIterator]::DEFAULT_API_VERSION
	[int] $pageSize = [SearchQueryIterator]::SEARCH_NESTED_RESULTS_MAX_PAGE_SIZE	
	# MAINTAINED BY OBJECT ITSELF
	hidden [String[]] $searchAfter # same format as sorters, null at beginning and after flush - setting will cause problems, hence hidden.
	[int] $lastQueryHeaderCount # For testing of the calling code. If the header count doesn't match the count(), then it's likely there was some searchAfter slippage due to not including "id" among the sorters.
	[String] $lastQueryDescription # Setting this does nothing - it's there for the caller's information.
	

	### CONSTRUCTORS ###


	<## @constructor SearchQueryIterator
		# @description - instantiates a [SearchQueryIterator] object which represents a search against the SailPoint API. 8 overloads with different signatures (2^3 signatures due to 3 optional params).
		# @param - authorizer - an [Authorizer] object for dealing with OAuth
		# @param searchQuery - [String] - the text of query from the search UI. NOTE: double-quotes will appropriately escaped during processing, so this value, if printed to screen, should look like as if you copied it from the /ui/search/search page. 
		# @param objectType - optional [SearchQueryIndex] - the "index" of the search query (one of the enumerated values). NOTE: If you want to use a constructor with fewer than 5 arguments, you may get unexpected behavior if trying to coerce a string into a [SearchQueryIndex], so it's better to pass the enum value explicitly, e.g.: [SearchQueryIndex]::identities, so that Powershell has no choice but to assume you mean one of the first 4 overloads.
		# @param sorters - optional [String[]] - the properties on which to sort, in order. Optionally, a prefix + or - specifies direction ("-lastName", e.g.). If param omitted, will sort on [SearchQueryIterator]::DEFAULT_SORT
		# @param queryResultStructure - optional [SearchQueryResultObjectStructure] - Data structure of the objects returned by the query. Contains a boolean flags for the includeNested query property, and arrays of Object Attribute names in dot notation to include or exclude. If omitted, all attributes are returned, and nested objects are also returned.
		#>

	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryIndex] $objectType, [Object[]] $sorters, [SearchQueryResultObjectStructure] $queryResultStructure){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 7"
		$this.init($authorizer, $searchQuery, $objectType, $sorters, $queryResultStructure)
	}

	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryIndex] $objectType, [Object[]] $sorters){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 6"
		$this.init($authorizer, $searchQuery, $objectType, $sorters, $null)
	}
	
	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryIndex] $objectType, [SearchQueryResultObjectStructure] $queryResultStructure){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 5"
		$this.init($authorizer, $searchQuery, $objectType, $null, $queryResultStructure)
	}

	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryIndex] $objectType){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 4"
		$this.init($authorizer, $searchQuery, $objectType, $null, $null)
	}
	
	
	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [Object[]] $sorters, [SearchQueryResultObjectStructure] $queryResultStructure){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 3"
		$this.init($authorizer, $searchQuery, $this.objectType, $sorters, $queryResultStructure)
	}

	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [Object[]] $sorters){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 2"
		$this.init($authorizer, $searchQuery, $this.objectType, $sorters, $null)
	}
	
	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryResultObjectStructure] $queryResultStructure){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 1"
		$this.init($authorizer, $searchQuery, $this.objectType, $null, $queryResultStructure)
	}

	SearchQueryIterator([Authorizer] $authorizer, [String] $searchQuery){
# Write-Host -BackgroundColor Cyan -ForegroundColor Black "IN CONSTRUCTOR 0"
		$this.init($authorizer, $searchQuery, $this.objectType, $null, $null)
	}
	
	### CONSTRUCTOR HELPER (HIDDEN INSTANCE METHOD) ###
	hidden init([Authorizer] $authorizer, [String] $searchQuery, [SearchQueryIndex] $objectType, [Object[]] $sorters, [SearchQueryResultObjectStructure] $queryResultStructure){
# Write-Host -BackgroundColor Green -ForegroundColor Black "IN INIT"
# Write-Host -ForegroundColor Green "authorizer: $(if ($authorizer) {$authorizer.toString() -replace "`n","`n`t"} else {'NULL/EMPTY'})"
# Write-Host -ForegroundColor Green "searchQuery: $(if ($searchQuery) {$searchQuery} else {'NULL/EMPTY'})"
# Write-Host -ForegroundColor Green "objectType: $(if ($objectType) {$objectType} else {'NULL/EMPTY'})"
# Write-Host -ForegroundColor Green "sorters: $(if ($sorters) {$sorters} else {'NULL/EMPTY'})"
# if ( $queryResultStructure -eq $null ) { Write-Host -ForegroundColor Green "queryResultStructure: NULL/EMPTY" }
# else { Write-Host -ForegroundColor Green "queryResultStructure: [$($queryResultStructure.getType())]`n`t$((($queryResultStructure | fl | Out-String) -replace "`n","`n`t").Trim())" }
		# MANDATORY AT CONSTRUCTION
		if ($authorizer -eq $null -or [String]::IsNullOrEmpty($searchQuery)){
			throw "SearchQueryIterator requires the 'authorizer' and 'searchQuery' parameters at a minimum."
		} else {
			$this.authorizer = $authorizer
			$this.searchQuery = $searchQuery
		}

		# OPTIONAL AT CONSTRUCTION
		if ($objectType) { $this.objectType = $objectType }
		if ($sorters) {
# $global:sorts = $sorters
# Write-Host -ForegroundColor Red "sorters TYPE: $($sorters.getType()); COUNT: $($sorters.count)"
			if (!$sorters.count) { throw "A list of sorters was passed, but it was empty." }
			if (($sorters | Where-Object {$_ -isNot [String]}).count) { throw "Not all values passed as sorters were of type [String], specifically: $($sorters | Where-Object {$_ -isNot [String]})" }
			$this.sorters = $sorters
		}
		if ($queryResultStructure) {
			$this.queryResultStructure = $queryResultStructure
			if (-Not $queryResultStructure.includeNested) { $this.pageSize = [SearchQueryIterator]::SEARCH_RESULTS_MAX_PAGE_SIZE } # Larger pages mean fewer calls without 500 errors.
		}
	}


	### HIDDEN STATIC METHODS ###
	
	hidden static [String] getQueryRepresentationOfStringArray ([String[]] $strArr){
		return ('[ "' + ($strArr -join '", "') + '" ]')
	}

	hidden static [String] escapeDoubleQuotesForQueryBody ([String] $unescaped){
		return ($unescaped -replace '"', '\"')
	}
	
	### HIDDEN INSTANCE METHODS ###
	
	hidden [String] generateSearchQueryBody(){
		
		$indicesValue = $( if($this.objectType) {$this.objectType} else {"*"} ) # ALL == 0, so else clause triggers.
		
		$usingQueryResultFilter = $this.queryResultStructure.includedAttributesInDotNotation.count -or $this.queryResultStructure.excludedAttributesInDotNotation.count
		
		# We guarantee lines in the query body for indices, query, includeNested, and sort. Additional lines are optional, so we need to know whether they exist so we can append a comma onto the last line of the sort property.
		$sortComma = (?: {$this.searchAfter -or $usingQueryResultFilter} {","} {""})

		# Build line for the searchAfter property, adding a comma if we will be using a queryResultStructure property.
		$searchAfterLine = $null
		if ($this.searchAfter){
			$searchAfterComma = (?: {$usingQueryResultFilter} {","} {""})
			$searchAfterLine = @"
	"searchAfter": $([SearchQueryIterator]::getQueryRepresentationOfStringArray($this.searchAfter))$searchAfterComma
"@
		}

		$queryResultFilterLines = $null
		if ($usingQueryResultFilter){
			$includesLine = $null
			if ($this.queryResultStructure.includedAttributesInDotNotation.count){
				$includesComma = (?: {$this.queryResultStructure.excludedAttributesInDotNotation.count} {","} {""})
				$includesLine = @"
		"includes": $([SearchQueryIterator]::getQueryRepresentationOfStringArray($this.queryResultStructure.includedAttributesInDotNotation))$includesComma
"@
			}
			$excludesLine = $null
			if ($this.queryResultStructure.excludedAttributesInDotNotation.count){
				$excludesLine = @"
		"excludes": $([SearchQueryIterator]::getQueryRepresentationOfStringArray($this.queryResultStructure.excludedAttributesInDotNotation))
"@
			}
			$queryResultFilterLines = @"
	"queryResultFilter": {
$includesLine
$excludesLine
	}
"@
		}

		$queryBody = @"
{
	"indices": [`"$indicesValue`"],
	"query": {
		"query": "$([SearchQueryIterator]::escapeDoubleQuotesForQueryBody($this.searchQuery))"
	},
	"includeNested": $($this.queryResultStructure.includeNested),
	"sort": $([SearchQueryIterator]::getQueryRepresentationOfStringArray($this.sorters))$sortComma
$searchAfterLine
$queryResultFilterLines
}
"@

		return $queryBody
	}

	
	### INSTANCE METHODS ###

	<## @method flush
		# @description - empties the results of previous calls to execute(), forcing a call to the garbage collector
		# @returns - [void]
		#>
	[void] flush(){
		$this.ids.Clear()
		$this.objects.Clear()
		$this.index = 0
		$this.searchAfter = $null

		[System.GC]::Collect()
		[System.GC]::WaitForPendingFinalizers()
	}

	# executeQuery Overloads
	# Run the query to get the Iterator ready for iteration
	# throws an exception if a problem arises with the REST call.

	<## @method executeQuery
		# @description - simplest overload for executeQuery that shows a progress indicator with the default activity name  "Running search for object type: <objectType>", "e.g.: 'Running search for object type: identities'"
		# @returns - [void]
		#>
	[void] executeQuery(){
		$this.executeQuery($true, "Running search for object type: $($this.objectType)")
	}

	<## @method executeQuery
		# @description - simplest overload for executeQuery that shows a progress indicator with the default activity name  "Running search for object type: <objectType>", "e.g.: 'Running search for object type: identities'"
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @returns - [void]
		#>
	[void] executeQuery([bool] $showProgressIndicators){
		$this.executeQuery($showProgressIndicators, "Running search for object type: $($this.objectType)")
	}

	<## @method executeQuery
		# @description - overload for executeQuery that shows a progress indicator with the passed $progressBarActivityName
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - if progressBarActivityName is null or empty $progressBarActivityName
		# @returns - [void]
		#>
	[void] executeQuery([String] $progressBarActivityName){
		$this.executeQuery($true, $progressBarActivityName)
	}

	<## @method executeQuery
		# @description - Executes the the query specified by the queryObject member property and populates the ids and objects members.
		# @param - showProgressIndicators - [bool] whether or not to show the progress bar
		# @param - progressBarActivityName - the [String] to display on the progress bar as the Activity Name
		# @throws - [System.Management.Automation.RuntimeException] - if $progressBarActivityName is null or empty when $showProgressIndicators is true. Technically, you COULD not showProgressIndicators and pass a progressBarActivityName, but it wouldn't matter.
		# @returns - [void]
		#>
	[void] executeQuery([bool] $showProgressIndicators, [String] $progressBarActivityName){
		# calls flush prior to action to ensure we don't have leftover state from the last execution
		$this.flush()
		
		$searchEndpointUrl = "https://$($this.authorizer.orgName).api.identitynow.com/$($this.idnApiVersion)/search"
		$queryBody = $this.generateSearchQueryBody()
		
		# pageNum & numPages only defined up here to deal with scopes bug (blocks in classes seem to define new child scopes
		$pageNum = 1 
		$numPages = 1
		
		# If we are going to showProgressIndicators, we need to fetch one object and use the X-Total-Count header to get the denominator for calculating the progress bar state.
		if ($showProgressIndicators){
			if ($progressBarActivityName -eq $null -or $progressBarActivityName -eq ""){
				throw "[SearchQueryIterator] method 'executeQuery': Must provide a non-empty string value for $progressBarActivityName if $showProgressIndicators is true"
			}
			$this.lastQueryDescription = $progressBarActivityName
			
			# Get count of objects by running the search with different parameters.
			$countingUrl = "${searchEndpointUrl}?limit=1&count=true"

			try{
				$apiResponse = Invoke-WebRequest -Method POST -URI $countingUrl -Body $queryBody -Headers $this.authorizer.getHeader() -ContentType ([SearchQueryIterator]::DEFAULT_CONTENT_TYPE) -UseBasicParsing
				$numObjects= $apiResponse.Headers.'X-Total-Count'
				$this.lastQueryHeaderCount = $numObjects
				$numPages = [Math]::Ceiling($apiResponse.Headers.'X-Total-Count'/$this.pageSize)
			} catch {
				throw ("Error counting objects:$($_.Exception.message) - $(getUsefulErrorCodes($_))")
			}
		}

		if ($numPages){ # Don't need to hit the /search endpoint if there are no objects to fetch
			$searchQueryUrl = "${searchEndpointUrl}?limit=$($this.pageSize)"
			$numObjectsInResponse = 0
			do{ # until all objects have been iterated
				if ($showProgressIndicators){
					Write-Progress -Activity $progressBarActivityName -Status "Obtaining page $pageNum of $numPages. Page size: $($this.pageSize)" -PercentComplete ($pageNum/$numPages*100)
				}
				$apiResponse = Invoke-RestMethod -Method POST -Uri $searchQueryUrl -Body $queryBody -Headers $this.authorizer.getHeader() -ContentType ([SearchQueryIterator]::DEFAULT_CONTENT_TYPE)
				$numObjectsInResponse = $apiResponse.count

				foreach ($object in $apiResponse){
					$this.ids.add($object.id)
					$this.objects[$object.id] = $object
				}

				$lastObject = $this.getObjectByIndex($this.count() - 1)
				$this.searchAfter = @()
				foreach ($dotNotationPath in $this.sorters){
					# Array addition is clean, and reasonably efficient for the small array sizes here.
					# The Invoke-Expression is required because of the possibility of non-top-level sorters accessible by walking the dotNotationPath
					$this.searchAfter += Invoke-Expression "`$lastObject.$dotNotationPath"
				}
				
				$queryBody = $this.generateSearchQueryBody()
				if ($showProgressIndicators) {$pageNum++}
			} while ($numObjectsInResponse -eq $this.pageSize)
			if ($showProgressIndicators) {Write-Progress -Activity $progressBarActivityName -Status "Done" -Completed}
		}
	}
#>

	<## @method ToString
		# @returns - [String] - a string representation of the object
		#>
	[String] ToString(){
		return ($this | fl | Out-String).Trim() -replace "^","`r`n"
	}
	
}
