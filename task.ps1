$rg = "mate-azure-task-5"

# ponytail: Linux VMs only (this task's VM); Windows would need RunPowerShellScript + offline volume
$unmountTemplate = @'
set -e
dev=$(readlink -f /dev/disk/azure/scsi1/lun__LUN__)
test -b "$dev"
for mnt in $(lsblk -rno MOUNTPOINT "$dev" | grep . || true); do
    umount "$mnt"
    sed -i "\|[[:space:]]$mnt[[:space:]]|d" /etc/fstab
done
'@

# unmount in the guest, then detach; a failed unmount throws, so a mounted disk is never detached
foreach ($vm in Get-AzVM -ResourceGroupName $rg) {
    $dataDisks = @($vm.StorageProfile.DataDisks)
    foreach ($dataDisk in $dataDisks) {
        $unmount = $unmountTemplate -replace '__LUN__', $dataDisk.Lun
        Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vm.Name -CommandId RunShellScript -ScriptString $unmount -ErrorAction Stop | Out-Null
        Remove-AzVMDataDisk -VM $vm -DataDiskNames $dataDisk.Name | Out-Null
    }
    if ($dataDisks) { Update-AzVM -ResourceGroupName $rg -VM $vm | Out-Null }
}

$unattachedDisks = Get-AzDisk -ResourceGroupName $rg | Where-Object { $_.DiskState -eq "Unattached" -and -not $_.ManagedBy }

# ponytail: default ConvertTo-Json depth (2) is enough for Name/DiskState; -InputObject keeps a single disk as a JSON array
ConvertTo-Json -InputObject @($unattachedDisks) | Out-File -FilePath "$PSScriptRoot/result.json" -Force
