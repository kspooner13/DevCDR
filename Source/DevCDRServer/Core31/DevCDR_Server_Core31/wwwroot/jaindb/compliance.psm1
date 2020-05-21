﻿function Test-Logging {
    <#
        .Description
        test if logging is enabled
    #>

    if (Get-Module -ListAvailable -Name WriteAnalyticsLog) { return $true } else { return $false }
}

function Test-Nuget {
    <#
        .Description
        Check if Nuget PackageProvider is installed
    #>

    try {
        if ([version]((Get-PackageProvider nuget | Sort-Object version)[-1]).Version -lt "2.8.5.208") { Install-PackageProvider -Name "Nuget" -Force }
    }
    catch { Install-PackageProvider -Name "Nuget" -Force }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("Nuget")) { $global:chk.Remove("Nuget") }
    $global:chk.Add("Nuget", ((Get-PackageProvider nuget | Sort-Object version)[-1]).Version.ToString())
}

function Test-NetMetered {
    <#
        .Description
        Check if Device is using a metered network connection.
    #>

    # Source: https://www.powershellgallery.com/packages/NetMetered/1.0/Content/NetMetered.psm1
    # Created by:     Wil Taylor (wilfridtaylor@gmail.com) 
    $res = $false;
    try {
        [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
        $networkprofile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()

        if ($networkprofile -eq $null) {
            Write-Warning "Can't find any internet connections!"
        }
        else {
            $cost = $networkprofile.GetConnectionCost()
    
            if ($cost -eq $null) {
                Write-Warning "Can't find any internet connections with a cost!"
            }
    
            if ($cost.Roaming -or $cost.OverDataLimit) {
                $res = $true
            }
            
            if ($cost.NetworkCostType -eq [Windows.Networking.Connectivity.NetworkCostType]::Unrestricted) {
                $res = $false
            }

            if ($cost.NetworkCostType -eq [Windows.Networking.Connectivity.NetworkCostType]::Fixed -or
                $cost.NetworkCostType -eq [Windows.Networking.Connectivity.NetworkCostType]::Variable) {
                $res = $true
            }
        }
    }
    catch { $res = $false }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("Metered")) { $global:chk.Remove("Metered") }
    $global:chk.Add("Metered", $res)

    return $res
}

function Test-OneGetProvider($ProviderVersion = "1.7.1.3", $DownloadURL = "https://github.com/rzander/ruckzuck/releases/download/$($ProviderVersion)/RuckZuck.provider.for.OneGet_x64.msi" ) {
    <#
        .Description
        If missing, install latest RuckZuck Provider for OneGet...
    #>
    

    if (Get-PackageProvider -Name Ruckzuck -ea SilentlyContinue) { } else {
        if ($bLogging) {
            Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 1000; Description = "Installing OneGet v1.7.1.3"; CustomerID = $( Get-DevcdrID ); DeviceID = $( GetMyID ) }) -LogType "DevCDRCore" 
        }
        &msiexec -i $DownloadURL /qn REBOOT=REALLYSUPPRESS 
    }

    if ((Get-PackageProvider -Name Ruckzuck).Version -lt [version]($ProviderVersion)) {
        if ($bLogging) {
            Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 1000; Description = "Updating to OneGet v1.7.1.3"; CustomerID = $( Get-DevcdrID ); DeviceID = $( GetMyID ) }) -LogType "DevCDRCore" 
        }
        &msiexec -i $DownloadURL /qn REBOOT=REALLYSUPPRESS 
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("OneGetProvider")) { $global:chk.Remove("OneGetProvider") }
    $global:chk.Add("OneGetProvider", (Get-PackageProvider -Name Ruckzuck).Version.ToString())
}

function Test-DevCDRAgent($AgentVersion = "2.0.1.36") {
    <#
        .Description
        Install or Update DevCDRAgentCore if required
    #>
    $fix = "1.0.0.7"
    if (-NOT (Get-Process DevCDRAgent -ea SilentlyContinue)) {
        if ([version](get-item "$($env:ProgramFiles)\DevCDRAgentCore\DevCDRAgentCore.exe").VersionInfo.FileVersion -lt [version]($AgentVersion)) {
            [xml]$a = Get-Content "$($env:ProgramFiles)\DevCDRAgentCore\DevCDRAgentCore.exe.config"
            $customerId = ($a.configuration.applicationSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'CustomerID' }).value
            $ep = ($a.configuration.userSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'Endpoint' }).value

            if ($customerId) { 
                $customerId > $env:temp\customer.log
                if ($bLogging) {
                    Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 1002; Description = "Updating DevCDRAgent to v$($AgentVersion)"; DeviceID = $( GetMyID ); CustomerID = $( Get-DevcdrID ) }) -LogType "DevCDRCore" 
                }
                &msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi CUSTOMER="$($customerId)" /qn REBOOT=REALLYSUPPRESS  
            }
            else {
                &msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi ENDPOINT="$($ep)" /qn REBOOT=REALLYSUPPRESS  
            }
        }
    }
    else {
        Get-ScheduledTask DevCDR | Unregister-ScheduledTask -Confirm:$False
        return
    }

    #Add Scheduled-Task to repair Agent 
    if ((Get-ScheduledTask DevCDR -ea SilentlyContinue).Description -ne "DeviceCommander fix $($fix)") {
        if ($bLogging) {
            Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 1004; Description = "Registering Scheduled-Task for DevCDR fix $($fix)"; DeviceID = $( GetMyID ); CustomerID = $( Get-DevcdrID ) }) -LogType "DevCDRCore" 
        }
        try {
            $scheduleObject = New-Object -ComObject schedule.service
            $scheduleObject.connect()
            $rootFolder = $scheduleObject.GetFolder("\")
            $rootFolder.CreateFolder("DevCDR")
        }
        catch { }

        [xml]$a = Get-Content "$($env:ProgramFiles)\DevCDRAgentCore\DevCDRAgentCore.exe.config"
        $customerId = ($a.configuration.applicationSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'CustomerID' }).value
        $ep = ($a.configuration.userSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'Endpoint' }).value
        if ($customerId) {
            if ($ep) {
                $arg = "if(-not (get-process DevCDRAgentCore -ea SilentlyContinue)) { `"&msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi CUSTOMER=$($customerId) ENDPOINT=$($ep) /qn REBOOT=REALLYSUPPRESS`" }"
                $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arg
                $trigger = New-ScheduledTaskTrigger -Daily -At 11:25am -RandomDelay 00:25:00
                $Stset = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration 00:02:00 -IdleWaitTimeout 02:30:00 -WakeToRun
            }
            else {
                $arg = "if(-not (get-process DevCDRAgentCore -ea SilentlyContinue)) { `"&msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi CUSTOMER=$($customerId) ENDPOINT=https://devcdrcore.azurewebsites.net/chat /qn REBOOT=REALLYSUPPRESS`" }"
                $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arg
                $trigger = New-ScheduledTaskTrigger -Daily -At 11:25am -RandomDelay 00:25:00
                $Stset = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration 00:02:00 -IdleWaitTimeout 02:30:00 -WakeToRun
            }
            Register-ScheduledTask -Action $action -Settings $Stset -Trigger $trigger -TaskName "DevCDR" -Description "DeviceCommander fix $($fix)" -User "System" -TaskPath "\DevCDR" -Force
        }
        else {
            if ($ep) {
                $arg = "if(-not (get-process DevCDRAgentCore -ea SilentlyContinue)) { `"&msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi ENDPOINT=$($ep) /qn REBOOT=REALLYSUPPRESS`" }"
                $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arg
                $trigger = New-ScheduledTaskTrigger -Daily -At 11:25am -RandomDelay 00:25:00
                $Stset = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration 00:02:00 -IdleWaitTimeout 02:30:00 -WakeToRun
            }
            else {
                $arg = "if(-not (get-process DevCDRAgentCore -ea SilentlyContinue)) { `"&msiexec -i https://devcdrcore.azurewebsites.net/DevCDRAgentCoreNew.msi ENDPOINT=https://devcdrcore.azurewebsites.net/chat /qn REBOOT=REALLYSUPPRESS`" }"
                $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arg
                $trigger = New-ScheduledTaskTrigger -Daily -At 11:25am -RandomDelay 00:25:00
                $Stset = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration 00:02:00 -IdleWaitTimeout 02:30:00 -WakeToRun
            }
            Register-ScheduledTask -Action $action -Settings $Stset -Trigger $trigger -TaskName "DevCDR" -Description "DeviceCommander fix $($fix)" -User "System" -TaskPath "\DevCDR" -Force
        }
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("DevCDRAgent")) { $global:chk.Remove("DevCDRAgent") }
    $global:chk.Add("DevCDRAgent", (get-item "$($env:ProgramFiles)\DevCDRAgentCore\DevCDRAgentCore.exe").VersionInfo.FileVersion )
}

function Test-Administrators {
    <#
        .Description
        Fix local Admins on CloudJoined Devices, PowerShell Isseue if unknown cloud users/groups are member of a local group
    #>
    
    $bRes = $false;
    #Skip fix if running on a DC
    if ( (Get-WmiObject Win32_OperatingSystem).ProductType -ne 2) {
        if (Get-LocalGroupMember -SID S-1-5-32-544 -ea SilentlyContinue) { } else {
            $localgroup = (Get-LocalGroup -SID "S-1-5-32-544").Name
            $Group = [ADSI]"WinNT://localhost/$LocalGroup, group"
            $members = $Group.psbase.Invoke("Members")
            $members | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) } | Where-Object { $_ -like "S-1-12-1-*" } | ForEach-Object { Remove-LocalGroupMember -Name $localgroup $_ } 
            $bRes = $true;
        }
    } 
}

function Set-LocalAdmin($disableAdmin = $true, $randomizeAdmin = $true) {
    <#
        .Description
         disable local Admin account or randomize PW if older than 4 hours
    #>

    #Skip fix if running on a DC
    if ( (Get-WmiObject Win32_OperatingSystem).ProductType -ne 2) {
        $pwlastset = (Get-LocalUser | Where-Object { $_.SID -like "S-1-5-21-*-500" }).PasswordLastSet
        if (!$pwlastset) { $pwlastset = Get-Date -Date "1970-01-01 00:00:00Z" }
        if (((get-date) - $pwlastset).TotalHours -gt 4) {
            if ($disableAdmin) {
                (Get-LocalUser | Where-Object { $_.SID -like "S-1-5-21-*-500" }) | Disable-LocalUser
            }
            else {
                (Get-LocalUser | Where-Object { $_.SID -like "S-1-5-21-*-500" }) | Enable-LocalUser 
            }

            if ($randomizeAdmin) {
                if (((get-date) - $pwlastset).TotalHours -gt 12) {
                    $pw = get-random -count 12 -input (35..37 + 45..46 + 48..57 + 65..90 + 97..122) | ForEach-Object -begin { $aa = $null } -process { $aa += [char]$_ } -end { $aa }; 
                    (Get-LocalUser | Where-Object { $_.SID -like "S-1-5-21-*-500" }) | Set-LocalUser -Password (ConvertTo-SecureString -String $pw -AsPlainText -Force)

                    if (Test-Logging) {
                        Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 1001; Description = "AdminPW:" + $pw; CustomerID = $( Get-DevcdrID ); DeviceID = $( GetMyID ) }) -LogType "DevCDR" -TennantID "DevCDR"
                    }
                }
            }
        }
    }
}

function Test-LocalAdmin {
    <#
        .Description
         count local Admins
    #>

    $locAdmin = @()  
    #Skip fix if running on a DC
    if ( (Get-WmiObject Win32_OperatingSystem).ProductType -ne 2) {
        
        $admingroup = (Get-WmiObject -Class Win32_Group -Filter "LocalAccount='True' AND SID='S-1-5-32-544'").Name
       
        $groupconnection = [ADSI]("WinNT://localhost/$admingroup,group")
        $members = $groupconnection.Members()
        ForEach ($member in $members) {
            $name = $member.GetType().InvokeMember("Name", "GetProperty", $NULL, $member, $NULL)
            $class = $member.GetType().InvokeMember("Class", "GetProperty", $NULL, $member, $NULL)
            $bytes = $member.GetType().InvokeMember("objectsid", "GetProperty", $NULL, $member, $NULL)
            $sid = New-Object Security.Principal.SecurityIdentifier ($bytes, 0)
            $result = New-Object -TypeName psobject
            $result | Add-Member -MemberType NoteProperty -Name Name -Value $name
            $result | Add-Member -MemberType NoteProperty -Name ObjectClass -Value $class
            $result | Add-Member -MemberType NoteProperty -Name id -Value $sid.Value.ToString()
            #Exclude locaAdmin and DomainAdmins
            if (($result.id -notlike "S-1-5-21-*-500" ) -and ($result.id -notlike "S-1-5-21-*-512" )) {
                $locAdmin = $locAdmin + $result;
            }
        }
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("Admins")) { $global:chk.Remove("Admins") }
    $global:chk.Add("Admins", $locAdmin.Count)
}

function Test-WOL {
    <#
        .Description
        Enable WOL on NetworkAdapters
    #>
    $bRes = $false
    $niclist = Get-NetAdapter | Where-Object { ($_.MediaConnectionState -eq "Connected") -and (($_.name -match "Ethernet") -or ($_.name -match "local area connection")) }
    $niclist | ForEach-Object { 
        $nic = $_
        $nicPowerWake = Get-WmiObject MSPower_DeviceWakeEnable -Namespace root\wmi | Where-Object { $_.instancename -match [regex]::escape($nic.PNPDeviceID) }
        If ($nicPowerWake.Enable -eq $true) { }
        Else {
            try {
                $nicPowerWake.Enable = $True
                $nicPowerWake.psbase.Put() 
                $bRes = $true;
            }
            catch { }
        }
        $nicMagicPacket = Get-WmiObject MSNdis_DeviceWakeOnMagicPacketOnly -Namespace root\wmi | Where-Object { $_.instancename -match [regex]::escape($nic.PNPDeviceID) }
        If ($nicMagicPacket.EnableWakeOnMagicPacketOnly -eq $true) { }
        Else {
            try {
                $nicMagicPacket.EnableWakeOnMagicPacketOnly = $True
                $nicMagicPacket.psbase.Put()
                $bRes = $true;
            }
            catch { }
        }
    }

    
    #Enable WOL broadcasts
    if ((Get-NetFirewallRule -DisplayName "WOL" -ea SilentlyContinue).count -gt 1) {
        #Cleanup WOl Rules
        Remove-NetFirewallRule -DisplayName "WOL" -ea SilentlyContinue
    }
    if ((Get-NetFirewallRule -DisplayName "WOL" -ea SilentlyContinue).count -eq 0) {
        #Add WOL Rule
        New-NetFirewallRule -DisplayName "WOL" -Direction Outbound -RemotePort 9 -Protocol UDP -Action Allow
    }

    #if ($null -eq $global:chk) { $global:chk = @{ } }
    #if ($global:chk.ContainsKey("WOL")) { $global:chk.Remove("WOL") }
    #$global:chk.Add("WOL", $bRes)
}

function Test-FastBoot($Value = 0) {
    <#
        .Description
        Disable FastBoot
    #>

    New-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value $Value -PropertyType DWord -Force -ea SilentlyContinue | Out-Null;

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("FastBoot")) { $global:chk.Remove("FastBoot") }
    $global:chk.Add("FastBoot", $Value)
}

function Test-DeliveryOptimization {
    <#
        .Description
        restrict Peer Selection on DeliveryOptimization
    #>

    #Create the key if missing 
    If ((Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization') -eq $false ) { New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -force -ea SilentlyContinue } 

    #Enable Setting and Restrict to local Subnet only
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DORestrictPeerSelectionBy' -Value 1 -ea SilentlyContinue 

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("DO")) { $global:chk.Remove("DO") }
    $global:chk.Add("DO", 1)
}

function Test-locked {
    <#
        .Description
        check if device is locked
    #>
    $bRes = $false
    If (get-process logonui -ea SilentlyContinue) { $bRes = $true } else { $bRes = $false }
    
    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("locked")) { $global:chk.Remove("locked") }
    $global:chk.Add("locked", $bRes)

    return $bRes
}

function Test-Software {
    <#
        .Description
        Check for missing SW Updates
    #>

    #Find Software Updates
    $updates = Find-Package -ProviderName RuckZuck -Updates | Select-Object PackageFilename

    if ($updates) {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("RZUpdates")) { $global:chk.Remove("RZUpdates") }
        if ($updates) { $global:chk.Add("RZUpdates", $updates.PackageFilename -join ';') } else { $global:chk.Add("RZUpdates", "") }
    }
    else {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("RZUpdates")) { $global:chk.Remove("RZUpdates") }
        if ($updates) { $global:chk.Add("RZUpdates", "") } else { $global:chk.Add("RZUpdates", "") }   
    }
}
function Update-Software {
    <#
        .Description
        Update a specific list of Softwares
    #>
    param( 
        [parameter(Mandatory = $true)] [string[]] $SWList, 
        [parameter(Mandatory = $true)] [boolean] $CheckMeteredNetwork
    )

    if ($CheckMeteredNetwork) {
        if (Test-NetMetered) { return }
    }

    #Find Software Updates
    $updates = Find-Package -ProviderName RuckZuck -Updates | Select-Object PackageFilename | Sort-Object { Get-Random }
    $i = 0
    #Update only managed Software
    $SWList | ForEach-Object { 
        if ($updates.PackageFilename -contains $_) { 
            if (Test-Logging) {
                Write-Log -JSON ([pscustomobject]@{Computer = $env:COMPUTERNAME; EventID = 2000; Description = "RuckZuck updating: $($_)"; CustomerID = $( Get-DevcdrID ); DeviceID = $( GetMyID ) }) -LogType "DevCDR" -TennantID "DevCDR"
            }
            "Updating: " + $_ ;
            Install-Package -ProviderName RuckZuck "$($_)" -ea SilentlyContinue
        }
        else { $i++ }
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("SoftwareUpdates")) { $global:chk.Remove("SoftwareUpdates") }
    if ($updates) { $global:chk.Add("SoftwareUpdates", $updates.PackageFilename.count) } else { $global:chk.Add("SoftwareUpdates", 0) }
}

function Test-Temp {
    <#
        .Description
        Cleanup %WINDIR%\Temp if more than 100 Files are detected.
    #>

    if ((Get-ChildItem "$($env:windir)\Temp\*" -Recurse).Count -gt 100) {
        Remove-Item "$($env:windir)\Temp\*" -Force -Recurse -Exclude devcdrcore.log -ea SilentlyContinue
    }

    #if ($null -eq $global:chk) { $global:chk = @{ } }
    #if ($global:chk.ContainsKey("Temp")) { $global:chk.Remove("Temp") }
    #$global:chk.Add("Temp ", $true)
}

Function Test-Defender($Age = 7) {
    <#
        .Description
        Run Defender Quickscan if last scan is older than $Age days
    #>
    if ((Get-WmiObject -Namespace root\SecurityCenter2 -Query "SELECT * FROM AntiVirusProduct" -ea SilentlyContinue).displayName.count -eq 1) {
        $ScanAge = (Get-MpComputerStatus).QuickScanAge
        if ($ScanAge -ge $Age) { start-process "$($env:ProgramFiles)\Windows Defender\MpCmdRun.exe" -ArgumentList '-Scan -ScanType 1' }

        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("DefenderScanAge")) { $global:chk.Remove("DefenderScangAge") }
        $global:chk.Add("DefenderScanAge", $ScanAge)
    }
    else {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("DefenderScanAge")) { $global:chk.Remove("DefenderScanAge") }
        $global:chk.Add("DefenderScanAge", 999)
    }
}

Function Test-Bitlocker {
    <#
        .Description
        Check if BitLocker is enabled
    #>
    $bRes = "Off"
    try {
        if ((Get-BitLockerVolume C:).ProtectionStatus -eq "On") { $bRes = (Get-BitLockerVolume C:).EncryptionMethod.ToString() }
    }
    catch { }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("Bitlocker")) { $global:chk.Remove("Bitlocker") }
    $global:chk.Add("Bitlocker", $bRes)
}

Function Test-DiskSpace {
    <#
        .Description
        Check free Disk-Space
    #>

    #Get FreeSpace in %
    $c = get-psdrive C
    $free = [math]::Round((10 / (($c).Used + ($c).Free) * ($c).Free)) * 10

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("FreeSpace")) { $global:chk.Remove("FreeSpace") }
    $global:chk.Add("FreeSpace", $free)
}

Function Test-TPM {
    <#
        .Description
        Check TPM Status
    #>

    $res = "No"
    #Get FreeSpace in %
    $tpm = Get-Tpm -ea SilentlyContinue
    if ($tpm) {
        if ($tpm.TpmReady) { $res = "Ready" }
        if ($tpm.LockedOut) { $res = "LockedOut" }
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("TPM")) { $global:chk.Remove("TPM") }
    $global:chk.Add("TPM", $res)
}

Function Test-SecureBoot {
    <#
        .Description
        Check TPM Status
    #>

    $res = Confirm-SecureBootUEFI

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("SecureBoot")) { $global:chk.Remove("SecureBoot") }
    $global:chk.Add("SecureBoot", $res)
}

Function Test-Office {
    <#
        .Description
        Check Office Status
    #>

    $O365 = (Get-ItemProperty HKLM:SOFTWARE\Microsoft\Office\ClickToRun\Configuration -ea SilentlyContinue).VersionToReport

    if (-NOT $O365) {
        $O365 = (Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "Microsoft Office Professional Plus *" }).DisplayVersion | Select-Object -First 1
    }

    if (-NOT $O365) {
        $O365 = (Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "Microsoft Office Standard *" }).DisplayVersion | Select-Object -First 1
    }

    if (-NOT $O365) {
        $O365 = (Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "Microsoft Office Home *" }).DisplayVersion | Select-Object -First 1
    }

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("Office")) { $global:chk.Remove("Office") }
    $global:chk.Add("Office", $O365 )
}

Function Test-DefenderThreats {
    <#
        .Description
        Check Virus Threat Status
    #>

    if ((Get-WmiObject -Namespace root\SecurityCenter2 -Query "SELECT * FROM AntiVirusProduct" -ea SilentlyContinue).displayName.count -eq 1) {
        $Threats = Get-MpThreat -ea SilentlyContinue
        if ($Threats) {
            if ($null -eq $global:chk) { $global:chk = @{ } }
            if ($global:chk.ContainsKey("AVThreats")) { $global:chk.Remove("AVThreats") }
            if ($Threats.count) {
                $global:chk.Add("AVThreats", $Threats.count)
            }
            else {
                $global:chk.Add("AVThreats", 1) 
            }
        }
        else {
            if ($null -eq $global:chk) { $global:chk = @{ } }
            if ($global:chk.ContainsKey("AVThreats")) { $global:chk.Remove("AVThreats") }
            $global:chk.Add("AVThreats", 0)     
        }
    }
    else {
        $Threats = $null
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("AVThreats")) { $global:chk.Remove("AVThreats") }
        $global:chk.Add("AVThreats", -1) 
    }
}

Function Test-OSVersion {
    <#
        .Description
        Check OS Version
    #>

    $UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
    $Version = (Get-WMIObject win32_operatingsystem).Version
    $Caption = (Get-WMIObject win32_operatingsystem).caption

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("OSVersion")) { $global:chk.Remove("OSVersion") }
    $global:chk.Add("OSVersion", $Version + "." + $UBR )

    if ($null -eq $global:chk) { $global:chk = @{ } }
    if ($global:chk.ContainsKey("OS")) { $global:chk.Remove("OS") }
    $global:chk.Add("OS", $Caption )
}

Function Test-ASR {
    <#
        .Description
        Check Attack Surface Reduction
    #>

    $i = ((Get-MpPreference).AttackSurfaceReductionRules_Actions | Where-Object { $_ -eq 1 } ).count
    if ($i -gt 0) {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("ASR")) { $global:chk.Remove("ASR") }
        $global:chk.Add("ASR", $i )
    }
}

Function Test-Firewall {
    <#
        .Description
        Check Windows Firewall
    #>

    $i = ((Get-NetFirewallProfile).enabled | Where-Object { $_ -eq $true } ).count
    if ($i -gt 0) {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("FW")) { $global:chk.Remove("FW") }
        $global:chk.Add("FW", $i )
    }
}

Function Test-WU {
    <#
        .Description
        Check missing Windows Updates
    #>

    try {
        if (Get-InstalledModule -Name PSWindowsUpdate -MinimumVersion "2.2.0.2" -ea SilentlyContinue) { } else {
            set-executionpolicy bypass -Force
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted 
        }
        Install-Module PSWindowsUpdate -Force
        $upd = Get-WUList -MicrosoftUpdate

        if ($upd) {
            if ($null -eq $global:chk) { $global:chk = @{ } }
            if ($global:chk.ContainsKey("WU")) { $global:chk.Remove("WU") }
            $global:chk.Add("WU", $upd.count)
        }
        else {
            if ($null -eq $global:chk) { $global:chk = @{ } }
            if ($global:chk.ContainsKey("WU")) { $global:chk.Remove("WU") }
            $global:chk.Add("WU", 0) 
        }
        
    }
    catch {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("WU")) { $global:chk.Remove("WU") }
        $global:chk.Add("WU", -1) 
    }
}

Function Test-AppLocker {
    <#
        .Description
        Check if AppLocker is configured
    #>

    try {
        $AL = (Get-AppLockerPolicy -Effective).RuleCollections.count
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("AppLocker")) { $global:chk.Remove("AppLocker") }
        $global:chk.Add("AppLocker", $AL) 
    }
    catch {
        if ($null -eq $global:chk) { $global:chk = @{ } }
        if ($global:chk.ContainsKey("AppLocker")) { $global:chk.Remove("AppLocker") }
        $global:chk.Add("AppLocker", -1) 
    }
}

#region DevCDR

Function Get-DevcdrEP {
    <#
        .Description
        Get DeviceCommander Endpoint URL from NamedPipe
    #>
    try {
        $pipe = new-object System.IO.Pipes.NamedPipeClientStream '.', 'devcdrep', 'In'
        $pipe.Connect(5000)
        $sr = new-object System.IO.StreamReader $pipe
        while ($null -ne ($data = $sr.ReadLine())) { $sig = $data }
        $sr.Dispose()
        $pipe.Dispose()
        return $sig
    }
    catch { }

    return ""
}

Function Get-DevcdrSIG {
    <#
        .Description
        Get DeviceCommander Signature from NamedPipe
    #>
    try {
        $pipe = new-object System.IO.Pipes.NamedPipeClientStream '.', 'devcdrsig', 'In'
        $pipe.Connect(5000)
        $sr = new-object System.IO.StreamReader $pipe
        while ($null -ne ($data = $sr.ReadLine())) { $sig = $data }
        $sr.Dispose()
        $pipe.Dispose()
        return $sig
    }
    catch { }

    return ""
}

Function Get-DevcdrID {
    <#
        .Description
        Get DeviceCommander CustomerID from NamedPipe
    #>
    try {
        $pipe = new-object System.IO.Pipes.NamedPipeClientStream '.', 'devcdrid', 'In'
        $pipe.Connect(5000)
        $sr = new-object System.IO.StreamReader $pipe
        while ($null -ne ($data = $sr.ReadLine())) { $sig = $data }
        $sr.Dispose()
        $pipe.Dispose()
        return $sig
    }
    catch { }

    return ""
}
#endregion

#region Inventory
function GetHash([string]$txt) {
    return GetMD5($txt)
}

function GetMD5([string]$txt) {
    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.ASCIIEncoding
    return Base58(@(0xd5, 0x10) + $md5.ComputeHash($utf8.GetBytes($txt))) #To store hash in Multihash format, we add a 0xD5 to make it an MD5 and an 0x10 means 10Bytes length
}

function GetSHA2_256([string]$txt) {
    $sha = New-Object -TypeName System.Security.Cryptography.SHA256CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.ASCIIEncoding
    return Base58(@(0x12, 0x20) + $sha.ComputeHash($utf8.GetBytes($txt))) #To store hash in Multihash format, we add a 0x12 to make it an SHA256 and an 0x20 means 32Bytes length
}

function Base58([byte[]]$data) {
    $Digits = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    [bigint]$intData = 0
    for ($i = 0; $i -lt $data.Length; $i++) {
        $intData = ($intData * 256) + $data[$i]; 
    }
    [string]$result = "";
    while ($intData -gt 0) {
        $remainder = ($intData % 58);
        $intData /= 58;
        $result = $Digits[$remainder] + $result;
    }

    for ($i = 0; ($i -lt $data.Length) -and ($data[$i] -eq 0); $i++) {
        $result = '1' + $result;
    }

    return $result
}

function normalize([long]$number) {
    if ($number) {
        if ($number -gt 2000000000 ) { return ([math]::Truncate($number / 1000000000) * 1000000000) }
        if ($number -gt 100000000 ) { return ([math]::Truncate($number / 1000000) * 1000000) }
        if ($number -gt 1000000 ) { return ([math]::Truncate($number / 10000) * 10000) }
    }
    return $number
}

function GetInv {
    Param(
        [parameter(Mandatory = $true)]
        [String]
        $Name,
        [String]
        $Namespace,
        [parameter(Mandatory = $true)]
        [String]
        $WMIClass,
        [String[]]
        $Properties,
        [ref]
        $AppendObject,
        $AppendProperties
    )

    if ($Namespace) { } else { $Namespace = "root\cimv2" }
    $obj = Get-CimInstance -Namespace $Namespace -ClassName $WMIClass

    if ($null -eq $Properties) { $Properties = $obj.Properties.Name | Sort-Object }
    if ($null -eq $Namespace) { $Namespace = "root\cimv2" }

    $res = $obj | Select-Object $Properties -ea SilentlyContinue

    #WMI Results can be an array of objects
    if ($obj -is [array]) {
        $Properties | ForEach-Object { $prop = $_; $i = 0; $res | ForEach-Object {
                $val = $obj[$i].($prop.TrimStart('#@'));
                try {
                    if ($val.GetType() -eq [string]) {
                        $val = $val.Trim();
                        if (($val.Length -eq 25) -and ($val.IndexOf('.') -eq 14) -and ($val.IndexOf('+') -eq 21)) {
                            $OS = Get-WmiObject -class Win32_OperatingSystem
                            $val = $OS.ConvertToDateTime($val)
                        }
                    }
                }
                catch { }
                if ($val) {
                    $_ | Add-Member -MemberType NoteProperty -Name ($prop) -Value ($val) -Force;
                }
                else {
                    $_.PSObject.Properties.Remove($prop);
                }
                $i++
            }
        } 
    }
    else {
        $Properties | ForEach-Object { 
            $prop = $_;
            $val = $obj.($prop.TrimStart('#@'));
            try {
                if ($val.GetType() -eq [string]) {
                    $val = $val.Trim();
                    if (($val.Length -eq 25) -and ($val.IndexOf('.') -eq 14) -and ($val.IndexOf('+') -eq 21)) {
                        $OS = Get-WmiObject -class Win32_OperatingSystem
                        $val = $OS.ConvertToDateTime($val)
                    }
                }
            }
            catch { }
            if ($val) {
                $res | Add-Member -MemberType NoteProperty -Name ($prop) -Value ($val) -Force;
            }
            else {
                $res.PSObject.Properties.Remove($prop);
            }
        }
            
    }
        
    
    $res.psobject.TypeNames.Insert(0, $Name) 

    if ($null -ne $AppendProperties) {
        $AppendProperties.PSObject.Properties | ForEach-Object {
            if ($_.Value) {
                $res | Add-Member -MemberType NoteProperty -Name $_.Name -Value ($_.Value)
            }
        } 
    }

    if ($null -ne $AppendObject.Value) {
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name $Name -Value ($res)
        return $null
    }

    return $res
    
}

function GetMyID {
    $uuid = getinv -Name "Computer" -WMIClass "win32_ComputerSystemProduct" -Properties @("#UUID")
    $comp = getinv -Name "Computer" -WMIClass "win32_ComputerSystem" -Properties @("Domain", "#Name") -AppendProperties $uuid 
    return GetHash($comp | ConvertTo-Json -Compress)
}

function SetID {
    Param(
        [ref]
        $AppendObject )

    if ($null -ne $AppendObject.Value) {
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "#id" -Value (GetMyID) -ea SilentlyContinue
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "#UUID" -Value (getinv -Name "Computer" -WMIClass "win32_ComputerSystemProduct" -Properties @("#UUID"))."#UUID" -ea SilentlyContinue
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "#Name" -Value (getinv -Name "Computer" -WMIClass "win32_ComputerSystem" -Properties @("Name"))."Name" -ea SilentlyContinue
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "#SerialNumber" -Value (getinv -Name "Computer" -WMIClass "win32_SystemEnclosure" -Properties @("SerialNumber"))."SerialNumber" -ea SilentlyContinue
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "@MAC" -Value (Get-WmiObject -class "Win32_NetworkAdapterConfiguration" | Where-Object { ($_.IpEnabled -Match "True") }).MACAddress.Replace(':', '-')
		
        [xml]$a = Get-Content "$($env:ProgramFiles)\DevCDRAgentCore\DevCDRAgentCore.exe.config"
        $EP = ($a.configuration.applicationSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'Endpoint' }).value
        $customerId = ($a.configuration.applicationSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'CustomerID' }).value
        $devcdrgrp = ($a.configuration.applicationSettings."DevCDRAgent.Properties.Settings".setting | Where-Object { $_.name -eq 'Groups' }).value
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "DevCDREndpoint" -Value $EP
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "DevCDRGroups" -Value $devcdrgrp
        $AppendObject.Value | Add-Member -MemberType NoteProperty -Name "DevCDRCustomerID" -Value $customerId
        return $null
    }   
}
#endregion Inventory

# SIG # Begin signature block
# MIIOEgYJKoZIhvcNAQcCoIIOAzCCDf8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU4Tnd/07wj3odpK7Tu9Q4fw1e
# sZagggtIMIIFYDCCBEigAwIBAgIRANsn6eS1hYK93tsNS/iNfzcwDQYJKoZIhvcN
# AQELBQAwfTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3Rl
# cjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQx
# IzAhBgNVBAMTGkNPTU9ETyBSU0EgQ29kZSBTaWduaW5nIENBMB4XDTE4MDUyMjAw
# MDAwMFoXDTIxMDUyMTIzNTk1OVowgawxCzAJBgNVBAYTAkNIMQ0wCwYDVQQRDAQ4
# NDgzMQswCQYDVQQIDAJaSDESMBAGA1UEBwwJS29sbGJydW5uMRkwFwYDVQQJDBBI
# YWxkZW5zdHJhc3NlIDMxMQ0wCwYDVQQSDAQ4NDgzMRUwEwYDVQQKDAxSb2dlciBa
# YW5kZXIxFTATBgNVBAsMDFphbmRlciBUb29sczEVMBMGA1UEAwwMUm9nZXIgWmFu
# ZGVyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1ujnILmAULVtVv3b
# /CDpM6RCdLV9Zjg+CDJFWLBzzjwAcHueV0mv4YgF4WoOhuc3o7GcIvl3P1DqxW97
# ex8cCfFcqdObZszKpP9OyeU5ft4c/rmfPC6PD2sKEWIIvLHAw/RXFS4RFoHngyGo
# 4070NFEMfFdQOSvBwHodsa128FG8hThRn8lXlWJG3327o39kLfawFAaCtfqEBVDd
# k4lYLl2aRpvuobfEATZ016qAHhxkExtuI007gGH58aokxpX+QWJI6T/Bj5eBO4Lt
# IqS6JjJdkRZPNc4Pa98OA+91nxoY5uZdrCrKReDeZ8qNZcyobgqAaCLtBS2esDFN
# 8HMByQIDAQABo4IBqTCCAaUwHwYDVR0jBBgwFoAUKZFg/4pN+uv5pmq4z/nmS71J
# zhIwHQYDVR0OBBYEFE+rkhTxw3ewJzXsZWbrdnRwy7y0MA4GA1UdDwEB/wQEAwIH
# gDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGCWCGSAGG+EIB
# AQQEAwIEEDBGBgNVHSAEPzA9MDsGDCsGAQQBsjEBAgEDAjArMCkGCCsGAQUFBwIB
# Fh1odHRwczovL3NlY3VyZS5jb21vZG8ubmV0L0NQUzBDBgNVHR8EPDA6MDigNqA0
# hjJodHRwOi8vY3JsLmNvbW9kb2NhLmNvbS9DT01PRE9SU0FDb2RlU2lnbmluZ0NB
# LmNybDB0BggrBgEFBQcBAQRoMGYwPgYIKwYBBQUHMAKGMmh0dHA6Ly9jcnQuY29t
# b2RvY2EuY29tL0NPTU9ET1JTQUNvZGVTaWduaW5nQ0EuY3J0MCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wGgYDVR0RBBMwEYEPcm9nZXJAemFu
# ZGVyLmNoMA0GCSqGSIb3DQEBCwUAA4IBAQBHs/5P4BiQqAuF83Z4R0fFn7W4lvfE
# 6KJOKpXajK+Fok+I1bDl1pVC9JIqhdMt3tdOFwvSl0/qQ9Sp2cZnMovaxT8Bhc7s
# +PDbzRlklGGRlnVg6i7RHnJ90bRdxPTFUBbEMLy7UAjQ4iPPfRoxaR4rzF3BLaaz
# b7BoGc/oEPIMo/WmXWFngeHAVQ6gVlr2WXrKwHo8UlN0jmgzR7QrD3ZHbhR4yRNq
# M97TgVp8Fdw3o+PnwMRj4RIeFiIr9KGockQWqth+W9CDRlTgnxE8MhKl1PbUGUFM
# DcG3cV+dFTI8P2/sYD+aQHdBr0nDT2RWSgeEchQ1s/isFwOVBrYEqqf7MIIF4DCC
# A8igAwIBAgIQLnyHzA6TSlL+lP0ct800rzANBgkqhkiG9w0BAQwFADCBhTELMAkG
# A1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMH
# U2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxKzApBgNVBAMTIkNP
# TU9ETyBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTMwNTA5MDAwMDAw
# WhcNMjgwNTA4MjM1OTU5WjB9MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRl
# ciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRowGAYDVQQKExFDT01PRE8g
# Q0EgTGltaXRlZDEjMCEGA1UEAxMaQ09NT0RPIFJTQSBDb2RlIFNpZ25pbmcgQ0Ew
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCmmJBjd5E0f4rR3elnMRHr
# zB79MR2zuWJXP5O8W+OfHiQyESdrvFGRp8+eniWzX4GoGA8dHiAwDvthe4YJs+P9
# omidHCydv3Lj5HWg5TUjjsmK7hoMZMfYQqF7tVIDSzqwjiNLS2PgIpQ3e9V5kAoU
# GFEs5v7BEvAcP2FhCoyi3PbDMKrNKBh1SMF5WgjNu4xVjPfUdpA6M0ZQc5hc9IVK
# aw+A3V7Wvf2pL8Al9fl4141fEMJEVTyQPDFGy3CuB6kK46/BAW+QGiPiXzjbxghd
# R7ODQfAuADcUuRKqeZJSzYcPe9hiKaR+ML0btYxytEjy4+gh+V5MYnmLAgaff9UL
# AgMBAAGjggFRMIIBTTAfBgNVHSMEGDAWgBS7r34CPfqm8TyEjq3uOJjs2TIy1DAd
# BgNVHQ4EFgQUKZFg/4pN+uv5pmq4z/nmS71JzhIwDgYDVR0PAQH/BAQDAgGGMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwEQYDVR0gBAow
# CDAGBgRVHSAAMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmwuY29tb2RvY2Eu
# Y29tL0NPTU9ET1JTQUNlcnRpZmljYXRpb25BdXRob3JpdHkuY3JsMHEGCCsGAQUF
# BwEBBGUwYzA7BggrBgEFBQcwAoYvaHR0cDovL2NydC5jb21vZG9jYS5jb20vQ09N
# T0RPUlNBQWRkVHJ1c3RDQS5jcnQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmNv
# bW9kb2NhLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEAAj8COcPu+Mo7id4MbU2x8U6S
# T6/COCwEzMVjEasJY6+rotcCP8xvGcM91hoIlP8l2KmIpysQGuCbsQciGlEcOtTh
# 6Qm/5iR0rx57FjFuI+9UUS1SAuJ1CAVM8bdR4VEAxof2bO4QRHZXavHfWGshqknU
# fDdOvf+2dVRAGDZXZxHNTwLk/vPa/HUX2+y392UJI0kfQ1eD6n4gd2HITfK7ZU2o
# 94VFB696aSdlkClAi997OlE5jKgfcHmtbUIgos8MbAOMTM1zB5TnWo46BLqioXwf
# y2M6FafUFRunUkcyqfS/ZEfRqh9TTjIwc8Jvt3iCnVz/RrtrIh2IC/gbqjSm/Iz1
# 3X9ljIwxVzHQNuxHoc/Li6jvHBhYxQZ3ykubUa9MCEp6j+KjUuKOjswm5LLY5TjC
# qO3GgZw1a6lYYUoKl7RLQrZVnb6Z53BtWfhtKgx/GWBfDJqIbDCsUgmQFhv/K53b
# 0CDKieoofjKOGd97SDMe12X4rsn4gxSTdn1k0I7OvjV9/3IxTZ+evR5sL6iPDAZQ
# +4wns3bJ9ObXwzTijIchhmH+v1V04SF3AwpobLvkyanmz1kl63zsRQ55ZmjoIs24
# 75iFTZYRPAmK0H+8KCgT+2rKVI2SXM3CZZgGns5IW9S1N5NGQXwH3c/6Q++6Z2H/
# fUnguzB9XIDj5hY5S6cxggI0MIICMAIBATCBkjB9MQswCQYDVQQGEwJHQjEbMBkG
# A1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRowGAYD
# VQQKExFDT01PRE8gQ0EgTGltaXRlZDEjMCEGA1UEAxMaQ09NT0RPIFJTQSBDb2Rl
# IFNpZ25pbmcgQ0ECEQDbJ+nktYWCvd7bDUv4jX83MAkGBSsOAwIaBQCgeDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQ9
# IuEEsChF6vfhOujSJHJsV/yimzANBgkqhkiG9w0BAQEFAASCAQAEnSK1XlhNrNIf
# PcOQxDQXLJVYp3/1Ydsc27QR3JFOAMhpWdZjp0xqAyhcw91h/UxRSDEGeBY87CO0
# YJSQNuIdR3Pa/p63VpgrWzH5SZxEhHEE2DcO/tT7WjHhWdhwmVHwmmAIrQDonNb5
# VqCTKcIPDYkwpJDltEHXFSQIQH+HeBwtiwsTNoxIMFPMnOrOz8knJEq1EqeJbElH
# nkwcABi7c22/bWY+MWwQv5ne3u1grTjVEqMBMDrpjIIS3rPRIlffQOZpiZD1HRCQ
# ZXwbWBdLEDyGn0koe3ev9iEVwpA82Ap1JEjr8O8huexSkQkUSEdQFlJcxyw30Ni5
# Owzb2p7r
# SIG # End signature block
