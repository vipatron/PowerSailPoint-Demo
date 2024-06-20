### USING String[] of attributes in dot notation ###

$_SPOType_Url = "$API_BASE_URL/v3/accounts?filters=nativeIdentity eq `"$newNELMacctId`" and sourceId eq `"$NELMSrcID`""
try{
	$_SPOType_Iterator = [ObjectEndpointIterator]::new($authorizer,$_SPOType_Url)
	$_SPOType_Iterator.executeQuery("Looking up identityId for NON-USER authoritative acct '$NELMaccountName'")
	$log.trace("Proof of execution - _SPOType_Iterator.lastQueryDescription: $($_SPOType_Iterator.lastQueryDescription)")

	$script:_SPOType_Array = $_SPOType_Iterator.generateObjectArray(@("id", "name")) 
} catch {
	$log.error([Logger]::getLoggableMultilineErrorString($_))
	continue # or break, depending.
}
# Do something with $attributeArray
$log.info("_SPOType_Array [$($_SPOType_Array.count)]")
# $log.info("_SPOType_Array [$($_SPOType_Array.count)]: $($_SPOType_Array | ft | Out-String)")


### USING SIMPLE FILTER TABLE ###

$_SPOType_Url = "$API_BASE_URL/v3/accounts?filters=sourceName co `"AD`""
try{
	$_SPOType_Iterator = [ObjectEndpointIterator]::new($authorizer,$_SPOType_Url)
	$_SPOType_Iterator.executeQuery("Looking up identityId for NON-USER authoritative acct '$NELMaccountName'")
	$log.trace("Proof of execution - _SPOType_Iterator.lastQueryDescription: $($_SPOType_Iterator.lastQueryDescription)")

	$inputObjectTransformFilterTable = [PSCustomObject]@{
		name = {$Input.name}
		provisioningFeatures = { ($Input.attributes.memberOf | Where-Object {$_.name -like "*Admin*"}) -join " | " }
	}
	$script:_SPOType_Array = $_SPOType_Iterator.generateObjectArrayUsingInputVariable($inputObjectTransformFilterTable) 
} catch {
	$log.error([Logger]::getLoggableMultilineErrorString($_))
	continue # or break, depending.
}
# Do something with $attributeArray



### TODO - COMPLEX FILTER TABLES USING $Input VARIABLE ###

$_SPOType_Url = "$API_BASE_URL/v3/accounts?filters=sourceName co `"AD`""
try{
	$_SPOType_Iterator = [ObjectEndpointIterator]::new($authorizer,$_SPOType_Url)
	$_SPOType_Iterator.executeQuery("Looking up identityId for NON-USER authoritative acct '$NELMaccountName'")
	$log.trace("Proof of execution - _SPOType_Iterator.lastQueryDescription: $($_SPOType_Iterator.lastQueryDescription)")

	$inputObjectTransformFilterTable = [PSCustomObject]@{
		name = {$Input.name}
		provisioningFeatures = { ($Input.attributes.memberOf | Where-Object {$_.name -like "*Admin*"}) -join " | " }
	}
	$script:_SPOType_Array = $_SPOType_Iterator.generateObjectArrayUsingInputVariable($inputObjectTransformFilterTable) 
} catch {
	$log.error([Logger]::getLoggableMultilineErrorString($_))
	continue # or break, depending.
}
# Do something with $attributeArray

