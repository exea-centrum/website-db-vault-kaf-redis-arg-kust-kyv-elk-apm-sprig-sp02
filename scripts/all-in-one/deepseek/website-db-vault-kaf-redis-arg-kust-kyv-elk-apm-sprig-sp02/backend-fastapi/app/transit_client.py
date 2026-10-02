#!/usr/bin/env python3
"""
KROK 4 (Transit PII): Vault Transit Engine client.
Szyfruje/deszyfruje wrazliwe dane (PII) przed zapisem do PostgreSQL.
To NIE jest zastapione przez Istio - Istio chroni ruch, Transit chroni dane w spoczynku.
"""
import base64
import logging
import os
import time
from typing import Dict, Optional, Tuple
import requests

logger = logging.getLogger(__name__)
TOKEN_TTL_SECONDS = 3000
DEFAULT_VAULT_CA_FILE = "/etc/vault-tls/ca.crt"
DEFAULT_VAULT_TIMEOUT = 30


def vault_tls_config() -> Tuple[str, object]:
    scheme = os.environ.get("VAULT_TRANSIT_SCHEME", "https")
    addr = os.environ.get("VAULT_TRANSIT_ADDR") or f"{scheme}://vault.davtro02.svc.cluster.local:8203"
    ca_file = os.environ.get("VAULT_TRANSIT_CA_FILE", DEFAULT_VAULT_CA_FILE)
    if ca_file and os.path.exists(ca_file):
        return addr, ca_file
    if scheme == "https":
        logger.warning("Vault: brak pliku CA '%s' - uzywam systemowego store CA", ca_file)
        return addr, True
    return addr, False


class VaultTokenProvider:
    def __init__(self, vault_addr=None, verify=None, timeout=None):
        default_addr, default_verify = vault_tls_config()
        self.vault_addr = vault_addr or default_addr
        self.verify = default_verify if verify is None else verify
        self.auth_role = os.environ.get("VAULT_TRANSIT_AUTH_ROLE", "davtro-transit")
        self.timeout = timeout or int(os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT))
        self._token = None
        self._token_expiry = 0.0

    def get_token(self, renew=False):
        if self._token and not renew and time.time() < self._token_expiry:
            return self._token
        with open("/var/run/secrets/kubernetes.io/serviceaccount/token") as f:
            sa_token = f.read().strip()
        url = f"{self.vault_addr}/v1/auth/kubernetes/login"
        payload = {"jwt": sa_token, "role": self.auth_role}
        resp = requests.post(url, json=payload, timeout=self.timeout, verify=self.verify)
        resp.raise_for_status()
        auth = resp.json()["auth"]
        self._token = auth["client_token"]
        lease = int(auth.get("lease_duration") or 3600)
        self._token_expiry = time.time() + max(60, min(lease - 60, TOKEN_TTL_SECONDS))
        return self._token


class TransitClient:
    def __init__(self, key_name=None):
        self.vault_addr, self.verify = vault_tls_config()
        self.key_name = key_name or os.environ.get("VAULT_TRANSIT_KEY", "davtro-app")
        self.timeout = int(os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT))
        self.token_provider = VaultTokenProvider(self.vault_addr, self.verify)
        self._session = requests.Session()

    def _request(self, path, payload):
        url = f"{self.vault_addr}/v1/{path}"
        for attempt in (1, 2):
            token = self.token_provider.get_token(renew=(attempt == 2))
            resp = self._session.post(url, json=payload,
                                      headers={"X-Vault-Token": token},
                                      timeout=self.timeout, verify=self.verify)
            if resp.status_code == 403 and attempt == 1:
                continue
            resp.raise_for_status()
            return resp.json()["data"]
        raise RuntimeError("Vault transit: nieudana autoryzacja")

    def encrypt(self, plaintext):
        b64 = base64.b64encode(str(plaintext).encode()).decode()
        data = self._request(f"transit/encrypt/{self.key_name}", {"plaintext": b64})
        return data["ciphertext"]

    def decrypt(self, ciphertext):
        data = self._request(f"transit/decrypt/{self.key_name}", {"ciphertext": ciphertext})
        return base64.b64decode(data["plaintext"]).decode()


_transit_client = None


def get_transit_client():
    global _transit_client
    if _transit_client is None:
        _transit_client = TransitClient()
    return _transit_client


def encrypt(plaintext):
    return get_transit_client().encrypt(plaintext)


def decrypt(ciphertext):
    return get_transit_client().decrypt(ciphertext)
