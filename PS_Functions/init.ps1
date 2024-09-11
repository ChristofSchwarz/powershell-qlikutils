# creates some variables used by all the .ps1 files,
# and grabs the QlikClient certificate from the Certificate Store into var $cert
# and the log function

$currUser = whoami 

$conn = @{
    "server_url" = "https://localhost:4242"
    "auth_header" = @{
                "X-Qlik-User" = "UserDirectory=INTERNAL;UserId=sa_repository"
            }
}

# Define the filename with the current timestamp 
$filename = "$PSScriptRoot\..\log\$this-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt" 
Write-Host $filename
# create the output file
"Running as $currUser" >$filename

function log {
     param ($text)
     Write-Host $text
     $text >>$filename
}

# get the Qlik Certificate
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where {$_.Subject -like "*QlikClient*"}
If ($cert.Length -eq 0) {
    log "QlikClient certificate not found in Certificate Store. Are you running this script as Qlik service user and on the central node?"
    Exit
} 
