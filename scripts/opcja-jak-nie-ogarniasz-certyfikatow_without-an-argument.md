# DavTro — certyfikaty, port-forward-without-an-argument-ing i dostęp klientów

Dokument opisuje dwa skrypty i pełny workflow związany z wystawieniem usług DavTro z klastra K8s, wygenerowaniem certyfikatów TLS/mTLS oraz ich dystrybucją i importem na komputerach klientów.

---

## Spis treści

1. [Architektura — dwa skrypty, dwie role](#1-architektura--dwa-skrypty-dwie-role)
2. [Skrypt 1 — `scripts/port-forward-without-an-argument-ing.sh` (maszyna z K8s)](#2-skrypt-1--scriptsport-forward-without-an-argument-ingsh-maszyna-z-k8s)
3. [Skrypt 2 — `client-port-forward-without-an-argument-ing.sh` (komputer klienta)](#3-skrypt-2--client-port-forward-without-an-argument-ingsh-komputer-klienta)
4. [Workflow krok po kroku](#4-workflow-krok-po-kroku)
5. [Hasło do `.pfx` — gdzie jest i jak je zmienić](#5-hasło-do-pfx--gdzie-jest-i-jak-je-zmienić)
6. [Co się pojawia w `/tmp/ctr/`](#6-co-się-pojawia-w-tmpctr)
7. [Import certyfikatów do przeglądarki](#7-import-certyfikatów-do-przeglądarki)
8. [Diagnostyka błędów](#8-diagnostyka-błędów)
9. [Uwagi i ograniczenia](#9-uwagi-i-ograniczenia)

---

## 1. Architektura — dwa skrypty, dwie role

| Aspekt | `port-forward-without-an-argument-ing.sh` | `client-port-forward-without-an-argument-ing.sh` |
|--------|-------------------|-------------------|
| Gdzie uruchamiany | maszyna z `kubectl` / `microk8s` | komputer użytkownika (przeglądarka) |
| Wymaga `kubectl` | tak | **nie** |
| Wymaga `openssl` | tak (do generowania `.pfx`) | nie (dostaje gotowy `.pfx`) |
| Modyfikuje system | nie (tylko forwardy + pliki w `/tmp/ctr/`) | **tak** (magazyn CA, NSS, keychain) |
| Uprawnienia | user | `sudo` / admin |
| Rola | wystawia usługi + wypluwa certyfikaty | importuje CA + cert klienta |

**Skrypt z K8s = „wystaw usługi i wypluj certyfikaty".**
**Skrypt klienta = „zaufaj temu CA i zaimportuj swój certyfikat klienta".**

---

## 2. Skrypt 1 — `scripts/port-forward-without-an-argument-ing.sh` (maszyna z K8s)

### 2.1 Co robi bez argumentu

1. Odpala wszystkie forwardy **HTTP** (FastAPI, frontend, spring, spark-ui, grafana, kafka-ui, loki, tempo, prometheus, pgadmin, postgres, redis, vault, spark, kafka, kafka-exp, pg-exp, node-exp).
2. Tworzy katalog `/tmp/ctr/` (jeśli nie istnieje) i **wyciąga z Secretów** wszystkie certyfikaty TLS/mTLS.
3. Generuje z nich pliki `.pfx` i `.p12` z hasłem `slodkadziurkazwypiekami`.

### 2.2 Główne argumenty

```bash
./scripts/port-forward-without-an-argument-ing.sh                  # forwardy HTTP + ekstrakcja certów
./scripts/port-forward-without-an-argument-ing.sh https-fastapi  8443
./scripts/port-forward-without-an-argument-ing.sh https-frontend 8444
./scripts/port-forward-without-an-argument-ing.sh https-spring   8445
./scripts/port-forward-without-an-argument-ing.sh https-vault    8243
./scripts/port-forward-without-an-argument-ing.sh https-all        # wszystko naraz (wait, Ctrl+C kończy)
./scripts/port-forward-without-an-argument-ing.sh extract-tls <secret> [prefix]
./scripts/port-forward-without-an-argument-ing.sh extract-all      # to samo co bez argumentu, tylko ekstrakcja
./scripts/port-forward-without-an-argument-ing.sh serve            # serwuje /tmp/ctr/ na 0.0.0.0:8099
./scripts/port-forward-without-an-argument-ing.sh import-help      # instrukcja importu do przeglądarki
./scripts/port-forward-without-an-argument-ing.sh diag             # porty, logi, secrety, zawartość /tmp/ctr/
```

### 2.3 Konfiguracja (zmienne środowiskowe)

| Zmienna | Domyślnie | Znaczenie |
|---------|-----------|-----------|
| `ADDR` | `0.0.0.0` | adres bindowania forwardów (`127.0.0.1` = tylko lokalnie) |
| `NS` | `davtro02` | namespace w K8s |
| `CTR_DIR` | `/tmp/ctr` | katalog na certyfikaty |
| `PFX_PASS` | `slodkadziurkazwypiekami` | hasło do `.pfx`/`.p12` |

### 2.4 Sekrety wyciągane domyślnie

```bash
TLS_SECRETS=(
  "davtro-tls:davtro-tls"
  "fastapi-mtls:fastapi-mtls"
  "spring-app-mtls:spring-app-mtls"
  "message-processor-mtls:message-processor-mtls"
)
```

Rozszerzasz edytując tablicę w skrypcie.

---

## 3. Skrypt 2 — `client-port-forward-without-an-argument-ing.sh` (komputer klienta)

### 3.1 Co robi

1. Pobiera `davtro-tls-ca.crt` z `http://192.168.1.19:8099/`.
2. (Opcjonalnie, z `--mtls`) pobiera `<nazwa>-mtls.pfx`.
3. Importuje CA do zaufanych magazynów systemu i przeglądarki.
4. Importuje `.pfx` do magazynu certyfikatów klienta.

### 3.2 Użycie

```bash
./client-port-forward-without-an-argument-ing.sh                        # tylko CA (bez mTLS)
./client-port-forward-without-an-argument-ing.sh --mtls fastapi         # CA + cert klienta fastapi-mtls.pfx
./client-port-forward-without-an-argument-ing.sh --uninstall            # usuwa CA i cert klienta
```

### 3.3 Zmienne środowiskowe

| Zmienna | Domyślnie | Znaczenie |
|---------|-----------|-----------|
| `K8S_HOST` | `192.168.1.19` | adres maszyny z K8s |
| `K8S_PORT` | `8099` | port serwera HTTP z certyfikatami |
| `PFX_PASS` | `slodkadziurkazwypiekami` | hasło do `.pfx` |
| `WORKDIR` | `/tmp/davtro-client` | katalog roboczy na pobrane pliki |

### 3.4 Co robi na poszczególnych systemach

| System | CA | `.pfx` klienta |
|--------|----|----------------|
| **Linux** | `update-ca-certificates` | `pk12util` → NSS Chrome |
| **macOS** | `security add-trusted-cert` | `security import` → login keychain |
| **Windows** (Git Bash) | `certutil -addstore ROOT` | `certutil -importpfx MY` |

---

## 4. Workflow krok po kroku

### 4.1 Na maszynie z K8s (`192.168.1.19`)

```bash
# 1. Odpal forwardy HTTP + wyciagnij certy do /tmp/ctr/
./scripts/port-forward-without-an-argument-ing.sh

# 2. Udostepnij certy klientom przez HTTP
cp scripts/client-port-forward-without-an-argument-ing.sh /tmp/ctr/       # zeby klient mogl go pobrac
./scripts/port-forward-without-an-argument-ing.sh serve            # http://192.168.1.19:8099/
```

`serve` zostaw w `tmux` / `screen` — dopóki działa, klienci mogą pobierać pliki.

### 4.2 Na komputerze klienta

```bash
# 1. Pobierz skrypt klienta
curl -O http://192.168.1.19:8099/client-port-forward-without-an-argument-ing.sh
chmod +x client-port-forward-without-an-argument-ing.sh

# 2. Tylko CA (bez mTLS) — dla zwyklej przegladarki
./client-port-forward-without-an-argument-ing.sh

# 3. CA + cert klienta (mTLS) — jesli serwer wymaga certyfikatu klienta
./client-port-forward-without-an-argument-ing.sh --mtls fastapi

# 4. Odinstalowanie
./client-port-forward-without-an-argument-ing.sh --uninstall
```

### 4.3 Weryfikacja

```bash
curl -v https://192.168.1.19:8443/ 2>&1 | head -20
# Oczekiwane: "SSL certificate verify ok"
```

Otwórz w przeglądarce:

- `https://192.168.1.19:8443/` — FastAPI przez Ingress
- `https://192.168.1.19:8444/` — frontend przez Ingress
- `https://192.168.1.19:8445/` — spring przez Ingress

---

## 5. Hasło do `.pfx` — gdzie jest i jak je zmienić

| Miejsce | Wartość |
|---------|---------|
| `port-forward-without-an-argument-ing.sh` (domyślnie) | `slodkadziurkazwypiekami` |
| `client-port-forward-without-an-argument-ing.sh` (domyślnie) | `slodkadziurkazwypiekami` |
| Nadpisanie po stronie K8s | `PFX_PASS="inne" ./scripts/port-forward-without-an-argument-ing.sh` |
| Nadpisanie po stronie klienta | `PFX_PASS="inne" ./client-port-forward-without-an-argument-ing.sh --mtls fastapi` |

**Hasło musi być takie samo po obu stronach** — inaczej import `.pfx` się nie powiedzie.

---

## 6. Co się pojawia w `/tmp/ctr/`

Po uruchomieniu `./scripts/port-forward-without-an-argument-ing.sh` bez argumentu:

```
davtro-tls-ca.crt              ← CA do zaufania przeglądarki (to importuje klient)
davtro-tls.crt
davtro-tls.key
davtro-tls.pfx                 ← hasło: slodkadziurkazwypiekami
davtro-tls.p12

fastapi-mtls-ca.crt
fastapi-mtls.crt
fastapi-mtls.key
fastapi-mtls.pfx               ← hasło: slodkadziurkazwypiekami
fastapi-mtls.p12

spring-app-mtls.pfx
spring-app-mtls.p12

message-processor-mtls.pfx
message-processor-mtls.p12
```

Katalog ma uprawnienia `700`, klucze prywatne `600`.

---

## 7. Import certyfikatów do przeglądarki

### 7.1 Certyfikat CA (żeby przeglądarka ufała serwerowi)

#### Linux — Chromium / Chrome / Edge

Chrome na Linuxie używa **własnej bazy NSS**, a nie systemowego magazynu. Dwie opcje:

**Opcja A (systemowo + Chrome):**
```bash
sudo cp /tmp/ctr/davtro-tls-ca.crt /usr/local/share/ca-certificates/davtro-ca.crt
sudo update-ca-certificates
```
Potem w Chrome:
`chrome://settings/certificates` → **Certyfikaty lokalne** → **Linux** → zaznacz **„Używaj certyfikatów lokalnych zaimportowanych z systemu operacyjnego"**.

**Opcja B (ręcznie do bazy NSS Chrome):**
```bash
sudo apt install libnss3-tools
certutil -d sql:$HOME/.local/share/pki/nssdb -A -t "C,," \
  -n "davtro-internal CA" -i /tmp/ctr/davtro-tls-ca.crt
# starsze Chrome: $HOME/.pki/nssdb
```

#### Firefox

`about:preferences#privacy` → **Certyfikaty** → **Wyświetl certyfikaty** → **Urzędy certyfikacji** → **Importuj** → `/tmp/ctr/davtro-tls-ca.crt` → zaznacz **„Zaufaj temu CA do identyfikacji witryn internetowych"**.

Alternatywnie: `about:config` → `security.enterprise_roots.enabled = true` (Firefox ufa wtedy magazynowi systemowemu).

### 7.2 Certyfikat klienta (mTLS) — tylko `.pfx` / `.p12`

Przeglądarka **nie zaimportuje** `.crt` + `.key` osobno. Musi to być kontener PKCS#12:

```bash
./scripts/port-forward-without-an-argument-ing.sh make-pfx fastapi-mtls /tmp/ctr/fastapi.pfx "slodkadziurkazwypiekami" "fastapi client"
```

Import:

- **Chrome/Edge:** `chrome://settings/certificates` → **Twoje certyfikaty** → **Importuj** → `/tmp/ctr/fastapi-mtls.pfx` → hasło `slodkadziurkazwypiekami`.
- **Firefox:** `about:preferences#privacy` → **Certyfikaty** → **Wyświetl certyfikaty** → **Twoje certyfikaty** → **Importuj** → `/tmp/ctr/fastapi-mtls.pfx`.

---

## 8. Diagnostyka błędów

### 8.1 Typowe błędy przeglądarki

| Błąd | Znaczenie | Rozwiązanie |
|------|-----------|-------------|
| `ERR_SSL_PROTOCOL_ERROR` | złe `http://` vs `https://` albo forward nie działa | sprawdź `/tmp/pf-*.log`, użyj `https://` |
| `ERR_CONNECTION_REFUSED` | żaden port-forward-without-an-argument-ing nie nasłuchuje | `./scripts/port-forward-without-an-argument-ing.sh diag` |
| `ERR_CERT_AUTHORITY_INVALID` | CA niezaimportowane | punkt 7.1 |
| `ERR_CERT_COMMON_NAME_INVALID` | cert na inną nazwę (np. `*.davtro.local`), a wchodzisz po IP | dodaj SAN z IP albo używaj DNS z Ingressa |
| „Witryna prosi o wybór certyfikatu klienta" | mTLS działa | wybierz cert z punktu 7.2 |

### 8.2 Szybka diagnostyka

```bash
./scripts/port-forward-without-an-argument-ing.sh diag
```

Pokazuje:

- nasłuchujące porty,
- procesy `kubectl port-forward-without-an-argument-ing`,
- zawartość `/tmp/ctr/`,
- secrety TLS w `davtro02`.

### 8.3 Test z `curl`

```bash
# mTLS:
curl --cacert /tmp/ctr/fastapi-mtls-ca.crt \
     --cert   /tmp/ctr/fastapi-mtls.crt \
     --key    /tmp/ctr/fastapi-mtls.key \
     https://localhost:8443/api/health

# samo CA:
curl --cacert /tmp/ctr/davtro-tls-ca.crt https://localhost:8443/

# ignorowanie certyfikatu (dev):
curl -k https://localhost:8443/
```

---

## 9. Uwagi i ograniczenia

1. **Skrypt klienta nie potrzebuje `kubectl`** — pobiera gotowe pliki przez HTTP.
2. **`client-port-forward-without-an-argument-ing.sh` musi być dostępny na serwerze HTTP** — wrzuć go do `/tmp/ctr/` przed `serve`.
3. **`serve` binduje na `0.0.0.0:8099`** — jeśli nie chcesz wystawiać na cały LAN, użyj `--bind 127.0.0.1` i tuneluj SSH.
4. **Po restarcie maszyny z K8s** — forwardy i `serve` padają. Warto owinąć w `systemd` albo odpalać w `tmux`.
5. **Certyfikaty w `/tmp/ctr/`** — `/tmp` czyści się przy restarcie. Jeśli chcesz trwałe, ustaw `CTR_DIR=/srv/certs`.
6. **Nie kopiuj `.key` na klientów** — klucz prywatny serwera nie może wyciec. Klient dostaje **tylko** `.pfx` (jeśli mTLS) albo sam `ca.crt`.
7. **Nie importuj `.crt` + `.key` osobno w przeglądarce** — to nie zadziała. Tylko `.pfx` / `.p12`.

---

## Załączniki

- `scripts/port-forward-without-an-argument-ing.sh` — skrypt na maszynie z K8s (forwardy + ekstrakcja certów).
- `client-port-forward-without-an-argument-ing.sh` — skrypt na komputerze klienta (pobranie + import).
- `/tmp/ctr/` — katalog wymiany (na maszynie z K8s), serwowany przez `serve`.

---

*Dokument wygenerowany dla środowiska DavTro — K8s `davtro02`, host `192.168.1.19`, port HTTP dystrybucji certyfikatów `8099`.*


# ###############################################################

#

# Ja masz problem z cert i DNS na host klienta 

#

# ##################################################################
**Tak, te argumenty działają w obu skryptach — pod warunkiem, że używasz właściwej nazwy pliku.** Zobaczmy dokładnie.

## Co jest w Twoim repo

Z Twojego `git` output wynika, że masz:

```
scripts/port-forward-without-an-argument-ing.sh       ← nowy, z auto-detekcją Ingress Controllera
scripts/client-port-forward-without-an-argument-ing.sh ← skrypt klienta (client-setup)
```

**Uwaga:** w git output widzę `rename ... => client-port-forward-without-an-argument-ing-ing.sh`. To znaczy, że wcześniej miałeś `port-forward-without-an-argument-ing002.sh`, a teraz masz `client-port-forward-without-an-argument-ing-ing.sh`.

## Który plik ma jakie argumenty

### `scripts/port-forward-without-an-argument-ing.sh` (ten na maszynie z K8s)

To jest odpowiednik mojego `port-forward.sh`. **Ma wszystkie argumenty** wymienione w `case`:

| Argument | Co robi | Działa? |
|----------|---------|---------|
| *(bez argumentu)* | forwardy HTTP + `extract_all` | ✅ tak |
| `https-fastapi 8443` | forward HTTPS przez Ingress na `8443` | ✅ tak (jeśli wykryje Ingress Controller) |
| `https-frontend 8444` | forward HTTPS na `8444` | ✅ tak |
| `https-spring 8445` | forward HTTPS na `8445` | ✅ tak |
| `https-vault 8243` | forward Vault na `8243` | ✅ tak |
| `https-all` | wszystkie HTTPS na raz + `wait` | ✅ tak |
| `extract-tls <secret> [prefix]` | ekstrakcja jednego Secreta | ✅ tak |
| `extract-all` | ekstrakcja wszystkich Secretów | ✅ tak |
| `serve` | serwuje `/tmp/ctr/` na `8099` | ✅ tak |
| `import-help` | instrukcja importu | ✅ tak |
| `diag` | diagnostyka | ✅ tak |

### `scripts/client-port-forward-without-an-argument-ing.sh` (skrypt klienta)

To odpowiednik mojego `client-setup.sh`. **Ma inne argumenty:**

| Argument | Co robi | Działa? |
|----------|---------|---------|
| *(bez argumentu)* | pobiera CA, importuje | ✅ tak |
| `--mtls fastapi` | pobiera CA + `.pfx` klienta | ✅ tak |
| `--uninstall` | usuwa CA i cert klienta | ✅ tak |

**Ten skrypt NIE ma** `https-fastapi`, `extract-tls`, `serve`, `diag` — bo nie jest do tego. To skrypt klienta, nie admina.

## Dlaczego nazwy są mylące

Twoje pliki mają nazwy:
- `port-forward-without-an-argument-ing.sh` — sugeruje „bez argumentu", ale **ma argumenty**. Nazwa kłamie.
- `client-port-forward-without-an-argument-ing.sh` — sugeruje to samo, ale to skrypt klienta.

**To nie błąd funkcjonalny** — skrypty działają. Ale nazwy są mylące. Powinny być:

```
scripts/port-forward.sh              ← na maszynie z K8s
scripts/client-setup.sh              ← na maszynie klienta
```

Wtedy `import-help` i `diag` same pokazują `$0` w komunikatach, więc nazwa pliku pojawia się w output — i użytkownik nie musi się domyślać.

## Sprawdź, czy Twój plik faktycznie ma te argumenty

Otwórz i zobacz `case`:

```bash
grep -A 40 'case "${1:-}"' scripts/port-forward-without-an-argument-ing.sh
```

Powinieneś zobaczyć:
```
https-fastapi)  start_https_ingress fastapi  "${2:-8443}"; exit 0 ;;
https-frontend) start_https_ingress frontend "${2:-8444}"; exit 0 ;;
...
```

Jeśli widzisz — **wszystko działa**.

## Ale uwaga — w Twoim repo widzę problem

W `git` output masz:

```
rename scripts/{port-forward-without-an-argument002.sh => client-port-forward-without-an-argument-ing.sh} (100%)
mode change 100755 => 100644
create mode 100755 scripts/port-forward-without-an-argument-ing.sh
```

Zwróć uwagę:
- `client-port-forward-without-an-argument-ing.sh` ma **`100644`** — **nie jest wykonywalny!**
- `port-forward-without-an-argument-ing.sh` ma **`100755`** — jest OK.

Czyli klient, który pobierze `client-port-forward-without-an-argument-ing.sh`, **nie będzie mógł go uruchomić bez `chmod +x`**. Napraw:

```bash
chmod +x scripts/client-port-forward-without-an-argument-ing.sh
git add scripts/client-port-forward-without-an-argument-ing.sh
git commit -m "fix: client script executable bit"
git push
```

## Sprawdź też, czy `client-...sh` ma poprawne wnętrze

W `git` widać `rename ... (100%)`, co znaczy, że zawartość się nie zmieniła — tylko nazwa. Ale jeśli stary `port-forward-without-an-argument002.sh` był **kopią skryptu admina** (z `kubectl port-forward`), a nie skryptem klienta (`curl` + import), to klient dostanie zły plik.

Sprawdź:

```bash
head -30 scripts/client-port-forward-without-an-argument-ing.sh
grep -E 'kubectl|curl|update-ca|pk12util|certutil' scripts/client-port-forward-without-an-argument-ing.sh
```

Jeśli w środku jest `kubectl port-forward` — to znaczy, że to **nie jest skrypt klienta**, tylko kopia admina. Wtedy trzeba go nadpisać moim `client-setup.sh` (albo Twoim odpowiednikiem).

## Szybki test — co działa u Ciebie teraz

Odpal po kolei:

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01

# 1. Sprawdz, czy skrypt admina ma argumenty
grep -c 'https-fastapi\|extract-tls\|serve\|diag' scripts/port-forward-without-an-argument-ing.sh
# Oczekiwane: >= 4

# 2. Sprawdz, czy skrypt klienta jest skryptem klienta (a nie admina)
grep -c 'kubectl port-forward' scripts/client-port-forward-without-an-argument-ing.sh
# Oczekiwane: 0

# 3. Sprawdz uprawnienia
ls -la scripts/port-forward-without-an-argument-ing.sh scripts/client-port-forward-without-an-argument-ing.sh
# Oczekiwane: oba -rwxr-xr-x
```

**Wklej wyniki** — wtedy powiem, czy coś jeszcze trzeba poprawić.

## Podsumowanie

| Pytanie | Odpowiedź |
|---------|-----------|
| Czy argumenty `https-fastapi`, `extract-tls`, `serve`, `diag` działają? | ✅ Tak, w `port-forward-without-an-argument-ing.sh` |
| Czy `client-...sh` ma te same argumenty? | ❌ Nie — ma `--mtls` i `--uninstall`. To inny skrypt. |
| Czy nazwy są mylące? | ✅ Tak, bardzo. `without-an-argument` kłamie. |
| Czy `client-...sh` jest wykonywalny? | ❌ Nie — git pokazuje `100644`. Trzeba `chmod +x`. |
| Czy coś jest zepsute? | ⚠️ Możliwe — sprawdź, czy `client-...sh` to naprawdę skrypt klienta, nie kopia admina. |

**Wklej wyniki tych trzech poleceń** — wtedy dokładnie powiem, co poprawić, żeby nazwy i zawartość się zgadzały.



# #############################

**To jest dobry znak — Ingress Controller żyje i odpowiada po HTTPS.** `404 page not found` to odpowiedź **samego Ingress Controllera** (albo backendu), a nie błąd połączenia. Czyli:

- ✅ forward do Ingress Controllera działa,
- ✅ TLS handshake się udał,
- ✅ Ingress Controller przyjął request,
- ❌ ale **nie dopasował go do żadnej reguły** — dlatego 404.

## Dlaczego 404

Twój Ingress ma regułę **tylko dla Hosta `davtro.local`**:

```yaml
rules:
- host: davtro.local
  http:
    paths:
    - path: /api        → fastapi-web-app-svc:80
    - path: /           → frontend-svc:80
    - path: /grafana    → grafana:3000
    - path: /kafka-ui   → kafka-ui:80
    - path: /pgadmin    → pgadmin:80
```

A Ty wchodzisz na `https://192.168.1.19:8444/` — czyli z **Host: 192.168.1.19**. Ingress Controller szuka reguły dla `192.168.1.19`, nie znajduje, zwraca 404.

**Ingress routuje po Hoscie (nazwie), nie po IP.** To jest kluczowa rzecz, którą trzeba zrozumieć.

## Rozwiązanie — dwie opcje

### Opcja A (szybka, testowa) — wymuś Host w curl

```bash
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/ 2>&1 | tail -40
```

Jeśli to zadziała — problem jest wyłącznie w Hoscie, nie w konfiguracji.

### Opcja B (dla przeglądarki) — dodaj wpis do `/etc/hosts`

Na **maszynie klienta** (tej, gdzie masz przeglądarkę):

```bash
echo "192.168.1.19   davtro.local" | sudo tee -a /etc/hosts
```

Potem w Chrome wpisz:

```
https://davtro.local:8444/
```

**Nie** `https://192.168.1.19:8444/`. Musi być `davtro.local`.

## Sprawdź najpierw curl-em, czy to na pewno routing

```bash
# 1. Host: davtro.local (powinno dzialac - frontend)
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/ 2>&1 | tail -30

# 2. Host: davtro.local, sciezka /api (FastAPI)
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/api/health 2>&1 | tail -30

# 3. Host: 192.168.1.19 (twoj obecny blad - 404)
curl -skv https://192.168.1.19:8444/ 2>&1 | tail -30
```

Wynik #1 i #2 powie Ci, czy Ingress działa poprawnie (powinno być `HTTP/2 200` albo `HTTP/1.1 200`). Wynik #3 to Twój obecny błąd (404).

## Jeśli #1 też daje 404 — problem głębiej

Wtedy możliwe przyczyny:

1. **Ingress Controller nie widzi `davtro-ingress`** — bo `IngressClass: public` nie jest obsługiwany przez controller. Sprawdź:
   ```bash
   kubectl get ingressclass
   kubectl -n davtro02 describe ingress davtro-ingress | grep -iE 'class|error|event'
   ```

2. **Ingress Controller używa innej klasy** — np. ma `controller: k8s.io/ingress-nginx` a Ty masz `ingressClassName: public`. Sprawdź, jaka klasa jest domyślna:
   ```bash
   kubectl get ingressclass -o yaml
   ```

3. **Backend nie odpowiada** — wtedy zamiast 404 dostaniesz `502 Bad Gateway` / `503 Service Unavailable`. Ale Ty masz 404, więc to routing, nie backend.

## Co zobaczyć w logach Ingress Controllera

Skoro nie wiesz, gdzie on jest, najpierw go znajdź:

```bash
kubectl get pods -A | grep -iE 'ingress|traefik|nginx|envoy|haproxy|contour'
```

**Wklej wynik.** Potem:

```bash
# przyklad dla traefika:
kubectl -n <ns> logs <pod> --tail=50 | grep -i davtro

# przyklad dla nginx:
kubectl -n <ns> logs <pod> --tail=50 | grep -i davtro
```

W logach powinno być widać, czy request `Host: davtro.local` trafił do `frontend-svc:80`.

## Docelowa konfiguracja — jak to powinno wyglądać

Żeby `https://192.168.1.19:8444/` działało **bez** wpisu w `/etc/hosts`, masz dwie drogi:

### Droga 1 — dodaj `192.168.1.19` jako Host w Ingressie

Edytuj `davtro-ingress` i dodaj drugą regułę:

```yaml
spec:
  rules:
  - host: davtro.local
    http: { ... }        # obecna reguła
  - host: 192.168.1.19   # nowa reguła dla IP
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port: { number: 80 }
```

Ale to brzydkie rozwiązanie — lepiej używać nazwy.

### Droga 2 (rekomendowana) — używaj `davtro.local`

Wpis w `/etc/hosts` na każdym kliencie:

```
192.168.1.19   davtro.local
```

I wtedy:
- `https://davtro.local:8444/` — frontend
- `https://davtro.local:8444/api/health` — FastAPI
- `https://davtro.local:8444/grafana` — Grafana
- `https://davtro.local:8444/kafka-ui` — Kafka UI
- `https://davtro.local:8444/pgadmin` — pgAdmin

**Jeden port, jeden host, różne ścieżki.** To jest poprawne użycie Ingressa.

## Poprawka do skryptu — dopisz `davtro.local` do `/etc/hosts` klienta

W `client-port-forward-without-an-argument-ing.sh` (albo `client-setup.sh`) możesz dodać krok:

```bash
# Dodaj wpis do /etc/hosts (idempotentnie)
if ! grep -q "davtro.local" /etc/hosts; then
  echo "192.168.1.19   davtro.local" | sudo tee -a /etc/hosts
  echo "  Dodano davtro.local do /etc/hosts"
else
  echo "  davtro.local juz jest w /etc/hosts"
fi
```

Wtedy klient od razu po `client-setup.sh` może wejść na `https://davtro.local:8444/`.

## Sprawdź teraz

Wklej wynik:

```bash
echo "=== curl z Host: davtro.local ==="
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/ 2>&1 | tail -30

echo "=== curl z Host: 192.168.1.19 ==="
curl -skv https://192.168.1.19:8444/ 2>&1 | tail -30

echo "=== ingressclass ==="
kubectl get ingressclass

echo "=== ingress controller ==="
kubectl get pods -A | grep -iE 'ingress|traefik|nginx|envoy|haproxy|contour'
```

**Wklej wynik** — wtedy powiem, czy wystarczy wpis w `/etc/hosts`, czy trzeba jeszcze poprawić Ingress.

## Podsumowanie

| Co | Status |
|----|--------|
| Forward na 8444 | ✅ działa |
| TLS handshake | ✅ działa |
| Ingress Controller odpowiada | ✅ działa |
| Routing po Hoscie `davtro.local` | ✅ skonfigurowany |
| Wpis w `/etc/hosts` na kliencie | ❌ **brakuje — to jest Twój problem** |
| `https://192.168.1.19:8444/` | ❌ 404 — bo Host się nie zgadza |
| `https://davtro.local:8444/` | ✅ **to wpisz w Chrome** |

**Nic nie jest zepsute.** Musisz tylko używać `davtro.local` zamiast IP — albo dodać wpis do `/etc/hosts`, albo wymusić Host w curl-em `--resolve`.

#

**Na maszynie z K8s** (tam, gdzie jest `kubectl` i gdzie odpalasz `port-forward`).

## Dlaczego

`curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/` odwołuje się do `127.0.0.1:8444`. To znaczy:

- `127.0.0.1` = **ta sama maszyna, na której uruchamiasz curl**,
- `8444` = port, na którym nasłuchuje `kubectl port-forward`.

A `kubectl port-forward` żyje **tylko na maszynie z K8s** (na tej, gdzie go uruchomiłeś). Dlatego curl z `--resolve ... 127.0.0.1` ma sens **tylko** na maszynie z K8s.

## Co się stanie na poszczególnych maszynach

### Na maszynie z K8s (tam, gdzie `port-forward` działa)

`127.0.0.1:8444` → trafia w `kubectl port-forward` → ten przekazuje do Ingress Controllera → ten routuje po Hoscie `davtro.local` → dostajesz odpowiedź.

```bash
# tu dziala:
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/
```

### Na maszynie klienta (inny komputer w LAN)

`127.0.0.1:8444` → nic tam nie nasłuchuje (bo `port-forward` jest na maszynie z K8s) → `Connection refused`.

```bash
# tu NIE zadziala z 127.0.0.1:
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/
# → Connection refused

# tu zadziala, ale z IP maszyny z K8s:
curl -skv --resolve davtro.local:8444:192.168.1.19 https://davtro.local:8444/
```

**Zwróć uwagę na różnicę:** `--resolve davtro.local:8444:192.168.1.19` (IP maszyny z K8s, nie `127.0.0.1`).

### W przeglądarce na kliencie

Najprościej:

```bash
# /etc/hosts na kliencie:
192.168.1.19   davtro.local
```

I wtedy w Chrome:
```
https://davtro.local:8444/
```

## Tabela — co gdzie

| Gdzie uruchamiasz | Co wpisać w `--resolve` | Przykład |
|-------------------|-------------------------|----------|
| **Maszyna z K8s** | `127.0.0.1` | `--resolve davtro.local:8444:127.0.0.1` |
| **Klient w LAN** (curl) | IP maszyny z K8s | `--resolve davtro.local:8444:192.168.1.19` |
| **Klient w LAN** (Chrome) | wpis w `/etc/hosts` | `192.168.1.19 davtro.local` |

## Dlaczego na maszynie z K8s działa `127.0.0.1`

Bo `kubectl port-forward` binduje na `0.0.0.0:8444` (bo masz `ADDR=0.0.0.0`), więc:
- `127.0.0.1:8444` — działa (loopback),
- `192.168.1.19:8444` — też działa (LAN).

Na maszynie z K8s **obie** wersje działają:

```bash
# obie dzialaja na maszynie z K8s:
curl -skv --resolve davtro.local:8444:127.0.0.1  https://davtro.local:8444/
curl -skv --resolve davtro.local:8444:192.168.1.19 https://davtro.local:8444/
```

# Co robić — kolejność

# Krok 1 — na maszynie z K8s

Upewnij się, że `port-forward` żyje:

```bash
ss -tlnp | grep 8444
```

Powinno być `kubectl ... 0.0.0.0:8444`.

Potem:

```bash
curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/ 2>&1 | tail -40
```

**Wklej wynik.** Jeśli tu dostaniesz `HTTP/2 200` — Ingress działa poprawnie, problem był tylko w Hoscie.

# Krok 2 — na maszynie klienta (inny komputer)

Sprawdź, czy widzisz maszynę z K8s:

```bash
curl -skv --resolve davtro.local:8444:192.168.1.19 https://davtro.local:8444/ 2>&1 | tail -40
```

Jeśli tu też działa — dodaj wpis do `/etc/hosts`:

```bash
echo "192.168.1.19   davtro.local" | sudo tee -a /etc/hosts
```

I w Chrome: `https://davtro.local:8444/`.

## Podsumowanie

| Gdzie | Co uruchomić |
|-------|--------------|
| **Maszyna z K8s** | `curl -skv --resolve davtro.local:8444:127.0.0.1 https://davtro.local:8444/` |
| **Klient** | `curl -skv --resolve davtro.local:8444:192.168.1.19 https://davtro.local:8444/` |
| **Chrome (klient)** | wpis w `/etc/hosts` + `https://davtro.local:8444/` |

**Zacznij od maszyny z K8s** — tam `127.0.0.1` ma sens, bo tam działa `port-forward`. Wklej wynik, to powiem, czy Ingress routuje poprawnie.