# Как получить тестовый сертификат

Для уроков 04–06 нужен сертификат. Здесь — три способа получить его бесплатно.

---

## Способ 1: makecert (быстро, входит в Windows SDK)

`makecert.exe` входит в состав Windows SDK и Visual Studio.
Создаёт самоподписанный сертификат за 30 секунд.

```bash
makecert.exe -r -pe -n "CN=CryptoLearn" -ss my -sr currentuser -sky exchange -sp "Microsoft Strong Cryptographic Provider"
```

**Что означают параметры:**
- `-r` — самоподписанный
- `-pe` — закрытый ключ экспортируемый
- `-n "CN=CryptoLearn"` — имя сертификата (можно любое)
- `-ss my` — хранилище «Личное»
- `-sr currentuser` — для текущего пользователя
- `-sky exchange` — тип ключа для шифрования (обязательно!)
- `-sp "Microsoft Strong Cryptographic Provider"` — криптопровайдер

**Проверить результат:** `Win+R` → `certmgr.msc` → Личные → Сертификаты.
Должен появиться сертификат `CryptoLearn`.

> ⚠️ Параметр `-sky exchange` обязателен. Без него расшифровка будет
> завершаться ошибкой «Модуль криптографии не поддерживает установку
> пароля к закрытому ключу».

---

## Способ 2: КриптоПро Test CA (для ГОСТ)

Если нужен тестовый ГОСТ-сертификат (для уроков про КЭП и ФНС):

1. Установите КриптоПро CSP (есть бесплатный пробный период)
2. Зайдите на [testca.cryptopro.ru](https://testca.cryptopro.ru)
3. Создайте запрос на сертификат прямо на сайте
4. Установите полученный сертификат

Сертификат подходит для тестирования, но не имеет юридической силы.

---

## Способ 3: PowerShell (Windows 10/11, без SDK)

Если `makecert.exe` нет, используйте PowerShell:

```powershell
$cert = New-SelfSignedCertificate `
    -Subject "CN=CryptoLearn" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyUsage KeyEncipherment, DigitalSignature `
    -Provider "Microsoft Strong Cryptographic Provider" `
    -NotAfter (Get-Date).AddYears(2)

Write-Host "Отпечаток: $($cert.Thumbprint)"
```

Запустите PowerShell. Отпечаток из вывода используйте в примерах кода.

> ⚠️ `New-SelfSignedCertificate` привязывает ключ к провайдеру типа 1
> (Microsoft Strong Cryptographic Provider). 1С БСП не определяет его
> автоматически — придётся выбирать вручную в настройках.
> Для автоматического определения используйте Способ 4.

---

## Способ 4: скрипт Create-1C-Certificate.ps1 (рекомендуется для 1С БСП)

Готовый скрипт из папки [`scripts/`](../scripts/Create-1C-Certificate.ps1).
Использует `certreq` вместо `New-SelfSignedCertificate` — это гарантирует
правильный провайдер (тип 24, PROV_RSA_AES), который 1С БСП определяет
автоматически без ручного выбора в настройках.

**Что делает скрипт:**
- Создаёт сертификат с Key Usage: подпись + шифрование (0xF0)
- Явно прописывает провайдер `Microsoft Enhanced RSA and AES Cryptographic Provider` (тип 24)
- Экспортирует PFX с паролем
- Устанавливает сертификат в Trusted Root CA (чтобы 1С не ругался на недоверенный корень)
- Сохраняет инструкцию по подключению в 1С в файл `certificate_info.txt`

**Запуск** (PowerShell от имени администратора):

```powershell
.\scripts\Create-1C-Certificate.ps1 `
    -SubjectName "ООО Ромашка" `
    -Organization "ООО Ромашка" `
    -ExportPassword "Pa$$w0rd" `
    -ValidYears 3
```

**Параметры:**

| Параметр | Обязательный | По умолчанию | Описание |
|----------|:---:|---|---|
| `-SubjectName` | да | — | Имя в сертификате (CN) |
| `-Organization` | нет | `""` | Организация (O) |
| `-OrganizationUnit` | нет | `""` | Подразделение (OU) |
| `-Locality` | нет | `""` | Город (L) |
| `-Country` | нет | `RU` | Страна (C) |
| `-ValidYears` | нет | `3` | Срок действия, лет (1–30) |
| `-KeyLength` | нет | `2048` | Длина ключа: 2048 или 4096 |
| `-ExportPassword` | да | — | Пароль для PFX-файла |
| `-StoreLocation` | нет | `CurrentUser` | `CurrentUser` или `LocalMachine` |

**Результат** — папка `certs_<имя>_<дата>/` рядом со скриптом:
```
certs_ООО_Ромашка_20240315_143022/
├── certificate.pfx          # Сертификат + закрытый ключ (с паролем)
├── certificate.cer          # Публичный ключ (для передачи контрагентам)
└── certificate_info.txt     # Отпечаток и инструкция по подключению в 1С
```

**Подключение в 1С БСП** после запуска скрипта:

1. НСИ и администрирование → Электронная подпись и шифрование → Программы → Добавить:
   `Microsoft Enhanced RSA and AES Cryptographic Provider`, галки: Подписание + Шифрование
2. Сертификаты → Добавить из хранилища Windows → выбрать по отпечатку из `certificate_info.txt`
3. Добавить тот же сертификат второй раз с назначением «Шифрование»

---

## Как найти отпечаток установленного сертификата

### Через certmgr.msc

1. `Win+R` → `certmgr.msc`
2. Личные → Сертификаты
3. Двойной клик на сертификат
4. Вкладка «Состав» → Отпечаток
5. Скопируйте значение, удалите пробелы

### Через PowerShell

```powershell
Get-ChildItem Cert:\CurrentUser\My | Select-Object Subject, Thumbprint
```

---

## Удаление тестового сертификата

Когда тестирование закончено:

1. `certmgr.msc` → Личные → Сертификаты
2. Правый клик на сертификат → Удалить

Или PowerShell:
```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -like "*CryptoLearn*" | Remove-Item
```
