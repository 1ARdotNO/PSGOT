##Author Einar Stenberg


function Initialize-PSGOT {
    param(
        [Parameter(Mandatory = $true)]$path
    )
    
    if (!(test-path $path)) { New-Item -ItemType Directory -Path $path }
    else {
        Write-Output "$path already exists"
    }
    if (!(test-path $path\config.json)) {
        [pscustomobject]@{
            psgotpath   = $path
            wingetrepos = [pscustomobject]@{
                official = [pscustomobject]@{
                    url          = "https://github.com/microsoft/winget-pkgs.git"
                    manifestpath = "manifests"
                }
            }
        } | ConvertTo-Json -Depth 10 | Out-File $path\config.json
    }
    else {
        Write-Output "$path\config.json already exists"
    }
    #create app configs
    new-item -ItemType Directory $path\appconfig -ErrorAction SilentlyContinue | Out-Null
    [pscustomobject]@{
        appidentifier    = "asdasd.asdasd"
        name             = "Applicationprettyname"
        Description      = "Descriptionlongtext"
        Publisher        = "Publisher"
        Category         = "Set category, must exist!"
        Restartbehaviour = ""
        Installbehavior  = "user or system"

    } | ConvertTo-Json -Depth 10 | Out-File $path\appconfig\_template.json
    #downloadintuneutil
    Invoke-WebRequest https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/IntuneWinAppUtil.exe?raw=true -OutFile $path\IntuneWinAppUtil.exe
    #download repo's
    if (. git) {
        $config = Get-Content "$path\config.json" | ConvertFrom-Json
        new-item -ItemType Directory $path\winget -ErrorAction SilentlyContinue | Out-Null
        $config.wingetrepos | ForEach-Object {
            new-item -ItemType Directory "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)" -ErrorAction SilentlyContinue | Out-Null
            if (test-path "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)\.git") {
                write-output "Updating existing $($_.url)"
                . git -C "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)" pull
            }
            else {
                write-output "Cloning fresh $($_.url)"
                . git clone $_.$(($_ | get-member | where membertype -eq noteproperty).name).url "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)"
            }
        }
    }
    else {
        write-error "git missing! please install!"
    }

}


function New-PSGOTIntuneWin {
    param(
        $PSGOTpath = "c:\temp\psgot",
        $repotype = "winget",
        $reponame = "official",
        [Parameter(ValueFromPipeline)]$appname,
        $version = "newest",
        $locale = "en-US",
        $Architecture = "x64",
        $installtype= "exe"
    )
    BEGIN {
        $config = Get-Content "$PSGOTpath\config.json" | ConvertFrom-Json
        $manifestpath = "$PSGOTpath\$repotype\$reponame\$($config.wingetrepos.$($reponame).manifestpath)"
        if (!$GLOBAL:yamlimport) {
            $GLOBAL:yamlimport = gci $manifestpath -Recurse -File | where name -like "*installer*" | ForEach-Object {
                get-content $_.FullName | convertfrom-yaml
            }
        }   
    }
    PROCESS {
        switch ($repotype) {
            winget {
                $tinput = $appname
                $available = $GLOBAL:yamlimport | where { $_.PackageIdentifier -eq $tinput }
                $newest = 
                if ($version -like "*.*"){
                    $available | where { $_.packageversion -eq $version.tostring() }
                }
                elseif ($available.packageversion -gt 1) {
                    $versions = $available.packageversion | ForEach-Object {
                        $tempversion = $_
                        if ($tempversion -notlike "*.*") {
                            [pscustomobject]@{
                                rawversion = $tempversion
                                version = [version]"$tempversion.0"
                            }
                        }
                        else { 
                            [pscustomobject]@{
                                rawversion = $tempversion
                                version = [version]$_ 
                            }
                        }
                        
                    } | sort version -Descending
                    $newestversion = $versions[0]

                    $available | where { $_.packageversion -eq $newestversion.rawversion }
                }
                else { $available }
                $installer = $newest.installers
                #determineinstallertype
                $installertype = if ($newest.InstallerType) { $newest.InstallerType }else { $installer.InstallerType }
                #selectinstallertype
                if ($installertype -gt 1) {
                    if($installtype -eq "exe"){
                        if ($installertype | where { $_ -ne "msi" }) { $installer = $installer | where InstallerUrl -like "*.exe*" }
                    }else{
                        if ($installertype | where { $_ -eq "msi" }) { $installer = $installer | where InstallerUrl -like "*.msi*" }
                        #Treat "wix" as the same as msi
                        elseif ($installertype | where { $_ -eq "wix" }) { $installer = $installer | where InstallerUrl -like "*.msi*"; $installertype="msi" }
                    }
                    #$installertype = if ($newest.InstallerType) { $newest.InstallerType }else { $installer.InstallerType }
                }
                if ($installer.InstallerLocale) { $installer = $installer | where InstallerLocale -eq $locale }
                if ($installer.scope) { $installer = $installer | where Scope -eq "machine" }
                if ($installer.Architecture -eq "neutral")  {}
                elseif ($installer.Architecture)  {$installer = $installer | where Architecture -eq $Architecture}
                if ($installer.count -eq 0) { Write-Error "NO INSTALLER FOUND; OR FILTERED BY SELECTION FOR $tinput!" }
                if ($installer.InstallerUrl.count -gt 1) { Write-Error "MORE THAN ONE INSTALLER FOR $tinput!" }
                if ($installer.InstallerUrl.count -eq 0) { Write-Error "NO INSTALLER FOUND; OR FILTERED BY INSTALLERTYPE SELECTION FOR $tinput!" }
                #create folderstructure
                New-Item -ItemType Directory "$PSGOTpath\apps" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -ErrorAction SilentlyContinue
                $installerext = if ($installertype -eq "msi") { "msi" }else { "exe" }
                #Download installer
                if (!(test-path "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext")) {
                    $new = $true
                    "Downloading package for $appname"
                    Invoke-WebRequest $installer.InstallerUrl -OutFile "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext" -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
                }
                else { "file already exists: $PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername" }
                switch ($installertype) {
                    burn {
                        $installerswitches = "-q InstallAllUsers=1"
                    }
                    inno {
                        $installerswitches = "/NORESTART /ALLUSERS /SILENT"
                    }
                    nullsoft {
                        $installerswitches = "/S"
                    }
                    exe {
                        $installerswitches = if ($newest.InstallerSwitches.silent) { $newest.InstallerSwitches.silent }else { $installer.InstallerSwitches.silent }
                    }
                    msi {
                        $installerprefix = "msiexec /i"
                        $installerswitches = "/quiet /qn /norestart"
                    }

                }
                "Creating intunewin...."
                $intuneresult = . $PSGOTpath\IntuneWinAppUtil.exe -c "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -s "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext" -o "$PSGOTpath\apps\$($newest.PackageIdentifier)\" -q
                $intunefilename = ($intuneresult | where { $_ -like "*has been generated successfully" }).split("'")[1]
                
                if ($installerprefix) { $installerprefix | out-file "$intunefilename.installerprefix" }
                if ($installerswitches) { $installerswitches | out-file "$intunefilename.installerswitches" }
                if ($installertype) { $installertype | out-file "$intunefilename.installertype" }
                @{
                    intunewinfilename = $intunefilename
                    version           = $newest.PackageVersion.tostring().replace(',','.')
                    new               = $new
                    type              = $installerext
                }
            }
        }
    }
}



function Update-PSGOTIntuneApps {
    param(
        $PSGOTpath = "c:\temp\psgot",
        [Parameter(ValueFromPipeline)]$appconfigfile
        #$intunewinpath

    )
    BEGIN {
        #Connect intune
        
    }
    PROCESS {
        ##Intune settings 
        write-output "Start processing of $appconfigfile"
        $baseUrl = "https://graph.microsoft.com/beta/deviceAppManagement/"
        $logRequestUris = $true;
        $logHeaders = $false;
        $logContent = $true;
        $azureStorageUploadChunkSizeInMb = 6l;
        $sleep = 30
        ###
        $config = get-content $appconfigfile | ConvertFrom-Json
        $intunewindetails = $config.appidentifier | New-PSGOTIntuneWin -Architecture $config.Architecture -PSGOTpath $PSGOTpath -installtype $config.installtype

        $version = $intunewindetails.version
        $SourceFile = $intunewindetails.intunewinfilename
        
        #get version oapp from intune, if it exists
        $Intune_App = Get-IntuneApplication | where { $_.displayName -eq "$($config.name)" } | Sort-Object displayversion
        $Intune_AppUpdate = Get-IntuneApplication | where { $_.displayName -eq "Update-$($config.name)" }  | Sort-Object displayversion
        $Intune_App_newest = if($Intune_App.count -gt 1){($Intune_App | sort displayversion -Descending)[0]}else{$Intune_App}
        $Intune_AppUpdate_newest = if($Intune_AppUpdate.count -gt 1){($Intune_App | sort displayversion -Descending)[0]}else{$Intune_AppUpdate} 
        # Defining Intunewin32 detectionRules
        $DetectionXML = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"
        
        # Defining Intunewin32 detectionRules
        if ($config.detectionrule -eq "file") {
            $DetectionRule = New-DetectionRule -File -Path "C:\Program Files\Application" `
                -FileOrFolderName "application.exe" -FileDetectionType exists -check32BitOn64System False

        }
        elseif ($config.detectionrule -eq "registry") {
            $DetectionRule = New-DetectionRule -Registry -RegistryKeyPath "$($config.DetectionRegistryKeyPath)" `
                -RegistryDetectionType $config.DetectionRegistryDetectionType -RegistryValue $config.DetectionRegistryValue -check32BitRegOn64System false `
                -RegistryDetectionOperator $config.DetectionRegistryDetectionOperator -RegistryDetectionValue $version
        }
        elseif ($config.detectionrule -eq "msi") {
            $DetectionRule = New-DetectionRule -MSI -MSIproductCode $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
        }
        # Defining Intunewin32 RequirementRules
        if ($config.UpdateRequirementrule -eq "file") {
            $RequirementRule = New-RequirementRule -File -Path "C:\Program Files\Application" `
                -FileOrFolderName "application.exe" -FileDetectionType exists -check32BitOn64System False

        }
        elseif ($config.UpdateRequirementrule -eq "registry") {
            $RequirementRule = New-RequirementRule -Registry -RegistryKeyPath "$($config.UpdateRequirementRegistryKeyPath)" `
                -RegistryDetectionType $config.UpdateRequirementRegistryDetectionType -RegistryValue $config.UpdateRequirementRegistryValue -check32BitRegOn64System false `
                -RegistryDetectionOperator $config.UpdateRequirementRegistryDetectionOperator -RegistryDetectionValue $version
        }
        elseif ($config.UpdateRequirementrule -eq "msi") {
            $RequirementRule = New-DetectionRule -MSI -MSIproductCode $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
        }
                             
        $ReturnCodes = Get-DefaultReturnCodes
        
        $ReturnCodes += New-ReturnCode -returnCode 302 -type softReboot
        $ReturnCodes += New-ReturnCode -returnCode 145 -type hardReboot
        
        #installcmdline
        $installcmdline = if ($intunewindetails.type -eq "exe") {
            $installswitches = get-content "$SourceFile.installerswitches"
            "$($DetectionXML.ApplicationInfo.setupfile) $installswitches"
        }
        elseif ($intunewindetails.type -eq "msi") {
            $installswitches = get-content "$SourceFile.installerswitches"
            $installprefix = get-content "$SourceFile.installerprefix"
            "$installprefix $($DetectionXML.ApplicationInfo.setupfile) $installswitches"
        }
        $RequirementRules = @($RequirementRule)
        $DetectionRules = @($DetectionRule)
        $newAppversionavalable=if($Intune_App.count -eq 0){"yes"}elseif(([version]"$($Intune_App_newest.displayVersion)" -lt [version]$version)){"yes"}else{"no"}
        $newAppUpdateversionavalable=if($Intune_AppUpdate.count -eq 0){"yes"}elseif(([version]"$($Intune_AppUpdate_newest.displayVersion)" -lt [version]$version)){"yes"}else{"no"}
        # Win32 Application Upload
        if ($intunewindetails.type -eq "exe") {
            if ((($newAppversionavalable -eq "yes") -or ($Intune_App.count -eq 0)) -and ($config.PublishSelfservice -eq "true") ) {        
                "Sourcefile is: $SourceFile"
                "publisher is: $($config.publisher)"
                "description is: $($config.description)"
                "detectopnrule is: $($DetectionRules | ConvertTo-Json)"
                "installcmdline is: $installcmdline"
                "Version is: $version"
                Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
                    -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
                    -installCmdLine "$installcmdline" `
                    -uninstallCmdLine "powershell.exe .\uninstall.ps1" -displayName "$($config.name)" -version "$version"
                #assignment
                $selfserviceapp = Get-IntuneApplication | where { $_.displayname -eq "$($config.name)" } | where { $_.displayversion -eq "$version" }
                $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)/assignments"
                #Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"available","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $assignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if ($config.iconname) {
                    $iconbase64 = [Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent = '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if ($config.iconname -like "*.png*") { $iconcontent = $iconcontent.replace('image/jpeg', 'image/png') }
                    $iconcontent = $iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }

                #Unassign old versions
                $Intune_App | ForEach-Object {
                    $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($_.id)/assignments"
                    $assignments=Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                    if($assignments.value.id){Invoke-RestMethod -uri "$assignmenturi/$($assignments.value.id)" -Headers $global:authToken -Method DELETE}
                }

            }
            else { "Selfservice: The newest version of $($config.name): $version is already present in Intune" }
    
            if ((($newAppUpdateversionavalable -eq "yes") -or ($Intune_AppUpdate.count -eq 0)) -and ($config.PublishUpdate -eq "true") ) { 
                "APPUPDATE"       
                "Sourcefile is: $SourceFile"
                "publisher is: $($config.publisher)"
                "description is: $($config.description)"
                "detectopnrule is: $($DetectionRules | ConvertTo-Json)"
                "RequirementRule is $($RequirementRules | ConvertTo-Json)"
                "installcmdline is: $installcmdline"
                "Version is: $version"
                Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
                    -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
                    -installCmdLine "$installcmdline" `
                    -uninstallCmdLine "powershell.exe .\uninstall.ps1" -displayName "Update-$($config.name)" -version "$version" -RequirementRules $RequirementRules
                #assignment
                $updateapp = Get-IntuneApplication | where { $_.displayname -eq "Update-$($config.name)" } | where { $_.displayversion -eq "$version" }
                $updateassignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)/assignments"
                #Invoke-RestMethod -uri $updateassignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"required","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $updateassignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if ($config.iconname) {
                    $iconbase64 = [Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent = '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if ($config.iconname -like "*.png*") { $iconcontent = $iconcontent.replace('image/jpeg', 'image/png') }
                    $iconcontent = $iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }
                #Unassign old versions
                $Intune_AppUpdate | ForEach-Object {
                    $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($_.id)/assignments"
                    $assignments=Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                    if($assignments.value.id){Invoke-RestMethod -uri "$assignmenturi/$($assignments.value.id)" -Headers $global:authToken -Method DELETE}
                }

            }
            else { "Update: The newest version of $($config.name): $version is already present in Intune" }
        }
        elseif ($intunewindetails.type -eq "msi") {
            if ((($newAppversionavalable -eq "yes") -or ($Intune_App.count -eq 0)) -and ($config.PublishSelfservice -eq "true") ) {        
                "Sourcefile is: $SourceFile"
                "publisher is: $($config.publisher)"
                "description is: $($config.description)"
                "detectopnrule is: $($DetectionRules | ConvertTo-Json)"
                "Version is: $version"
                Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
                    -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
                    -displayName "$($config.name)"  -version "$version"

                #assignment
                $selfserviceapp = Get-IntuneApplication | where { $_.displayname -eq "$($config.name)" } | where { $_.displayversion -eq "$version" }
                $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)/assignments"
                #Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"available","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $assignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if ($config.iconname) {
                    $iconbase64 = [Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent = '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if ($config.iconname -like "*.png*") { $iconcontent = $iconcontent.replace('image/jpeg', 'image/png') }
                    $iconcontent = $iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }
                #Unassign old versions
                $Intune_App | ForEach-Object {
                    $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($_.id)/assignments"
                    $assignments=Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                    if($assignments.value.id){Invoke-RestMethod -uri "$assignmenturi/$($assignments.value.id)" -Headers $global:authToken -Method DELETE}
                }

            }
            else { "Selfservice: The newest version of $($config.name): $version is already present in Intune" }
            
            if ((($newAppUpdateversionavalable -eq "yes") -or ($Intune_AppUpdate.count -eq 0)) -and ($config.PublishUpdate -eq "true") ) { 
                "APPUPDATE"       
                "Sourcefile is: $SourceFile"
                "publisher is: $($config.publisher)"
                "description is: $($config.description)"
                "detectopnrule is: $($DetectionRules | ConvertTo-Json)"
                "RequirementRule is $($RequirementRules | ConvertTo-Json)"
                "Version is: $version"
                Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
                    -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
                    -displayName "Update-$($config.name)" -RequirementRules $RequirementRules  -version "$version"

                #assignment
                $updateapp = Get-IntuneApplication | where { $_.displayname -eq "Update-$($config.name)" } | where { $_.displayversion -eq "$version" }
                $updateassignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)/assignments"
                #Invoke-RestMethod -uri $updateassignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"required","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $updateassignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if ($config.iconname) {
                    $iconbase64 = [Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent = '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if ($config.iconname -like "*.png*") { $iconcontent = $iconcontent.replace('image/jpeg', 'image/png') }
                    $iconcontent = $iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }
                #Unassign old versions
                $Intune_AppUpdate | ForEach-Object {
                    $assignmenturi = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($_.id)/assignments"
                    $assignments=Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                    if($assignments.value.id){Invoke-RestMethod -uri "$assignmenturi/$($assignments.value.id)" -Headers $global:authToken -Method DELETE}
                }

                
            }
            else { "Update: The newest version of $($config.name): $version is already present in Intune" }
        }
    }
    
}

<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>

####################################################
function Get-AuthTokenWithUsernameAndpassword {

    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>
    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory = $true)]
        $User,
        $Password
    )
    
    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
    
    $tenant = $userUpn.Host
    
    Write-Host "Checking for AzureAD module..."
    
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    
    if ($AadModule -eq $null) {
    
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    
    }
    
    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }
    
    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    
    if ($AadModule.count -gt 1) {
    
        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]
    
        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
    
        # Checking if there are multiple versions of the same module found
    
        if ($AadModule.count -gt 1) {
    
            $aadModule = $AadModule | select -Unique
    
        }
    
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
    }
    
    else {
    
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
    }
    
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    
    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    
    $resourceAppIdURI = "https://graph.microsoft.com"
    
    $authority = "https://login.microsoftonline.com/$Tenant"
    
    try {
    
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    
        # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
    
        $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
    
        $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
    
        if ($Password -eq $null) {
    
            $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result
    
        }
    
        else {
    
            if ("$Password") {
    
                $UserPassword = $Password | ConvertTo-SecureString -AsPlainText -Force
    
                $userCredentials = new-object Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential -ArgumentList $userUPN, $UserPassword
    
                $authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authContext, $resourceAppIdURI, $clientid, $userCredentials).Result;
    
            }
    
            else {
    
                Write-Host "Path to Password file" $Password "doesn't exist, please specify a valid path..." -ForegroundColor Red
                Write-Host "Script can't continue..." -ForegroundColor Red
                Write-Host
                break
    
            }
    
        }
    
        if ($authResult.AccessToken) {
    
            # Creating header for Authorization token
    
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = "Bearer " + $authResult.AccessToken
                'ExpiresOn'     = $authResult.ExpiresOn
            }
    
            return $authHeader
    
        }
    
        else {
    
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
    
        }
    
    }
    
    catch {
    
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    
    }
    
}
function Get-AuthToken {

    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>
    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory = $true)]
        $User
    )
    
    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
    
    $tenant = $userUpn.Host
    
    Write-Host "Checking for AzureAD module..."
    
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    
    if ($AadModule -eq $null) {
    
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    
    }
    
    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }
    
    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    
    if ($AadModule.count -gt 1) {
    
        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]
    
        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
    
        # Checking if there are multiple versions of the same module found
    
        if ($AadModule.count -gt 1) {
    
            $aadModule = $AadModule | select -Unique
    
        }
    
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
    }
    
    else {
    
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
    }
    
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    
    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    
    $resourceAppIdURI = "https://graph.microsoft.com"
    
    $authority = "https://login.microsoftonline.com/$Tenant"
    
    try {
    
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    
        # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
    
        $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
    
        $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
    
        $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result
    
        # If the accesstoken is valid then create the authentication header
    
        if ($authResult.AccessToken) {
    
            # Creating header for Authorization token
    
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = "Bearer " + $authResult.AccessToken
                'ExpiresOn'     = $authResult.ExpiresOn
            }
    
            return $authHeader
    
        }
    
        else {
    
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
    
        }
    
    }
    
    catch {
    
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    
    }
    
}
     
####################################################
    
function CloneObject($object) {
    
    $stream = New-Object IO.MemoryStream;
    $formatter = New-Object Runtime.Serialization.Formatters.Binary.BinaryFormatter;
    $formatter.Serialize($stream, $object);
    $stream.Position = 0;
    $formatter.Deserialize($stream);
}
    
####################################################
    
function WriteHeaders($authToken) {
    
    foreach ($header in $authToken.GetEnumerator()) {
        if ($header.Name.ToLower() -eq "authorization") {
            continue;
        }
    
        Write-Host -ForegroundColor Gray "$($header.Name): $($header.Value)";
    }
}
    
####################################################
    
function MakeGetRequest($collectionPath) {
    
    $uri = "$baseUrl$collectionPath";
    $request = "GET $uri";
        
    if ($logRequestUris) { Write-Host $request; }
    if ($logHeaders) { WriteHeaders $authToken; }
    
    try {
        Test-AuthToken
        $response = Invoke-RestMethod $uri -Method Get -Headers $authToken;
        $response;
    }
    catch {
        Write-Host -ForegroundColor Red $request;
        Write-Host -ForegroundColor Red $_.Exception.Message;
        throw;
    }
}
    
####################################################
    
function MakePatchRequest($collectionPath, $body) {
    
    MakeRequest "PATCH" $collectionPath $body;
    
}
    
####################################################
    
function MakePostRequest($collectionPath, $body) {
    
    MakeRequest "POST" $collectionPath $body;
    
}
    
####################################################
    
function MakeRequest($verb, $collectionPath, $body) {
    
    $uri = "$baseUrl$collectionPath";
    $request = "$verb $uri";
        
    $clonedHeaders = CloneObject $authToken;
    $clonedHeaders["content-length"] = $body.Length;
    $clonedHeaders["content-type"] = "application/json";
    
    if ($logRequestUris) { Write-Host $request; }
    if ($logHeaders) { WriteHeaders $clonedHeaders; }
    if ($logContent) { Write-Host -ForegroundColor Gray $body; }
    
    try {
        Test-AuthToken
        $response = Invoke-RestMethod $uri -Method $verb -Headers $clonedHeaders -Body $body;
        $response;
    }
    catch {
        Write-Host -ForegroundColor Red $request;
        Write-Host -ForegroundColor Red $_.Exception.Message;
        throw;
    }
}
    
####################################################
    
function UploadAzureStorageChunk($sasUri, $id, $body) {
    
    $uri = "$sasUri&comp=block&blockid=$id";
    $request = "PUT $uri";
    
    $iso = [System.Text.Encoding]::GetEncoding("iso-8859-1");
    $encodedBody = $iso.GetString($body);
    $headers = @{
        "x-ms-blob-type" = "BlockBlob"
    };
    
    if ($logRequestUris) { Write-Host $request; }
    if ($logHeaders) { WriteHeaders $headers; }
    
    try {
        $response = Invoke-WebRequest $uri -Method Put -Headers $headers -Body $encodedBody;
    }
    catch {
        Write-Host -ForegroundColor Red $request;
        Write-Host -ForegroundColor Red $_.Exception.Message;
        throw;
    }
    
}
    
####################################################
    
function FinalizeAzureStorageUpload($sasUri, $ids) {
    
    $uri = "$sasUri&comp=blocklist";
    $request = "PUT $uri";
    
    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>';
    foreach ($id in $ids) {
        $xml += "<Latest>$id</Latest>";
    }
    $xml += '</BlockList>';
    
    if ($logRequestUris) { Write-Host $request; }
    if ($logContent) { Write-Host -ForegroundColor Gray $xml; }
    
    try {
        Invoke-RestMethod $uri -Method Put -Body $xml;
    }
    catch {
        Write-Host -ForegroundColor Red $request;
        Write-Host -ForegroundColor Red $_.Exception.Message;
        throw;
    }
}
    
####################################################
    
function UploadFileToAzureStorage($sasUri, $filepath, $fileUri) {
    
    try {
    
        $chunkSizeInBytes = 1024l * 1024l * $azureStorageUploadChunkSizeInMb;
            
        # Start the timer for SAS URI renewal.
        $sasRenewalTimer = [System.Diagnostics.Stopwatch]::StartNew()
            
        # Find the file size and open the file.
        $fileSize = (Get-Item $filepath).length;
        $chunks = [Math]::Ceiling($fileSize / $chunkSizeInBytes);
        $reader = New-Object System.IO.BinaryReader([System.IO.File]::Open($filepath, [System.IO.FileMode]::Open));
        $position = $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::Begin);
            
        # Upload each chunk. Check whether a SAS URI renewal is required after each chunk is uploaded and renew if needed.
        $ids = @();
    
        for ($chunk = 0; $chunk -lt $chunks; $chunk++) {
    
            $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")));
            $ids += $id;
    
            $start = $chunk * $chunkSizeInBytes;
            $length = [Math]::Min($chunkSizeInBytes, $fileSize - $start);
            $bytes = $reader.ReadBytes($length);
                
            $currentChunk = $chunk + 1;			
    
            Write-Progress -Activity "Uploading File to Azure Storage" -status "Uploading chunk $currentChunk of $chunks" `
                -percentComplete ($currentChunk / $chunks * 100)
    
            $uploadResponse = UploadAzureStorageChunk $sasUri $id $bytes;
                
            # Renew the SAS URI if 7 minutes have elapsed since the upload started or was renewed last.
            if ($currentChunk -lt $chunks -and $sasRenewalTimer.ElapsedMilliseconds -ge 450000) {
    
                $renewalResponse = RenewAzureStorageUpload $fileUri;
                $sasRenewalTimer.Restart();
                
            }
    
        }
    
        Write-Progress -Completed -Activity "Uploading File to Azure Storage"
    
        $reader.Close();
    
    }
    
    finally {
    
        if ($reader -ne $null) { $reader.Dispose(); }
        
    }
        
    # Finalize the upload.
    $uploadResponse = FinalizeAzureStorageUpload $sasUri $ids;
    
}
    
####################################################
    
function RenewAzureStorageUpload($fileUri) {
    
    $renewalUri = "$fileUri/renewUpload";
    $actionBody = "";
    $rewnewUriResult = MakePostRequest $renewalUri $actionBody;
        
    $file = WaitForFileProcessing $fileUri "AzureStorageUriRenewal" $azureStorageRenewSasUriBackOffTimeInSeconds;
    
}
    
####################################################
    
function WaitForFileProcessing($fileUri, $stage) {
    
    $attempts = 600;
    $waitTimeInSeconds = 10;
    
    $successState = "$($stage)Success";
    $pendingState = "$($stage)Pending";
    $failedState = "$($stage)Failed";
    $timedOutState = "$($stage)TimedOut";
    
    $file = $null;
    while ($attempts -gt 0) {
        $file = MakeGetRequest $fileUri;
    
        if ($file.uploadState -eq $successState) {
            break;
        }
        elseif ($file.uploadState -ne $pendingState) {
            Write-Host -ForegroundColor Red $_.Exception.Message;
            throw "File upload state is not success: $($file.uploadState)";
        }
    
        Start-Sleep $waitTimeInSeconds;
        $attempts--;
    }
    
    if ($file -eq $null -or $file.uploadState -ne $successState) {
        throw "File request did not complete in the allotted time.";
    }
    
    $file;
}
    
####################################################
    
function GetWin32AppBody() {
    
    param
    (
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE", Position = 1)]
        [Switch]$EXE,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFileName,
    
        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        $installExperience = "system",
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Version,
    
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiPackageType,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductCode,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiProductName,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductVersion,
    
        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiPublisher,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiRequiresReboot = "false",
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiUpgradeCode
    
    )
    
    if ($MSI) {
    
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" };
        $body.applicableArchitectures = "x64,x86";
        $body.description = $description;
        $body.developer = "";
        $body.displayName = $displayName;
        $body.displayVersion = $version;
        $body.fileName = $filename;
        $body.installCommandLine = "msiexec /i `"$SetupFileName`" /quiet /qn /norestart"
        $body.installExperience = @{"runAsAccount" = "$installExperience" };
        $body.informationUrl = $null;
        $body.isFeatured = $false;
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true };
        $body.msiInformation = @{
            "packageType"    = "$MsiPackageType";
            "productCode"    = "$MsiProductCode";
            "productName"    = "$MsiProductName";
            "productVersion" = "$MsiProductVersion";
            "publisher"      = "$MsiPublisher";
            "requiresReboot" = "$MsiRequiresReboot";
            "upgradeCode"    = "$MsiUpgradeCode"
        };
        $body.notes = "";
        $body.owner = "";
        $body.privacyInformationUrl = $null;
        $body.publisher = $publisher;
        $body.runAs32bit = $false;
        $body.setupFilePath = $SetupFileName;
        $body.uninstallCommandLine = "msiexec /x `"$MsiProductCode`""
    
    }
    
    elseif ($EXE) {
    
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" };
        $body.description = $description;
        $body.developer = "";
        $body.displayName = $displayName;
        $body.displayVersion = $Version;
        $body.fileName = $filename;
        $body.installCommandLine = "$installCommandLine"
        $body.installExperience = @{"runAsAccount" = "$installExperience" };
        $body.informationUrl = $null;
        $body.isFeatured = $false;
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true };
        $body.msiInformation = $null;
        $body.notes = "";
        $body.owner = "";
        $body.privacyInformationUrl = $null;
        $body.publisher = $publisher;
        $body.runAs32bit = $false;
        $body.setupFilePath = $SetupFileName;
        $body.uninstallCommandLine = "$uninstallCommandLine"
    
    }
    
    $body;
}
    
####################################################
    
function GetAppFileBody($name, $size, $sizeEncrypted, $manifest) {
    
    $body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" };
    $body.name = $name;
    $body.size = $size;
    $body.sizeEncrypted = $sizeEncrypted;
    $body.manifest = $manifest;
    $body.isDependency = $false;
    
    $body;
}
    
####################################################
    
function GetAppCommitBody($contentVersionId, $LobType) {
    
    $body = @{ "@odata.type" = "#$LobType" };
    $body.committedContentVersion = $contentVersionId;
    
    $body;
    
}
    
####################################################
    
Function Test-SourceFile() {
    
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceFile
    )
    
    try {
    
        if (!(test-path "$SourceFile")) {
    
            Write-Host
            Write-Host "Source File '$sourceFile' doesn't exist..." -ForegroundColor Red
            throw
    
        }
    
    }
    
    catch {
    
        Write-Host -ForegroundColor Red $_.Exception.Message;
        Write-Host
        break
    
    }
    
}
    
####################################################
    
Function New-DetectionRule() {
    
    [cmdletbinding()]
    
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell", Position = 1)]
        [Switch]$PowerShell,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,
    
        [parameter(Mandatory = $true, ParameterSetName = "File", Position = 1)]
        [Switch]$File,
    
        [parameter(Mandatory = $true, ParameterSetName = "Registry", Position = 1)]
        [Switch]$Registry,
    
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptFile,
    
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $enforceSignatureCheck,
    
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $runAs32Bit,
    
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        [String]$MSIproductCode,
       
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [String]$Path,
     
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [string]$FileOrFolderName,
    
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB")]
        [string]$FileDetectionType,
    
        [parameter(Mandatory = $false, ParameterSetName = "File")]
        $FileDetectionValue = $null,
    
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("True", "False")]
        [string]$check32BitOn64System = "False",
    
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryKeyPath,
    
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("notConfigured", "exists", "doesNotExist", "string", "integer", "version")]
        [string]$RegistryDetectionType,
    
        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryValue,

        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryDetectionValue,

        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateSet("greaterThanOrEqual", "equal", "notEqual", "notConfigured", "greaterThan", "lessThan", "lessThanOrEqual")]
        [String]$RegistryDetectionOperator,
    
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("True", "False")]
        [string]$check32BitRegOn64System = "False"
    
    )
    
    if ($PowerShell) {
    
        if (!(Test-Path "$ScriptFile")) {
                
            Write-Host
            Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
            Write-Host "Script can't continue..." -ForegroundColor Red
            Write-Host
            break
    
        }
            
        $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"));
            
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection" }
        $DR.enforceSignatureCheck = $false;
        $DR.runAs32Bit = $false;
        $DR.scriptContent = "$ScriptContent";
    
    }
        
    elseif ($MSI) {
        
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection" }
        $DR.productVersionOperator = "notConfigured";
        $DR.productCode = "$MsiProductCode";
        $DR.productVersion = $null;
    
    }
    
    elseif ($File) {
        
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection" }
        $DR.check32BitOn64System = "$check32BitOn64System";
        $DR.detectionType = "$FileDetectionType";
        $DR.detectionValue = $FileDetectionValue;
        $DR.fileOrFolderName = "$FileOrFolderName";
        $DR.operator = "notConfigured";
        $DR.path = "$Path"
    
    }
    
    elseif ($Registry) {
        
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppRegistryDetection" }
        $DR.check32BitOn64System = "$check32BitRegOn64System";
        $DR.detectionType = "$RegistryDetectionType";
        $DR.detectionValue = "$RegistryDetectionValue";
        $DR.keyPath = "$RegistryKeyPath";
        $DR.operator = "$RegistryDetectionOperator";
        $DR.valueName = "$RegistryValue"
    
    }
    
    return $DR
    
}

Function New-RequirementRule() {
    
    [cmdletbinding()]
        
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell", Position = 1)]
        [Switch]$PowerShell,
        
        [parameter(Mandatory = $true, ParameterSetName = "File", Position = 1)]
        [Switch]$File,
        
        [parameter(Mandatory = $true, ParameterSetName = "Registry", Position = 1)]
        [Switch]$Registry,
        
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptFile,
        
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $enforceSignatureCheck,
        
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $runAs32Bit,
           
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [String]$Path,
         
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [string]$FileOrFolderName,
        
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB")]
        [string]$FileDetectionType,
        
        [parameter(Mandatory = $false, ParameterSetName = "File")]
        $FileDetectionValue = $null,
        
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("True", "False")]
        [string]$check32BitOn64System = "False",
        
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryKeyPath,
        
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("notConfigured", "exists", "doesNotExist", "string", "integer", "version")]
        [string]$RegistryDetectionType,
        
        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryValue,
    
        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryDetectionValue,
    
        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateSet("greaterThanOrEqual", "equal", "notEqual", "notConfigured", "greaterThan", "lessThan", "lessThanOrEqual")]
        [String]$RegistryDetectionOperator,
        
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("True", "False")]
        [string]$check32BitRegOn64System = "False"
        
    )
        
    if ($PowerShell) {
        
        if (!(Test-Path "$ScriptFile")) {
                    
            Write-Host
            Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
            Write-Host "Script can't continue..." -ForegroundColor Red
            Write-Host
            break
        
        }
                
        $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"));
                
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRequirement" }
        $DR.enforceSignatureCheck = $false;
        $DR.runAs32Bit = $false;
        $DR.scriptContent = "$ScriptContent";
        
    }
        
    elseif ($File) {
            
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppFileSystemRequirement" }
        $DR.check32BitOn64System = "$check32BitOn64System";
        $DR.detectionType = "$FileDetectionType";
        $DR.detectionValue = $FileDetectionValue;
        $DR.fileOrFolderName = "$FileOrFolderName";
        $DR.operator = "notConfigured";
        $DR.path = "$Path"
        
    }
        
    elseif ($Registry) {
            
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppRegistryRequirement" }
        $DR.check32BitOn64System = "$check32BitRegOn64System";
        $DR.detectionType = "$RegistryDetectionType";
        $DR.detectionValue = "$RegistryDetectionValue";
        $DR.keyPath = "$RegistryKeyPath";
        $DR.operator = "$RegistryDetectionOperator";
        $DR.valueName = "$RegistryValue"
        
    }
        
    return $DR
        
}
    
####################################################
    
function Get-DefaultReturnCodes() {
    
    @{"returnCode" = 0; "type" = "success" }, `
    @{"returnCode" = 1707; "type" = "success" }, `
    @{"returnCode" = 3010; "type" = "softReboot" }, `
    @{"returnCode" = 1641; "type" = "hardReboot" }, `
    @{"returnCode" = 1618; "type" = "retry" }
    
}
    
####################################################
    
function New-ReturnCode() {
    
    param
    (
        [parameter(Mandatory = $true)]
        [int]$returnCode,
        [parameter(Mandatory = $true)]
        [ValidateSet('success', 'softReboot', 'hardReboot', 'retry')]
        $type
    )
    
    @{"returnCode" = $returnCode; "type" = "$type" }
    
}
    
####################################################
    
Function Get-IntuneWinXML() {
    
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,
    
        [Parameter(Mandatory = $true)]
        $fileName,
    
        [Parameter(Mandatory = $false)]
        [ValidateSet("false", "true")]
        [string]$removeitem = "true"
    )
    
    Test-SourceFile "$SourceFile"
    
    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")
    
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$SourceFile")
    
    $zip.Entries | where { $_.Name -like "$filename" } | foreach {
    
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$filename", $true)
    
    }
    
    $zip.Dispose()
    
    [xml]$IntuneWinXML = gc "$Directory\$filename"
    
    return $IntuneWinXML
    
    if ($removeitem -eq "true") { remove-item "$Directory\$filename" }
    
}
    
####################################################
    
Function Get-IntuneWinFile() {
    
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,
    
        [Parameter(Mandatory = $true)]
        $fileName,
    
        [Parameter(Mandatory = $false)]
        [string]$Folder = "win32"
    )
    
    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")
    
    if (!(Test-Path "$Directory\$folder")) {
    
        New-Item -ItemType Directory -Path "$Directory" -Name "$folder" | Out-Null
    
    }
    
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$SourceFile")
    
    $zip.Entries | where { $_.Name -like "$filename" } | foreach {
    
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$folder\$filename", $true)
    
    }
    
    $zip.Dispose()
    
    return "$Directory\$folder\$filename"
    
    if ($removeitem -eq "true") { remove-item "$Directory\$filename" }
    
}
    
####################################################
    
function Upload-Win32Lob() {
    
    <#
    .SYNOPSIS
    This function is used to upload a Win32 Application to the Intune Service
    .DESCRIPTION
    This function is used to upload a Win32 Application to the Intune Service
    .EXAMPLE
    Upload-Win32Lob "C:\Packages\package.intunewin" -publisher "Microsoft" -description "Package"
    This example uses all parameters required to add an intunewin File into the Intune Service
    .NOTES
    NAME: Upload-Win32LOB
    #>
    
    [cmdletbinding()]
    
    param
    (
        [parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceFile,
    
        [parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,
    
        [parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,
    
        [parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$version,
        
        [parameter(Mandatory = $true, Position = 3)]
        [ValidateNotNullOrEmpty()]
        [string]$description,
    
        [parameter(Mandatory = $true, Position = 4)]
        [ValidateNotNullOrEmpty()]
        $detectionRules,

        [parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        $RequirementRules,  

        [parameter(Mandatory = $true, Position = 5)]
        [ValidateNotNullOrEmpty()]
        $returnCodes,
    
        [parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullOrEmpty()]
        [string]$installCmdLine,
    
        [parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullOrEmpty()]
        [string]$uninstallCmdLine,
    
        [parameter(Mandatory = $false, Position = 8)]
        [ValidateSet('system', 'user')]
        $installExperience = "system"
    )
    
    try	{
    
        $LOBType = "microsoft.graph.win32LobApp"
    
        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"
    
        $Win32Path = "$SourceFile"
    
        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
    
        # Funciton to read Win32LOB file
        $DetectionXML = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"
    
        # If displayName input don't use Name from detection.xml file
        if ($displayName) { $DisplayName = $displayName }
        else { $DisplayName = $DetectionXML.ApplicationInfo.Name }
            
        $FileName = $DetectionXML.ApplicationInfo.FileName
    
        $SetupFileName = $DetectionXML.ApplicationInfo.SetupFile
    
        $Ext = [System.IO.Path]::GetExtension($SetupFileName)
    
        if ((($Ext).contains("msi") -or ($Ext).contains("Msi")) -and (!$installCmdLine -or !$uninstallCmdLine)) {
    
            # MSI
            $MsiExecutionContext = $DetectionXML.ApplicationInfo.MsiInfo.MsiExecutionContext
            $MsiPackageType = "DualPurpose";
            if ($MsiExecutionContext -eq "System") { $MsiPackageType = "PerMachine" }
            elseif ($MsiExecutionContext -eq "User") { $MsiPackageType = "PerUser" }
    
            $MsiProductCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
            $MsiProductVersion = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductVersion
            $MsiPublisher = $DetectionXML.ApplicationInfo.MsiInfo.MsiPublisher
            $MsiRequiresReboot = $DetectionXML.ApplicationInfo.MsiInfo.MsiRequiresReboot
            $MsiUpgradeCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiUpgradeCode
                
            if ($MsiRequiresReboot -eq "false") { $MsiRequiresReboot = $false }
            elseif ($MsiRequiresReboot -eq "true") { $MsiRequiresReboot = $true }
    
            $mobileAppBody = GetWin32AppBody `
                -MSI `
                -displayName "$DisplayName" `
                -publisher "$publisher" `
                -description $description `
                -filename $FileName `
                -SetupFileName "$SetupFileName" `
                -installExperience $installExperience `
                -MsiPackageType $MsiPackageType `
                -MsiProductCode $MsiProductCode `
                -MsiProductName $displayName `
                -MsiProductVersion $MsiProductVersion `
                -MsiPublisher $MsiPublisher `
                -version "$version"  `
                -MsiRequiresReboot $MsiRequiresReboot `
                -MsiUpgradeCode $MsiUpgradeCode
    
        }
    
        else {
    
            $mobileAppBody = GetWin32AppBody -EXE -displayName "$DisplayName" -publisher "$publisher" `
                -description $description -filename $FileName -SetupFileName "$SetupFileName" `
                -installExperience $installExperience -installCommandLine $installCmdLine `
                -uninstallCommandLine $uninstallcmdline -version "$version"
    
        }
    
        if ($DetectionRules.'@odata.type' -contains "#microsoft.graph.win32LobAppPowerShellScriptDetection" -and @($DetectionRules).'@odata.type'.Count -gt 1) {
    
            Write-Host
            Write-Warning "A Detection Rule can either be 'Manually configure detection rules' or 'Use a custom detection script'"
            Write-Warning "It can't include both..."
            Write-Host
            break
    
        }
    
        else {
    
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'detectionRules' -Value $detectionRules
    
        }
        if ($RequirementRules.'@odata.type' -contains "#microsoft.graph.win32LobAppPowerShellScriptRequirement" -and @($requirementRules).'@odata.type'.Count -gt 1) {
    
            Write-Host
            Write-Warning "A Requirement Rule can either be 'Manually configure Requirement rules' or 'Use a custom Requirement script'"
            Write-Warning "It can't include both..."
            Write-Host
            break
    
        }
    
        else {
    
            if ($RequirementRules) { $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'requirementRules' -Value $RequirementRules }    
        }
    
        #ReturnCodes
    
        if ($returnCodes) {
            
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'returnCodes' -Value @($returnCodes)
    
        }
    
        else {
    
            Write-Host
            Write-Warning "Intunewin file requires ReturnCodes to be specified"
            Write-Warning "If you want to use the default ReturnCode run 'Get-DefaultReturnCodes'"
            Write-Host
            break
    
        }
    
        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        $mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json);
    
        # Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
        $appId = $mobileApp.id;
        $contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
        $contentVersion = MakePostRequest $contentVersionUri "{}";
    
        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Getting Encryption Information for '$SourceFile'..." -ForegroundColor Yellow
    
        $encryptionInfo = @{};
        $encryptionInfo.encryptionKey = $DetectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
        $encryptionInfo.macKey = $DetectionXML.ApplicationInfo.EncryptionInfo.macKey
        $encryptionInfo.initializationVector = $DetectionXML.ApplicationInfo.EncryptionInfo.initializationVector
        $encryptionInfo.mac = $DetectionXML.ApplicationInfo.EncryptionInfo.mac
        $encryptionInfo.profileIdentifier = "ProfileVersion1";
        $encryptionInfo.fileDigest = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigest
        $encryptionInfo.fileDigestAlgorithm = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm
    
        $fileEncryptionInfo = @{};
        $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo;
    
        # Extracting encrypted file
        $IntuneWinFile = Get-IntuneWinFile "$SourceFile" -fileName "$filename"
    
        [int64]$Size = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        $EncrySize = (Get-Item "$IntuneWinFile").Length
    
        # Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
        $contentVersionId = $contentVersion.id;
        $fileBody = GetAppFileBody "$FileName" $Size $EncrySize $null;
        $filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
        $file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json);
        
        # Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
        $fileId = $file.id;
        $fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
        $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest";
    
        # Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage..." -f Yellow
    
        $sasUri = $file.azureStorageUri;
        UploadFileToAzureStorage $file.azureStorageUri "$IntuneWinFile" $fileUri;
    
        # Need to Add removal of IntuneWin file
        $IntuneWinFolder = [System.IO.Path]::GetDirectoryName("$IntuneWinFile")
        Remove-Item "$IntuneWinFile" -Force
    
        # Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
        $commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
        MakePostRequest $commitFileUri ($fileEncryptionInfo | ConvertTo-Json);
    
        # Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "CommitFile";
    
        # Commit the app.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
        $commitAppUri = "mobileApps/$appId";
        $commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
        MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json);
    
        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host
        
    }
        
    catch {
    
        Write-Host "";
        Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())";
        
    }
}
    
####################################################
    
Function Test-AuthToken() {
    
    # Checking if authToken exists before running authentication
    if ($global:authToken) {
    
        # Setting DateTime to Universal time to work in all timezones
        $DateTime = (Get-Date).ToUniversalTime()
    
        # If the authToken exists checking when it expires
        $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes
    
        if ($TokenExpires -le 0) {
    
            write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
            write-host
    
            # Defining Azure AD tenant name, this is the name of your Azure Active Directory (do not use the verified domain name)
    
            if ($User -eq $null -or $User -eq "") {
    
                $Global:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
                Write-Host
    
            }
    
            $global:authToken = Get-AuthToken -User $User
    
        }
    }
    
    # Authentication doesn't exist, calling Get-AuthToken function
    
    else {
    
        if ($User -eq $null -or $User -eq "") {
    
            $Global:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
            Write-Host
    
        }
    
        # Getting the authorization token
        $global:authToken = Get-AuthToken -User $User
    
    }
}
    
####################################################

####################################################
    
Function Get-IntuneApplication() {
    
    <#
    .SYNOPSIS
    This function is used to get applications from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any applications added
    .EXAMPLE
    Get-IntuneApplication
    Returns any applications configured in Intune
    .NOTES
    NAME: Get-IntuneApplication
    #>
    
    [cmdletbinding()]
    
    param
    (
        $Name
    )
    
    $graphApiVersion = "Beta"
    $Resource = "deviceAppManagement/mobileApps"
    
    try {
    
        if ($Name) {
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { ($_.'displayName').contains("$Name") -and (!($_.'@odata.type').Contains("managed")) -and (!($_.'@odata.type').Contains("#microsoft.graph.iosVppApp")) }
    
        }
    
        else {
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { (!($_.'@odata.type').Contains("managed")) -and (!($_.'@odata.type').Contains("#microsoft.graph.iosVppApp")) }
    
        }
    
    }
    
    catch {
    
        $ex = $_.Exception
        Write-Host "Request to $Uri failed with HTTP Status $([int]$ex.Response.StatusCode) $($ex.Response.StatusDescription)" -f Red
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    
    }
    
}
    
####################################################
    
Function Get-ApplicationAssignment() {
    
    <#
    .SYNOPSIS
    This function is used to get an application assignment from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets an application assignment
    .EXAMPLE
    Get-ApplicationAssignment
    Returns an Application Assignment configured in Intune
    .NOTES
    NAME: Get-ApplicationAssignment
    #>
    
    [cmdletbinding()]
    
    param
    (
        $ApplicationId
    )
    
    $graphApiVersion = "Beta"
    $Resource = "deviceAppManagement/mobileApps/$ApplicationId/assignments"
    
    try {
    
        if (!$ApplicationId) {
    
            write-host "No Application Id specified, specify a valid Application Id" -f Red
            break
    
        }
    
        else {
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
        }
    
    }
    
    catch {
    
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    
    }
    
}
    
####################################################
    
Function Get-AADGroup() {
    
    <#
    .SYNOPSIS
    This function is used to get AAD Groups from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Groups registered with AAD
    .EXAMPLE
    Get-AADGroup
    Returns all users registered with Azure AD
    .NOTES
    NAME: Get-AADGroup
    #>
    
    [cmdletbinding()]
    
    param
    (
        $GroupName,
        $id,
        [switch]$Members
    )
    
    # Defining Variables
    $graphApiVersion = "v1.0"
    $Group_resource = "groups"
    
    try {
    
        if ($id) {
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
        }
    
        elseif ($GroupName -eq "" -or $GroupName -eq $null) {
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
        }
    
        else {
    
            if (!$Members) {
    
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
                (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
            }
    
            elseif ($Members) {
    
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
                $Group = (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
                if ($Group) {
    
                    $GID = $Group.id
    
                    $Group.displayName
                    write-host
    
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)/$GID/Members"
                    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
                }
    
            }
    
        }
    
    }
    
    catch {
    
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    
    }
    
}
    
####################################################

    
Function Add-ApplicationAssignment() {

    <#
.SYNOPSIS
This function is used to add an application assignment using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a application assignment
.EXAMPLE
Add-ApplicationAssignment -ApplicationId $ApplicationId -TargetGroupId $TargetGroupId -InstallIntent $InstallIntent
Adds an application assignment in Intune
.NOTES
NAME: Add-ApplicationAssignment
#>

    [cmdletbinding()]

    param
    (
        $ApplicationId,
        $TargetGroupId,
        [ValidateSet("available", "required")]
        $InstallIntent
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceAppManagement/mobileApps/$ApplicationId/assign"
    
    try {

        if (!$ApplicationId) {

            write-host "No Application Id specified, specify a valid Application Id" -f Red
            break

        }

        if (!$TargetGroupId) {

            write-host "No Target Group Id specified, specify a valid Target Group Id" -f Red
            break

        }

        
        if (!$InstallIntent) {

            write-host "No Install Intent specified, specify a valid Install Intent - available, notApplicable, required, uninstall, availableWithoutEnrollment" -f Red
            break

        }

        $AssignedGroups = (Get-ApplicationAssignment -ApplicationId $ApplicationId).assignments

        if ($AssignedGroups) {

            $App_Count = @($AssignedGroups).count
            $i = 1

            if ($AssignedGroups.target.GroupId -contains $TargetGroupId) {

                Write-Host "'$AADGroup' is already targetted to this application, can't add an AAD Group already assigned..." -f Red

            }

            else {

                # Creating header of JSON File
                $JSON = @"

{
    "mobileAppAssignments": [
    {
      "@odata.type": "#microsoft.graph.mobileAppAssignment",
      "target": {
        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
        "groupId": "$TargetGroupId"
      },
      "intent": "$InstallIntent"
    },
"@

                # Looping through all existing assignments and adding them to the JSON object
                foreach ($Assignment in $AssignedGroups) {

                    $ExistingTargetGroupId = $Assignment.target.GroupId
                    $ExistingInstallIntent = $Assignment.intent

                    $JSON += @"
    
    {
      "@odata.type": "#microsoft.graph.mobileAppAssignment",
      "target": {
        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
        "groupId": "$ExistingTargetGroupId"
      },
      "intent": "$ExistingInstallIntent"
"@

                    if ($i -ne $App_Count) {

                        $JSON += @"

    },

"@

                    }

                    else {

                        $JSON += @"

    }

"@

                    }

                    $i++

                }

                # Adding close of JSON object
                $JSON += @"

    ]
}

"@

                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
                Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $JSON -ContentType "application/json"

            }

        }

        else {

            $JSON = @"

{
    "mobileAppAssignments": [
    {
        "@odata.type": "#microsoft.graph.mobileAppAssignment",
        "target": {
        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
        "groupId": "$TargetGroupId"
        },
        "intent": "$InstallIntent"
    }
    ]
}

"@

            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $JSON -ContentType "application/json"

        }

    }
    
    catch {

        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break

    }

}

####################################################
