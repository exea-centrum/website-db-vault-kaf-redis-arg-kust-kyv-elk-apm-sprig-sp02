from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import asyncpg
import redis.asyncio as aioredis
import asyncio
import json
import os
from datetime import datetime, date
from .kafka_producer import get_producer, publish_event
import uvicorn

# KROK 5 (Auth): logowanie rezerwujacych - PBKDF2 (stdlib), sesje w Redis.
from .auth import hash_password, verify_password, new_session_token, SESSION_TTL_SECONDS, generate_random_password

# KROK 4 (Transit PII): szyfrowanie danych wrazliwych (imie, e-mail, telefon)
# przez Vault Transit Engine (key davtro-app). Fail-safe: gdy Vault/Transit sa
# chwilowo niedostepne, logujemy blad i zapisujemy plaintext - API nie pada.
try:
    from .transit_client import decrypt as transit_decrypt
    from .transit_client import encrypt as transit_encrypt

    _TRANSIT_IMPORTED = True
except Exception as _transit_exc:  # pragma: no cover - brak modulu/wersji
    transit_encrypt = None
    transit_decrypt = None
    _TRANSIT_IMPORTED = False
    print("transit_client niedostepny:", _transit_exc)

TRANSIT_ENABLED = os.getenv("VAULT_TRANSIT_ENABLED", "true").lower() in ("1", "true", "yes")
# Ciphertext Vault Transit ma prefiks "vault:vN:" - po nim rozpoznajemy zaszyfrowane pole.
_TRANSIT_PREFIX = "vault:v"

app = FastAPI(title="DavTro Rentals API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9094")

db_pool = None


def transit_ready():
    """Czy szyfrowanie PII przez Vault Transit jest aktywne."""
    return _TRANSIT_IMPORTED and TRANSIT_ENABLED


def encrypt_pii(value):
    """Szyfruje PII przed zapisem do bazy. Fallback: zwraca plaintext."""
    if value is None or not transit_ready():
        return value
    try:
        return transit_encrypt(str(value))
    except Exception as exc:
        print("encrypt_pii error:", exc)
        return value


def decrypt_pii(value):
    """Deszyfruje PII przy odczycie. Plaintext (stare wiersze) zwraca bez zmian."""
    if not isinstance(value, str) or not value.startswith(_TRANSIT_PREFIX):
        return value
    if not transit_ready():
        return value
    try:
        return transit_decrypt(value)
    except Exception as exc:
        print("decrypt_pii error:", exc)
        return value


def _read_creds_file(path):
    """Odczyt credsyw z pliku montowanego z sekretu ESO (rotowane przez Vault)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def db_creds():
    """Credsy DB: pliki z Vault (database/creds/davtro-app-rw) albo fallback na env."""
    user = (_read_creds_file(DB_USER_FILE) if DB_USER_FILE else None) or os.getenv("DB_USER")
    password = (_read_creds_file(DB_PASSWORD_FILE) if DB_PASSWORD_FILE else None) or os.getenv("DB_PASSWORD")
    if not user or not password:
        raise RuntimeError("Brak credsy DB: oczekiwano DB_USER_FILE/DB_PASSWORD_FILE (Vault/ESO) lub DB_USER/DB_PASSWORD")
    return user, password


# KROK 5b (Auth): haslo admina WYLACZNIE z Vaulta przez ESO (KV davtro/auth ->
# klucz ADMIN_PASSWORD w Secrecie davtro-secrets, ktory deployment juz ma w envFrom)
# albo z pliku ADMIN_PASSWORD_FILE. W repo NIE MA zadnego hasla - gdy Vault go
# nie dostarczy, konto admina dostaje haslo LOSOWE, generowane przy starcie
# (i jednorazowo pokazane w logu), dokladnie jak DB_PASSWORD w bootstrapie.
def admin_password():
    """Zwraca haslo admina z Vaulta/ESO albo None (gdy Vault go nie dostarczyl)."""
    file_path = os.getenv("ADMIN_PASSWORD_FILE")
    from_file = _read_creds_file(file_path) if file_path else None
    return from_file or os.getenv("ADMIN_PASSWORD") or None


def admin_password_or_generated():
    """Haslo z Vaulta; gdy brak - losowe (jednorazowo widoczne w logu)."""
    pwd = admin_password()
    if pwd is not None:
        return pwd
    pwd = generate_random_password()
    print(f"init_db: brak ADMIN_PASSWORD z Vaulta - wygenerowano losowe haslo admina: {pwd}")
    print("init_db: przejmij kontrole nad haslem: vault kv put davtro/auth ADMIN_PASSWORD='<haslo>'")
    return pwd


async def create_db_pool(user, password):
    return await asyncpg.create_pool(
        host=DB_HOST, port=DB_PORT, database=DB_NAME,
        user=user, password=password, min_size=5, max_size=20,
    )


async def watch_db_creds():
    """Rotacja dynamicznych credsyw z Vault: ESO odswieza sekret co refreshInterval,
    kubelet aktualizuje pliki w podzie. Po wykryciu zmiany budujemy nowa pule,
    podmieniamy global (routery i tak czytaja global przy kazdym zapytaniu)
    i zamykamy stara pule."""
    global db_pool
    last = db_creds()
    while True:
        await asyncio.sleep(30)
        try:
            current = db_creds()
            if current != last:
                old_pool = db_pool
                db_pool = await create_db_pool(*current)
                last = current
                if old_pool:
                    await old_pool.close()
                print("db_pool: przelaczono na nowe credsy z Vault")
        except Exception as exc:  # rotacja moze byc chwilowo niedostepna - trzymamy stara pule
            print("watch_db_creds error:", exc)
redis_pool = None
kafka_producer = None

class BookingCreate(BaseModel):
    property_id: int
    guest_name: str
    email: EmailStr
    phone: Optional[str] = None
    guests: int = 1
    check_in: date
    check_out: date
    total_price: float

class BookingResponse(BaseModel):
    id: str
    property_id: int
    property_name: str
    guest_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    check_in: str
    check_out: str
    total_price: Optional[float] = None
    status: str
    created_at: str
    # KROK 5 (Auth): masked=True -> dane gościa (imie/email/telefon/cena) ukryte,
    # bo widz jest zalogowany jako inny uzytkownik (albo niezalogowany).
    masked: bool = False
    # mine=True -> to rezerwacja zalogowanego uzytkownika (odznaka "Moja rezerwacja").
    mine: bool = False

class AuthUser(BaseModel):
    id: int
    username: str
    role: str
    full_name: Optional[str] = None
    email: Optional[str] = None

class AuthRequest(BaseModel):
    username: str
    password: str

class RegisterRequest(AuthRequest):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

class AdminSetPasswordRequest(BaseModel):
    username: str
    new_password: str

@app.on_event("startup")
async def startup():
    global db_pool, redis_pool, kafka_producer
    user, password = db_creds()
    db_pool = await create_db_pool(user, password)
    redis_pool = aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}", decode_responses=True)
    # KROK 11: klient mTLS (confluent-kafka) na listenerze Kafka 9094.
    kafka_producer = get_producer()
    asyncio.create_task(watch_db_creds())
    await init_db()

@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer:
        kafka_producer.flush(5)

async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(255), guests INT, user_id INT, username VARCHAR(100), check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
        # KROK 4 (Transit PII) FIX: szyfrogram Vault Transit ("vault:v1:...") ma ~65-90 znakow,
        # a kolumna phone byla VARCHAR(50) -> kazdy INSERT padal z StringDataRightTruncation.
        # Idempotentna migracja baz utworzonych starsza wersja kodu (no-op, gdy juz 255).
        # ALTER wymaga wlasnosci tabeli, a API laczy sie dynamicznymi credsami z Vaulta
        # (davtro-app-rw: SELECT/INSERT/UPDATE/DELETE, bez ALTER) - dlatego best-effort:
        # brak uprawnien logujemy i dzialamy dalej (swieza baza ma VARCHAR(255) w DDL).
        try:
            await conn.execute("ALTER TABLE bookings ALTER COLUMN phone TYPE VARCHAR(255)")
        except Exception as exc:
            print("init_db: pomijam ALTER bookings.phone (brak wlasnosci tabeli):", exc)
        # KROK 5 (Auth): konta rezerwujacych + powiazanie rezerwacji z kontem
        # (user_id/username), zeby jeden rezerwujacy nie widzial danych drugiego.
        await conn.execute("""CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY, username VARCHAR(100) UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, role VARCHAR(20) NOT NULL DEFAULT 'user',
            full_name VARCHAR(255), email VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW())""")
        # KROK 5 (Auth): kolumny user_id/username sa opcjonalne - aplikacja laczy sie
        # dynamicznymi credsami z Vaulta, ktore moga nie miec prawa ALTER (tabela
        # bookings nalezy do wczesniejszego, wygaslego uzytkownika Vault). API musi
        # wtedy dalej dzialac (bez powiazania rezerwacji z kontem).
        global BOOKINGS_HAS_USER_ID, BOOKINGS_HAS_USERNAME
        for ddl in ("ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id INT",
                    "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS username VARCHAR(100)"):
            try:
                await conn.execute(ddl)
            except Exception as exc:
                print("init_db: pomijam", ddl, ":", exc)
        BOOKINGS_HAS_USER_ID = bool(await conn.fetchval(
            "SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='user_id'"))
        BOOKINGS_HAS_USERNAME = bool(await conn.fetchval(
            "SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='username'"))
        if not (BOOKINGS_HAS_USER_ID and BOOKINGS_HAS_USERNAME):
            print("init_db: UWAGA - brak kolumn user_id/username w bookings (brak praw ALTER); "
                  "rezerwacje nie beda powiazane z kontami, dopoki tabela nalezy do innego uzytkownika")
        elif await conn.fetchval("SELECT COUNT(*) FROM bookings WHERE user_id IS NULL") > 0:
            # KROK 5b (Backfill): rezerwacje utworzone przed dodaniem kolumn - przypisujemy
            # je do kont po e-mailu gościa (obie strony deszyfrowane Vault Transitem).
            # Bez tego wlasciciel widzialby wlasne rezerwacje jako "Zastrzezone".
            try:
                orphan_rows = await conn.fetch(
                    "SELECT id, email FROM bookings WHERE user_id IS NULL AND email IS NOT NULL")
                user_rows = await conn.fetch("SELECT id, email FROM users WHERE email IS NOT NULL")
                email_to_uid = {}
                for u in user_rows:
                    try:
                        email_to_uid[(decrypt_pii(u["email"]) or "").strip().lower()] = u["id"]
                    except Exception:
                        continue
                linked = 0
                for b in orphan_rows:
                    try:
                        b_email = (decrypt_pii(b["email"]) or "").strip().lower()
                    except Exception:
                        continue
                    uid = email_to_uid.get(b_email)
                    if uid is not None:
                        await conn.execute(
                            """UPDATE bookings SET user_id=$1,
                                   username=(SELECT username FROM users WHERE id=$1)
                               WHERE id=$2""", uid, b["id"])
                        linked += 1
                if linked:
                    print(f"init_db: backfill - przypisano {linked} rezerwacji do kont (po e-mailu)")
            except Exception as exc:
                print("init_db: backfill rezerwacji pominiony:", exc)
        count = await conn.fetchval("SELECT COUNT(*) FROM properties")
        if count == 0:
            await conn.execute("""INSERT INTO properties (id, name, location, price, guests, description, amenities) VALUES
                (1, 'Apartament Premium - Warszawa', 'warsaw', 450, 4, 'Luksusowy apartament w centrum', '["WiFi","Klimatyzacja","Balkon","Parking"]'),
                (2, 'Studio Modern - Krakow', 'krakow', 320, 2, 'Stylowe studio obok Rynku', '["WiFi","Smart TV","Kuchnia"]'),
                (3, 'Villa nad Morzem - Gdansk', 'gdansk', 680, 6, 'Willa 200m od plazy', '["WiFi","Ogrodek","Grill","Parking"]'),
                (4, 'Loft Industrial - Wroclaw', 'wroclaw', 280, 3, 'Industrialny loft', '["WiFi","Projektor","Klimatyzacja"]'),
                (5, 'Penthouse View - Warszawa', 'warsaw', 850, 4, 'Ekskluzywny penthouse', '["WiFi","Basen","Silownia","Concierge"]'),
                (6, 'Apartament Royal - Krakow', 'krakow', 390, 4, 'Elegancki apartament w Kazimierzu', '["WiFi","Klimatyzacja","Balkon"]')
                ON CONFLICT DO NOTHING""")
        # KROK 5 (Auth): konto administratora (widzi wszystkie dane gości).
        # Seed per-username: dziala tez, gdy tabela users ma juz innych uzytkownikow
        # (np. po uruchomieniu starszej wersji aplikacji bez seeda admina).
        admin_user = os.getenv("ADMIN_USERNAME", "admin")
        # KROK 5b: haslo WYLACZNIE z Vaulta; gdy Vault go nie dostarczyl -
        # losowe generowane przy starcie (jedyne miejsce, gdzie je widać: log startu).
        admin_pass = admin_password_or_generated()
        if await conn.fetchval("SELECT 1 FROM users WHERE username=$1", admin_user) is None:
            await conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ($1,$2,'admin') ON CONFLICT (username) DO NOTHING",
                admin_user, hash_password(admin_pass))
            print(f"init_db: utworzono konto admina '{admin_user}'")

@app.get("/api/health")
async def health():
    redis_ok = await redis_pool.ping()
    async with db_pool.acquire() as conn:
        db_ok = await conn.fetchval("SELECT 1")
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok, "kafka": kafka_producer is not None, "transit": transit_ready()}

@app.get("/api/properties")
async def get_properties():
    cache_key = "properties:all"
    cached = await redis_pool.get(cache_key)
    if cached: return json.loads(cached)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM properties ORDER BY id")
    properties = [{"id": r["id"], "name": r["name"], "location": r["location"], "price": float(r["price"]), "guests": r["guests"], "description": r["description"], "amenities": json.loads(r["amenities"])} for r in rows]
    await redis_pool.setex(cache_key, 300, json.dumps(properties))
    return properties

# KROK 5 (Auth): sesje trzymane w Redis (session:<token>, TTL 24h).
SESSION_KEY_PREFIX = "session:"
# Czy tabela bookings ma kolumny powiazania z kontem (wykrywane w init_db - kolumny
# moga nie istniec, gdy brak praw ALTER do tabeli utworzonej przez innego uzytkownika).
BOOKINGS_HAS_USER_ID = True
BOOKINGS_HAS_USERNAME = True


async def get_current_user(request: Request) -> Optional[AuthUser]:
    """Odczytuje usera z naglowka Authorization: Bearer <token> (Redis)."""
    auth_header = request.headers.get("authorization") or ""
    if not auth_header.lower().startswith("bearer "):
        return None
    token = auth_header[7:].strip()
    if not token:
        return None
    raw = await redis_pool.get(SESSION_KEY_PREFIX + token)
    if not raw:
        return None
    data = json.loads(raw)
    return AuthUser(id=data["id"], username=data["username"], role=data["role"],
                    full_name=data.get("full_name"), email=data.get("email"))


async def require_user(request: Request) -> AuthUser:
    """Rezerwacja wymaga zalogowania (KROK 5)."""
    user = await get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Wymagane zalogowanie")
    return user


def is_admin(user: Optional[AuthUser]) -> bool:
    return user is not None and user.role == "admin"


def owns_booking(user: Optional[AuthUser], row_user_id) -> bool:
    """Wlasciciel rezerwacji (albo admin) widzi pelne dane; inni - tylko maske."""
    if user is None:
        return False
    if user.role == "admin":
        return True
    return row_user_id is not None and int(row_user_id) == int(user.id)

# Wartosci zwracane dla "obcych" rezerwacji - dane gościa sa zastrzezone.
MASKED_GUEST_NAME = "Zastrzeżone (dane gościa ukryte)"


@app.post("/api/auth/register")
async def register_user(payload: RegisterRequest):
    """Rejestracja rezerwujacego + natychmiastowy login (token do Redisa)."""
    username = payload.username.strip()
    if len(username) < 3 or len(payload.password) < 6:
        raise HTTPException(status_code=400, detail="Login min. 3 znaki, haslo min. 6 znakow")
    full_name = encrypt_pii(payload.full_name) if payload.full_name else None
    email = encrypt_pii(payload.email) if payload.email else None
    async with db_pool.acquire() as conn:
        exists = await conn.fetchval("SELECT 1 FROM users WHERE username=$1", username)
        if exists:
            raise HTTPException(status_code=409, detail="Ten login jest juz zajety")
        user_id = await conn.fetchval(
            """INSERT INTO users (username, password_hash, role, full_name, email)
               VALUES ($1,$2,'user',$3,$4) RETURNING id""",
            username, hash_password(payload.password), full_name, email)
    token = new_session_token()
    await redis_pool.setex(SESSION_KEY_PREFIX + token, SESSION_TTL_SECONDS,
                           json.dumps({"id": user_id, "username": username, "role": "user",
                                       "full_name": decrypt_pii(full_name) if full_name else None,
                                       "email": decrypt_pii(email) if email else None}))
    return {"token": token, "user": AuthUser(id=user_id, username=username, role="user",
                                             full_name=decrypt_pii(full_name) if full_name else None,
                                             email=decrypt_pii(email) if email else None)}


@app.post("/api/auth/login")
async def login_user(payload: AuthRequest):
    """Login/haslo -> token sesyjny w Redis (Authorization: Bearer)."""
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE username=$1", payload.username.strip())
        # Bootstrap-awaryjny: brak konta admina (np. seed nie przeszedl przy pierwszym
        # starcie starszej wersji) -> tworzymy je z ADMIN_PASSWORD przy probie logowania.
        if row is None and payload.username.strip() == os.getenv("ADMIN_USERNAME", "admin"):
            admin_user = payload.username.strip()
            await conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ($1,$2,'admin') ON CONFLICT (username) DO NOTHING",
                admin_user, hash_password(admin_password_or_generated()))
            print(f"login: bootstrap konta admina '{admin_user}' (brak konta przy logowaniu)")
            row = await conn.fetchrow("SELECT * FROM users WHERE username=$1", admin_user)
    if row is None or not verify_password(payload.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Nieprawidlowy login lub haslo")
    full_name = decrypt_pii(row["full_name"]) if row["full_name"] else None
    email = decrypt_pii(row["email"]) if row["email"] else None
    token = new_session_token()
    await redis_pool.setex(SESSION_KEY_PREFIX + token, SESSION_TTL_SECONDS,
                           json.dumps({"id": row["id"], "username": row["username"],
                                       "role": row["role"], "full_name": full_name, "email": email}))
    return {"token": token, "user": AuthUser(id=row["id"], username=row["username"],
                                             role=row["role"], full_name=full_name, email=email)}


@app.post("/api/auth/logout")
async def logout_user(request: Request):
    auth_header = request.headers.get("authorization") or ""
    if auth_header.lower().startswith("bearer "):
        await redis_pool.delete(SESSION_KEY_PREFIX + auth_header[7:].strip())
    return {"ok": True}


@app.get("/api/auth/me")
async def me(request: Request):
    user = await get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Brak aktywnej sesji")
    return user


@app.post("/api/auth/change-password")
async def change_password(payload: ChangePasswordRequest, request: Request):
    """Zmiana wlasnego hasla - wymaga aktualnego hasla (KROK 5b)."""
    user = await require_user(request)
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Nowe haslo musi miec min. 6 znakow")
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT password_hash FROM users WHERE id=$1", user.id)
        if row is None or not verify_password(payload.current_password, row["password_hash"]):
            raise HTTPException(status_code=401, detail="Aktualne haslo jest nieprawidlowe")
        await conn.execute("UPDATE users SET password_hash=$1 WHERE id=$2",
                           hash_password(payload.new_password), user.id)
    return {"ok": True, "message": "Haslo zmienione"}


@app.post("/api/auth/admin/set-password")
async def admin_set_password(payload: AdminSetPasswordRequest, request: Request):
    """Tylko admin: reset hasla dowolnego uzytkownika (KROK 5b)."""
    user = await require_user(request)
    if not is_admin(user):
        raise HTTPException(status_code=403, detail="Tylko administrator moze zmieniac cudze hasla")
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Nowe haslo musi miec min. 6 znakow")
    async with db_pool.acquire() as conn:
        found = await conn.fetchval("SELECT 1 FROM users WHERE username=$1", payload.username.strip())
        if found is None:
            raise HTTPException(status_code=404, detail="Nie ma takiego uzytkownika")
        await conn.execute("UPDATE users SET password_hash=$1 WHERE username=$2",
                           hash_password(payload.new_password), payload.username.strip())
    return {"ok": True, "message": f"Haslo uzytkownika {payload.username.strip()} zostalo zmienione"}


@app.post("/api/bookings")
async def create_booking(booking: BookingCreate, background_tasks: BackgroundTasks, request: Request):
    # KROK 5 (Auth): rezerwacja wymaga zalogowania - inaczej nie da sie ukryc
    # danych gościa przed innymi rezerwujacymi.
    user = await require_user(request)
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    # FIX: booking.dict() zostawial obiekty datetime.date, na ktorych json.dumps()
    # rzucal TypeError ("Object of type date is not JSON serializable") -> 500.
    # model_dump(mode="json") konwertuje date na ISO-8601 (str), wiec SETEX do Redisa
    # i events do Kafki przechodza bez zmian w przeplywie.
    booking_data = booking.model_dump(mode="json")
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    # KROK 4 (Transit PII): dane osobowe (imie, e-mail, telefon) zapisujemy do
    # PostgreSQL zaszyfrowane kluczem Vault Transit (key davtro-app). Kafka i Redis
    # dostaja plaintext, bo message-processor wysyla z niego e-maile.
    async with db_pool.acquire() as conn:
        # KROK 5: powiazanie rezerwacji z kontem tylko gdy kolumny istnieja
        # (gdy brak praw ALTER do tabeli zapisujemy bez user_id/username).
        if BOOKINGS_HAS_USER_ID and BOOKINGS_HAS_USERNAME:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests, user_id, username,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, user.id, user.username, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending",
            )
        else:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending",
            )
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    publish_event("bookings-created", {"event": "booking_created", "booking_id": booking_id, "property_id": booking.property_id, "guest_name": booking.guest_name, "email": booking.email, "phone": booking.phone, "check_in": str(booking.check_in), "check_out": str(booking.check_out), "nights": nights, "total_price": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    publish_event("email-invoices", {"event": "invoice_request", "booking_id": booking_id, "email": booking.email, "guest_name": booking.guest_name, "total_price": float(booking.total_price), "property_id": booking.property_id, "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    publish_event("marketing-actions", {"event": "new_booking", "property_id": booking.property_id, "guest_email": booking.email, "guest_name": booking.guest_name, "booking_value": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="", guest_name=booking.guest_name, email=booking.email, check_in=str(booking.check_in), check_out=str(booking.check_out), total_price=booking.total_price, status="pending", created_at=datetime.now().isoformat())

@app.get("/api/bookings")
async def get_bookings(request: Request, property_id: Optional[int] = None):
    """KROK 5 (Auth): wlasciciel rezerwacji i admin widza pelne dane gościa
    (imie, email, telefon, kwote). Pozostali dostaja wiersz zamaskowany -
    w kolach kalendarza daty zostaja, bo potrzebne do pokazania dostepnosci."""
    user = await get_current_user(request)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id WHERE ($1::int IS NULL OR b.property_id = $1::int) ORDER BY b.created_at DESC",
            property_id)
    result = []
    for r in rows:
        # .get() - kolumna user_id moze nie istniec w starszej tabeli bookings
        is_own = user is not None and r.get("user_id") is not None and int(r.get("user_id")) == int(user.id)
        if owns_booking(user, r.get("user_id")):
            result.append(BookingResponse(
                id=r["id"], property_id=r["property_id"], property_name=r["property_name"],
                guest_name=decrypt_pii(r["guest_name"]), email=decrypt_pii(r["email"]),
                phone=decrypt_pii(r["phone"]) if r["phone"] else None,
                check_in=str(r["check_in"]), check_out=str(r["check_out"]),
                total_price=float(r["total_price"]), status=r["status"],
                created_at=str(r["created_at"]), masked=False, mine=is_own and user.role != "admin"))
        else:
            result.append(BookingResponse(
                id=r["id"], property_id=r["property_id"], property_name=r["property_name"],
                guest_name=MASKED_GUEST_NAME, email=None, phone=None,
                check_in=str(r["check_in"]), check_out=str(r["check_out"]),
                total_price=None, status=r["status"],
                created_at=str(r["created_at"]), masked=True, mine=False))
    return result

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
