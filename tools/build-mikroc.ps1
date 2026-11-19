param(
    [Parameter(Mandatory=$true)][string]$CompilerRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot
)
$ErrorActionPreference = 'Stop'

# The IDE records this raw Windows argument format in hello.log.
$libraries = '"__Lib_Math.emcl" "__Lib_MathDouble.emcl" "__Lib_Delays.emcl" ' +
    '"__Lib_System_F7xx.emcl" "__Lib_GPIO_32F7xx_Defs.emcl" "__Lib_GPIO_32F7xx.emcl"'
$search = '-SP"{0}\Defs\" -SP"{0}\Uses\ST M7\" -SP"{1}\" -IP"{0}\Uses\ST M7\"' -f $CompilerRoot, $ProjectRoot
$output = '-N"{0}\hello.mcpar"' -f $ProjectRoot
$arguments = '-MSF -DBG -pSTM32F746ZG -BIN -LHF -DL -SSA -O11111114 -fo16 ' +
    "$output $search " + '"hello.c" ' + $libraries

$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = Join-Path $CompilerRoot 'mikroCARM.exe'
$start.WorkingDirectory = $ProjectRoot
$start.Arguments = $arguments
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$compiler = [System.Diagnostics.Process]::Start($start)
$compiler.StandardOutput.ReadToEnd()
$compiler.WaitForExit()
exit $compiler.ExitCode
