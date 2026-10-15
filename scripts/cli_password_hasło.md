## Jak wyciągać hasła kubectl (komendy) to jest przydład dla mojej infry env

```bash
NS=davtro02
K="microk8s.kubectl"   # u Ciebie; zamiennie: kubectl

# 1. Hasło wspólne dla pgAdmina i Postgresa + użytkownik
$K -n $NS get secret davtro-secrets -o jsonpath='{.data.DB_USER}'   | base64 -d; echo
$K -n $NS get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo

# 2. Wszystkie pola sekretu naraz (czytelnie)
$K -n $NS get secret davtro-secrets -o json | \
  python3 -c "import json,base64,sys; [print(k,'=',base64.b64decode(v).decode()) for k,v in json.load(sys.stdin)['data'].items()]"

# 3. Skąd pgAdmin bierze hasło (weryfikacja env w Deploymentcie)
$K -n $NS get deploy pgadmin -o jsonpath='{.spec.template.spec.containers[0].env}'; echo

# 4. Skąd PostgreSQL bierze user/hasło (StatefulSet)
$K -n $NS get sts postgres-db -o jsonpath='{.spec.template.spec.containers[0].env}'; echo

# 5. Sprawdzenie wewnątrz żywego Postgresa (że hasło z sekretu = hasło w bazie)
$K -n $NS exec postgres-db-0 -it -- psql -U davtro -d davtro_rentals -c '\du'

# 6. Hasło zapisane w samym Vaultie (źródło prawdy, w podzie vault-0)
$K -n $NS exec vault-0 -it -- sh -c 'vault kv get -field=DB_PASSWORD davtro/db'
# (root token do Vaulta: plik /vault/data/bootstrap-keys w PVC vaulta)

# 7. Credsy dynamiczne aplikacji (rotowane co 30 min - nie mylić z adminem)
$K -n $NS get secret fastapi-db-creds -o jsonpath='{.data.username}' | base64 -d; echo
$K -n $NS get secret fastapi-db-creds -o jsonpath='{.data.password}' | base64 -d; echo
```

Uwagi:
- Sekret `davtro-secrets` jest odtwarzany przez External Secrets Operator (refresh 1h) — ręczna zmiana w sekrecie zostanie nadpisana. Aby trwale zmienić hasło: `vault kv put davtro/db DB_USER=davtro DB_PASSWORD='<nowe>'` i czekać na odświeżenie ESO (bootstraper sam robi restart pgadmin/exporter/spring).
- Hasło w sekrecie jest **tym samym** hasłem, którego używa pgAdmin do logowania `admin@davtro.pl`.
- W historii gita w katalogu `scripts/all-in-one/*/manifests/base/pgadmin.yaml` oraz `scripts/istio/*` są kopie manifestów, ale wszystkie też pobierają hasło z sekretu — żadnego jawnego hasła w plikach projektu nie ma.


Wklejanie z kopiuj-wklej bywa zawodne — bezpieczniej przepisać albo sprawdzić znaki po znaku (bez spacji na końcu).

## Szybka ściągawka „które hasło do czego"

```bash
K="microk8s.kubectl"; NS=davtro02

# hasło pgAdmina == hasło superusera Postgres (davtro)
$K -n $NS get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo

# hasło admina panelu rezerwacji (aplikacja web, NIE pgAdmin)
$K -n $NS get secret davtro-secrets -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo

# weryfikacja, co faktycznie siedzi w podzie pgAdmina
$K -n $NS exec deploy/pgadmin -- printenv PGADMIN_DEFAULT_EMAIL PGADMIN_DEFAULT_PASSWORD
```

Uwaga: `exec deploy/pgadmin` zadziała tylko gdy masz jednego replice (masz — `replicas: 1`).






# Poprawiona komenda — z **wypisaniem danych z tabeli `users`**

Twoja komenda `\du` to **lista ról bazy**, a **nie** tabela `users`. Poniżej **właściwe** wersje.

---

## Komenda 1: **Z poda `postgres-db-0`** (bez hasła, `peer` auth)

**Uwaga:** `kubectl exec ... -- psql -U davtro` — **`davtro`** musi **mieć hasło** (bo to **nie `peer`** auth). Jeśli **`davtro` ma hasło** — **zapyta** o nie (interaktywnie) **albo** musisz je podać.

**Najprościej** — **jako `postgres`** (jeśli obraz **ma usera `postgres`** i `peer`/`trust`):

```bash
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  psql -U postgres -d davtro_rentals -c 'SELECT id, username, role FROM users;'
```

**Jeśli `postgres` nie istnieje** (albo `peer` nie działa) — użyj **`davtro`** + hasło:

```bash
# Wyciagnij DB_PASSWORD z Vaulta:
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

# Uzyj go:
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c 'SELECT id, username, role FROM users;'
```

**Uwaga:** `env PGPASSWORD=...` **przed `psql`** — ustawia zmienną **wewnątrz poda**. To **obejście** dla `kubectl exec`, bo **nie da się** przekazać env **bez `env`**.

---

## Komenda 2: **Wszystko z tabeli `users`** (z `PGPASSWORD`)

```bash
# Wyciagnij DB_PASSWORD z Vaulta:
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

# Wyciagnij DB_USER:
DB_USER=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_USER}' | base64 -d)

# Wypisz wszystko z users:
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d davtro_rentals -c 'SELECT * FROM users;'
```

**Wynik, np.:**

```
 id |     username     |         password_hash          | role  | full_name | email | created_at
----+------------------+--------------------------------+-------+-----------+-------+------------
  1 | admin@davtro.pl  | pbkdf2:sha256:...              | admin |           |       |
  2 | user@example.com | pbkdf2:sha256:...              | user  |           |       |
```

**Jeśli `full_name` / `email` są `vault:v1:...`** — to **Vault Transit**, **odszyfrujesz** przez **API FastAPI** (`GET /api/auth/me`).

---

## Komenda 3: **Z klienta** (przez port-forward)

```bash
# 1) Na serwerze — odpal port-forward Postgresa:
/snap/bin/microk8s kubectl port-forward --address 0.0.0.0 \
  -n davtro02 svc/postgres-clusterip 5432:5432 &
# Zostaw w tle (albo w osobnym terminalu).

# 2) Wyciagnij haslo (na serwerze):
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)
echo "DB_PASS=$DB_PASS"

# 3) Na kliencie (david@lmde) — uzyj psql:
PGPASSWORD="$DB_PASS" psql -h 192.168.1.19 -p 5432 -U davtro -d davtro_rentals -c 'SELECT id, username, role FROM users;'
```

---

## Komenda 4: **Wszystko z `users` + szyfrowane pola** (pełny wypis)

```bash
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -x -c 'SELECT * FROM users;'
```

**`-x`** = **expanded output** (każda kolumna w osobnej linii — czytelniejsze):

```
-[ RECORD 1 ]-+---------------------------
id            | 1
username      | admin@davtro.pl
password_hash | pbkdf2:sha256:600000$...
role          | admin
full_name     | vault:v1:...
email         | vault:v1:...
created_at    | 2026-10-14 05:15:00
-[ RECORD 2 ]-+---------------------------
id            | 2
username      | user@example.com
...
```

---

## Komenda 5: **Struktura tabeli `users`** (żeby wiedzieć, jakie kolumny wybrać)

```bash
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c '\d users'
```

**Wynik pokaże wszystkie kolumny** (`id`, `username`, `password_hash`, `role`, `full_name`, `email`, `created_at`), **typy**, **indeksy**.

---

## Komenda 6: **`\du`** — lista ról bazy (Twoja oryginalna, ale **poprawna**)

**Jeśli chcesz `\du`** (role bazy, **nie** tabela `users`):

```bash
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  psql -U postgres -d davtro_rentals -c '\du'
```

**Albo** — **jeśli `davtro` ma hasło**:

```bash
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c '\du'
```

**Wynik:**

```
        List of roles
 Role name |                         Attributes
-----------+------------------------------------------------------------
 davtro    | Superuser
 postgres  | Superuser
 v-token-...| 
```

**To są role PostgreSQL** (konta bazy), **nie użytkownicy aplikacji**.

---

## Podsumowanie — **jedna komenda, która robi to, co chcesz**

**Wklej to na serwerze** (jedna linia, **wielolinijkowa** — z `\` na końcu):

```bash
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d) && \
DB_USER=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_USER}' | base64 -d) && \
echo "=== Tabele ===" && \
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- env PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d davtro_rentals -c '\dt' && \
echo && \
echo "=== Struktura users ===" && \
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- env PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d davtro_rentals -c '\d users' && \
echo && \
echo "=== Dane z users ===" && \
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- env PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d davtro_rentals -c 'SELECT * FROM users;'
```

**To wypisze:**

1. **Wszystkie tabele** (`\dt`),
2. **Strukturę `users`** (`\d users`),
3. **Dane z `users`** (`SELECT * FROM users;`).

**Wklej output** — powiem Ci:

- **jakie są kolumny w `users`**,
- **ilu userów** jest,
- **jakie role** mają,
- **jak odszyfrować PII** (jeśli `vault:v1:...`).

**Jeśli `DB_PASSWORD` nie działa** — spróbuj `ADMIN_PASSWORD`:

```bash
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d)
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c '\dt'
```
# Cieszę się, że działa! 🎉

## Krótkie podsumowanie — co ustaliliśmy w tej sesji

**Konto pgAdmin (`admin@davtro.pl`):**
- Było `locked = 1` (zablokowane) → **odblokowane** przez `UPDATE user SET locked=0`,
- Hasło **zresetowane** do `NoweHasloPgAdmin123` (przez `/venv/bin/python3` w podzie pgAdmina).

**PostgreSQL (główne credsy):**
- Wyciągasz hasło przez:
  ```bash
  /snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
  ```
- `psql` w podzie (bez port-forward) przez `env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals`.

---

## 🔐 Zanim zamkniesz ten wątek — **dwie ważne rzeczy do zrobienia**

### 1. **ZMIEŃ HASŁO `ADMIN_PASSWORD`** (bo wyciekło w czacie)

`slodkadziurkazwypiekami` było **jawne** w historii czatu. **Zmień je** w Vaultcie:

```bash
/snap/bin/microk8s kubectl -n davtro02 exec vault-0 -- \
  vault kv put davtro/auth ADMIN_PASSWORD="TwojeNoweBezpieczneHaslo-K3y!"
```
```bash
/snap/bin/microk8s kubectl -n davtro02 exec vault-0 -- \
  vault kv put davtro/auth ADMIN_PASSWORD="TwojaNowaSlodkadziurkapelnawypiekow"
```
**Po zmianie:**
- **ESO odświeży** `davtro-secrets` (do ~1h — albo wymuś: `kubectl annotate externalsecret davtro-secrets force-sync="$(date +%s)" --overwrite`),
- **Aplikacje** (FastAPI, Spring) **nie wymagają restartu** — biorą env z Secretu przy starcie, ale **stare hasło** do Postgresa **dalej działa** (bo `ALTER USER` się nie dzieje automatycznie).

**Uwaga:** pgAdmin ma **własną bazę** (`pgadmin4.db`) — zmiana `ADMIN_PASSWORD` w Vaultcie **NIE zmieni** hasła w pgAdminie. **Trzeba osobno**:
- **w UI pgAdmina** (avatar → Change password), **albo**
- **resetem** jak wcześniej (`/venv/bin/python3 -c "..."`).

### 2. **Zabezpiecz `DB_PASSWORD`**

To **główne hasło bazy `davtro`**. Też nie powinno wyciekać. **Sprawdź, czy nie jest nigdzie** zapisane w plaintext:

```bash
# Sprawdz, czy nie ma go w repo:
cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
git log -S 'DB_PASSWORD' --oneline | head -5

# Sprawdz, czy nie ma go w plikach:
grep -r 'davtro-app-rw\|DB_PASSWORD' --include="*.yaml" --include="*.py" --include="*.sh" . | grep -v 'vault-bootstrap.yaml' | head -10
```

**Jeśli jest** — **usuń** i **przenieś do Vaulta** (jeśli już tam nie ma).

---

## 💡 Ściąga — najczęstsze komendy (do zapisania)

```bash
# === POSTGRES ===

# Wyciagnij DB_PASSWORD:
DB_PASS=$(/snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)

# Polacz sie z bazy (wewnatrz poda):
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals

# Lista tabel:
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c '\dt'

# Dane z users:
/snap/bin/microk8s kubectl -n davtro02 exec -it postgres-db-0 -- \
  env PGPASSWORD="$DB_PASS" psql -U davtro -d davtro_rentals -c 'SELECT id, username, role FROM users;'


# === PGADMIN (reset hasla) ===

# Wejdz do poda:
/snap/bin/microk8s kubectl -n davtro02 exec -it deploy/pgadmin -- sh

# Zresetuj haslo:
/venv/bin/python3 -c "import sqlite3; from werkzeug.security import generate_password_hash; db=sqlite3.connect('/var/lib/pgadmin/pgadmin4.db'); cur=db.cursor(); h=generate_password_hash('NoweHaslo', method='pbkdf2:sha256'); cur.execute('UPDATE user SET password=?, locked=0 WHERE email=?', (h, 'admin@davtro.pl')); db.commit(); print('OK'); db.close()"


# === VAULT ===

# Status Vaulta:
/snap/bin/microk8s kubectl -n davtro02 exec vault-0 -- vault status

# Sekrety KV:
/snap/bin/microk8s kubectl -n davtro02 exec vault-0 -- vault kv list davtro/
/snap/bin/microk8s kubectl -n davtro02 exec vault-0 -- vault kv get davtro/auth


# === PORT-FORWARD ===

# Wszystkie forwardy (pelna paczka):
./scripts/Port-forwarding-deepseek-cleanup-sierot.sh

# Tylko Gateway HTTPS:
./scripts/Port-forwarding-deepseek-cleanup-sierot.sh https-gateway 8443

# Sprzatanie sierot (poza 8080, 10443):
./scripts/Port-forwarding-deepseek-cleanup-sierot.sh cleanup


# === CERTY ===

# Wyciagnij CA Gatewaya:
./scripts/Port-forwarding-deepseek-cleanup-sierot.sh extract-tls davtro-gateway-tls "" istio-system
# -> /tmp/cert-davtro/davtro-gateway-tls-ca.crt

# Skopiuj na klienta:
scp david@192.168.1.19:/tmp/cert-davtro/davtro-gateway-tls-ca.crt ~/davtro-ca.crt

# Zaimportuj na kliencie:
./scripts/Client-import-certs-deepseek.sh ~/davtro-ca.crt
```

---

## 📝 Jeśli chcesz wrócić do tego wątku później

**Wklej mi na start:**

```bash
# 1) Stan klastra:
/snap/bin/microk8s kubectl -n davtro02 get pods
/snap/bin/microk8s kubectl -n argocd get application

# 2) Stan forwardow:
ps aux | grep port-forward | grep -v grep
sudo ss -tlnp | grep -E '8443|8243|5432|8080'
```

**I napisz, co chcesz zrobić** — pomogę.

---

## 🚀 Co dalej (opcjonalnie)

**Jeśli chcesz iść dalej z projektem:**

1. **Backupy Postgresa** — `pg_dump` + CronJob (jak `vault-snapshot`),
2. **Monitoring Postgresa** — `postgres-exporter` już masz, sprawdź w Grafanie,
3. **Rotacja dynamicznych creds** — Vault database engine **już to robi** (`davtro-app-rw`, TTL 1h),
4. **HTTPS na Postgresie** — `sslmode=require` (obecnie `disable` w `vault-bootstrap`),
5. **Restore z backupu Vaulta** — `vault operator raft snapshot restore`.

**Ale to na spokojnie.** **Na dziś — masz wszystko, co potrzebne.**

**Dzięki za cierpliwość!** 🎯 Jeśli coś jeszcze — pisz.