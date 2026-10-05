"""
KROK 5 (Auth): logowanie rezerwujacych - hashowanie hasel PBKDF2 (stdlib,
bez nowych zaleznosci) i generowanie tokenow sesyjnych (przechowywane w Redis).

Uzycie:
    from .auth import hash_password, verify_password, new_session_token

    pwd_hash = hash_password("tajne")
    assert verify_password("tajne", pwd_hash)
"""

import hashlib
import hmac
import secrets

PBKDF2_ITERATIONS = 260_000
SALT_BYTES = 16
SESSION_TOKEN_BYTES = 32
SESSION_TTL_SECONDS = 86_400  # 24h


def hash_password(password: str) -> str:
    """PBKDF2-HMAC-SHA256; format: pbkdf2_sha256$<iter>$<salt_hex>$<hash_hex>."""
    salt = secrets.token_bytes(SALT_BYTES)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS
    )
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """Stale-time porownanie; zwraca False przy uszkodzonym formacie."""
    try:
        algo, iterations, salt_hex, hash_hex = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt_hex),
            int(iterations),
        )
        return hmac.compare_digest(digest.hex(), hash_hex)
    except (ValueError, TypeError):
        return False


def new_session_token() -> str:
    """Token sesyjny do przechowania w Redis (klucz session:<token>, TTL 24h)."""
    return secrets.token_urlsafe(SESSION_TOKEN_BYTES)


def generate_random_password(length: int = 24) -> str:
    """Losowe haslo admina generowane przy starcie, gdy Vault nie dostarczyl
    ADMIN_PASSWORD (dokladnie jak DB_PASSWORD generowane przez bootstrap)."""
    return secrets.token_urlsafe(max(16, min(length, 64)))
