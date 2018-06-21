$null = Login-AzureRmAccount
$allSubs = Get-AzureRmSubscription | where {$_.State -ne 'Disabled'}

$recoveryVaultList = New-Object System.Collections.ArrayList

$allSubs | % {

    $thisSub = $_
    $null = $thisSub | Select-AzureRmSubscription

    $progressParams = @{
        Activity        = "Getting recovery vault info for subscription {0}" -f $thisSub.Name
        Status          = " "
        PercentComplete = 0
    }
    Write-Progress @progressParams
    Get-AzureRmRecoveryServicesVault | % {
                
        $thisVault = $_
        $thisVault | Set-AzureRmRecoveryServicesVaultContext
        $loopCount = 0
        
        $thisVaultsContainers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"
        $thisVaultsContainers | % {
            
            $thisContainer = $_

            $loopCount += 1
            $progressParams.Status = "Vault: {0}, Container: {1}" -f $thisVault.Name, $thisContainer.FriendlyName
            $progressParams.PercentComplete = ($loopCount / $thisVaultsContainers.count) * 100
            Write-Progress @progressParams

            $recoveryItem = Get-AzureRmRecoveryServicesBackupItem -Container $thisContainer -WorkloadType "AzureVM" | select VirtualMachineId, ProtectionStatus, ProtectionState, LastBackupStatus, LastBackupTime, LatestRecoveryPoint
    
            $null = $recoveryVaultList.Add( $recoveryItem )
        }
    }
}

$recoveryVaultList
