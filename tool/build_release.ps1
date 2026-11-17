# Build de release SEGURO para compartir el APK (H-08).
#  - Firma con la llave propia (android/key.properties); el build falla si no existe.
#  - Ofusca el codigo Dart (--obfuscate) ademas de R8 (Java/Kotlin) y separa simbolos de depuracion.
#  - Verifica: no debuggable, sin permiso INTERNET, firma valida y no-debug; imprime SHA-256.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
if ($LASTEXITCODE -ne 0) { throw 'Fallo el build de release' }

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$bt = Get-ChildItem "$sdk\build-tools" | Sort-Object Name -Descending | Select-Object -First 1
$aapt2 = "$($bt.FullName)\aapt2.exe"
$apksigner = "$($bt.FullName)\apksigner.bat"

Get-ChildItem build\app\outputs\flutter-apk\*-release.apk | ForEach-Object {
    "=== $($_.Name) ($([math]::Round($_.Length/1MB,1)) MB)"
    $badging = & $aapt2 dump badging $_.FullName
    $debuggable = ($badging | Select-String 'application-debuggable') -ne $null
    $perms = ($badging | Select-String "uses-permission: name='([^']+)'" -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value }
    "debuggable : $debuggable"
    "permisos   : $($perms -join ', ')"
    if ($debuggable) { throw 'El APK es debuggable' }
    $allowed = @('android.permission.CAMERA','android.permission.USE_BIOMETRIC','android.permission.USE_FINGERPRINT',
                 'android.permission.WAKE_LOCK','com.academic.asl.sign_language_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION')
    $extra = $perms | Where-Object { $allowed -notcontains $_ }
    if ($extra) { throw "Permisos no permitidos en release: $($extra -join ', ')" }
    $certs = & $apksigner verify --print-certs $_.FullName
    $certs | Select-String 'Signer #1 certificate (DN|SHA-256)' | ForEach-Object { $_.Line }
    if (($certs | Out-String) -match 'Android Debug') { throw 'APK firmado con la llave de DEBUG' }
    "SHA-256 APK: $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
}
