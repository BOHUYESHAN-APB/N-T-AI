"""
Serve script for Astra-Me backend with optional self-signed certificate generation.
Usage:
  - Set environment variable USE_HTTPS=true to enable HTTPS (or edit app.core.config.Settings)
  - Run: python serve.py

This script will generate certs at the configured paths if they don't exist.
"""

import os
import sys
import logging
from datetime import datetime, timedelta

from app.core.config import settings

try:
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
except Exception as e:
    print("Missing cryptography package. Please install dependencies (see backend/requirements.txt).")
    raise


def ensure_certs(cert_path: str, key_path: str, hostnames=("localhost", "127.0.0.1")):
    cert_dir = os.path.dirname(os.path.abspath(cert_path))
    if not os.path.exists(cert_dir):
        os.makedirs(cert_dir, exist_ok=True)

    if os.path.exists(cert_path) and os.path.exists(key_path):
        logging.info(f"Found existing cert/key at {cert_path} and {key_path}")
        return cert_path, key_path

    # Generate private key
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, u"localhost"),
    ])

    alt_names = [x509.DNSName(h) for h in hostnames]
    san = x509.SubjectAltName(alt_names)

    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.utcnow() - timedelta(days=1))
        .not_valid_after(datetime.utcnow() + timedelta(days=365 * 5))
        .add_extension(san, critical=False)
        .sign(key, hashes.SHA256())
    )

    # Write key
    with open(key_path, "wb") as f:
        f.write(
            key.private_bytes(
                encoding=Encoding.PEM,
                format=PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=NoEncryption(),
            )
        )

    # Write cert
    with open(cert_path, "wb") as f:
        f.write(cert.public_bytes(Encoding.PEM))

    logging.info(f"Generated self-signed cert -> {cert_path}, key -> {key_path}")
    return cert_path, key_path


def rotate_certs_if_needed(cert_path: str, key_path: str, rotate_days: int = 30):
    """Rotate certs if older than rotate_days. Keep previous certs with timestamp suffix."""
    try:
        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            return ensure_certs(cert_path, key_path)

        mtime = os.path.getmtime(cert_path)
        age_days = (datetime.utcnow() - datetime.fromtimestamp(mtime)).days
        if age_days >= rotate_days or os.environ.get("FORCE_CERT_ROTATE", "false").lower() == "true":
            # Archive old
            ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
            archived_cert = f"{cert_path}.{ts}.bak"
            archived_key = f"{key_path}.{ts}.bak"
            os.rename(cert_path, archived_cert)
            os.rename(key_path, archived_key)
            logging.info(f"Archived cert/key to {archived_cert} / {archived_key}")
            # Generate new
            new_cert, new_key = ensure_certs(cert_path, key_path)
            return new_cert, new_key
    except Exception as e:
        logging.error(f"Error rotating certs: {e}")
    return cert_path, key_path


if __name__ == "__main__":
    import uvicorn

    use_https = bool(os.environ.get("USE_HTTPS", str(settings.USE_HTTPS)))
    host = os.environ.get("HOST", settings.HOST)
    port = int(os.environ.get("PORT", settings.PORT))
    cert_path = os.environ.get("SSL_CERT_PATH", settings.SSL_CERT_PATH)
    key_path = os.environ.get("SSL_KEY_PATH", settings.SSL_KEY_PATH)

    if use_https:
        # Ensure certs exist and rotate if needed
        rotate_certs_if_needed(cert_path, key_path, rotate_days=int(os.environ.get('CERT_ROTATE_DAYS', '30')))
        print(f"Starting server with HTTPS at https://{host}:{port}")
        uvicorn.run("main:app", host=host, port=port, ssl_certfile=cert_path, ssl_keyfile=key_path)
    else:
        print(f"Starting server with HTTP at http://{host}:{port}")
        uvicorn.run("main:app", host=host, port=port)
