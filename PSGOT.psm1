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
                    ($available | sort packageversion -descending)[0]
                }else{$available}
                $installer=$newest.installers 
                $installer=$installer | where InstallerLocale -eq $locale
                $installer=$installer | where Architecture -eq $Architecture
                #create folderstructure
                New-Item -ItemType Directory "$PSGOTpath\apps" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)" -ErrorAction SilentlyContinue
                New-Item -ItemType Directory "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -ErrorAction SilentlyContinue
                #determineinstallertype
                $installertype=if($newest.InstallerType){$newest.InstallerType}else{$installer.InstallerType}
                $installername=$installer.InstallerUrl | Split-Path -Leaf
                #Download installer
                if(!(test-path "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername")){
                    $new=$true
                    "Downloading package for $appname"
                    Invoke-WebRequest $installer.InstallerUrl -OutFile "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername"
                }else{"file already exists: $PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername"}
                switch($installertype){
                    exe {
                        $installerswitches=if($newest.InstallerSwitches.silent){$newest.InstallerSwitches.silent}else{$installer.InstallerSwitches.silent}
                    }
                    msi{

                    }
                }
                "Creating intunewin...."
                $intuneresult=. $PSGOTpath\IntuneWinAppUtil.exe -c "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)" -s "$PSGOTpath\apps\$($newest.PackageIdentifier)\$($newest.PackageVersion)\$installername" -o "$PSGOTpath\apps\$($newest.PackageIdentifier)\" -q
                $intunefilename=($intuneresult | where {$_ -like "*has been generated successfully"}).split("'")[1]
                
                if($installerswitches){$installerswitches | out-file "$intunefilename.installerswitches"}
                if($installertype){$installertype | out-file "$intunefilename.installertype"}
                @{
                    intunewinfilename=$intunefilename
                    version = $newest.PackageVersion
                    new = $new
                }
            }
        }
    }
}

function Add-PSGOTAppconfig{
    param(

    )
    [pscustomobject]@{
        appidentifier = "RARLab.WinRAR"
        name = "WinRAR"
        Description = "Tool for extracting stuff"
        Publisher = "Publisher"
        Category = "Set category, must exist!"
        Restartbehaviour = ""
        Installbehavior = "system"
        $RegistryRule = "yes"
        $Registrykeypath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver"
        $RegistryValuename = "DisplayVersion"
        $RegistryDetectionmethod = "version"
        $Registryoperator = "ge"
        

    } | ConvertTo-Json -Depth 10 | Out-File $path\appconfig\WinRar.json
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
        $intunewindetails=$config.appidentifier | New-PSGOTIntuneWin
        $version=$intunewindetails.version
        $SourceFile = $intunewindetails.intunewinfilename
        
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
                
        $ReturnCodes = Get-DefaultReturnCodes
        
        $ReturnCodes += New-ReturnCode -returnCode 302 -type softReboot
        $ReturnCodes += New-ReturnCode -returnCode 145 -type hardReboot
        
        #installcmdline
        $installcmdline = if("exe"){
            $installswitches=get-content "$SourceFile.installerswitches"
            "$($DetectionXML.ApplicationInfo.setupfile) $installswitches"
        }
        $DetectionRules=@($DetectionRule)
        # Win32 Application Upload
        Upload-Win32Lob -SourceFile "$SourceFile" -publisher "$($config.publisher)" `
        -description "$($config.description)" -detectionRules $DetectionRules -returnCodes $ReturnCodes `
        -installCmdLine "$installcmdline" `
        -uninstallCmdLine "powershell.exe .\uninstall.ps1"
    }
    

}

"C:\temp\psgot\appconfig\winrar.json" | Update-PSGOTIntuneApps -intunewinpath "C:\temp\psgot\apps\RARLab.WinRAR\winrar-x64-602.intunewin"

"WinSCP.WinSCP" | New-PSGOTIntuneWin

$appname="WinSCP.WinSCP"

