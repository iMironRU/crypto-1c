# Как получить тестовый сертификат

Для уроков 04–06 нужен сертификат. Здесь — три способа получить его бесплатно.

---

## Способ 1: makecert (быстро, без установки)

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
    -KeyUsage KeyEncipherment, DigitalSignature `
    -NotAfter (Get-Date).AddYears(2)

Write-Host "Отпечаток: $($cert.Thumbprint)"
```

Запустите PowerShell от имени администратора. Отпечаток из вывода
используйте в примерах кода.

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
