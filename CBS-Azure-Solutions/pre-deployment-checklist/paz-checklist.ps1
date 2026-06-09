<#
    paz-checklist.ps1 -
    Version:        3.1.3
    Author:         Vaclav Jirovsky, Adam Mazouz, David Stamen @ Everpure
.SYNOPSIS
    Checking if the prerequisites required for deploying Everpure Cloud Dedicated are met before create the array on Azure.
.DESCRIPTION
    This script will validate and verify the following:
	- Check if the region where VNET is created is supported for Everpure Cloud Dedicated deployments.
	- Check if the region has enough Ebdsv5 or DSv3 Family vCPU to deploy Everpure Cloud Dedicated.
	- Check if the System Subnet has outbound internet Access.
    - Check if the Signed In User has the required Azure Role Assignment.
.INPUTS
    - Azure Subscription Id.
    - Pure Everpure Cloud Dedicated Model (V20MUR1, V10MUR1, V10MP2R2, V20MP2R2, V50MP2R2).
    - Azure Virtual Network, where Everpure Cloud Dedicated subnets are located.
    - Azure Subnet, designated for Everpure Cloud Dedicated System subnet.
    - (optional) Tags to be assigned for a temporary VM created for connectivity test
.OUTPUTS
    Print out the on console the validation results.
.EXAMPLE
    Option 1: Use Azure Cloud Shell to paste the script and run it
        & paz-checklist.ps1
    Option 2: Or use your local machine to install Azure Powershell Module and make sure to login to Azure first
        Connect-AzAccount
#>
<#
.DISCLAIMER
The sample script and documentation are provided AS IS and are not supported by the author or the author's employer, unless otherwise agreed in writing. You bear all risk relating to the use or performance of the sample script and documentation.
The author and the author's employer disclaim all express or implied warranties (including, without limitation, any warranties of merchantability, title, infringement 	or fitness for a particular purpose). In no event shall the author, the author's employer or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever arising out of the use or performance of the sample script and 	documentation (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss), even if 	such person has been advised of the possibility of such damages.
#>
param (
  [Parameter(Mandatory = $true, HelpMessage = 'Enter the SubscriptionId where your Resource Group is located')]
  [ValidateNotNullOrEmpty()]
  [ValidateScript(
    { $null -ne (Get-AzSubscription -SubscriptionId $_ -WarningAction silentlyContinue) }
  )]
  [string]
  $subscriptionId,

  [Parameter(Mandatory = $true, HelpMessage = 'Enter Everpure Cloud Dedicated Model (V10MUR1, V20MUR1, V10MP2R2, V20MP2R2, V50MP2R2)')]
  [ValidateNotNullOrEmpty()]
  [ValidateSet('V10MUR1', 'V20MUR1', 'V10MP2R2', 'V20MP2R2','V50MP2R2')]
  [string]
  $Model,

  [Parameter(Mandatory = $true, HelpMessage = 'Enter your vNET name')]
  [ValidateNotNullOrEmpty()]
  [string]
  $VNETName,

  [Parameter(Mandatory = $false, HelpMessage = "Enter your subnet name within vNET used for 'system'")]
  [ValidateNotNullOrEmpty()]
  [string]
  $vnetSystemSubnetName = 'system',

  [Parameter(Mandatory = $false, HelpMessage = 'Enter name for temporary VM created for connectivity tests')]
  [ValidateNotNullOrEmpty()]
  [string]
  $tempVmName = 'ECDedicated-TestVM',

  [Parameter(Mandatory = $false, HelpMessage = "List of tags to be assigned to the temporary VM created for connectivity tests, required by your Azure landing zone (e.g. @{'tag1'='value1';'tag2'='value2'})")]
  [hashtable]
  $tempVmTags = @{},

  [Parameter(Mandatory = $false, HelpMessage = 'VM Size to be Used. Defaults to Standard_B1s')]
  $tempVmSize = 'Standard_B1s',

  [Parameter(Mandatory = $false, HelpMessage = 'VM Operating System to be Used. Choices, Suse, Ubuntu, Redhat. Defaults to Ubuntu')]
  $tempVmOS = 'Ubuntu'
)

$finalReportOutput = @()

$AcceptableOS = @('Ubuntu', 'RedHat', 'Suse')
if ($tempVmOS -in $AcceptableOS) {

} else {
  Write-Error 'Unknown VM Operating System selected. Please select one of the following: Ubuntu, Suse, Redhat';
  Exit
}

if ($Model-eq 'V10MP2R2' -or $Model-eq 'V20MP2R2') {
  $supportedRegions =
  'australiacentral',
  'australiaeast',
  'brazilsouth',
  'brazilsoutheast',
  'canadacentral',
  'canadaeast',
  'centralindia',
  'centralus',
  'eastasia',
  'eastus',
  'eastus2',
  'francecentral',
  'germanywestcentral',
  'israelcentral',
  'italynorth',
  'japaneast',
  'koreacentral',
  'mexicocentral',
  'northeurope',
  'northcentralus',
  'norwayeast',
  'norwaywest',
  'polandcentral',
  'qatarcentral',
  'southafricanorth',
  'southcentralus',
  'southeastasia',
  'spaincentral',
  'swedencentral',
  'switzerlandnorth',
  'uaenorth',
  'uksouth',
  'ukwest',
  'westeurope',
  'westcentralus',
  'westus',
  'westus2',
  'westus3'
} elseif ($Model-eq 'V10MUR1' -or $Model-eq 'V20MUR1') {
  $supportedRegions =
  'australiacentral',
  'australiaeast',
  'brazilsouth',
  'brazilsoutheast',
  'canadacentral',
  'canadaeast',
  'centralindia',
  'centralus',
  'eastasia',
  'eastus',
  'eastus2',
  'francecentral',
  'germanywestcentral',
  'italynorth',
  'japaneast',
  'koreacentral',
  'koreasouth',
  'northcentralus',
  'northeurope',
  'polandcentral',
  'qatarcentral',
  'southafricanorth',
  'southcentralus',
  'southeastasia',
  'swedencentral',
  'switzerlandnorth',
  'uaenorth',
  'uksouth',
  'ukwest',
  'westeurope',
  'westus',
  'westus2',
  'westus3'
}
elseif ($Model-eq 'V50MP2R2') {
  $supportedRegions =
  'eastus2',
  'centralus',
  'eastus',
  'canadaeast',
  'canadacentral'
}
else {
  Write-Error 'Unknown Everpure Cloud Dedicated Model selected. Please select one of the following: V10MUR1, V20MUR1, V10MP2R2, V20MP2R2';
  exit;
}

$CLI_VERSION = '3.1.3'

Write-Host -ForegroundColor DarkRed @"
  ______
 |  ____|
 | |__ __   _____ _ __ _ __  _   _ _ __ ___
 |  __|\ \ / / _ \ '__| '_ \| | | | '__/ _ \
 | |____\ V /  __/ |  | |_) | |_| | | |  __/
 |______|\_/ \___|_|  | .__/ \__,_|_|  \___|
                      | |
                      |_|
"@

Write-Host  @"
------------------------------------------------------------
    Everpure Cloud Dedicated - Pre-Deployment Check Report
                (c) 2026 Everpure, Inc
                        v$CLI_VERSION
------------------------------------------------------------
"@

try {


  # Select validated subscription
  Select-AzSubscription -SubscriptionId $subscriptionId -WarningAction silentlyContinue | Out-Null

  $PSStyle.Progress.View = 'Classic'
  $endpointsToTest =
  'rest.cloud-support.purestorage.com',
  'ra.cloud-support.purestorage.com',
  'restricted-rest.cloud-support.purestorage.com',
  'restricted-ra.cloud-support.purestorage.com',
  'rest.cloud-support.purestorage.com',
  'rest2.cloud-support.purestorage.com',
  'management.azure.com',
  'cosmos.azure.com'

  # Resource_Group
  Write-Progress 'Checking vNET presence' -PercentComplete 0

  $rg = (Get-AzVirtualNetwork -Name $VNETName).ResourceGroupName
  if ($null -eq $rg) {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'vNET existence'
      Result   = 'FAILED'
      Details  = "vNET '$VNETName' WAS NOT found"
    };

    exit;
  }
  Write-Progress 'Checking vNET presence' -PercentComplete 100

  $finalReportOutput += [pscustomobject]@{
    TestName = 'vNET existence'
    Result   = 'OK'
    Details  = "vNET '$VNETName' was found in RG '$rg'"
  };

  Write-Progress 'Checking subnet presence' -PercentComplete 0

  $PSvnet = Get-AzVirtualNetwork -Name $VNETName
  $PSSubnet = Get-AzVirtualNetworkSubnetConfig -Name $vnetSystemSubnetName -VirtualNetwork $PSvnet
  if ($null -eq $PSSubnet) {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Subnet existence'
      Result   = 'FAILED'
      Details  = "Subnet '$vnetSystemSubnetName' WAS NOT found"
    };
    exit;
  }

  $finalReportOutput += [pscustomobject]@{
    TestName = 'Subnet existence'
    Result   = 'OK'
    Details  = "Subnet '$vnetSystemSubnetName' was found"
  };

  Write-Progress 'Checking subnet presence' -PercentComplete 100

  Write-Progress 'Checking region support' -PercentComplete 0
  # REGION
  $region = (Get-AzVirtualNetwork -Name  $VNETName).Location

  ###################
  ## Region Supported ##
  ###################
  if ($region -in $supportedRegions) {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Region support'
      Result   = 'OK'
      Details  = "Region '$region' is declared as supported for deploying a $Model"
    };
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Region support'
      Result   = 'FAILED'
      Details  = "Region '$region' IS declared as NOT supported for deploying a $Model"
    };
      exit;
  }
  Write-Progress 'Checking region support' -PercentComplete 100
  Write-Progress 'Checking vCPU limits' -PercentComplete 0

  ###################
  ##  vCPU Limits  ##
  ###################

  $VCPU = switch ($Model) {
    'V10MUR1' { 64 }
    'V20MUR1' { 128 }
    'V10MP2R2' { 32 }
    'V20MP2R2' { 64 }
    'V50MP2R2' { 256 }
    Default { Write-Host 'Invalid Everpure Cloud Dedicated Model selected.'; exit }
  }

  $vmSize = switch ($Model) {
    'V10MUR1' { 'Standard_D32s_v3' }
    'V20MUR1' { 'Standard_D64s_v3' }
    'V10MP2R2' { 'Standard_E16bds_v5' }
    'V20MP2R2' { 'Standard_E32bds_v5' }
    'V50MP2R2' { 'Standard_D128ds_v6' }
    Default { Write-Host 'Invalid Everpure Cloud Dedicated Model selected.'; exit }
  }

  $diskType = switch ($Model) {
    'V10MUR1' { 'UltraSSD_LRS' }
    'V20MUR1' { 'UltraSSD_LRS' }
    'V10MP2R2' { 'PremiumV2_LRS' }
    'V20MP2R2' { 'PremiumV2_LRS' }
    'V50MP2R2' { 'PremiumV2_LRS' }

    Default { Write-Host 'Invalid Everpure Cloud Dedicated Model selected.'; exit }
  }
  ##################################
  ##  Azure VM Stuff Availability ##
  ##################################

  try {
    $VMFamily = (Get-AzComputeResourceSku -Location $region | Where-Object ResourceType -EQ 'virtualMachines' | Select-Object Name, Family | Where-Object Name -EQ $vmSize | Select-Object -Property Family).Family
  } catch {
    Write-Host "Error retrieving VM Family for $vmSize in $region $_"
    exit;
  }


  $currentLimit = Get-AzVMUsage -Location $region | Where-Object { $_.Name.Value -eq $VMFamily } | Select-Object -ExpandProperty CurrentValue
  Write-Progress 'Checking vCPU limits' -PercentComplete 50
  $limit = Get-AzVMUsage -Location $region | Where-Object { $_.Name.Value -eq $VMFamily } | Select-Object -ExpandProperty Limit

  $vCPUAfterDeploy = $limit - ($VCPU + $currentLimit)
  if (($VCPU + $currentLimit) -le $limit) {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'vCPUs availability (quota)'
      Result   = 'OK'
      Details  = "There is enough $vmSize vCPUs for deploying a $Model($vCPUAfterDeploy after deployment, currently used $currentLimit, total limit $limit)"
    };
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'vCPUs availability (quota)'
      Result   = 'FAILED'
      Details  = "There IS NOT enough $vmSize vCPUs for deploying a $Model($vCPUAfterDeploy after deployment, currently used $currentLimit, total limit $limit)"
    };
    exit;
  }
  Write-Progress 'Checking vCPU limits' -PercentComplete 100

  Write-Progress 'Checking VM Region/Zone Restrictions limits' -PercentComplete 0
  Write-Progress 'Checking VM Region/Zone Restrictions limits' -PercentComplete 50
  try {
    $VMRestrictions = Get-AzComputeResourceSku -Location $region | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $vmSize } | Select-Object -ExpandProperty RestrictionInfo
  } catch {
    Write-Host "Error retrieving VM Region/Zone Restrictions: $_"
    exit;
  }
  if ($null -eq $VMRestrictions) {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'VM Region/Zone Restrictions'
      Result   = 'OK'
      Details  = "There is currently no Region/Zone restriction for $vmSize in $region"
    };
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'VM Region/Zone Restictions'
      Result   = 'FAILED'
      Details  = "There is currently a Region/Zone restriction for $vmSize. Restriction: $VMRestrictions"
    };

    exit;
  }
  Write-Progress 'Checking VM Region/Zone Restrictions limits' -PercentComplete 100

  ###################
  ## Backend Azure Disk Availability ##
  ###################

  Write-Progress 'Checking Managed Disk availability' -PercentComplete 0
  try {
    $diskSku = Get-AzComputeResourceSku -Location $region | Where-Object { $_.ResourceType -eq 'disks' -and $_.Name -eq $diskType }

    if ($null -eq $diskSku) {
      throw "Disk SKU '$diskType' not found in Azure Resource SKU data for region '$region'"
    }

    $locationInfo = $diskSku.LocationInfo
    $zones = $diskSku.LocationInfo.Zones
  } catch {
    Write-Host "Error retrieving disk SKU availability: $_"
    exit
  }

  if ($null -ne $locationInfo) {
    # Disk SKU is available in this region
    if ($null -ne $zones -and $zones.Count -gt 0) {
      $finalReportOutput += [pscustomobject]@{
        TestName = 'Managed Disks availability'
        Result   = 'OK'
        Details  = "The disk SKU '$diskType' is available in region '$region' in availability zones '$zones' for deploying a $Model"
      };
    } else {
      # No zonal region - disk is available but doesn't have multiple zones
      $finalReportOutput += [pscustomobject]@{
        TestName = 'Managed Disks availability'
        Result   = 'OK'
        Details  = "The disk SKU '$diskType' is available in region '$region' (No Zonal Region - single datacenter) for deploying a $Model"
      };
    }
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Managed Disks availability'
      Result   = 'FAILED'
      Details  = "The disk SKU '$diskType' is NOT available in region '$region' for deploying a $Model"
    };

    Write-Progress 'Checking Managed Disk availability' -PercentComplete 100

    # Print final report and exit since Managed Disks are not available
    Write-Host
    Write-Host -ForegroundColor DarkRed '-----------------------------------------------------'
    Write-Host -ForegroundColor DarkRed 'Final Report'
    Write-Host -ForegroundColor DarkRed '-----------------------------------------------------'
    Write-Host
    $finalReportOutput | Format-Table -AutoSize
    Write-Host
    Write-Error "Cannot continue: Managed disk SKU '$diskType' is not available in region '$region'. This is a critical prerequisite for deploying $Model." -ErrorAction Stop
    exit
  }

  Write-Progress 'Checking Managed Disk availability' -PercentComplete 100

  ####################
  ## Service Endpoint ##
  ####################

  Write-Progress 'Checking Service Endpoints' -PercentComplete 0

  $ServiceEndpoints = (Get-AzVirtualNetworkSubnetConfig -Name $vnetSystemSubnetName -VirtualNetwork $PSvnet).ServiceEndpoints

  Write-Progress 'Checking Service Endpoints' -PercentComplete 33

  if ($ServiceEndpoints.Service -eq 'Microsoft.KeyVault') {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Azure Key Vault Service Endpoint'
      Result   = 'OK'
      Details  = "The service endpoint for KeyVault is attached to the System Subnet '$vnetSystemSubnetName'"
    };
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Azure KeyVault Service Endpoint'
      Result   = 'FAILED'
      Details  = "The service endpoint for KeyVault is NOT attached to the System Subnet '$vnetSystemSubnetName'"
    };
  }

  Write-Progress 'Checking Service Endpoints' -PercentComplete 65

  if ($ServiceEndpoints.Service -eq 'Microsoft.Storage') {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Azure Storage Service Endpoint'
      Result   = 'OK'
      Details  = "The service endpoint for Storage is attached to the System Subnet '$vnetSystemSubnetName'"
    };
  } else {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Azure Storage Service Endpoint'
      Result   = 'FAILED'
      Details  = "The service endpoint for Storage is NOT attached to the System Subnet '$vnetSystemSubnetName'"
    };
  }

  Write-Progress 'Checking Service Endpoints' -PercentComplete 100

  ####################
  ## Azure IAM Roles ##
  ####################
  Write-Progress 'Checking IAM Role' -PercentComplete 0
  $currentContext = Get-AzContext
  if ($currentContext.Account.Type -eq 'ManagedService') {
    $finalReportOutput += [pscustomobject]@{
      TestName = 'Azure IAM Role'
      Result   = 'SKIPPED'
      Details  = 'Unable to check role assignment for Managed Service Identity (MSI)'
    };
  } else {
    $currentSignInName = $currentContext.Account.Id
    try {
      $listOfAssignedRoles = Get-AzRoleAssignment -SignInName $currentSignInName -ExpandPrincipalGroups | Where-Object Scope -EQ "/subscriptions/$subscriptionId"
    } catch {
      Write-Host "Error retrieving Azure role assignments: $_"
      exit;
    }
    $collections = $listOfAssignedRoles.RoleDefinitionName
    if ($listOfAssignedRoles) {
      if ($collections -like 'Contributor' -or $collections -like 'Owner' -or $collections -like 'Managed Application Contributor Role') {
        $finalReportOutput += [pscustomobject]@{
          TestName = 'Azure IAM Role'
          Result   = 'OK'
          Details  = 'Signed user has at least one of the required role assigned to the subscription'
        };
      } else {
        $finalReportOutput += [pscustomobject]@{
          TestName = 'Azure IAM Role'
          Result   = 'FAILED'
          Details  = "Signed user DOESN'T have any of the required role (Managed Application Contributor/Contributor/Owner) assigned to the subscription"
        };
      }
    }
  }
  Write-Progress 'Checking IAM Role' -PercentComplete 100

  ####################
  ## Connectivity Test ##
  ####################

  # 1/ Create Test_VM in System Subnet
  ####################

  $region = (Get-AzVirtualNetwork -Name  $VNETName).Location

  Write-Progress 'Creating a temporary test loadbalancer in System subnet' -PercentComplete 0

  $backendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name myBackendPool
  $frontendIP = New-AzLoadBalancerFrontendIpConfig -Name myFrontendIP -Subnet $PSSubnet
  $lbRule = New-AzLoadBalancerRuleConfig -Name myLoadBalancerRule -FrontendIpConfiguration $frontendIP -BackendAddressPool $backendPool -Protocol Tcp -FrontendPort 80 -BackendPort 80

  Write-Progress 'Creating a temporary test loadbalancer in System subnet' -PercentComplete 50

  try {
    $loadBalancer = New-AzLoadBalancer -ResourceGroupName $rg -Name "$TempVMName-LB" -Location $region -FrontendIpConfiguration $frontendIP -LoadBalancingRule $lbRule -BackendAddressPool $backendPool -Sku 'Standard' -Force -Confirm:$false

    if ($null -eq $loadBalancer) {
      throw "LoadBalancer creation returned null. Check resource group '$rg' and name '$TempVMName-LB' validity."
    }

    $bepool = $loadBalancer.BackendAddressPools[0]
  } catch {
    Write-Host
    Write-Host -ForegroundColor DarkRed '-----------------------------------------------------'
    Write-Host -ForegroundColor DarkRed 'Final Report'
    Write-Host -ForegroundColor DarkRed '-----------------------------------------------------'
    Write-Host
    $finalReportOutput | Format-Table -AutoSize
    Write-Host
    Write-Error "Failed to create temporary LoadBalancer: $_" -ErrorAction Stop
    exit
  }

  Write-Progress 'Creating a temporary test loadbalancer in System subnet' -PercentComplete 100

  Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 0
  ## Define a credential object to store the username and password for the virtual machine
  $UserName = 'azureuser'
  $Password = ConvertTo-SecureString ( -Join ('ABCDabcd&@#$%1234'.tochararray() | Get-Random -Count 10 | ForEach-Object { [char]$_ })) -AsPlainText -Force
  $psCred = New-Object System.Management.Automation.PSCredential($UserName, $Password)

  $NetworkSG = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $region -Name "$tempVMName-NSG" -Force
  $NIC = New-AzNetworkInterface -Name "$tempVMName-NIC" -ResourceGroupName $rg -Location $region -Subnet $PSSubnet -LoadBalancerBackendAddressPool $bepool -NetworkSecurityGroup $NetworkSG -Force

  Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 20

  try {
    ## Set the VM Size and Type
    $VirtualMachine = New-AzVMConfig -VMName $tempVMName -VMSize $tempVmSize -Tags $tempVmTags
    $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Linux -ComputerName $tempVMName -Credential $psCred
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
    $VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
  } catch {
    Write-Host 'An error occurred:'
    Write-Host $_
    exit
  }
  try {
    ## Set the VM Source Image
    if ($tempVmOS -eq 'Ubuntu') {
      #get-azvmimage -Location 'EastUS' -PublisherName 'Canonical' -Offer 'ubuntu-24_04-lts' -Skus server
      $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'Canonical' -Offer 'ubuntu-24_04-lts' -Skus 'server' -Version 'latest'
    } elseif ($tempVmOS -eq 'Suse') {
      #get-azvmimage -Location 'EastUS' -PublisherName 'suse' -Offer 'sles-15-sp5-basic' -Skus 'gen2' -Version latest
      $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'suse' -Offer 'sles-15-sp5' -Skus 'gen2' -Version 'latest'
    } elseif ($tempVmOS -eq 'Redhat') {
      #get-azvmimage -Location 'EastUS' -PublisherName 'redHat' -Offer 'RHEL' -Skus '87-gen2' -Version latest
      $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'redhat' -Offer 'RHEL' -Skus '9-lvm-gen2' -Version 'latest'
    }
    #if (-not $VirtualMachine.StorageProfile.ImageReference) {
    #    Write-Error "VM Image not found for OS type '$tempVmOS'. Please check the Publisher, Offer, and SKU details."
    #    exit 1 # Stop the script
    #}
    Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 40
    Update-AzConfig -DisplayBreakingChangeWarning $false -AppliesTo Az.Compute|Out-Null #Temp to Not Break Deployment
    Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 50
    New-AzVM -ResourceGroupName $rg -Location $region -VM $VirtualMachine -WarningAction Stop | Out-Null
    Update-AzConfig -DisplayBreakingChangeWarning $true -AppliesTo Az.Compute|Out-Null #Temp to Reset Warning
    Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 60
    Set-AzVMExtension -ResourceGroupName $rg -Location $region -VMName $tempVMName -Name 'NetworkWatcherAgentLinux' -ExtensionType 'NetworkWatcherAgentLinux' -Publisher 'Microsoft.Azure.NetworkWatcher' -TypeHandlerVersion '1.4' | Out-Null
    # 2/ Wait for the VM to be created
    ####################
    $VMStatus = (Get-AzVM -Name $tempVMName -ResourceGroupName $rg -Status).Statuses[1].DisplayStatus
    while ($VMStatus -ne 'VM running' ) {
      Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 75
      Start-Sleep -Seconds 10
    }
  } catch {
    Write-Host 'An error occurred:'
    Write-Host $_
    exit
  }

  Write-Progress 'Creating a temporary test VM in System subnet' -PercentComplete 100

  # 3/ Run Command against the Test_VM
  ####################
  Write-Progress 'Testing endpoints connectivity (approx. 5 mins)' -Status 'waiting...' -PercentComplete 0

  $VM1 = Get-AzVM -ResourceGroupName $rg | Where-Object -Property Name -EQ $tempVMName
  Write-Progress 'Testing endpoints connectivity (approx. 5 mins)' -Status 'starting...' -PercentComplete 0

  $networkWatcher = Get-AzNetworkWatcher | Where-Object -Property Location -EQ -Value $VM1.Location

  Write-Progress 'Testing endpoints connectivity (approx. 5 mins)' -Status 'started' -PercentComplete 10

  $i = 0;
  foreach ($endpoint in $endpointsToTest) {
    Write-Progress 'Testing endpoints connectivity (approx. 5 mins)' -CurrentOperation $endpoint -PercentComplete (($i + 1) * 100 / $endpointsToTest.Count)

    $TestConnectionStatus = (Test-AzNetworkWatcherConnectivity -NetworkWatcher $networkWatcher -SourceId $VM1.id -DestinationAddress $endpoint -DestinationPort 443).ConnectionStatus
    if ($TestConnectionStatus -eq 'Reachable') {
      $finalReportOutput += [pscustomobject]@{
        TestName = "$endpoint connection"
        Result   = 'OK'
        Details  = "Connection over HTTPS (port 443) has been succesfully established to $endpoint"
      };
    } else {
      $finalReportOutput += [pscustomobject]@{
        TestName = "$endpoint connection"
        Result   = 'FAILED'
        Details  = "Connection over HTTPS (port 443) has NOT been succesfully established to $endpoint"
      };
    }

    $i++;
  }

  Write-Progress 'Testing endpoints connectivity (approx. 5 mins)' -PercentComplete 100

  # 4/ Remove the Test_VM
  Write-Progress 'Removing the temporary test VM' -PercentComplete 0
  $vm = Get-AzVM -Name $tempVMName -ResourceGroupName $rg

    $diskName = $vm.StorageProfile.OsDisk.Name
    $null = $vm | Remove-AzVM -Force
    Write-Progress "Removing the temporary test VM" -PercentComplete 25
    Remove-AzNetworkInterface -Name "$tempVMName-NIC" -ResourceGroupName $rg -Force
    Write-Progress "Removing the temporary test VM" -PercentComplete 50
    Remove-AzDisk -ResourceGroupName $rg -DiskName $diskName -Force  | Out-Null
    Write-Progress "Removing the temporary test VM" -PercentComplete 75
    Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "$tempVMName-NSG" -Force
    Write-Progress "Removing the temporary test VM" -PercentComplete 100
    Write-Progress "Removing the temporary load balancer" -PercentComplete 0
    Remove-AzLoadBalancer -ResourceGroupName $rg -Name "$TempVMName-LB" -Force
    Write-Progress "Removing the temporary load balancer" -PercentComplete 100
}

finally {
    Write-Output ""
    Write-Output "-----------------------------------------------------"
    Write-Output "                   Final Report                      "
    write-Output "-----------------------------------------------------"

    Write-Output $finalReportOutput | Format-Table @{
        Label      = 'TestName'
        Expression =
        {
            switch ($_.TestName) {
                { $_ } { $color = "$($PSStyle.Foreground.FromRGB(255,255,49))" }
            }
            "$color$($_.TestName)$($PSStyle.Reset)"
        }
    },
    @{
        Label      = 'Result'
        Expression =
        {
            switch ($_.Result) {
                { $_ -eq "OK" } { $color = "$($PSStyle.Foreground.Green)" }
                { $_ -ne "OK" } { $color = "$($PSStyle.Foreground.Red)$($PSStyle.Blink)" }
            }
            "$color$($_.Result)$($PSStyle.Reset)"
        }

    },
    @{
        Label      = 'Details'
        Expression =
        {
            "$color$($_.Details)$($PSStyle.Reset)"
        }

    }
}
