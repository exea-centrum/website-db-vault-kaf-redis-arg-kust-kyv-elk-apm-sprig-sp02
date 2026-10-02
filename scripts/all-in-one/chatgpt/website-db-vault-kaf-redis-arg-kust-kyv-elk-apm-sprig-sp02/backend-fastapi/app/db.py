import os
import threading
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")

# KROK 3: dynamiczne credsy z Vault (database/creds/davtro-app-rw) dostarczane przez ESO.
# Sekret montowany jest jako PLIKI (DB_USER_FILE / DB_PASSWORD_FILE); kubelet odswieza
# montaz po rotacji, a get_engine() przebudowuje silnik po wykryciu zmiany tresci.
# Fallback dla dev lokalnego: DB_USER/DB_PASSWORD z env albo pelny DATABASE_URL.
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
DATABASE_URL = os.getenv("DATABASE_URL")  # tylko dev lokalny (statyczne credsy)


def _read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def current_creds():
    if DATABASE_URL:
        return DATABASE_URL
    user = (_read_file(DB_USER_FILE) if DB_USER_FILE else None) or os.getenv("DB_USER")
    password = (_read_file(DB_PASSWORD_FILE) if DB_PASSWORD_FILE else None) or os.getenv("DB_PASSWORD")
    if not user or not password:
        raise RuntimeError(
            "Brak credsy DB: oczekiwano DB_USER_FILE/DB_PASSWORD_FILE (Vault/ESO) "
            "lub DB_USER/DB_PASSWORD/DATABASE_URL (dev lokalny)"
        )
    return f"postgresql://{user}:{password}@{DB_HOST}:{DB_PORT}/{DB_NAME}"


_engine_cache = {"key": None, "engine": None}
_cache_lock = threading.Lock()


def get_engine():
    url = current_creds()
    with _cache_lock:
        if _engine_cache["key"] != url:
            old = _engine_cache["engine"]
            _engine_cache["engine"] = create_engine(url, pool_pre_ping=True, pool_recycle=300)
            _engine_cache["key"] = url
            if old is not None:
                old.dispose()
        return _engine_cache["engine"]


def get_session():
    """Sesja zwiazana z AKTUALNYM silnikiem - po rotacji credsyw z Vaulta
    kolejne wywolania lacza sie juz nowym, tymczasowym uzytkownikiem."""
    return sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)()


SessionLocal = get_session  # zgodnosc wstecz (consumer.py)
Base = declarative_base()


class Apartment(Base):
    __tablename__ = "apartments"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    price_per_night = Column(Numeric(10, 2), nullable=False)


class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    apartment_id = Column(Integer, nullable=False)
    date_from = Column(Date, nullable=False)
    date_to = Column(Date, nullable=False)
    guest_name = Column(String, nullable=False)
    guest_email = Column(String, nullable=False)
    marketing_consent = Column(Boolean, default=False)
    status = Column(String, default="pending")
    invoice_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


def init_db():
    engine = get_engine()
    Base.metadata.create_all(bind=engine)
    session = get_session()
    if session.query(Apartment).count() == 0:
        session.add_all([
            Apartment(name="Apartament Centrum", description="2 pokoje, blisko rynku", price_per_night=250),
            Apartment(name="Apartament Panoramiczny", description="Widok na miasto", price_per_night=320),
            Apartment(name="Studio Kompakt", description="Idealne dla pary", price_per_night=180),
        ])
        session.commit()
    session.close()
