param (
    [Parameter(Mandatory = $true, HelpMessage = 'A name of a new certificate')]
    [String] [ValidatePattern('^[0-9a-zA-Z-]{4,32}$')] $NewCertificateName,
    [Parameter(Mandatory = $true, HelpMessage = 'Valid values are client / server')]
    [String] [ValidateSet('client', 'server')] $NewCertificateType,
    [Parameter(Mandatory = $true, HelpMessage = 'Certificate''s subject alternative name (affects a server certificate)')] # TODO: Disable for client certificates
    [String] [ValidatePattern('^[0-9a-z.-]*$')] [AllowEmptyString()] $NewCertificateSubAltName,
    [Parameter(Mandatory = $true, HelpMessage = 'A directory containing CA certificate pair for a new certificate')]
    [String] [ValidateNotNullOrEmpty()] $CertificateAuthorityPath,
    [Parameter(HelpMessage = 'Path to ca.conf')]
    [String] [ValidateNotNullOrEmpty()] $CertificateAuthorityConfPath = "./ca.conf"
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

try {
    [String] [ValidateNotNullOrEmpty()] $CurrentDate = $(Get-Date -Format 'yyMMdd-HHmmss')
    [String] [ValidateNotNullOrEmpty()] $StartingDir = (Get-Location).Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityConfPath = (Resolve-Path -Path "$CertificateAuthorityConfPath").Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityPath = (Resolve-Path -Path "$CertificateAuthorityPath").Path -replace '\\', '/' # A directory, that contains CA's certificate pair and other mandatory files, where a new server/client certificate is going to be generated

    Read-Host -Prompt "`n>>> Confirm a working directory - '$ResolvedCertificateAuthorityPath' [Enter]"
    Set-Location -Path "$ResolvedCertificateAuthorityPath"

    [String] $NewCertificatesSerial = $(Get-Content -Path serial -Encoding UTF8 -First 1 -ErrorAction Ignore)

    while ($NewCertificatesSerial -notmatch '^[0-9a-fA-F]+$') {
        try {
            [ValidatePattern('^[0-9a-fA-F]+$')] $NewCertificatesSerial = Read-Host -Prompt '>>> Enter certificate''s HEX serial number'
        }
        catch {
            Write-Information '>>> Invalid value! Enter HEX serial and try again'
        }
    }

    # Convert the serial to a valid hexadecimal number
    :ConvertToHexLoop do {
        [Bool] $SerialIsOdd = $NewCertificatesSerial.Length % 2
        if ($SerialIsOdd -and $NewCertificatesSerial -match '^0') {
            $NewCertificatesSerial = $NewCertificatesSerial -replace '^0', ''
        }
        elseif ($SerialIsOdd -and $NewCertificatesSerial -notmatch '^0') {
            $NewCertificatesSerial = "0$NewCertificatesSerial"
            break ConvertToHexLoop
        }
        elseif ($NewCertificatesSerial -match '^00') {
            $NewCertificatesSerial = $NewCertificatesSerial -replace '^00', ''
        }
        else {
            break ConvertToHexLoop
        }
        
        [Int] $Cycles += 1
        if ($Cycles -ge 100) {
            throw '>>> Loop of the cycle detected!'
        } 
    } while ($true)
    $NewCertificatesSerial.ToUpper() > serial

    if (!(Test-Path "$ResolvedCertificateAuthorityConfPath" -PathType Leaf)) { throw '>>> CA configuration file is missing!' }

    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DNS\.1\s+=\s)([^#\n]*)(?=\s?)', "`$1$NewCertificateSubAltName" -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', "`$1$ResolvedCertificateAuthorityPath" | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Intermediate CA directory was set to '$ResolvedCertificateAuthorityPath'`n    - Subject alternative name was set to '$NewCertificateSubAltName'"

    if (!(Test-Path -Path index.txt)) { New-Item -ItemType File index.txt }
    New-Item -ItemType Directory "$NewCertificateName`_$NewCertificateType`-crt_$CurrentDate" && Set-Location "$NewCertificateName`_$NewCertificateType`-crt_$CurrentDate"

    Write-Information ">>> Creating $NewCertificateType certificate '$NewCertificateName' in folder '$((Get-Location).Path)'..."
    openssl genrsa -out "$NewCertificateName.key" 4096
    openssl req -new -config $ResolvedCertificateAuthorityConfPath -key "$NewCertificateName.key" -out "$NewCertificateName.csr" -extensions "v3_$NewCertificateType`_crt"
    Write-Information ">>> Enter password for an existing parent CA:"
    openssl ca -batch -config $ResolvedCertificateAuthorityConfPath -notext -in "$NewCertificateName.csr" -out "$NewCertificateName.crt" -extensions "v3_$NewCertificateType`_crt" -policy policy_loose

    Set-Location ..
    openssl ca -config $ResolvedCertificateAuthorityConfPath -gencrl -keyfile ca.key -cert ca.crt -out ca.crl # Update of a CRL file
}
finally {
    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DNS\.1\s+=\s)([^#\n]*)(?=\s?)', '$1COMMON_NAME' -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', '$1CERT_DIR_PATH' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Intermediate CA directory has been reset to a default value`n    - Subject alternative name has been reset to a default value"

    Set-Location -Path $StartingDir
}
