import os
import smtplib
from email.mime.text import MIMEText

SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
FROM_EMAIL = os.getenv("FROM_EMAIL", "rezerwacje@davtro.pl")


def _send(to_email: str, subject: str, body: str):
    if not SMTP_HOST:
        print(f"[DEV] Email do {to_email}: {subject}\n{body}")
        return
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = FROM_EMAIL
    msg["To"] = to_email
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.sendmail(FROM_EMAIL, [to_email], msg.as_string())


def send_confirmation_email(to_email: str, guest_name: str, event: dict):
    subject = f"Potwierdzenie rezerwacji nr {event['booking_id']}"
    body = (
        f"Cześć {guest_name},\n\n"
        f"Twoja rezerwacja ({event['date_from']} - {event['date_to']}) została potwierdzona.\n"
        f"W załączeniu (proforma) prosimy o dokonanie płatności przed przyjazdem.\n\n"
        f"Pozdrawiamy,\nDavtro Apartments"
    )
    _send(to_email, subject, body)


def send_marketing_email(to_email: str, guest_name: str):
    subject = "Sprawdź nasze najnowsze oferty!"
    body = f"Cześć {guest_name}, mamy dla Ciebie nowe promocje na pobyty krótkoterminowe."
    _send(to_email, subject, body)
