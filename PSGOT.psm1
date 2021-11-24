##Author Einar Stenberg


function Initialize-PSGOT {
    param(
        [Parameter(Mandatory=$true)]$path
    )
    
    if(!(test-path $path)){New-Item -ItemType Directory -Path $path}
    else {
        Write-Output "$path already exists"
    }
    if(!(test-path $path\config.json)){
        [pscustomobject]@{
            psgotpath = $path
            wingetrepos = [pscustomobject]@{
                official = [pscustomobject]@{
                    url = "https://github.com/microsoft/winget-pkgs.git"
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
        appidentifier = "asdasd.asdasd"
        name = "Applicationprettyname"
        Description = "Descriptionlongtext"
        Publisher = "Publisher"
        Category = "Set category, must exist!"
        Restartbehaviour = ""
        Installbehavior = "user or system"

    } | ConvertTo-Json -Depth 10 | Out-File $path\appconfig\_template.json
    #downloadintuneutil
    Invoke-WebRequest https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/IntuneWinAppUtil.exe?raw=true -OutFile $path\IntuneWinAppUtil.exe
    #download repo's
    if(. git){
        $config= Get-Content "$path\config.json" | ConvertFrom-Json
        new-item -ItemType Directory $path\winget -ErrorAction SilentlyContinue | Out-Null
        $config.wingetrepos | ForEach-Object {
            new-item -ItemType Directory "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)" -ErrorAction SilentlyContinue | Out-Null
            if(test-path "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)\.git"){
                write-output "Updating existing $($_.url)"
                . git -C "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)" pull
            }else{
                write-output "Cloning fresh $($_.url)"
                . git clone $_.url "$path\winget\$(($_ | get-member | where membertype -eq noteproperty).name)"
            }
        }
    }else{
        write-error "git missing! please install!"
    }

}

Initialize-PSGOT -path c:\temp\psgot


function New-PSGOTIntuneWin {
    param(
        $PSGOTpath="c:\temp\psgot",
        $repotype="winget",
        $reponame="official",
        [Parameter(ValueFromPipeline)]$appname,
        $version="newest",
        $locale="en-US",
        $Architecture="x64"
    )
    BEGIN{
        $config= Get-Content "$PSGOTpath\config.json" | ConvertFrom-Json
        $manifestpath="$PSGOTpath\$repotype\$reponame\$($config.wingetrepos.$($reponame).manifestpath)"
        if(!$GLOBAL:yamlimport){
            $GLOBAL:yamlimport=gci $manifestpath -Recurse -File | where name -like "*installer*" | ForEach-Object{
                get-content $_.FullName | convertfrom-yaml
            }
        }   
    }
    PROCESS{
        switch($repotype){
            winget {
                $tinput=$input
                $available=$GLOBAL:yamlimport | where {$_.PackageIdentifier -eq $tinput}
                $newest=if($available.packageversion -gt 1){
                    $versions=$available.packageversion | ForEach-Object{
                        $tempversion=$_
                        if($tempversion -notlike "*.*"){
                            [version]"$tempversion.0"
                        }else{[version]$_ }
                        
                    } | sort -Descending
                    $newestversion=$versions[0]
                    $available | where {$_.packageversion -eq $newestversion.tostring()}
                }else{$available}
                $installer=$newest.installers 
                if($installer.InstallerLocale){$installer=$installer | where InstallerLocale -eq $locale}
                if($installer.scope){$installer=$installer | where Scope -eq "machine"}
                $installer=$installer | where Architecture -eq $Architecture
                if($installer.count -eq 0){Write-Error "NO INSTALLER FOUND; OR FILTERED BY SELECTION FOR $tinput!"}
                if($installer.InstallerUrl.count -gt 1){Write-Error "MORE THAN ONE INSTALLER FOR $tinput!"}
                #create folderstructure
                New-Item -ItemType Directory "$PSGOTpath\apps" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -ErrorAction SilentlyContinue
                #determineinstallertype
                $installertype=if($newest.InstallerType){$newest.InstallerType}else{$installer.InstallerType}
                #selectinstallertype
                if($installertype -gt 1){
                    if($installertype | where {$_ -eq "msi"}){$installer=$installer | where InstallerUrl -like "*.msi*"}
                    $installertype=if($newest.InstallerType){$newest.InstallerType}else{$installer.InstallerType}
                }
                $installerext=if($installertype -eq "msi"){"msi"}else{"exe"}
                #Download installer
                if(!(test-path "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext")){
                    $new=$true
                    "Downloading package for $appname"
                    Invoke-WebRequest $installer.InstallerUrl -OutFile "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext" -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
                }else{"file already exists: $PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername"}
                switch($installertype){
                    inno {
                        $installerswitches="/NORESTART /ALLUSERS /SILENT"
                    }
                    nullsoft {
                        $installerswitches="/S"
                    }
                    exe {
                        $installerswitches=if($newest.InstallerSwitches.silent){$newest.InstallerSwitches.silent}else{$installer.InstallerSwitches.silent}
                    }
                    msi{
                        $installerprefix="msiexec /i"
                        $installerswitches="/quiet /qn /norestart"
                    }
                }
                "Creating intunewin...."
                $intuneresult=. $PSGOTpath\IntuneWinAppUtil.exe -c "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -s "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$($newest.PackageIdentifier)-$($newest.PackageVersion).$installerext" -o "$PSGOTpath\apps\$($newest.PackageIdentifier)\" -q
                $intunefilename=($intuneresult | where {$_ -like "*has been generated successfully"}).split("'")[1]
                
                if($installerprefix){$installerprefix | out-file "$intunefilename.installerprefix"}
                if($installerswitches){$installerswitches | out-file "$intunefilename.installerswitches"}
                if($installertype){$installertype | out-file "$intunefilename.installertype"}
                @{
                    intunewinfilename=$intunefilename
                    version = $newest.PackageVersion
                    new = $new
                    type = $installerext
                }
            }
        }
    }
}



function Update-PSGOTIntuneApps {
    param(
        $PSGOTpath="c:\temp\psgot",
        [Parameter(ValueFromPipeline)]$appconfigfile
        #$intunewinpath

    )
    BEGIN{
        #Connect intune
        
    }
    PROCESS{
         ##Intune settings 
        $baseUrl = "https://graph.microsoft.com/beta/deviceAppManagement/"
        $logRequestUris = $true;
        $logHeaders = $false;
        $logContent = $true;
        $azureStorageUploadChunkSizeInMb = 6l;
        $sleep = 30
        ###
        $config=get-content $appconfigfile | ConvertFrom-Json
        $intunewindetails=$config.appidentifier | New-PSGOTIntuneWin -Architecture $config.Architecture

        $version=$intunewindetails.version
        $SourceFile = $intunewindetails.intunewinfilename
        
        #get version oapp from intune, if it exists
        $Intune_App = Get-IntuneApplication | where {$_.displayName -eq "$($config.name)"} | Sort-Object displayversion
        $Intune_AppUpdate = Get-IntuneApplication | where {$_.displayName -eq "Update-$($config.name)"}
        # Defining Intunewin32 detectionRules
        $DetectionXML = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"
        
        # Defining Intunewin32 detectionRules
        if($config.detectionrule -eq "file"){
            $DetectionRule = New-DetectionRule -File -Path "C:\Program Files\Application" `
            -FileOrFolderName "application.exe" -FileDetectionType exists -check32BitOn64System False

        }elseif($config.detectionrule -eq "registry"){
            $DetectionRule = New-DetectionRule -Registry -RegistryKeyPath "$($config.DetectionRegistryKeyPath)" `
            -RegistryDetectionType $config.DetectionRegistryDetectionType -RegistryValue $config.DetectionRegistryValue -check32BitRegOn64System false `
            -RegistryDetectionOperator $config.DetectionRegistryDetectionOperator -RegistryDetectionValue $version
        }
        elseif($config.detectionrule -eq "msi"){
            $DetectionRule = New-DetectionRule -MSI -MSIproductCode $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
        }
        # Defining Intunewin32 RequirementRules
        if($config.UpdateRequirementrule -eq "file"){
            $RequirementRule = New-RequirementRule -File -Path "C:\Program Files\Application" `
            -FileOrFolderName "application.exe" -FileDetectionType exists -check32BitOn64System False

        }elseif($config.UpdateRequirementrule -eq "registry"){
            $RequirementRule = New-RequirementRule -Registry -RegistryKeyPath "$($config.UpdateRequirementRegistryKeyPath)" `
            -RegistryDetectionType $config.UpdateRequirementRegistryDetectionType -RegistryValue $config.UpdateRequirementRegistryValue -check32BitRegOn64System false `
            -RegistryDetectionOperator $config.UpdateRequirementRegistryDetectionOperator -RegistryDetectionValue $version
        }
        elseif($config.UpdateRequirementrule -eq "msi"){
            $RequirementRule = New-DetectionRule -MSI -MSIproductCode $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
        }
                             
        $ReturnCodes = Get-DefaultReturnCodes
        
        $ReturnCodes += New-ReturnCode -returnCode 302 -type softReboot
        $ReturnCodes += New-ReturnCode -returnCode 145 -type hardReboot
        
        #installcmdline
        $installcmdline = if($intunewindetails.type -eq "exe"){
            $installswitches=get-content "$SourceFile.installerswitches"
            "$($DetectionXML.ApplicationInfo.setupfile) $installswitches"
        }elseif($intunewindetails.type -eq "msi"){
            $installswitches=get-content "$SourceFile.installerswitches"
            $installprefix=get-content "$SourceFile.installerprefix"
            "$installprefix $($DetectionXML.ApplicationInfo.setupfile) $installswitches"
        }
        $RequirementRules=@($RequirementRule)
        $DetectionRules=@($DetectionRule)
        # Win32 Application Upload
        if($intunewindetails.type -eq "exe"){
            if([version]$Intune_App.displayVersion -lt [version]$version ){        
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
                $selfserviceapp=Get-IntuneApplication | where {$_.displayname -eq "$($config.name)"}| where {$_.displayversion -eq "$version"}
                $assignmenturi="https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)/assignments"
                Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"available","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $assignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if($config.iconname){
                    $iconbase64=[Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent= '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if($config.iconname -like "*.png*"){$iconcontent=$iconcontent.replace('image/jpeg','image/png')}
                    $iconcontent=$iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }

            }else{"Selfservice: The newest version of $($config.name): $version is already present in Intune"}
    
            if(([version]$Intune_AppUpdate.displayVersion -lt [version]$version) -and ($config.PublishUpdate -eq "true") ){ 
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
                $updateapp=Get-IntuneApplication | where {$_.displayname -eq "Update-$($config.name)"}| where {$_.displayversion -eq "$version"}
                $updateassignmenturi="https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)/assignments"
                Invoke-RestMethod -uri $updateassignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"required","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $updateassignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if($config.iconname){
                    $iconbase64=[Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent= '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if($config.iconname -like "*.png*"){$iconcontent=$iconcontent.replace('image/jpeg','image/png')}
                    $iconcontent=$iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }

            }else{"Update: The newest version of $($config.name): $version is already present in Intune"}
        }elseif($intunewindetails.type -eq "msi"){
            if($Intune_App.displayVersion -lt $version ){        
                "Sourcefile is: $SourceFile"
                "publisher is: $($config.publisher)"
                "description is: $($config.description)"
                "detectopnrule is: $($DetectionRules | ConvertTo-Json)"
                "Version is: $version"
                Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
                -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
                -displayName "$($config.name)"  -version "$version"

                #assignment
                $selfserviceapp=Get-IntuneApplication | where {$_.displayname -eq "$($config.name)"}| where {$_.displayversion -eq "$version"}
                $assignmenturi="https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)/assignments"
                Invoke-RestMethod -uri $assignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"available","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $assignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if($config.iconname){
                    $iconbase64=[Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent= '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if($config.iconname -like "*.png*"){$iconcontent=$iconcontent.replace('image/jpeg','image/png')}
                    $iconcontent=$iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selfserviceapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }

            }else{"Selfservice: The newest version of $($config.name): $version is already present in Intune"}
            
            if(($Intune_AppUpdate.displayVersion -lt $version) -and ($config.PublishUpdate -eq "true") ){ 
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
                $updateapp=Get-IntuneApplication | where {$_.displayname -eq "Update-$($config.name)"}| where {$_.displayversion -eq "$version"}
                $updateassignmenturi="https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)/assignments"
                Invoke-RestMethod -uri $updateassignmenturi -Headers $global:authToken -Method GET
                $content = '{"intent":"required","source": "direct", "sourceId": null,"target":{"@odata.type": "#microsoft.graph.allLicensedUsersAssignmentTarget"}}'
                Invoke-RestMethod -Uri $updateassignmenturi -Headers $global:authToken -Method Post -Body $content -ContentType 'application/json'

                #icon
                if($config.iconname){
                    $iconbase64=[Convert]::ToBase64String((Get-Content -raw -Path $PSGOTpath\icons\$($config.iconname) -Encoding Byte))
                    $iconcontent= '{"@odata.type": "#microsoft.graph.win32LobApp", "largeIcon":{ "type": "image/jpeg", "value":"BASE64" }}'
                    if($config.iconname -like "*.png*"){$iconcontent=$iconcontent.replace('image/jpeg','image/png')}
                    $iconcontent=$iconcontent.replace('BASE64', $iconbase64)
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($updateapp.id)" -Method patch -Body $iconcontent -ContentType 'application/json' -Headers $global:authToken
                }

                
            }else{"Update: The newest version of $($config.name): $version is already present in Intune"}
        }
    }
    
}

. C:\ScheduledTask\_SystemMailCredentials.ps1

connect-azuread -credential $smtpcred
Test-AuthToken
#"C:\temp\psgot\appconfig\winrar.json" | Update-PSGOTIntuneApps 
"C:\temp\psgot\appconfig\Firefox.json" | Update-PSGOTIntuneApps
"C:\temp\psgot\appconfig\chrome.json" | Update-PSGOTIntuneApps
"C:\temp\psgot\appconfig\Notepad++.json" | Update-PSGOTIntuneApps
"C:\temp\psgot\appconfig\winscp.json" | Update-PSGOTIntuneApps
"C:\temp\psgot\appconfig\LogitechOptions.json" | Update-PSGOTIntuneApps
"C:\temp\psgot\appconfig\keepass.json"| Update-PSGOTIntuneApps
Get-ChildItem "C:\temp\psgot\appconfig\" | foreach {$_.fullname | Update-PSGOTIntuneApps}

"DominikReichl.KeePass" | New-PSGOTIntuneWin -Architecture x86
"WinSCP.WinSCP" | New-PSGOTIntuneWin -Architecture x86
"Mozilla.Firefox" | New-PSGOTIntuneWin
"Google.Chrome" | New-PSGOTIntuneWin
$appname="WinSCP.WinSCP"
