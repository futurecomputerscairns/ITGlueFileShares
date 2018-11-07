<#
.SYNOPSIS
This script grabs all shared folders in the current server along with their shared path, disk path and permsissions

.DESCRIPTION
Options:

  -help                  - Display the current help menu
  -silent                - Run the script without printing anything
  -api  <string>         - Declare a file name for an API config file to post flex asset directly to IT Glue 
  -file <string>         - Declare a location to save script output to as a csv
  -organization <string> - Declare the name of the organization

.NOTES
This script is largely a modification on grolo's "Audit File Share Perms" script available at http://poshcode.org/3398.
We thank grolo for doing a lot of the heavy lifting for us.

Author: Mark Jacobs
Author: Caleb Albers

.LINK
https://github.com/itglue/automation

#>

[cmdletbinding()]

Param (
    [switch]$help = $False,
    [switch]$silent = $False,
    [switch]$continuum = $False,
    [string]$api,
    [string]$file,
    [string]$organization = ""
)

# Print Results
function writeOutput {
    Write-Host "Organization Name:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $organization "`n"

    Write-Host "Server:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $currentServer "`n"

    Write-Host "Share Name:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $share "`n"

    Write-Host "Share Path:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $writePath "`n"

    Write-Host "Disk Path:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $DiskPath "`n"

    <#Write-Host "Permissions:  `t" -ForegroundColor Gray -NoNewline
    Write-Host "`t `t" $permissions "`n"#>
}

function updateAPIConfigFile {
    
    $api__flex_asset_type_id = $api_config.flexible_asset_type_id
    
    $api__key_name_ShareName = $api_config.key_name_ShareName
    $api__key_name_ShareDescription = $api_config.key_name_ShareDescription
    $api__key_name_Server = $api_config.key_name_Server
    $api__key_name_SharePath = $api_config.key_name_SharePath
    $api__key_name_DiskPath = $api_config.key_name_DiskPath
    $api__key_name_Permissions = $api_config.key_name_Permissions
    
    
@"
@{
        org_id = '$api__org_id'
        flexible_asset_type_id = '$api__flex_asset_type_id'
    
        key_name_ShareName = '$api__key_name_ShareName'
        key_name_ShareDescription = '$api__key_name_ShareDescription'
        key_name_Server = '$api__key_name_Server'
        key_name_SharePath = '$api__key_name_SharePath'
        key_name_DiskPath = '$api__key_name_DiskPath'
        key_name_Permissions = '$api__key_name_Permissions'
}
"@ | Out-File -FilePath $api -Force
}
    
function formatAPIData {
    
    $api__flex_asset_type_id = $api_config.flexible_asset_type_id
    
    $api__key_name_ShareName = $api_config.key_name_ShareName
    $api__key_name_Server = $api_config.key_name_Server
    $api__key_name_SharePath = $api_config.key_name_SharePath
    $api__key_name_DiskPath = $api_config.key_name_DiskPath
    $api__key_name_Permissions = $api_config.key_name_Permissions
    

    if($api_config.org_id) {
        $api__org_id = $api_config.org_id
    }
    elseif($organization) {

        Write-Host "No organization id was specified in the config file, attempting an `
        auto-match based on the name: " $organization -ForegroundColor Yellow

        $attempted_match = Get-ITGlueOrganizations -filter_name "$organization"

        if($attempted_match.data[0].attributes.name -eq $organization) {
            Write-Host "Auto-match successful. Updating config file with organization id." -ForegroundColor Green

            $api__org_id = $attempted_match.data.id

            updateAPIConfigFile

        }
        else {
            Write-Error "No auto-match was found. Please pass the exact name to -organization <string> or `
            add the organization id to the config file."

            return
        }
    }
    else {
        Write-Error "No organization id was found. Please add an organization id to the config file `
        or attempt a match by putting the full name in the -organization <string> parameter."

        return
    }

    $api__Server_id = (Get-ITGlueConfigurations -filter_organization_id $api__org_id -filter_name $currentServer)[0].id

    $api__body = @{
        type = "flexible_assets"
        attributes = @{
            organization_id = $api__org_id
            flexible_asset_type_id = $api_config.flexible_asset_type_id
            traits = @{
                $api__key_name_ShareName = $share
                $api__key_name_Server = $api__Server_id
                $api__key_name_SharePath = $writePath
                $api__key_name_DiskPath = $DiskPath
                $api__key_name_Permissions = $permissions
            }
        }
    }

    return $api__body
}

if($help) {
    Get-Help $MyInvocation.MyCommand.Path
    exit
}

if(($silent) -and !($api -or $file)) {
    Write-Error -Message "ERROR: Using the silent flag requires a location to save results to." `
                -Category InvalidOperation `
}

    if($continuum) {
        $organization = (Get-ItemProperty "HKLM:\SOFTWARE\Wow6432Node\SAAZOD").SITENAME
    }

    $computer = $env:COMPUTERNAME
    $SaveData = @()

    $Files = gwmi -Class win32_share -ComputerName $computer -Filter "Type=0" | Where-Object{$_.Name -NotMatch "^print|^NETLOGON|^MTATempStore|^prnproc"}
    $shares = $Files| select -ExpandProperty Name
    $description =  $Files| select -ExpandProperty Description
    $path = $Files| select -ExpandProperty Path
    $server= ([regex]::matches($Files, "(?<=[\\][\\])[^\\]+"))

    $i=0
    foreach ($share in $shares) {
        #if( $shares -notlike "print$" -or $shares -notlike "NETLOGON" -or $shares -notlike "MTATempStore$"){
            $acl = $null # or $sharePath[$i]

            $permissions= ""
            Write-Host $share -ForegroundColor Green
            Write-Host $('-' * $share.Length) -ForegroundColor Green
            $currentServer= $server[$i]
            $writePath = "\\$currentServer\$share"



            $files = Get-WMIObject -Class Win32_LogicalShareSecuritySetting -Filter "name='$Share'"  -ComputerName $computer | where-Object {$share -NotLike "print$" -or $share -NotLike "NETLOGON" -or $share -NotLike "MTATempStore$"} 
            if($files){
                $obj = @()
                $ACLS = $files.GetSecurityDescriptor().Descriptor.DACL
                foreach($ACL in $ACLS){
                    $User = $ACL.Trustee.Name
                    if(!($user)){$user = $ACL.Trustee.SID} #If there is no username use SID
                    $Domain = $ACL.Trustee.Domain
                    switch($ACL.AccessMask) {
                        2032127 {$Perm = "Full Control"}
                        1245631 {$Perm = "Change"}
                        1179817 {$Perm = "Read"}
						  
                    }
                    $permissions= $permissions + "<p>$Domain\$user $Perm</p>"
                } # End foreach $ACL
                
                $DiskPath= $path[$i]

                if(!$silent){writeOutput}

                if($url -or $files) {
                    $PostData = @{
                        "Organization" = "$organization"
                        "Share Name" = "$share"
                        
                        "Server" = "$currentServer"
                        "Share Path" = "$writePath"
                        "Disk Path" = "$DiskPath"
                        "Permissions" = "$permissions"
                    }
                }
                if($file) {
                    $SaveData += New-Object PSObject -Property $PostData
                }
                if($api) {
                    try {
                        Import-Module ITGlueAPI
                    }
                    catch {
                        Write-Error "ERROR: The IT Glue API PowerShell module cannot be imported."
                        Write-Error "Please download it from https://github.com/itglue/powershellwrapper, configure it, and try again."
                    }

                    if(test-path $api) {
                        $api_config = Import-LocalizedData -FileName $api

                        Write-Host "File Shares flex asset configuration file found!" -ForegroundColor Green

                        $api__body = formatAPIData # format data for API call
                        $api__org_id = $api__body.attributes.organization_id
                        $api__flex_asset_id = $api_config.flex_asset_id
                        
                        if($api__org_id) {
                            Write-Host "Creating a new flexible asset."
							Write-Host "$api__body.attributes.traits"

                            $api__output_data = New-ITGlueFlexibleAssets -data $api__body

                            $api__output_data
                        }
                    }
                    else {
                        Write-Error "ERROR: File Shares flex asset configuration file was found. Please create one and re-run the script."
                    }
                }

            $i++
            }# end if $file
        #}# end if(notlike)
    } # end foreach $share
    if($file){
        $SaveData | export-csv -Path $file -NoTypeInformation
    }
