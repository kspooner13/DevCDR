﻿$cert = Get-ChildItem cert:\CurrentUser\My -CodeSigningCert | ? { $_.Thumbprint -eq 'FDECFF173C9ECE56047F277E9E5A2D779BF809AC' }
cd $psscriptroot

Set-AuthenticodeSignature wwwroot\jaindb\compliance.psm1 $cert[0]
Set-AuthenticodeSignature wwwroot\jaindb\Compliance_Default.ps1 $cert[0]
Set-AuthenticodeSignature wwwroot\jaindb\inventory.ps1 $cert[0]
Set-AuthenticodeSignature wwwroot\jaindb\inventory2.ps1 $cert[0]
Set-AuthenticodeSignature wwwroot\PSScripts\UpdateWindows.ps1 $cert[0]
Set-AuthenticodeSignature wwwroot\PSScripts\GetMissingOSUpdates.ps1 $cert[0]
