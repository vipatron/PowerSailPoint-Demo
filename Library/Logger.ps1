enum LogLevel {
	Fatal = 0
	Error = 1
	Warning = 2
	Info = 3
	Debug = 4
	Trace = 5
}


# LogStyle - simple class that holds color names. Using the constructors provides name validation.
class LogStyle{

	# STATIC METHODS

	static [bool] validateConsoleColorName([string] $colorName){ # throws exception on validation failure.
		if ($colorName -notin [ConsoleColor].GetEnumNames()){
			# Get-PSCallStack -Verbose
			throw ("'{0}' isn't a ConsoleColor. Specify a value from below:`n ($([ConsoleColor].GetEnumNames() -join ' | '))" -f $colorName)
		}
		return $true;
	}
	
	# PROPERTIES
	
	[String] $foregroundColor
	[String] $backgroundColor

	
	# CONSTRUCTORS

	LogStyle(){} # NO-ARG, default style

	LogStyle([string] $colorName){ # no background, colored text only
    [LogStyle]::validateConsoleColorName($colorName) # throws exception if validation fails.		
		$this.foregroundColor = $colorName
	}

	LogStyle([ConsoleColor] $ForegroundColor){# no background, colored text only
		$this.foregroundColor = $ForegroundColor
	}
	
	LogStyle([string] $foregroundColorName, $backgroundColorName){
    [LogStyle]::validateConsoleColorName($foregroundColorName) # throws exception if validation fails.		
    [LogStyle]::validateConsoleColorName($backgroundColorName) # throws exception if validation fails.		
		$this.foregroundColor = $foregroundColorName
		$this.backgroundColor = $backgroundColorName
	}

	LogStyle([ConsoleColor] $ForegroundColor, [ConsoleColor] $BackgroundColor){
		$this.foregroundColor = $ForegroundColor
		$this.backgroundColor = $BackgroundColor
	}

	[String] ToString(){
		return ([PSCustomObject]@{
			foregroundColor =  $this.foregroundColor
			backgroundColor =  $this.backgroundColor
		} | fl | Out-String).Trim()
	}
}

# LogStyleSet - simple container class that holds LogStyles for every level of message, with default values for each
class LogStyleSet{
	
	# PROPERTIES
	
	# Boring Style
	[LogStyle] $fatal = [LogStyle]::new('White', 'DarkRed')
	[LogStyle] $error = [LogStyle]::new('Red')
	[LogStyle] $warning = [LogStyle]::new('Yellow')
	[LogStyle] $info = [LogStyle]::new('Yellow', 'DarkCyan')
	[LogStyle] $debug = [LogStyle]::new('Green')
	[LogStyle] $trace = [LogStyle]::new('Gray')
	
	# STATIC METHODS
	static [LogStyleSet] generateBoldLogStyles(){
		$result = [LogStyleSet]::new()
		
		$result.fatal = [LogStyle]::new('White', 'DarkRed')
		# $result.error = [LogStyle]::new('Red', 'Black')
		$result.error = [LogStyle]::new('Black', 'Red')
		# $result.warning = [LogStyle]::new('Yellow', 'Black')
		$result.warning = [LogStyle]::new('Black', 'Yellow')
		$result.info = [LogStyle]::new('Green','DarkGray')
		$result.debug = [LogStyle]::new('Green', 'DarkCyan')
		$result.trace = [LogStyle]::new('Green', 'Magenta')
		
		return $result
	}
	
	# METHODS
	
	
	[String] ToString(){
		$LogStyleRepresentation = [System.Collections.ArrayList]::new()
		foreach($level in @("fatal", "error", "warning", "info", "debug", "trace")){
			$LogStyleRepresentation.add([PSCustomObject]@{
				level = $level
				foregroundColor = $this.$level.foregroundColor
				backgroundColor = $this.$level.backgroundColor
			})
		}
		return ($LogStyleRepresentation | ft -wrap | Out-String)
	}
}

class Logger {	

	# PROPERTIES
	
	# hidden [String] $runtimeEnvironment = "Console"
	[String] $name
	[LogLevel] $level = [LogLevel]::Error
	[LogStyleSet] $logStyles = [LogStyleSet]::new()
	[String] $logFile # default: null - no writing to any file unless provided with a path
	
	# HIDDEN STATIC METHODS
	
	# Transforms "\path\to\callingScript.ps1" into "\path\to\log\callingScript.log"
	static [String] getLogFileNameMatchingCallingScript(){
		$callstack = Get-PSCallStack
		return ($callstack)[$callstack.count - 2].scriptName -replace '([^\\]+).ps1$','log\$1.log' 
	}
	
	hidden static [String] generateLogPrefix([Logger] $logger, [LogLevel] $messageLevel ){
		# $timeStamp = (Get-Date)
		return "{0} : {1} : {2} : " -f $messageLevel.toString().toUpper().padRight(7), (Get-Date).toString("yyyy-MM-dd HH:mm:ss.fff"), $logger.name
	}

	hidden static [void] writeToConsole([LogStyle] $logStyle, [String] $logLine){
		if ($logStyle -eq $null -or ($logStyle.foregroundColor -eq $null -and $logStyle.backgroundColor -eq $null)){
			Write-Host $logLine
		} else { # $logStyle contains one or both values
			if ($logStyle.foregroundColor -eq $null){ # backgroundColor is the only non-null color
				Write-Host -BackgroundColor $logStyle.backgroundColor $logLine
			} elseif ($logStyle.backgroundColor -eq $null){# foregroundColor is the only non-null color
				Write-Host -ForegroundColor $logStyle.foregroundColor $logLine
			} else { # both colors are non-null
				Write-Host -ForegroundColor $logStyle.foregroundColor -BackgroundColor $logStyle.backgroundColor $logLine
			}
		}
	}

	hidden static [void] validateLoggerName($name){ # Throws exception on failure
		if ([string]::IsNullOrWhitespace($name)){
			throw "Logger cannot be instantiated without a name"
		}
	}
	
	# STATIC METHODS
	static [string] getLoggableMultilineErrorString(
		[System.Management.Automation.ErrorRecord] $error
	){
		if ($error.toString() -ne $error.Exception.ErrorRecord){
			return "{0}`n{1}`n{2}`n{3}" -f $error.toString() , $error.Exception.ErrorRecord, $error.InvocationInfo.PositionMessage, $error.ScriptStackTrace
		} else {
			return "{0}`n{1}`n{2}" -f $error.Exception.ErrorRecord, $error.InvocationInfo.PositionMessage, $error.ScriptStackTrace
		}
	}
	
	# CONSTRUCTORS
	Logger([String] $name){
# Write-Host -foregroundColor Yellow "In name-only constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
	}
	
	Logger([String] $name, [LogLevel] $level, [LogStyleSet] $customLogStyles, [String] $logFile){
# Write-Host -foregroundColor Yellow "In full-arg constructor"		
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.level = $level
		$this.logStyles = $customLogStyles
		$this.logFile = $logFile
	}

	Logger([String] $name, [LogStyleSet] $customLogStyles, [String] $logFile){
# Write-Host -foregroundColor Yellow "In no level constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.logStyles = $customLogStyles
		$this.logFile = $logFile
	}

	Logger([String] $name, [LogLevel] $level, [String] $logFile){
# Write-Host -foregroundColor Yellow "In no customLogStyles constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.level = $level
		$this.logFile = $logFile
	}
	
	Logger([String] $name, [LogLevel] $level, [LogStyleSet] $customLogStyles){
# Write-Host -foregroundColor Yellow "In no logfile constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.level = $level
		$this.logStyles = $customLogStyles
	}

	Logger([String] $name, [LogLevel] $level){
# Write-Host -foregroundColor Yellow "In level-only constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.level = $level
	}

	Logger([String] $name, [LogStyleSet] $customLogStyles){
# Write-Host -foregroundColor Yellow "In customLogStyles-only constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		$this.logStyles = $customLogStyles
	}

	Logger([String] $name, [String] $logFileOrLogLevelName){
# Write-Host -foregroundColor Yellow "In string-only constructor"
		[Logger]::validateLoggerName($name)
		$this.name = $name
		if ($logFileOrLogLevelName -in [LogLevel].GetEnumNames()){
			$this.level = [LogLevel] $logFileOrLogLevelName
		} else {
			$this.logFile = $logFileOrLogLevelName
		}
	}
	
	# HIDDEN METHODS

	# writes to console using logStyles
	# if this object has a logfile property, will also write to that file, and will create the intermediate folder structure if necessary.
	hidden [void] processLogMessage ([LogLevel] $messageLevel, [LogStyle] $logStyle, [String] $message){
		if ($this.level -ge $messageLevel){
			$logLine = "{0}{1}" -f [Logger]::generateLogPrefix($this, $messageLevel), $message
			if ($this.logFile -ne $null){
				if (-Not (Test-Path $this.logFile)){
					$enclosingFolder = $this.logFile -replace '([^\\]+)$','' # take off every but the final backslash
					New-Item -Path $enclosingFolder -ItemType Directory -Force # force turns this into the bash command "mkdir -p", but does not overwrite folder if it exists, it just returns it.
					# NOTE: we don't need to make the logfile, because the call to Out-File below takes care of that.
				}

				# Add-Content $this.logFile -Value $logLine
				$logLine | Out-File -FilePath $this.logFile -Append
			}
			[Logger]::writeToConsole($logStyle, $logLine)
		}
		# # Write-Host ((Get-PSCallStack)[0].InvocationInfo.PositionMessage | Out-String)
		# # Write-Host ((Get-PSCallStack)[0].InvocationInfo | fl | Out-String)
		# Write-Host (Get-PSCallStack | out-string)
		# Write-Host -ForegroundColor Cyan "messageLevel: $messageLevel"
		# Write-Host -ForegroundColor Cyan "logStyle: $($logStyle | ft | out-string)"
		# Write-Host -ForegroundColor Cyan "message: $message"
		
	}
		
	hidden [void] processLogMessage ([LogLevel] $messageLevel, [String] $message){
		$defaultLogStyle = $this.logStyles.$messageLevel
# Write-Host -BackgroundColor DarkCyan -ForegroundColor Magenta "DEFAULT LOG STYLE FOR MESSAGE LEVEL ${messageLevel}:`n$($defaultLogStyle | fl | out-string)"
		$this.processLogMessage($messageLevel, $defaultLogStyle, $message)
	}	
	
	# PUBLIC METHODS
	
	[void] fatal ([String] $message){
		$this.processLogMessage([LogLevel]::fatal, $message)
	}

	[void] fatal ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::fatal, $logStyle, $message)
	}
	
	[void] error ([String] $message){
		$this.processLogMessage([LogLevel]::error, $message)
	}

	[void] error ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::error, $logStyle, $message)
	}
	
	[void] warning ([String] $message){
		$this.processLogMessage([LogLevel]::warning, $message)
	}

	[void] warning ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::warning, $logStyle, $message)
	}
	
	[void] info ([String] $message){
		$this.processLogMessage([LogLevel]::info, $message)
	}

	[void] info ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::info, $logStyle, $message)
	}
	
	[void] debug ([String] $message){
		$this.processLogMessage([LogLevel]::debug, $message)
	}

	[void] debug ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::debug, $logStyle, $message)
	}
	
	[void] trace ([String] $message){
		$this.processLogMessage([LogLevel]::trace, $message)
	}

	[void] trace ([LogStyle] $logStyle, [String] $message){
		$this.processLogMessage([LogLevel]::trace, $logStyle, $message)
	}

	
	[String] ToString(){
		return ($this | fl | Out-String).Trim()
	}

}



# ATTEMPT AT PULLING A DEFAULT COLOR - MAY NEED TO MAKE IT ISE-AWARE
# CONSOLE
# - PS C:\Users\u730339\Documents\TEMP_DUMP\PS Import Tests> $Host.Name
# ConsoleHost

#ISE
# $Host.Name
# Windows PowerShell ISE Host

#Write-Host -ForegroundColor ([System.Console]::ForegroundColor) -BackgroundColor ([System.Console]::BackgroundColor) "message"


# HOW TO GET THE FUNCTION STACK: (use this to construct the log prefix)
# Write-Host -ForegroundColor ([System.Console]::ForegroundColor) -BackgroundColor ([System.Console]::BackgroundColor) "message"

# function inner(){
# Get-PSCallStack -Verbose
# Get-PScallstack | foreach-object {$_ | fl}

# $(Get-PSCallStack)[0].InvocationInfo | fl
# }

# function outer(){
    # inner
# }

# outer

# $(Get-PSCallStack)[0].InvocationInfo | fl