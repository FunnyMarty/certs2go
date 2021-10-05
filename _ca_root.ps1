param ( # TODO: Set certificates' expiry date in parameters
    [Parameter(Mandatory = $true, HelpMessage = 'Default HEX serial number of future certificates')]
    [String] [ValidatePattern('[0-9a-fA-F]+')] $HexDefaultSerial,
    [Parameter(HelpMessage = 'Path to ca.conf')]
    [String] [ValidateNotNullOrEmpty()] $CertificateAuthorityConfPath = "./ca.conf"
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

try {
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityConfPath = (Resolve-Path -Path "$CertificateAuthorityConfPath").Path
    [String] $NewCertificateAuthorityPath = (Get-Location).Path -replace '\\', '/'

    Read-Host -Prompt "`n>>> Confirm a working directory - '$NewCertificateAuthorityPath' [Enter]"
    New-Item -ItemType Directory -Path "$NewCertificateAuthorityPath/_backup"

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

    if (!(Test-Path "$ResolvedCertificateAuthorityConfPath" -PathType Leaf)) {
        throw '>>> CA configuration file is missing!'
    }
    elseif (Test-Path 'ca.*' -PathType Leaf -Exclude "$(Split-Path -Path $ResolvedCertificateAuthorityConfPath -Leaf)") {
        throw '>>> Some files of the old CA still exists!'
    }

    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', "`$1$NewCertificateAuthorityPath" `
        -replace '^(\[ v3_server_alt_names \]\nDNS\.1\s+=\s)([^#\n]*)(?=\s?)', '$1COMMON_NAME' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Root CA directory was set to '$NewCertificateAuthorityPath'`n    - Subject alternative name has been reset to a default value"

    Write-Information ">>> Creating a new root CA (enter its pass phrase below)..."
    openssl genrsa -aes256 -out ca.key 4096
    Write-Information ">>> Enter password for the new root CA:"
    openssl req -new -x509 -sha512 -days 3650 -config "$ResolvedCertificateAuthorityConfPath" -key ca.key -out ca.crt

    New-Item -ItemType File index.txt
    Write-Output '1000' > crlnumber
    Write-Output $HexDefaultSerial.ToUpper() > serial
}
finally {
    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', '$1CERT_DIR_PATH' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Root CA directory has been reset to a default value"
}
