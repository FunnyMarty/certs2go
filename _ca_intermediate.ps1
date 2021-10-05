param (
    [Parameter(Mandatory = $true, HelpMessage = 'A name of a new intermediate CA')]
    [String] [ValidatePattern('^[0-9a-zA-Z-]{4,32}$')] $NewCertificateAuthorityName,
    [Parameter(Mandatory = $true, HelpMessage = 'Default HEX serial number of future certificates')]
    [String] [ValidatePattern('^[0-9a-fA-F]+$')] $HexDefaultSerial,
    [Parameter(HelpMessage = 'Path to ca.conf')]
    [String] [ValidateNotNullOrEmpty()] $CertificateAuthorityConfPath = "./ca.conf",
    [Parameter(HelpMessage = 'A directory containing a root CA certificate pair')]
    [String] [ValidateNotNullOrEmpty()] $ExistingRootCertificateAuthorityPath = "."
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

try {
    [String] [ValidateNotNullOrEmpty()] $StartingDir = (Get-Location).Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityConfPath = (Resolve-Path -Path "$CertificateAuthorityConfPath").Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedRootCertificateAuthorityPath = (Resolve-Path -Path "$ExistingRootCertificateAuthorityPath").Path -replace '\\', '/'
    [String] $NewCertificateAuthorityPath = "$ResolvedRootCertificateAuthorityPath/ca_$NewCertificateAuthorityName"

    if (Test-Path "$NewCertificateAuthorityPath") {
        throw ">>> Intermediate CA '$NewCertificateAuthorityName' already exists! (Path: '$NewCertificateAuthorityPath')"
    }

    Read-Host -Prompt "`n>>> Confirm a working directory - '$NewCertificateAuthorityPath' [Enter]"
    New-Item -ItemType Directory -Path "$NewCertificateAuthorityPath/_backup"
    Set-Location -Path "$NewCertificateAuthorityPath"

    # Convert the serial to a valid hexadecimal number
    :ConvertToHexLoop do {
        [Bool] $SerialIsOdd = $HexDefaultSerial.Length % 2
        if ($SerialIsOdd -and $HexDefaultSerial -match '^0') {
            $HexDefaultSerial = $HexDefaultSerial -replace '^0', ''
        }
        elseif ($SerialIsOdd -and $HexDefaultSerial -notmatch '^0') {
            $HexDefaultSerial = "0$HexDefaultSerial"
            break ConvertToHexLoop
        }
        elseif ($HexDefaultSerial -match '^00') {
            $HexDefaultSerial = $HexDefaultSerial -replace '^00', ''
        }
        else {
            break ConvertToHexLoop
        }
    
        [Int] $Cycles += 1
        if ($Cycles -ge 100) {
            throw '>>> Loop of the cycle detected!'
        } 
    } while ($true)

    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', "`$1$ResolvedRootCertificateAuthorityPath" `
        -replace '^(\[ v3_server_alt_names \]\nDNS\.1\s+=\s)([^#\n]*)(?=\s?)', '$1COMMON_NAME' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Root CA directory was set to '$ResolvedRootCertificateAuthorityPath'`n    - Subject alternative name has been reset to a default value"

    Write-Information ">>> Creating a new intermediate CA (enter its pass phrase below)..."
    openssl genrsa -aes256 -out ca.key 4096
    Write-Information ">>> Enter password for the new intermediate CA:"
    openssl req -new -sha512 -config "$ResolvedCertificateAuthorityConfPath" -key ca.key -out ca.csr
    Write-Information ">>> Enter password for an existing root CA:"
    openssl ca -batch -md sha512 -days 3650 -notext -config $ResolvedCertificateAuthorityConfPath -in ca.csr -out ca.crt -extensions v3_intermediate_ca

    New-Item -ItemType File index.txt
    Write-Output '1000' > crlnumber
    Write-Output $HexDefaultSerial.ToUpper() > serial

    Set-Location ..
    Write-Information ">>> Enter password for the existing root CA:"
    openssl ca -config $ResolvedCertificateAuthorityConfPath -gencrl -keyfile ca.key -cert ca.crt -out ca.crl # Update of a CRL file
}
finally {
    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', '$1CERT_DIR_PATH' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Root CA directory has been reset to a default value"

    Set-Location -Path $StartingDir
}
