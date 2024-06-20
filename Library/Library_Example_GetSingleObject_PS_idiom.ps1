### VERSION 1 - NAIVE ###

$_SPOType_Url = "$API_BASE_URL/v3/accounts?filters=nativeIdentity eq `"$newNELMacctId`" and sourceId eq `"$NELMSrcID`""
$_SPOType_Iterator = [ObjectEndpointIterator]::new($authorizer,$_SPOType_Url)
$_SPOType_Obj = $_SPOType_Iterator.executeQueryForSingleObject("Looking up identityId for NON-USER authoritative acct '$NELMaccountName'")
$log.trace("Proof of execution - _SPOType_Iterator.lastQueryDescription: $($_SPOType_Iterator.lastQueryDescription)")
# Do something with $_SPOType_Obj


### VERSION 2 - BETTER ###

$_SPOType_Url = "$API_BASE_URL/v3/accounts?filters=nativeIdentity eq `"$newNELMacctId`" and sourceId eq `"$NELMSrcID`""
try{
	$_SPOType_Iterator = [ObjectEndpointIterator]::new($authorizer,$_SPOType_Url)
	$script:_SPOType_Obj = $_SPOType_Iterator.executeQueryForSingleObject("Looking up identityId for NON-USER authoritative acct '$NELMaccountName'")
	$log.trace("Proof of execution - _SPOType_Iterator.lastQueryDescription: $($_SPOType_Iterator.lastQueryDescription)")
} catch {
	$log.error([Logger]::getLoggableMultilineErrorString($_))
	continue # or break, depending.
}
# Do something with $_SPOType_Obj.memberProperty
