# Variables
$OU = "OU=Users,OU=Dallas,OU=Texas,DC=Contoso,DC=local"
$SG = "TestGroupTest"


$OUMembers = Get-ADUser -SearchBase $OU -Filter * -ResultSetSize 1000 | Select SamAccountName

Foreach ($User in  $OUMembers) {

     
     Write-Output $User.SamAccountName
     $GroupMembers = Get-ADGroupMember -Identity $SG -Recursive | Select SamAccountName
     
        If ($GroupMembers.SamAccountName -contains $User.SamAccountName) {
                Write-Host "$User is already member of $SG"
            } 
        Else {
                Write-Host "Adding User: $User"
                Add-ADGroupMember -Identity "TestGroupTest" -Members $User
       
             }
    
    }
