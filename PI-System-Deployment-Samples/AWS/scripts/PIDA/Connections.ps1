# ***********************************************************************
# * DISCLAIMER:
# * All sample code is provided by OSIsoft for illustrative purposes only.
# * These examples have not been thoroughly tested under all conditions.
# * OSIsoft provides no guarantee nor implies any reliability, 
# * serviceability, or function of these programs.
# * ALL PROGRAMS CONTAINED HEREIN ARE PROVIDED TO YOU "AS IS" 
# * WITHOUT ANY WARRANTIES OF ANY KIND. ALL WARRANTIES INCLUDING 
# * THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY
# * AND FITNESS FOR A PARTICULAR PURPOSE ARE EXPRESSLY DISCLAIMED.
# ************************************************************************

param(
	[Parameter(Position=0, Mandatory=$true)]
	[string] $PIServerName,
	
	[Parameter(Position=1, Mandatory=$false)]
	[DateTime] $StartTime,
	
	[Parameter(Position=2, Mandatory=$false)]
	[DateTime] $EndTime)

$srv = Get-PIDataArchiveConnectionConfiguration -Name $PIServerName -ErrorAction Stop
$connection = Connect-PIDataArchive -PIDataArchiveConnectionConfiguration $srv -ErrorAction Stop

[Version] $v390 = "3.4.390"
[Version] $v385 = "3.4.385"

[bool] $is390 = $false
[bool] $is385 = $false

if ($connection.ServerVersion -gt $v390)
{
	$is390 = $true
}
elseif ($connection.ServerVersion -gt $v385)
{
	$is385 = $true
}
else
{
	"Unsupported PI server version found."
	exit
}

# If StartTime is not passed in, get the startup time of pinetmgr and use that as the StartTime
if ($StartTime -eq $null)
{
	$service = Get-WmiObject win32_service -filter "name = 'pinetmgr'" -ComputerName $connection.Address.Host
	$serverStartup = ((Get-Date) - ([wmi]'').ConvertToDateTime((Get-WmiObject Win32_Process -ComputerName $connection.Address.Host -filter "ProcessID = '$($service.ProcessId)'").CreationDate))
	
	$StartTime = (Get-Date) - $serverStartup
}

# If EndTime is not passed in, use current time as end time
if ($EndTime -eq $null)
{
	$EndTime = Get-Date
}

# Get all the connections since StartTime
# Message ID's are the following:
# 7039 - Begin connection
# 7080 - Connection information
# 7096 - End connection
# 7121 - End connection
# 7133 - Connection Statistics
$messages = Get-PIMessage -Connection $connection -StartTime $StartTime -EndTime $EndTime -ID 7039,7080,7096,7121,7133

# Store all the active connection information in a hashtable of obects.
# The hashtable is indexed by Connection ID
# When a connection is completed, move the entry from the Hashtable into an array
# This is to handle reused Connection IDs
[Hashtable] $activeConnections = @{}
[Array] $closedConnections = @()

foreach($item in $messages)
{
	if ($item.ID -eq 7039)
	{
		# begin connection message
		if ($item.Message -match "Process name:\s*(.*) ID: (.*)" -eq $true)
		{
			# $Matches[1] Process Name
			# $Matches[2] Connection ID
			
			$id = $Matches[2].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $false)
			{
				#Parse out connection information
				$appInfo = $Matches[1]
				if ($appInfo -match "(.*)\((.*)\):(.*)\((.*)\)" -eq $true)
				{
					$isRemote = $true
					$appName = $Matches[1]
					$appPID = $Matches[2]
				}
				elseif ($appInfo -match "(.*)\((.*)\)" -eq $true)
				{
					$isRemote = $false
					$appName = $Matches[1]
					$appPID = $Matches[2]
				}
				else
				{
					$isRemote = $null
					$appName = $appInfo
					$appPID = $null
				}
				
				$temp = New-Object PSCustomObject
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ID" -Value $id
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ApplicationName" -Value $appName
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ApplicationPID" -Value $appPID
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "IsRemote" -Value $isRemote
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "PIUser" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "OSUser" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "IPAddress" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "Duration" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "StartTime" -Value $item.LogTime
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "EndTime" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "KBSent" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "KBReceived" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "DisconnectReason" -Value $null
				$activeConnections.Add($id, $temp)
			}
		}
	}
	elseif ($item.ID -eq 7080)
	{
		# connection information message 3.4.390
		if ($is390 -eq $true)
		{
			if ($item.Message -match "Connection ID: (.*) ; Process name: (.*) ; User: (.*) ; OS User: (.*) ; Hostname: (.*) IP: (.*) ; AppID: (.*) ; AppName: (.*)" -eq $true)
			{
				# $Matches[1] Connection ID
				# $Matches[3] PIUser
				# $Matches[4] OSUser
				# $Matches[6] IP address
				
				$id = $Matches[1].Trim() -as [Int32]
				if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
				{
					$activeConnections[$id].PIUser = $Matches[3].Trim()
					$activeConnections[$id].OSUser = $Matches[4].Trim()
					$activeConnections[$id].IPAddress = $Matches[6].Trim()
				}
			}
		}
		# connection information message 3.4.385
		elseif ($is385 -eq $true)
		{
			if ($item.Message -match "Connection ID: (.*) ; Process name: (.*) ; User: (.*) ; OS User: (.*) ; IP: (.*) ; AppID: (.*) ; AppName: (.*)" -eq $true)
			{
				# $Matches[1] Connection ID
				# $Matches[3] PIUser
				# $Matches[4] OSUser
				# $Matches[5] IP address
				
				$id = $Matches[1].Trim() -as [Int32]
				if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
				{
					$activeConnections[$id].PIUser = $Matches[3].Trim()
					$activeConnections[$id].OSUser = $Matches[4].Trim()
					$activeConnections[$id].IPAddress = $Matches[5].Trim()
				}
			}
		}
	}
	elseif ($item.ID -eq 7096 -or $item.ID -eq 7121)
	{
		#end connection message
		if ($item.Message -match "Deleting connection: (.*), (.*), ID: (.*) (.*)" -eq $true)
		{
			# $Matches[1] Application name
			# $Matches[2] Disconnect reason
			# $Matches[3] Connection ID
			# $Matches[4] Connection address
			
			$id = $Matches[3].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
			{
				$activeConnections[$id].DisconnectReason = $Matches[2].Trim()
				$activeConnections[$id].EndTime = $item.LogTime
				if ($activeConnections[$id].StartTime -ne $null)
				{
					$activeConnections[$id].Duration = $activeConnections[$id].EndTime - $activeConnections[$id].StartTime
				}
			}
		}
	}
	elseif ($item.ID -eq 7133)
	{
		#Connection Statistics message
		if ($item.Message -match "ID: (.*); Duration: (.*); kbytes sent: (.*); kbytes recv: (.*); app: (.*); user: (.*); osuser: (.*); trust: (.*); ip address: (.*); ip host: (.*)" -eq $true)
		{
			# $Matches[1] Connection ID
			# $Matches[3] KBSent
			# $Matches[4] KBReceived
			
			$id = $Matches[1].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
			{
				$activeConnections[$id].KBSent = $Matches[3] -as [Float]
				$activeConnections[$id].KBReceived = $Matches[4] -as [Float]
				
				# Copy connection information into closed connections array
				$closedConnections += $activeConnections[$id]
				# Remove active connection
				$activeConnections.Remove($id)
			}
		}
	}
}

# Write all connections to output pipeline
$activeConnections.Values
$closedConnections
# SIG # Begin signature block
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDDSw9jIFs6Q6pH
# OHtXIOW+GLkJZEoBEca/dC3HmjzuC6CCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVWMIIEPqADAgECAhAFTTVZN0yftPMcszD508Q/MA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTkwNjE3MDAwMDAw
# WhcNMjAwNzAxMTIwMDAwWjCBkjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEkMCIGCSqGSIb3DQEJARYV
# c21hbmFnZXJzQG9zaXNvZnQuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAqbP+VTz8qtsq4SWhF7LsXqeDGyUwtDpf0vlSg+aQh2fOqJhW2uiPa1GO
# M5+xbr+RhTTWzJX2vEwqSIzN43ktTdgcVT9Bf5W2md+RCYE1D17jGlj5sCFTS4eX
# Htm+lFoQF0donavbA+7+ggd577FdgOnjuYxEpZe2lbUyWcKOHrLQr6Mk/bKjcYSY
# B/ipNK4hvXKTLEsN7k5kyzRkq77PaqbVAQRgnQiv/Lav5xWXuOn7M94TNX4+1Mk8
# 74nuny62KLcMRtjPCc2aWBpHmhD3wPcUVvTW+lGwEaT0DrCwcZDuG/Igkhqj/8Rf
# HYfnZQtWMnBFAHcuA4jJgmZ7xYMPoQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFNcTKM3o/Fjj9J3iOakcmKx6
# CPetMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAigLIcsGUWzXlZuVQY8s1UOxYgch5qO1Y
# YEDFF8abzJQ4RiB8rcdoRWjsfpWxtGOS0wkA2CfyuWhjO/XqgmYJ8AUHIKKCy6QE
# 31/I6izI6iDCg8X5lSR6nKsB2BCZCOnGJOEi3r+WDS18PMuW24kaBo1ezx6KQOx4
# N0qSrMJqJRXfPHpl3WpcLs3VA1Gew9ATOQ9IXbt8QCvyMICRJxq4heHXPLE3EpK8
# 2wlBKwX3P4phapmEUOWxB45QOcRJqgahe9qIALbLS+i5lxV+eX/87YuEiyDtGfH+
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEJQwghCQ
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggZ4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIEt4ctjyA0Rd
# +ZMo8aj9AWqftBoMLu7GgkDq1h7wLxTdMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBM
# nqU5GRs+gS+Pu4xpx5rOzSBn7INgLY74B5KWjmoAn98WCSSy//d2nglkqYf4jNKi
# roHsyvwUp+VX55UYf3CV1qoNtkPZ1CPSwgaq4faRyClq6p8LsA1zhfTOWlKmdpxv
# aNgCz9o07RO1BJpaOZR8NXO5AP1wlyhimvkqsC3Y7S0ZJ7zBt/wnIjREtopw3nug
# /iZwltb4zqaiU5Ungz+DaUA6Sn4wpBjy+j7IfW6ooiRpjTZjMXCRWP7B1RgH85j8
# AT7uwE7/Fkfh8QYX/5J9MshO3g5/gifJ26tEols80nhgm2IgHA3HcaN/6VfM+Oq9
# vzq5DZYvDcjtQ5IFTP+poYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgdZHM
# bcmOF62ew/knTW8WgkeTQrhL8/l7v0nFlnNUopMCFQCuCTxWF+0lEC7dLylhPR/u
# WvmmkhgPMjAyMDAxMjMyMDIwMzNaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
# MR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50
# ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UEAxMoU3ltYW50ZWMgU0hBMjU2IFRpbWVT
# dGFtcGluZyBTaWduZXIgLSBHM6CCCoswggU4MIIEIKADAgECAhB7BbHUSWhRRPfJ
# idKcGZ0SMA0GCSqGSIb3DQEBCwUAMIG9MQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# VmVyaVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsx
# OjA4BgNVBAsTMShjKSAyMDA4IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1dGhvcml6
# ZWQgdXNlIG9ubHkxODA2BgNVBAMTL1ZlcmlTaWduIFVuaXZlcnNhbCBSb290IENl
# cnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTE2MDExMjAwMDAwMFoXDTMxMDExMTIz
# NTk1OVowdzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0
# aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9T
# eW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5nIENBMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAu1mdWVVPnYxyXRqBoutV87ABrTxxrDKPBWuGmicAMpdq
# TclkFEspu8LZKbku7GOz4c8/C1aQ+GIbfuumB+Lef15tQDjUkQbnQXx5HMvLrRu/
# 2JWR8/DubPitljkuf8EnuHg5xYSl7e2vh47Ojcdt6tKYtTofHjmdw/SaqPSE4cTR
# fHHGBim0P+SDDSbDewg+TfkKtzNJ/8o71PWym0vhiJka9cDpMxTW38eA25Hu/ryS
# V3J39M2ozP4J9ZM3vpWIasXc9LFL1M7oCZFftYR5NYp4rBkyjyPBMkEbWQ6pPrHM
# +dYr77fY5NUdbRE6kvaTyZzjSO67Uw7UNpeGeMWhNwIDAQABo4IBdzCCAXMwDgYD
# VR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwZgYDVR0gBF8wXTBbBgtg
# hkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRwczovL2Quc3ltY2IuY29tL2Nw
# czAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3ltY2IuY29tL3JwYTAuBggrBgEF
# BQcBAQQiMCAwHgYIKwYBBQUHMAGGEmh0dHA6Ly9zLnN5bWNkLmNvbTA2BgNVHR8E
# LzAtMCugKaAnhiVodHRwOi8vcy5zeW1jYi5jb20vdW5pdmVyc2FsLXJvb3QuY3Js
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQDExBU
# aW1lU3RhbXAtMjA0OC0zMB0GA1UdDgQWBBSvY9bKo06FcuCnvEHzKaI4f4B1YjAf
# BgNVHSMEGDAWgBS2d/ppSEefUxLVwuoHMnYH0ZcHGTANBgkqhkiG9w0BAQsFAAOC
# AQEAdeqwLdU0GVwyRf4O4dRPpnjBb9fq3dxP86HIgYj3p48V5kApreZd9KLZVmSE
# cTAq3R5hF2YgVgaYGY1dcfL4l7wJ/RyRR8ni6I0D+8yQL9YKbE4z7Na0k8hMkGNI
# OUAhxN3WbomYPLWYl+ipBrcJyY9TV0GQL+EeTU7cyhB4bEJu8LbF+GFcUvVO9muN
# 90p6vvPN/QPX2fYDqA/jU/cKdezGdS6qZoUEmbf4Blfhxg726K/a7JsYH6q54zoA
# v86KlMsB257HOLsPUqvR45QDYApNoP4nbRQy/D+XQOG/mYnb5DkUvdrk08PqK1qz
# lVhVBH3HmuwjA42FKtL/rqlhgTCCBUswggQzoAMCAQICEHvU5a+6zAc/oQEjBCJB
# TRIwDQYJKoZIhvcNAQELBQAwdzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFu
# dGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3Jr
# MSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTE3
# MTIyMzAwMDAwMFoXDTI5MDMyMjIzNTk1OVowgYAxCzAJBgNVBAYTAlVTMR0wGwYD
# VQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1
# c3QgTmV0d29yazExMC8GA1UEAxMoU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGlu
# ZyBTaWduZXIgLSBHMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK8O
# iqr43L9pe1QXcUcJvY08gfh0FXdnkJz93k4Cnkt29uU2PmXVJCBtMPndHYPpPydK
# M05tForkjUCNIqq+pwsb0ge2PLUaJCj4G3JRPcgJiCYIOvn6QyN1R3AMs19bjwgd
# ckhXZU2vAjxA9/TdMjiTP+UspvNZI8uA3hNN+RDJqgoYbFVhV9HxAizEtavybCPS
# nw0PGWythWJp/U6FwYpSMatb2Ml0UuNXbCK/VX9vygarP0q3InZl7Ow28paVgSYs
# /buYqgE4068lQJsJU/ApV4VYXuqFSEEhh+XetNMmsntAU1h5jlIxBk2UA0XEzjwD
# 7LcA8joixbRv5e+wipsCAwEAAaOCAccwggHDMAwGA1UdEwEB/wQCMAAwZgYDVR0g
# BF8wXTBbBgtghkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRwczovL2Quc3lt
# Y2IuY29tL2NwczAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3ltY2IuY29tL3Jw
# YTBABgNVHR8EOTA3MDWgM6Axhi9odHRwOi8vdHMtY3JsLndzLnN5bWFudGVjLmNv
# bS9zaGEyNTYtdHNzLWNhLmNybDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCB4AwdwYIKwYBBQUHAQEEazBpMCoGCCsGAQUFBzABhh5odHRwOi8v
# dHMtb2NzcC53cy5zeW1hbnRlYy5jb20wOwYIKwYBBQUHMAKGL2h0dHA6Ly90cy1h
# aWEud3Muc3ltYW50ZWMuY29tL3NoYTI1Ni10c3MtY2EuY2VyMCgGA1UdEQQhMB+k
# HTAbMRkwFwYDVQQDExBUaW1lU3RhbXAtMjA0OC02MB0GA1UdDgQWBBSlEwGpn4XM
# G24WHl87Map5NgB7HTAfBgNVHSMEGDAWgBSvY9bKo06FcuCnvEHzKaI4f4B1YjAN
# BgkqhkiG9w0BAQsFAAOCAQEARp6v8LiiX6KZSM+oJ0shzbK5pnJwYy/jVSl7OUZO
# 535lBliLvFeKkg0I2BC6NiT6Cnv7O9Niv0qUFeaC24pUbf8o/mfPcT/mMwnZolkQ
# 9B5K/mXM3tRr41IpdQBKK6XMy5voqU33tBdZkkHDtz+G5vbAf0Q8RlwXWuOkO9Vp
# JtUhfeGAZ35irLdOLhWa5Zwjr1sR6nGpQfkNeTipoQ3PtLHaPpp6xyLFdM3fRwmG
# xPyRJbIblumFCOjd6nRgbmClVnoNyERY3Ob5SBSe5b/eAL13sZgUchQk38cRLB8A
# P8NLFMZnHMweBqOQX1xUiz7jM1uCD8W3hgJOcZ/pZkU/djGCAlowggJWAgEBMIGL
# MHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEf
# MB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEoMCYGA1UEAxMfU3ltYW50
# ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQe9Tlr7rMBz+hASMEIkFNEjALBglg
# hkgBZQMEAgGggaQwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3
# DQEJBTEPFw0yMDAxMjMyMDIwMzNaMC8GCSqGSIb3DQEJBDEiBCCM7STna5Uzij0V
# NpkKy5C/o7X9yYI/97SjDSVCwXvnjTA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# af+sMahR5W+WFeIoV9Kfdg83YSshMRdEZ4QugbSrsogdClXGM9JrVXmeo/nmkpqg
# NM6GTBtZCmjfqJVDW/fJuu1SNNd8shXVmGiWdLMfw2Td6rfanAEDOU2M6BEI4UoF
# b3oH3TnAy9LU3Uj9ggqxt0kEXMmNr06G1Y6AitgzmJHm0d+X3QpImSNmtuA8eLGN
# MFmsR6Oq+xTSEN7/o5frB0XdT5Fclue1wDW05yZqOw9mimN/LHGSm64UngfZBafi
# fZS5tOefq3YPWL5GoFIU4bqj9Xt1IBLkZXHQFCup/bBdeC8WjftJXJ6fTNTd+nH4
# B5XknpLRtjiazZob7HfpXA==
# SIG # End signature block
