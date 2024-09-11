###############################################################################################################################
#   ABOUT
###############################################################################################################################
# 
# this is a script to backup essentials parts of this qlik site

# 1. creates new folder with date as name
# 2. exports apps (as QVF) into the backup folder
# 3. copies a local folder structure into the backup folder (e.g. QVD layers, the QDF folder ...)
# 4. cleanes other backup folders that are no longer needed 
# 5. writes-out transcript log in \Log location

# Version 1.0.0  2024-09-03  by Christof Schwarz
# Version 1.0.1  2024-09-03  by Christof Schwarz: support to run script from Rim Node


param (
     [Parameter(Mandatory = $true)] $streamFilter,  # filter parameter for GET qrs/stream call
     # e.g.: id eq 12345678-1234-1234-1234-123456789
     # or  : name eq 'Benelux'
     # or  : tags.name eq 'StandaloneCountries'
     [Parameter(Mandatory = $false)] $backupFolder, # relative folder to this script which should 
     # be backed up together with the apps

     [Parameter(Mandatory = $true)] $cleanup # true or false to check if older backup
     # folders should be removed according to the retention rules 1 .. 3 below
)

# It outputs the backups into a subfolder \Backup\QDF and \Backup\Apps which is in the same
# parent folder as this backup_script.ps1 file is in.

$this = $($MyInvocation.MyCommand.Name)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$logfilename = "$scriptDirectory\Log\$this-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt" 

# include file to communicate with QRS API
. "$PSScriptRoot\PS_Functions\fn-qrs-api.ps1"

$justSimulate = $false # if $true, no QVF export will be made, just printed on screen and log


# if Log Folder does not exist, create it now.
if (-not (Test-Path -Path "$scriptDirectory\Log" -PathType "Container")) {
    New-Item -Path "$scriptDirectory\Log" -ItemType "Directory" | Out-Null
}

Start-Transcript -path $logfilename -Append  # start transscripting into Log file
Write-Host -b Black "Running as user $(WhoAmI) on node $(Hostname)"

###############################################################################################################################
#   CLEANUP RETENTION RULES
###############################################################################################################################
# 
# Rule 1: keep backups of 1.January of each year
$rule1 = $true

# Rule 2: keep rolling last 12 backups of 1. day of each month
$rule2 = $true

# Rule 3: keep rolling last 3 days' backups
$rule3 = $true

If ("$(hostname)" -like "???U*") {
    Write-Host "Running on UAT environment. No Rule1 and Rule2 for backup retention"
    $rule1 = $false
    $rule2 = $false
} 

###############################################################################################################################
#   FUNCTIONS
###############################################################################################################################

function bulkExportApps  {
    param ( 
        [Parameter(Mandatory = $true)] $filter, # filter parameter for QRS API GET app
        [Parameter(Mandatory = $true)] $skipData, # true (export w/o data) or $false (export with data)
        [Parameter(Mandatory = $true)] $exportRootFolder,
        [Parameter(Mandatory = $true)] $streamSubfolder
        # also uses global variables
        # - $conn 
        # - $nodes 
    )

    $call = @("GET", "qrs/app?filter=$filter")
    # log "$($call[0]) $($call[1])"
    $apps = QRS_API -conn $conn -cert $cert -method $call[0] -api $call[1] 
    $appArr = @()
    
    foreach ($app in $apps) {
        $appArr += "`"$($app.id)`""
    }
    
    Write-Host "$($appArr.Length) apps in stream with skipData: $skipData"
    
    if ($appArr.Length -gt 0 -and -not $justSimulate) {
    
        $call = @("POST", "qrs/app/exportapps/$(New-Guid)?skipData=$skipData&exportScope=all")
        # log "$($call[0]) $($call[1])"

        $body = "[" + ($appArr -Join ",") + "]"

        $res = QRS_API -conn $conn -cert $cert -method $call[0] -api $call[1] -body $body
    
        Write-Host ($res | ConvertTo-Json)
        if (-not $res.downloadPath) {
            Write-Host -f Yellow "Error in exportapps API call. Script stopped."
            Exit
        }
        # fix downloadPath if the script is run from another node
        $res.downloadPath = $res.downloadPath.replace("C:\", "\\$($nodes.hostname)\C$\")
        $statusFile = "$($res.downloadPath)\status.txt"
    
        # Initialize the first line variable
        $firstLine = ""
        $retry = 0
        $maxRetries = 60 # max wait time in 2xseconds (60 => 2 minutes)
    
        Write-Host "checking export status in file '$statusFile'"

        # Loop until the first line reads "DONE"
        while (-not ($firstLine -like "*Done") -and $retry -lt $maxRetries) {
            try {
                # Read the first line of the file
                $firstLine = Get-Content -Path $statusFile -TotalCount 1
                # Optional: Display the current first line (for debugging)
                Write-Host "File says: $firstLine"
                # Wait for a short interval before checking again (e.g., 1 second)
                Start-Sleep -Seconds 2
                $retry++
            } catch {
                # Handle any errors that might occur during file reading
                Write-Host "An error occurred while reading the file: $statusFile"
            }
        }
    
        if ($firstLine -like "*Done") {
            
            # if folder for the stream does not exist, create it now.
            if (-not (Test-Path -Path "$exportRootFolder\$streamSubfolder")) {
                New-Item -Path "$exportRootFolder\$streamSubfolder" -ItemType "Directory" | Out-Null
            }
            Move-Item "$($res.downloadPath)\*.qvf" -Destination "$exportRootFolder\$streamSubfolder" -Force
            Write-Host "*.qvf files moved to '$exportRootFolder\$streamSubfolder'"
    
            Remove-Item $res.downloadPath -Recurse -Force
            Write-Host "Downloadpath $($res.downloadPath) removed again."
        } 
        else {
            Write-Host "waited $maxRetry seconds but the status.txt doesnt get to 'Done'"
        }
    }

}

###############################################################################################################################
#    MAIN CODE
###############################################################################################################################

# where to backup
# $backupParentFolder 		= 'D:\Qlik_Sense\02-Acceptance\Sense_Storage\Backup\SnapsQDF'
# Changed to work in a relative path location (Christof Schwarz)

# $backupParentFolder = "$scriptDirectory\SnapsQDF"
$backupParentFolder = "$scriptDirectory\Backup"
# if backup ParentFolder does not exist, create it now.
if (-not (Test-Path -Path $backupParentFolder -PathType "Container")) {
    New-Item -Path $backupParentFolder -ItemType "Directory" | Out-Null
}

$todaysBackupFolder = "$backupParentFolder\$(Get-Date -UFormat '%Y%m%d_%H%M')"

If (Test-Path -Path $todaysBackupFolder) {
    Remove-Item $todaysBackupFolder -Recurse -Force -Confirm:$false
    # Remove-Item $todaysBackupFolder -Force -Confirm:$false
    Write-Host "Removed folder $todaysBackupFolder as it existed already from another run of this script today."
}

Write-Host "Creating Folder $todaysBackupFolder"
New-Item -Path $todaysBackupFolder -ItemType "Directory" | out-null



###############################################################################################################################
#     EXPORTING APPS AS QVF
###############################################################################################################################

$nodes = QRS_API -conn $conn -cert $cert -method "GET" -api "qrs/ServerNodeConfiguration?filter=name eq 'Central'"
if ($nodes.hostname) {
    Write-Host "Central node of this cluster is $($nodes.hostname)"
    # manipulate the server_url attribute to use the central node url instead of localhost
    $conn.server_url = "https://$($nodes.hostname):4242"
} 
else {
    Write-Host "Error: cannot find out which is the central node of this environment."
    Exit
}

$call = @("GET", "qrs/stream?filter=$streamFilter")
# log "$($call[0]) $($call[1])"

$streams = QRS_API -conn $conn -cert $cert -method $call[0] -api $call[1] 

foreach ($stream in $streams) {
    Write-Host -f Cyan "`nLooking for apps in stream '$($stream.name)' ($($stream.id))"
    # Log "Stream $($stream.id) $($stream.name)"
 
     # if folder for the Apps does not exist, create it now.
     if (-not (Test-Path -Path "$todaysBackupFolder\Apps")) {
        New-Item -Path "$todaysBackupFolder\Apps" -ItemType "Directory" | Out-Null
    }

    bulkExportApps -filter "stream.id eq $($stream.id) and tags.name eq 'backupWithoutData'"  `
        -skipData $true -exportRootFolder "$todaysBackupFolder\Apps" -streamSubfolder $stream.name
 
    bulkExportApps -filter "stream.id eq $($stream.id) and tags.name eq 'backupWithData'"   `
        -skipData $false -exportRootFolder "$todaysBackupFolder\Apps" -streamSubfolder $stream.name

}

###############################################################################################################################
#     BACKING UP FOLDERS
###############################################################################################################################
# 

if ($backupFolder) {
Write-Host "Starting backup of folder '$backupFolder' at $(Get-Date)"


# folders to backup:
# $QDF = 'D:\Qlik_Sense\02-Acceptance\Sense_Storage\1.QDF\01.SDWH\' 
$QDF = "$scriptDirectory\$backupFolder" 

copy-item  $QDF -Destination "$todaysBackupFolder\QDF" -Recurse
##copy-item  $QDFRestricted -Destination $todaysBackupFolder\QDFRestricted -Recurse

Write-Host "File Backup Completed into folder '$todaysBackupFolder'"

}


###############################################################################################################################
#       CLEANUP FOLDERS
###############################################################################################################################

if ($cleanup) {
    Write-Host "**start Cleanup Folder Checks**"
    Write-Host "Retention Rule1 = $rule1, Rule2 = $rule2, Rule3 = $rule3"
    ForEach ($folder in get-childitem $backupParentFolder -Directory) {
        
        if ($folder -match '^\d{8}' -and "$backupParentFolder\$folder" -ne $todaysBackupFolder) {
            # the folder starts with 8 digits
            # don't act on the folder just created before/above

            $keepFolder = ""
            # get Folder Date from the first 8 digits.
            $folderDate = [datetime]::ParseExact("$folder".Substring(0, 8), "yyyyMMdd", $null)
            
            # Write-Host "Folder $folder is from $folderDate"

            Write-Host "`nFolder " -NoNewline
            Write-Host -f Cyan "'$folder' " -NoNewline
            if ($rule1 -and $folderDate.Day -eq 1 -and $folderDate.Month -eq 1) {
                $keepFolder = "keep because first of year"
            } 
            elseif ($rule2 -and $folderDate.Day -eq 1 -and $folderDate.Year -eq (Get-Date).Year) {
                $keepFolder = "keep because first of month in current year"
            } 
            elseif ($rule2 -and $folderDate.Day -eq 1 -and $folderDate.Year -eq ((Get-Date).Year - 1) -and $folderDate.Month -gt (Get-Date).Month) {
                $keepFolder = "keep because first of month in previous year"
            } 
            elseif ($rule3 -and $folderDate -gt (Get-Date).AddDays(-3)) {
                $keepFolder = "keep because less than 3 days old"
            } 

            if ($keepFolder) {
                Write-Host -f Green $keepFolder
            } else {
                Write-Host -f Red "delete folder"
                Remove-Item "$backupParentFolder\$folder" -Recurse -Force -Confirm:$false
                # Remove-Item "$backupParentFolder\$folder"
            }
        }
    }
}
else {
    Write-Host "**Skip Cleanup Folder**"
}
Stop-Transcript

