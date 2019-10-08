# ------------------- Imports -------------------------------------------------

Import-Module ActiveDirectory
Import-Module MSOnline

# ------------------- Define Script Functions ---------------------------------

function Force-ADSync #Sync On-Prem AD to Azure/O365
{
 $s = New-PSSession -ComputerName $ADSyncSVR
 Invoke-Command -Session $s -ScriptBlock {Import-Module "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync\ADSync.psd1"}
 Invoke-Command -Session $s -ScriptBlock {Start-ADSyncSyncCycle -PolicyType Delta}
 Remove-PSSession $s
}

function Password-Algo # Create generic password based on user's full name and current year
{
 param($FName, $LName)
 $Year = Get-Date -Format yy
 $Algo = $FName.Substring(0,1).ToUpper() + $LName.Substring(0,1).ToUpper() + $Year + $FName.Substring($FName.get_Length() - 1).ToLower() + $LName.Substring($LName.get_Length() - 1).ToLower() + "!!"
 Return $Algo
}



# ------------------- Define Constants ----------------------------------------


$NewADUsers    = Import-csv .\import_users.csv # Imort CSV rows into $ADUsers variable
$OU            = "OU=Import,DC=contoso,DC=com"
$Domain        = "contoso.com"
$RoutingDomain = "contoso.onmicrosoft.com"
$ExchangeSVR   = "ExProd1.contoso.local"
$ADSyncSVR     = "DCProd1.contoso.local"  
Connect-MsolService   # Authenticate to Msol Service 

# ------------------- Begin Script --------------------------------------------

# Loop through each row to import user fields

foreach ($User in $NewADUsers)
{
	# Required user fields
	
	$Firstname 	    = $User.firstname
	$Lastname 	    = $User.lastname	
	$Username 	    = $User.firstname.Substring(0,1) + $User.lastname
    $Telephone      = $User.telephone
    $Alias          = $User.alias
    $Email          = $Username + '@' + $Domain
    $RoutingAddress = $Username + '@' + $RoutingDomain
    $Password       = Password-Algo $Firstname $Lastname
    $Is_Prem        = $User.is_prem 
    
    # Check for preexisting users

	if (Get-ADUser -F {SamAccountName -eq $Username})
	{
		 # Output warning if user already exists in AD Domain

		 Write-Warning "A user account with username $Username already exist in $Domain"
	}
	else
	{
		# Continue if user does not exist in AD Domain
		
        # Create account in $OU with required fileds

        New-ADUser `
            -SamAccountName $Username `
            -UserPrincipalName "$Email" `
            -Email "$Email" `
            -Name "$Firstname $Lastname" `
            -GivenName $Firstname `
            -Surname $Lastname `
            -Enabled $True `
            -DisplayName "$Firstname $Lastname" `
            -Path $OU `
            -AccountPassword (convertto-securestring $Password -AsPlainText -Force) -ChangePasswordAtLogon $True
        
        # Add group logic or default groups here

        Add-ADGroupMember -Identity "All Employees" -Members $Username

        # Set optional user properties here

        If ($Telephone -match "^\d+$")
            {
             Set-ADUser $Username -Replace @{telephoneNumber="$Telephone"}
            }
        


        Force-ADSync # Force sync with Azure/O365

        # Provision O365 License

        write-host -fore yellow "Ignore warning about User Not Found"
        While (-not (Get-MsolUser -UserPrincipalName $Email)) # Pause until user is visible in O365
            {
              write-host -fore yellow "Sleeping 30 Seconds - Performing ADSync" 
              Start-Sleep -Milliseconds 30000
            }

        Set-MsolUser -UserPrincipalName $Email -UsageLocation "US"
        If ($Is_Prem.toLower() -eq 'yes' -or $Is_Prem.ToLower() -eq 'y')
            {
             Set-MsolUserLicense -UserPrincipalName "$Email" -AddLicenses "Contoso:O365_BUSINESS_PREMIUM" # run Get-MsolAccountSku to see licenses available to your account
             Write-Output "Premium License Assigned"
            }
            
        Else
            {
             Set-MsolUserLicense -UserPrincipalName "$Email" -AddLicenses "Contoso:O365_BUSINESS_ESSENTIALS" # run Get-MsolAccountSku to see licenses available to your account
             Write-Output "Essentials License Assigned"
            }
        

       

        # Create O365 mailbox addresses on local 

        $ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$ExchangeSVR/PowerShell/ -Authentication Kerberos
        Import-PSSession $ExchangeSession -DisableNameChecking -AllowClobber
        Enable-RemoteMailbox $Email -PrimarySmtpAddress $Email -RemoteRoutingAddress $RoutingAddress
        Set-RemoteMailbox $Email –EmailAddressPolicyEnabled $true

        # Check alias, create if not in use 
        If ($Alias -match "^\d+$")
            {
             $CheckAlias = Get-Recipient -Identity "$Alias@$Domain" -ErrorAction SilentlyContinue
               If (!$CheckAlias) 
                    {
                     Write-Output "Alias not in use... Proceeding"
                     Set-RmoteMailbox $Email -EmailAddresses @{add="$Alias@$Domain"}
                    }

               Else
                    {
                     Write-Warning "Alias $Alias@$Domain already in use"
                    } 
            }
         Remove-PSSession $ExchangeSession

        
    }
}

