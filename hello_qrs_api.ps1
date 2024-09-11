$this = $($MyInvocation.MyCommand.Name)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$logfilename = "$scriptDirectory\Log\$this-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt" 

# include file to communicate with QRS API
. "$PSScriptRoot\PS_Functions\fn-qrs-api.ps1"

Write-Host -b Black "Running as user $(WhoAmI) on node $(Hostname)"

###############################################################################################################################
#    MAIN CODE
###############################################################################################################################

$res = QRS_API -conn $conn -cert $cert -method "GET" -api "qrs/about"
Write-Host ($res | ConvertTo-Json)
