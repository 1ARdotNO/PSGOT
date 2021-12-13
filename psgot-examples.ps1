$PSGOTPATH="c:\ScheduledTask\psgot"

#Import credentials
. C:\ScheduledTask\_SystemMailCredentials.ps1



#initialize and sync repo
Initialize-PSGOT -path $PSGOTPATH

#authenticate
$global:authToken = Get-AuthTokenWithUsernameAndpassword -user "$smtpsender" -password "$smtppassword"

(Get-ChildItem "$PSGOTPATH\appconfig\" | where {$_.name -notlike "_*"}).fullname  | Update-PSGOTIntuneApps


<#TESTING STUFF

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
#>