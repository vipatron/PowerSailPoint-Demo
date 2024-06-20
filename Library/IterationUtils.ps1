# Taken from https://powershell.one/tricks/performance/pipeline#where-objectfast
# Author: Dr. Tobias Weltner (Maybe? not clear which member of the group wrote it)
# Vip's summary of article: By precompiling the "hard-coded" filter function in the begin{} block, you avoid the per-iteration overhead of invoking the filter scriptblock. This can be especially impactful on what the article author describes as "Type A" systems - those on which scriptblock logging is enabled.
# His example showed a 65x speed boost on 100K items. We will filter against 30K identities in this script, so we'd expect significant speed boosts.

# ALGO: In the begin{} block, we craft the filter process from a string, cast it as a scriptblock, then get a steppable pipeline to which we can pass the incoming $_ value during the process{} block. End{} just closes out the pipeline.
function Where-ObjectFast {
  param ([ScriptBlock] $FilterScript)
  
  begin {
    # construct a hard-coded anonymous simple filter function (returns piped object if filter returns true):
    $code = @"
& {
  process { 
    if ($FilterScript) 
    { `$_ }
  }
}
"@
    # turn code into a scriptblock and invoke it via a steppable pipeline so we can feed in data as it comes in via the pipeline:
    $pip = [ScriptBlock]::Create($code).GetSteppablePipeline()
    $pip.Begin($true)
  }
  process {
    # forward incoming pipeline data to the custom scriptblock:
    $pip.Process($_)
  }
  end {
    $pip.End()
  }
}

# ALGO: In the begin{} block, we craft a simple function with begin, process, and end blocks from a string, cast it as a scriptblock, then get a steppable pipeline to which we can pass the incoming $_ value during the process{} block. End{} just closes out the pipeline.
function Foreach-ObjectFast
{
  param
  (
    [ScriptBlock] $Process, #Process comes first so that a single, unnamed scriptblock arg gets treated as the Process block.
    
    [ScriptBlock] $Begin,
    
    [ScriptBlock] $End
  )
  
  begin
  {
    # construct a hard-coded anonymous simple function from
    # the submitted scriptblocks:
    $code = @"
& {
  begin
  {
    $Begin
  }
  process
  {
    $Process
  }
  end
  {
    $End
  }
}
"@
    # turn code into a scriptblock and invoke it
    # via a steppable pipeline so we can feed in data
    # as it comes in via the pipeline:
    $pip = [ScriptBlock]::Create($code).GetSteppablePipeline()
    $pip.Begin($true)
  }
  process 
  {
    # forward incoming pipeline data to the custom scriptblock:
    $pip.Process($_)
  }
  end
  {
    $pip.End()
  }
}