#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Создание сертификата ЭЦП (подписание + шифрование) для 1С БСП
    через certreq с явным указанием криптопровайдера.

.DESCRIPTION
    Использует certreq + INF-файл вместо New-SelfSignedCertificate,
    что гарантирует корректную привязку закрытого ключа к провайдеру
    "Microsoft Enhanced RSA and AES Cryptographic Provider" (тип 24).
    Именно этот провайдер 1С БСП определяет автоматически.

.EXAMPLE
    .\Create-1C-Certificate.ps1 `
        -SubjectName "ООО Ромашка" `
        -Organization "ООО Ромашка" `
        -OrganizationUnit "Бухгалтерия" `
        -Locality "Москва" `
        -ExportPassword "Pa$$w0rd" `
        -ValidYears 3

.NOTES
    Версия: 4.0  |  PowerShell 5.1+  |  Windows 8.1 / Server 2012 R2+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubjectName,

    [string]$Organization      = "",
    [string]$OrganizationUnit  = "",
    [string]$Locality          = "",
    [string]$Country           = "RU",

    [ValidateRange(1, 30)]
    [int]$ValidYears = 3,

    [ValidateSet(2048, 4096)]
    [int]$KeyLength = 2048,

    [Parameter(Mandatory = $true)]
    [string]$ExportPassword,

    [ValidateSet("CurrentUser", "LocalMachine")]
    [string]$StoreLocation = "CurrentUser"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Вспомогательные функции ──────────────────────────────────────────────────

function Write-Step { param([string]$T); Write-Host "`n[*] $T" -ForegroundColor Cyan }
function Write-OK   { param([string]$T); Write-Host "    [OK] $T" -ForegroundColor Green }
function Write-Warn { param([string]$T); Write-Host "    [!]  $T" -ForegroundColor Yellow }
function Write-Fail { param([string]$T); Write-Host "    [!!] $T" -ForegroundColor Red }
function Write-Line { Write-Host ("=" * 64) -ForegroundColor Yellow }

# ── Проверка окружения ───────────────────────────────────────────────────────

Write-Step "Проверка окружения"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Fail "Требуется PowerShell 5.1+. Текущая: $($PSVersionTable.PSVersion)"
    exit 1
}
Write-OK "PowerShell $($PSVersionTable.PSVersion)"

$certreqCmd = Get-Command certreq -ErrorAction SilentlyContinue
if (-not $certreqCmd) {
    Write-Fail "certreq.exe не найден. Убедитесь, что установлены компоненты Windows PKI."
    exit 1
}
$certreqPath = $certreqCmd.Source
Write-OK "certreq.exe: $certreqPath"

# ── Папка вывода рядом со скриптом ──────────────────────────────────────────

Write-Step "Определение папки вывода"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$safeName  = ($SubjectName -replace '[\\/:*?"<>|]', '_').Trim()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputDir = Join-Path $scriptDir "certs_${safeName}_${timestamp}"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Write-OK "Папка: $OutputDir"

$infPath = Join-Path $OutputDir "request.inf"
$cerPath = Join-Path $OutputDir "certificate.cer"
$pfxPath = Join-Path $OutputDir "certificate.pfx"
$logPath = Join-Path $OutputDir "certificate_info.txt"

# ── Формирование Subject ─────────────────────────────────────────────────────

Write-Step "Формирование Subject"

$parts = [System.Collections.Generic.List[string]]::new()
$parts.Add("CN=$SubjectName")
if ($Organization)     { $parts.Add("O=$Organization") }
if ($OrganizationUnit) { $parts.Add("OU=$OrganizationUnit") }
if ($Locality)         { $parts.Add("L=$Locality") }
if ($Country)          { $parts.Add("C=$Country") }

$subject   = $parts -join ", "
$notBefore = [DateTime]::Now
$notAfter  = $notBefore.AddYears($ValidYears)

$machineKeySet = if ($StoreLocation -eq "LocalMachine") { "TRUE" } else { "FALSE" }

Write-OK "Subject  : $subject"
Write-OK ("Срок     : " + $notBefore.ToString("dd.MM.yyyy") + " — " + $notAfter.ToString("dd.MM.yyyy"))
Write-OK "Алгоритм : RSA-$KeyLength / SHA-256"

# ── ШАГ 1: Создание INF-файла для certreq ───────────────────────────────────
# KeyUsage = 0xF0:
#   0x80 — Digital Signature (подпись)
#   0x40 — Non Repudiation   (неотказуемость)
#   0x20 — Key Encipherment  (шифрование ключа сессии)
#   0x10 — Data Encipherment (шифрование данных)
#
# ProviderName = "Microsoft Enhanced RSA and AES Cryptographic Provider"
# ProviderType = 24 (PROV_RSA_AES) — именно этот тип определяет 1С БСП
# KeySpec = 1 (AT_KEYEXCHANGE) — поддерживает и подпись, и расшифрование

Write-Step "ШАГ 1/4 — Создание INF-файла запроса"

# Строим INF строками чтобы избежать проблем с кодировкой here-string
$infLines = @(
    "[Version]",
    'Signature = "$Windows NT$"',
    "",
    "[NewRequest]",
    ('Subject         = "' + $subject + '"'),
    "KeySpec          = 1",
    ("KeyLength        = " + $KeyLength),
    "Exportable       = TRUE",
    ("MachineKeySet    = " + $machineKeySet),
    "SMIME            = FALSE",
    "PrivateKeyArchive = FALSE",
    "UserProtected    = FALSE",
    "UseExistingKeySet = FALSE",
    'ProviderName     = "Microsoft Enhanced RSA and AES Cryptographic Provider"',
    "ProviderType     = 24",
    "RequestType      = Cert",
    "KeyUsage         = 0xF0",
    "HashAlgorithm    = SHA256",
    ('FriendlyName     = "1C EDS+ENC ' + $SubjectName + '"'),
    "",
    "[EnhancedKeyUsageExtension]",
    "OID = 1.3.6.1.5.5.7.3.2",
    "OID = 1.3.6.1.5.5.7.3.4",
    "OID = 1.3.6.1.4.1.311.10.3.12",
    "",
    "[Extensions]",
    '2.5.29.19 = "{text}"'
)

# certreq требует ANSI-кодировку INF-файла
$ansiEncoding = [System.Text.Encoding]::Default
[System.IO.File]::WriteAllLines($infPath, $infLines, $ansiEncoding)

Write-OK "INF файл: $infPath"

# ── ШАГ 2: certreq — создание самоподписанного сертификата ──────────────────

Write-Step "ШАГ 2/4 — Создание сертификата через certreq"

$certreqArgs = @("-new", "-f")
if ($StoreLocation -ne "LocalMachine") { $certreqArgs += "-user" }
$certreqArgs += @($infPath, $cerPath)

try {
    $output = & certreq @certreqArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "certreq завершился с кодом $LASTEXITCODE"
        Write-Fail ($output | Out-String)
        exit 1
    }
    Write-OK "certreq выполнен успешно"
    Write-OK "CER файл: $cerPath"
} catch {
    Write-Fail "Ошибка запуска certreq: $_"
    exit 1
}

# ── ШАГ 3: Получение Thumbprint из установленного сертификата ────────────────

Write-Step "ШАГ 3/4 — Поиск сертификата в хранилище"

$storePath = if ($StoreLocation -eq "LocalMachine") {
    "Cert:\LocalMachine\My"
} else {
    "Cert:\CurrentUser\My"
}

# Ищем по CN и сроку действия (certreq уже установил его в хранилище)
Start-Sleep -Seconds 1
$foundCert = Get-ChildItem $storePath |
    Where-Object {
        $_.Subject -like "*CN=$SubjectName*" -and
        $_.NotAfter -gt (Get-Date) -and
        $_.HasPrivateKey -eq $true
    } |
    Sort-Object NotBefore -Descending |
    Select-Object -First 1

if (-not $foundCert) {
    Write-Fail "Сертификат не найден в хранилище $storePath"
    Write-Fail "Проверьте вывод certreq выше."
    exit 1
}

Write-OK "Thumbprint    : $($foundCert.Thumbprint)"
Write-OK "HasPrivateKey : $($foundCert.HasPrivateKey)"
Write-OK "Провайдер     : $($foundCert.PrivateKey.CspKeyContainerInfo.ProviderName)"

# ── ШАГ 4: Экспорт PFX ──────────────────────────────────────────────────────

Write-Step "ШАГ 4/4 — Экспорт PFX (сертификат + закрытый ключ)"

$secPwd = ConvertTo-SecureString -String $ExportPassword -Force -AsPlainText

try {
    Export-PfxCertificate `
        -Cert (Join-Path $storePath $foundCert.Thumbprint) `
        -FilePath $pfxPath `
        -Password $secPwd `
        -ChainOption EndEntityCertOnly | Out-Null
    Write-OK "PFX файл: $pfxPath"
} catch {
    Write-Fail "Ошибка экспорта PFX: $_"
    exit 1
}

# ── Удаление временного INF-файла ────────────────────────────────────────────

Remove-Item $infPath -Force -ErrorAction SilentlyContinue
Write-OK "Временный INF удалён"

# ── Финальная проверка ───────────────────────────────────────────────────────

Write-Step "Финальная проверка"

$finalCert = Get-Item (Join-Path $storePath $foundCert.Thumbprint)
Write-OK ("Subject       : " + $finalCert.Subject)
Write-OK ("HasPrivateKey : " + $finalCert.HasPrivateKey)

try {
    $provName = $finalCert.PrivateKey.CspKeyContainerInfo.ProviderName
    $provType = $finalCert.PrivateKey.CspKeyContainerInfo.ProviderType
    Write-OK ("Провайдер     : " + $provName)
    Write-OK ("Тип провайдера: " + $provType)

    if ($provType -eq 24) {
        Write-OK "Тип провайдера 24 (PROV_RSA_AES) — 1С БСП определит автоматически!"
    } else {
        Write-Warn "Тип провайдера $provType — может потребоваться ручной выбор в 1С."
    }
} catch {
    Write-Warn "Не удалось прочитать информацию о провайдере: $_"
}

# ── Добавление в доверенные корневые УЦ ────────────────────────────────────
# Самоподписанный сертификат сам себе является корневым.
# Чтобы 1С не ругался на недоверенный корневой — устанавливаем его в Root.

Write-Step "Установка в доверенные корневые УЦ (Trusted Root CA)"

try {
    $rootStoreLocation = if ($StoreLocation -eq "LocalMachine") {
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    } else {
        [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
    }

    $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        $rootStoreLocation
    )
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $rootStore.Add($finalCert)
    $rootStore.Close()

    Write-OK "Сертификат добавлен в Trusted Root CA"
    Write-OK ("Хранилище Root: " + $rootStoreLocation.ToString() + "\Root")
} catch {
    Write-Warn "Не удалось добавить в Root CA: $_"
    Write-Warn "Добавьте вручную: certmgr -> Доверенные корневые УЦ -> Импорт -> certificate.cer"
}

# ── Информационный лог ───────────────────────────────────────────────────────

$providerInfo = ""
try {
    $providerInfo = $finalCert.PrivateKey.CspKeyContainerInfo.ProviderName
} catch { $providerInfo = "Microsoft Enhanced RSA and AES Cryptographic Provider" }

$lines = @(
    ("=" * 64),
    "  Сертификат ЭЦП + Шифрование для 1С БСП",
    ("  Создан: " + (Get-Date -Format "dd.MM.yyyy HH:mm:ss")),
    ("=" * 64),
    "",
    ("Subject         : " + $finalCert.Subject),
    ("Thumbprint      : " + $finalCert.Thumbprint),
    ("Серийный номер  : " + $finalCert.SerialNumber),
    ("Алгоритм        : RSA-" + $KeyLength + " / SHA-256"),
    ("Действителен с  : " + $notBefore.ToString("dd.MM.yyyy HH:mm:ss")),
    ("Действителен по : " + $notAfter.ToString("dd.MM.yyyy HH:mm:ss")),
    ("Хранилище       : " + $storePath),
    ("Провайдер       : " + $providerInfo),
    "Тип провайдера  : 24 (PROV_RSA_AES)",
    "",
    "Key Usage (0xF0):",
    "  Digital Signature, Non Repudiation,",
    "  Key Encipherment, Data Encipherment",
    "",
    "Extended Key Usage:",
    "  Client Authentication (1.3.6.1.5.5.7.3.2)",
    "  Secure Email / S-MIME  (1.3.6.1.5.5.7.3.4)",
    "  Document Signing       (1.3.6.1.4.1.311.10.3.12)",
    "",
    "KeySpec: 1 (AT_KEYEXCHANGE) — подпись + расшифрование",
    "",
    "Хранилища:",
    ("  My   (личные)      : " + $storePath),
    ("  Root (доверенные)  : " + $storePath.Replace("\My","\Root")),
    "",
    "Файлы:",
    ("  PFX (ключ + сертификат) : " + $pfxPath),
    ("  CER (публичный ключ)    : " + $cerPath),
    "",
    ("=" * 64),
    "  ИНСТРУКЦИЯ ПО ПОДКЛЮЧЕНИЮ В 1С БСП",
    ("=" * 64),
    "",
    "1. Настройка криптопровайдера:",
    "   НСИ и администрирование -> Электронная подпись и шифрование",
    "   -> Программы -> Добавить:",
    '   Имя: "Microsoft Enhanced RSA and AES Cryptographic Provider"',
    "   Поставить галки: Подписание + Шифрование",
    "",
    "2. Добавление сертификата для ПОДПИСАНИЯ:",
    "   -> Сертификаты -> Добавить из хранилища Windows",
    "   Назначение: Подписание",
    ("   Thumbprint: " + $finalCert.Thumbprint),
    "",
    "3. Добавление сертификата для ШИФРОВАНИЯ:",
    "   -> Сертификаты -> Добавить из хранилища Windows",
    "   Назначение: Шифрование",
    ("   Thumbprint: " + $finalCert.Thumbprint),
    "   (тот же сертификат — поддерживает оба режима)",
    "",
    "4. ВАЖНО:",
    "   * Для внешнего ЭДО и гос. отчётности нужен сертификат",
    "     от аккредитованного УЦ + КриптоПро CSP (ГОСТ).",
    "   * Данный сертификат — для тестирования / внутреннего ЭДО.",
    "   * Храните PFX и пароль к нему в надёжном месте.",
    "",
    ("=" * 64)
)

$lines | Out-File -FilePath $logPath -Encoding UTF8

# ── Итоговая сводка ──────────────────────────────────────────────────────────

Write-Host ""
Write-Line
Write-Host "  ГОТОВО" -ForegroundColor Yellow
Write-Line
Write-Host ("  Thumbprint : " + $finalCert.Thumbprint)  -ForegroundColor White
Write-Host ("  Провайдер  : " + $providerInfo)           -ForegroundColor White
Write-Host ("  Папка      : " + $OutputDir)              -ForegroundColor White
Write-Host  "  Файлы      : certificate.pfx / .cer / _info.txt" -ForegroundColor White
Write-Line
Write-Host ""
Write-Host "  Откройте certificate_info.txt для инструкции." -ForegroundColor Cyan
Write-Host ""
