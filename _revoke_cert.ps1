param (
    [Parameter(Mandatory = $true, HelpMessage = 'A directory containing parent CA certificate pair of a certificate for revocation')]
    [String] [ValidateNotNullOrEmpty()] $ParentCertificateAuthorityPath,
    [Parameter(Mandatory = $true, HelpMessage = 'A name of a folder containing certificate for revocation')]
    [String] [ValidatePattern('^[0-9a-zA-Z._-]+$')] $CertificateFolderName,
    [Parameter(HelpMessage = 'A name of a certificate for revocation')]
    [String] [ValidatePattern('^[0-9a-zA-Z_-]+$')] $CertificateName = "$(($CertificateFolderName).Substring(0,$CertificateFolderName.LastIndexOf("_")))",
    [Parameter(HelpMessage = 'Path to ca.conf')]
    [String] [ValidateNotNullOrEmpty()] $CertificateAuthorityConfPath = "./ca.conf"
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

try {
    [String] [ValidateNotNullOrEmpty()] $StartingDir = (Get-Location).Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityConfPath = (Resolve-Path -Path "$CertificateAuthorityConfPath").Path
    [String] [ValidateNotNullOrEmpty()] $ResolvedCertificateAuthorityPath = (Resolve-Path -Path "$ParentCertificateAuthorityPath").Path -replace '\\', '/' # A directory, that contains CA's certificate pair, CRL file and folder with already generated certificate for revocation
    [String] [ValidateNotNullOrEmpty()] $CertToRevokePath = (Resolve-Path -Path "$ResolvedCertificateAuthorityPath/$CertificateFolderName/$CertificateName.crt").Path

    Read-Host -Prompt "`n>>> Confirm a working directory - '$ResolvedCertificateAuthorityPath' [Enter]"
    Set-Location -Path "$ResolvedCertificateAuthorityPath"

    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', "`$1$ResolvedCertificateAuthorityPath" | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Parent CA directory was set up to '$ResolvedCertificateAuthorityPath'"

    Write-Information ">>> Revoking certificate '$CertToRevokePath'...`n>>> Enter password for a parent CA:"
    openssl ca -config $ResolvedCertificateAuthorityConfPath -revoke $CertToRevokePath -keyfile ca.key -cert ca.crt
    Write-Information ">>> Enter password for the parent CA:"
    openssl ca -config $ResolvedCertificateAuthorityConfPath -gencrl -keyfile ca.key -cert ca.crt -out ca.crl # Update of CRL file
}
finally {
    $(Get-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8) -replace '^(DIR_CA\s+=\s)([^#\n]*)(?=\s?)', '$1CERT_DIR_PATH' | Set-Content -Path "$ResolvedCertificateAuthorityConfPath" -Encoding UTF8 -Force
    Write-Information ">>> Changes in '$ResolvedCertificateAuthorityConfPath':`n    - Parent CA directory has been reset to a default value"

    Set-Location -Path $StartingDir
}
