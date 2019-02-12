<#
.SYNOPSIS
    Move Azure backups from one recovery vault to another
.DESCRIPTION
    Move Azure backups from one recovery vault to another.  Currently only supports AzureVM workloads.
    Optionally, you can remove existing recovery points.
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    None
.OUTPUTS
    Microsoft.Azure.Commands.RecoveryServices.Backup.Cmdlets.Models.JobBase
#>

function Move-AzureRecoveryVaultBackupItem {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [string] $SourceVaultName,

        [Parameter(Mandatory)]
        [string] $TargetVaultName,

        [Parameter()]
        [Guid] $SubscriptionID,

        [Parameter()]
        [Guid] $TargetSubscriptionID,

        [Parameter()]
        [string[]] $ComputerName,

        [Parameter()]
        [switch] $RemoveRecoveryPoints,

        [Parameter()]
        [switch] $PassThru

    )

    # TODO: add progress bar as this process can be slow

    $ErrorActionPreference = 'Stop'

    # select subscription and get vaults
    # if subscription id isn't provided, assume current context is correct
    if ( $PSBoundParameters.ContainsKey('SubscriptionID') ) {
        Select-AzureRmSubscription -Subscription $SubscriptionID | Out-String | Write-Verbose
    }
    $vaults = Get-AzureRmRecoveryServicesVault

    # set source vault context
    Write-Verbose ("Setting context for source vault {0}" -f $SourceVaultName)
    $vaults.where{$_.Name -eq $SourceVaultName} | Set-AzureRmRecoveryServicesVaultContext

    # get protection policies from source in case we need to recreate on target later
    $sourcePolicies = Get-AzureRmRecoveryServicesBackupProtectionPolicy

    $thisVaultsContainers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"

    if ( $PSBoundParameters.ContainsKey('ComputerName') ) {
        $thisVaultsContainers = $thisVaultsContainers.Where{$_.FriendlyName -in $ComputerName}
    }

    # these will be the items we setup on the target
    $backupItems = foreach ($cont in $thisVaultsContainers) {
        $bi = Get-AzureRmRecoveryServicesBackupItem -Container $cont -WorkloadType AzureVM
        Write-Verbose "disabling $($bi.name)"
        $params = @{
            Item                 = $bi[0]
            RemoveRecoveryPoints = $RemoveRecoveryPoints
            Force                = $true
        }
        Disable-AzureRmRecoveryServicesBackupProtection @params | Write-Verbose
        $bi
    }

    # set target subscription and vault context
    if ( $PSBoundParameters.ContainsKey('TargetSubscriptionID') ) {
        Select-AzureRmSubscription -Subscription $TargetSubscriptionID | Out-String | Write-Verbose
    }

    Write-Verbose ("Setting context for target vault {0}" -f $TargetVaultName)
    $vaults.where{$_.Name -eq $TargetVaultName} | Set-AzureRmRecoveryServicesVaultContext

    $targetPolicies = Get-AzureRmRecoveryServicesBackupProtectionPolicy
    Write-Verbose ("Target policies {0}" -f $targetPolicies | Out-String)

    $newItems = foreach ($bi in $backupItems) {

        $targetPolicy = $targetPolicies | Where-Object {$_.name -eq $bi.ProtectionPolicyName}

        # create backup policy on target if it doesn't exist
        if ( $targetPolicy ) {
            Write-Verbose ('{0} policy already exists' -f $bi.ProtectionPolicyName)
        }
        else {
            Write-Verbose ('{0} policy does not exist, creating...' -f $bi.ProtectionPolicyName)
            $sourcePolicies | Where-Object {$_.name -eq ($bi.ProtectionPolicyName)} | ForEach-Object {
                $params = @{
                    Name            = $_.Name
                    WorkloadType    = $_.WorkloadType
                    RetentionPolicy = $_.RetentionPolicy
                    SchedulePolicy  = $_.SchedulePolicy
                }
                $targetPolicy = New-AzureRmRecoveryServicesBackupProtectionPolicy @params
            }
        }

        Write-Verbose "enabling $($bi.name)"
        Enable-AzureRmRecoveryServicesBackupProtection -Policy $targetPolicy -Item $bi
    }

    if ( $PassThru ) {
        $newItems
    }
}
