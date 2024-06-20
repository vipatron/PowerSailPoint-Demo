. ../Logger.ps1
# using module .\Logger.psm1
# Import-Module $PSScriptRoot\Logger.psm1 -verbose

# [Logger]::getLogFileNameMatchingCallingScript()
# $testdircreationlogger = [Logger]::new("testdircreationlogger", [Logger]::getLogFileNameMatchingCallingScript())
# ls
# $testdircreationlogger.error("SAMPLE")
# ls 
# exit;

Write-Host -ForegroundColor ([System.Console]::ForegroundColor) -BackgroundColor ([System.Console]::BackgroundColor) "message"

Write-host "testEmptyLogStyle"
$testEmptyLogStyle = [LogStyle]::new()
Write-host "testRedColorNameLogStyle"
$testRedColorNameLogStyle = [LogStyle]::new('Red')
try{
	# $testFailedLogStyle = [LogStyle]::new('Yellowa') # turn off to suppress noise
} catch {
	Write-Error $_.exception
	Write-Error $_.ScriptStackTrace
	Write-Error $_.ErrorDetails
}
Write-host "testRedConsoleColorLogStyle"
$testRedConsoleColorLogStyle = [LogStyle]::new([ConsoleColor]::Red)
Write-host "testRedOnWhiteLogStyle"
$testRedOnWhiteLogStyle = [LogStyle]::new([ConsoleColor]::Red, [ConsoleColor]::White)
write-host "colorName: ($colorName)"


$testLogStyleSet = [LogStyleSet]::new()
$testLogStyleSet.fatal = [LogStyle]::new('White', 'Black')
$testLogStyleSet.error = [LogStyle]::new('White', 'DarkMagenta')
$testLogStyleSet.warning = [LogStyle]::new('DarkMagenta','Yellow')
$testLogStyleSet.info = [LogStyle]::new('DarkCyan', 'Yellow')
$testLogStyleSet.debug = [LogStyle]::new('Green', 'DarkGray')
$testLogStyleSet.trace = [LogStyle]::new('DarkCyan', 'Gray')


# In name-only constructor
# In full-arg constructor
# In no level constructor
# In no customLogStyles constructor
# In no logfile constructor
# In level-only constructor
# In customLogStyles-only constructor
# In string-only constructor
# In string-only constructor
$loggers = @()
$loggers += [Logger]::new("0-DefaultLogger")
$loggers += [Logger]::new("1-Debug|CustomStyles|Logfile", "debug", $testLogStyleSet, [Logger]::getLogFileNameMatchingCallingScript())
$loggers += [Logger]::new("2-CustomStyles|Logfile", $testLogStyleSet, [Logger]::getLogFileNameMatchingCallingScript())
$loggers += [Logger]::new("3-Debug|Logfile", "debug", [Logger]::getLogFileNameMatchingCallingScript())
$loggers += [Logger]::new("4-Debug|CustomStyles", "debug", $testLogStyleSet)
$loggers += [Logger]::new("5-Debug", [LogLevel]"debug")
$loggers += [Logger]::new("6-CustomStyles", $testLogStyleSet)
$loggers += [Logger]::new("7-Logfile", [Logger]::getLogFileNameMatchingCallingScript())
$loggers += [Logger]::new("8-Debug", "debug")
$loggers += [Logger]::new("9-Debug|BOLDStyle", "debug", [LogStyleSet]::generateBoldLogStyles())

# $i = 0
# foreach ($logger in $loggers){
	# Write-Host -ForegroundColor Red "LOGGER #${i}"
	# Write-Host -BackgroundColor DarkGray "$($logger | fl | out-string)========================`n$($logger | ConvertTo-JSON)"
	# $i++
# }
echo "yolo"


$fatalLogStyle = [LogStyle]::new('DarkRed', 'White')
$errorLogStyle = [LogStyle]::new('DarkRed', 'Yellow')
$warningLogStyle = [LogStyle]::new('DarkRed', 'Gray')
$infoLogStyle = [LogStyle]::new('DarkRed', 'Cyan')
$debugLogStyle = [LogStyle]::new('DarkRed', 'Green')
$traceLogStyle = [LogStyle]::new('DarkRed', 'Magenta')

foreach ($logger in $loggers){
	Write-Host  -ForegroundColor Yellow -BackgroundColor DarkCyan ($logger | Select-Object level, @{n="logStyles"; e={$_.logStyles | ConvertTo-Json}},name, logFile | fl | Out-String) # | out-string)
	# Write-Host -BackgroundColor DarkCyan -ForegroundColor Magenta ($logger | ConvertTo-JSON)

	$logger.fatal("Example fatal message")
	$logger.fatal($fatalLogStyle, "Example fatal message with custom LogStyle")
	$logger.error("Example error message")
	$logger.error($errorLogStyle, "Example error message with custom LogStyle")
	$logger.warning("Example warning message")
	$logger.warning($warningLogStyle, "Example warning message with custom LogStyle")
	$logger.info("Example info message")
	$logger.info($infoLogStyle, "Example info message with custom LogStyle")
	$logger.debug("Example debug message")
	$logger.debug($debugLogStyle, "Example debug message with custom LogStyle")
	$logger.trace("SHOULD NOT SEE THIS trace message")
	$logger.trace($traceLogStyle, "SHOULD NOT SEE THIS trace message with custom LogStyle")
	$logger.level = [LogLevel]::trace
	$logger | fl
	$logger.trace("Example trace message")
	$logger.trace($traceLogStyle, "Example trace message with custom LogStyle")
	# $logger.debug($debugLogStyle, ($logger | fl | Out-String))
}