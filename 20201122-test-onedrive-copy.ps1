
#前置作業
##需安裝這些模組

Install-Module SharePointPnPPowerShellOnline -Force

Install-Module MSOnline -Force

Install-Module -Name Microsoft.Online.SharePoint.PowerShell

##檢查暫存檔的目錄是否存在,如果不存在程式會自動產生
if (-not( Test-Path C:\temp) )
{
    mkdir "c:\temp"
}



###先利用以下的指令取得全公司的使用者的onedrive連結,之後再去選出本次的目標使用者連結貼手動貼到$departingUserUnderscore中

$TenantUrl = "https://vsco365-admin.sharepoint.com"
$LogFile = [Environment]::GetFolderPath("Desktop") + "\OneDriveSites.log"
Connect-SPOService -Url $TenantUrl 
Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Url -like '-my.sharepoint.com/personal/'" | Select -ExpandProperty Url | Out-File $LogFile -Force
Write-Host "Done! File saved as $($LogFile)."



###開始作業

$departinguser = Read-Host "Enter departing user's email"
$destinationuser = Read-Host "Enter destination user's email"
$globaladmin = Read-Host "Enter the username of your Global Admin account"
$credentials = Get-Credential -Credential $globaladmin
Connect-MsolService -Credential $credentials
 
$InitialDomain = Get-MsolDomain | Where-Object {$_.IsInitial -eq $true}
  
$SharePointAdminURL = "https://$($InitialDomain.Name.Split(".")[0])-admin.sharepoint.com"
  
#$departingUserUnderscore = $departinguser -replace "[^a-zA-Z]", "_"
$departingUserUnderscore = "lab-jack-a1_vsco365_onmicrosoft_com"
$destinationUserUnderscore = "jack_lai_vsco365_onmicrosoft_com"

#手動方式指定來源使用者  
#$departingOneDriveSite = "https://vsco365-my.sharepoint.com/personal/lab-jack-a1_vsco365_onmicrosoft_com"
#利用變數departingUserUnderscore來指定
$departingOneDriveSite = "https://vsco365-my.sharepoint.com/personal/$departingUserUnderscore"

#手動方式指定目的使用者
#$destinationOneDriveSite = "https://vsco365-my.sharepoint.com/personal/jack_lai_vsco365_onmicrosoft_com"
#利用變數destinationUserUnderscore來指定
$destinationOneDriveSite = "https://vsco365-my.sharepoint.com/personal/$destinationUserUnderscore"

Write-Host "`nConnecting to SharePoint Online" -ForegroundColor Blue
Connect-SPOService -Url $SharePointAdminURL -Credential $credentials
  
Write-Host "`nAdding $globaladmin as site collection admin on both OneDrive site collections" -ForegroundColor Blue
# Set current admin as a Site Collection Admin on both OneDrive Site Collections
Set-SPOUser -Site $departingOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $true
#Set-SPOUser -Site $destinationOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $true
  
Write-Host "`nConnecting to $departinguser's OneDrive via SharePoint Online PNP module" -ForegroundColor Blue
  
Connect-PnPOnline -Url $departingOneDriveSite -Credentials $credentials
  
Write-Host "`nGetting display name of $departinguser" -ForegroundColor Blue
# Get name of departing user to create folder name.
$departingOwner = Get-PnPSiteCollectionAdmin | Where-Object {$_.loginname -match $departinguser}
  
# If there's an issue retrieving the departing user's display name, set this one.
if ($departingOwner -contains $null) {
    $departingOwner = @{
        Title = "Departing User"
    }
}
  
# Define relative folder locations for OneDrive source and destination
$departingOneDrivePath = "/personal/$departingUserUnderscore/Documents"
$destinationOneDrivePath = "/personal/$destinationUserUnderscore/Documents/$($departingOwner.Title)'s Files"
$destinationOneDriveSiteRelativePath = "Documents/$($departingOwner.Title)'s Files"
  
Write-Host "`nGetting all items from $($departingOwner.Title)" -ForegroundColor Blue
# Get all items from source OneDrive
$items = Get-PnPListItem -List Documents -PageSize 1000
  
$largeItems = $items | Where-Object {[long]$_.fieldvalues.SMTotalFileStreamSize -ge 2610954240 -and $_.FileSystemObjectType -contains "File"}
if ($largeItems) {
    $largeexport = @()
    foreach ($item in $largeitems) {
        $largeexport += "$(Get-Date) - Size: $([math]::Round(($item.FieldValues.SMTotalFileStreamSize / 1MB),2)) MB Path: $($item.FieldValues.FileRef)"
        Write-Host "File too large to copy: $($item.FieldValues.FileRef)" -ForegroundColor DarkYellow
    }
    $largeexport | Out-file C:\temp\largefiles.txt -Append
    Write-Host "A list of files too large to be copied from $($departingOwner.Title) have been exported to C:\temp\LargeFiles.txt" -ForegroundColor Yellow
}
  
$rightSizeItems = $items | Where-Object {[long]$_.fieldvalues.SMTotalFileStreamSize -lt 2610954240 -or $_.FileSystemObjectType -contains "Folder"}
  
Write-Host "`nConnecting to $destinationuser via SharePoint PNP PowerShell module" -ForegroundColor Blue
Connect-PnPOnline -Url $destinationOneDriveSite -Credentials $credentials
  
Write-Host "`nFilter by folders" -ForegroundColor Blue
# Filter by Folders to create directory structure
$folders = $rightSizeItems | Where-Object {$_.FileSystemObjectType -contains "Folder"}
  
Write-Host "`nCreating Directory Structure" -ForegroundColor Blue
foreach ($folder in $folders) {
    $path = ('{0}{1}' -f $destinationOneDriveSiteRelativePath, $folder.fieldvalues.FileRef).Replace($departingOneDrivePath, '')
    Write-Host "Creating folder in $path" -ForegroundColor Green
    $newfolder = Ensure-PnPFolder -SiteRelativePath $path
}
  
 
Write-Host "`nCopying Files" -ForegroundColor Blue
$files = $rightSizeItems | Where-Object {$_.FileSystemObjectType -contains "File"}
$fileerrors = ""
foreach ($file in $files) {
      
    $destpath = ("$destinationOneDrivePath$($file.fieldvalues.FileDirRef)").Replace($departingOneDrivePath, "")
    Write-Host "Copying $($file.fieldvalues.FileLeafRef) to $destpath" -ForegroundColor Green
    $newfile = Copy-PnPFile -SourceUrl $file.fieldvalues.FileRef -TargetUrl $destpath -OverwriteIfAlreadyExists -Force -ErrorVariable errors -ErrorAction SilentlyContinue
    #$newfile = Copy-PnPFile -SourceUrl $file.fieldvalues.FileRef -TargetUrl $destinationOneDrivePath
    $fileerrors += $errors
}



$fileerrors | Out-File c:\temp\fileerrors.txt
  
# Remove Global Admin from Site Collection Admin role for both users
Write-Host "`nRemoving $globaladmin from OneDrive site collections" -ForegroundColor Blue
Set-SPOUser -Site $departingOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $false
#Set-SPOUser -Site $destinationOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $false
Write-Host "`nComplete!" -ForegroundColor Green


