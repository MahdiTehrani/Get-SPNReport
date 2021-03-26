function Get-SPNReport
{

##################################
####### Find Global Catalog ######
##################################

$LocalSite   = (Get-ADDomainController -Discover).Site
$NewTargetGC = Get-ADDomainController -Discover -Service 6 -SiteName $LocalSite
IF (!$NewTargetGC)
{ 
    $NewTargetGC = Get-ADDomainController -Discover -Service 6 -NextClosestSite 
}

$NewTargetGCHostName = $NewTargetGC.HostName
$LocalGC             = “$NewTargetGCHostName” + “:3268”




#################################
####### Defining Variables ######
#################################
$DNSRoot        = (Get-ADDomain).DNSRoot
$AllUsers       = Get-ADUser -Filter * -Server $DNSRoot -Properties serviceprincipalnames | Where-Object {($_.samaccountname -ne "krbtgt") -and ($_.serviceprincipalnames -ne $null)}
$CountUsers     = $AllUsers.Count
$CounterUser    = 0
[array]$Domains = (Get-ADForest).domains
[array]$List    = $null
[array]$Table   = $null




###################################
####### Processing Each User ######
###################################
foreach($User in $AllUsers)
{
    [array]$SPNs = $User.serviceprincipalnames
    $Samaccount  = $User.SamAccountName
    $DN          = $User.DistinguishedName
    $Enabled     = $User.Enabled
    $CounterUser = $CounterUser + 1

    Write-Progress -Activity "Processing users of ($DNSRoot)" -Status "Please wait while the report is being generated" -PercentComplete (($CounterUser/$CountUsers)*100) -id 1

    foreach($Row in $SPNs)
    {
        $DomainValue = "N/A"
        $Status      = "N/A"
        $Value = ($Row -split '/')[1] | Where-Object {$_ -ne "" }
    
        if($Value -like "*:*")
        {
            $Value = ($Value -split ':')[0]
        }

        if($Value -like "*.*")
        {
            $StartPosition = $Value.IndexOf('.')
            $DomainValue   = $Value.Substring($StartPosition+1)
            $Value         = $Value.Split(".")[0]
        }

        if($DomainValue -ne "N/A")
        {
            try
            {
                if(Get-ADComputer $Value -Server $DomainValue)
                {
                    $Status = "Valid"
                }
            }

            catch
            {
                if($DomainValue -notin $Domains)
                {
                    $Status = "External"
                }

                else
                {
                    $Status = "Phantom"
                }
            }

        }

        if($DomainValue -eq "N/A")
        {
            try
            {
                if(Get-ADComputer $Value -Server $DNSRoot)
                {
                    $DomainValue = $DNSRoot
                    $Status      = "Valid"
                }
            }
            catch
            {
                if(Get-ADcomputer -Filter {Name -eq $Value} -Server $LocalGC )
                {
                    $DNSHostName   = (Get-ADcomputer -Filter {Name -eq $Value} -Server $LocalGC).DNSHostName
                    $StartPosition = $DNSHostName.IndexOf('.')
                    $DomainValue   = $DNSHostName.Substring($StartPosition+1)
                    $Status        = "Valid (Child Domain)"
                }
                
                else
                {
                    $Status  = "Phantom (Semi)"
                }
            }
        }

        $Obj = New-Object -TypeName PSObject -Property @{
            "Username"     = $Samaccount
            "User Domain"  = $DNSRoot
            "Hostname"     = $Value
            "SPN"          = $Row
            "Domain"       = $DomainValue 
            "UserEnabled"  = $Enabled
            "SPN Status"   = $Status
        }

        $Table += $Obj
    }
}

$Table | select Username,'User Domain',UserEnabled,Hostname,SPN,Domain,'SPN Status' | Out-GridView -Title "SPN Report of ($DNSRoot)"

}



