# Astra-Me Serve Script
import sys
print("Astra-Me Backend initializing runtime...", flush=True)

import os
import logging
import warnings
import traceback

# Suppress websockets deprecation warning
warnings.filterwarnings("ignore", category=DeprecationWarning, message="remove second argument of ws_handler")

def ensure_certs(cert_path: str, key_path: str, hostnames=("localhost", "127.0.0.1")):
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
    except Exception:
        raise RuntimeError("cryptography not available")

    from datetime import datetime, timedelta

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
    san = x509.SubjectAlternativeName(alt_names)

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


def rotate_certs_if_needed(cert_path: str, key_path: str, rotate_days: int = 30) -> bool:
    """Rotate certs if older than rotate_days. Keep previous certs with timestamp suffix.
       Returns True if certs are valid/generated, False if generation failed.
    """
    from datetime import datetime
    try:
        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            ensure_certs(cert_path, key_path)
            return True

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
            ensure_certs(cert_path, key_path)
            return True
        return True # Existing certs are fine
    except Exception as e:
        logging.error(f"Error rotating/generating certs: {e}")
        return False



def main():
    print("Astra-Me Backend Loader starting...")
    import socket
    import urllib.request
    import ssl
    import json
    import time
    
    # Deferred heavy imports
    print("Loading core configuration...")
    from app.core.config import settings

    try:
        # Move heavy imports later
        print("Checking configuration...")
        is_frozen = bool(getattr(sys, "frozen", False))

        if is_frozen:
            use_https = os.environ.get("USE_HTTPS", "false").lower() == "true"
        else:
            use_https = os.environ.get("USE_HTTPS", str(settings.USE_HTTPS)).lower() == "true"

        host = os.environ.get("HOST", settings.HOST)
        port = int(os.environ.get("PORT", settings.PORT))
        cert_path = os.environ.get("SSL_CERT_PATH", settings.SSL_CERT_PATH)
        key_path = os.environ.get("SSL_KEY_PATH", settings.SSL_KEY_PATH)

        def _can_connect(check_host: str, check_port: int) -> bool:
            try:
                with socket.create_connection((check_host, check_port), timeout=0.3):
                    return True
            except Exception:
                return False

        def _health_ok(check_url: str, insecure_ssl: bool) -> bool:
            try:
                context = ssl._create_unverified_context() if insecure_ssl else None
                with urllib.request.urlopen(check_url, timeout=0.6, context=context) as resp:
                    return 200 <= int(resp.status) < 300
            except Exception:
                return False

        probe_host = "127.0.0.1" if host in ("0.0.0.0", "::") else host
        
        # Helper to write server info
        def _write_server_info(scheme, host, port):
            try:
                info = {
                    "url": f"{scheme}://{host}:{port}",
                    "port": port,
                    "host": host,
                    "pid": os.getpid(),
                    "scheme": scheme
                }
                with open("server_info.json", "w") as f:
                    json.dump(info, f)
                print(f"[SERVER_INFO] {json.dumps(info)}")
            except Exception as e:
                print(f"Error writing server_info.json: {e}")

        # Try finding an available port if the default is taken
        start_port = port
        max_retries = 10
        
        # Check if port scanning is disabled via env var or if we are using a custom port
        if os.environ.get("DISABLE_PORT_SCAN", "false").lower() == "true":
            max_retries = 0
            
        actual_port = start_port
        
        for i in range(max_retries + 1):
            check_port = start_port + i
            if not _can_connect(probe_host, check_port):
                # Port is free!
                actual_port = check_port
                break
            else:
                # Port is taken, check if it's our own service
                scheme = "https" if use_https else "http"
                health_url = f"{scheme}://{probe_host}:{check_port}/health"
                if _health_ok(health_url, insecure_ssl=use_https):
                    print(f"Backend already running at {scheme}://{probe_host}:{check_port}")
                    # Write info file even if already running, so frontend can find it
                    _write_server_info(scheme, probe_host, check_port)
                    sys.exit(0)
                print(f"Port {check_port} is busy, trying next...")

        port = actual_port
        
        if use_https:
            crypto_available = True
            try:
                from cryptography import x509
            except ImportError:
                crypto_available = False

            if not crypto_available:
                print("WARNING: cryptography unavailable. Falling back to HTTP.")
                use_https = False
            else:
                certs_ok = rotate_certs_if_needed(
                    cert_path,
                    key_path,
                    rotate_days=int(os.environ.get("CERT_ROTATE_DAYS", "30")),
                )
                if certs_ok and os.path.exists(cert_path) and os.path.exists(key_path):
                    print(f"Starting server with HTTPS at https://{host}:{port}")
                    _write_server_info("https", probe_host, port)
                    print("Loading application modules...")
                    import uvicorn
                    try:
                        from main import app as asgi_app
                    except Exception:
                        print("CRITICAL ERROR: Failed to import ASGI app from main.py")
                        traceback.print_exc()
                        sys.exit(1)
                    uvicorn.run(
                        asgi_app,
                        host=host,
                        port=port,
                        ssl_certfile=cert_path,
                        ssl_keyfile=key_path,
                    )
                else:
                    print("WARNING: Certificate init failed. Falling back to HTTP.")
                    use_https = False

        if not use_https:
            print(f"Starting server with HTTP at http://{host}:{port}")
            _write_server_info("http", probe_host, port)
            print("Loading application modules...")
            import uvicorn
            try:
                from main import app as asgi_app
            except Exception:
                print("CRITICAL ERROR: Failed to import ASGI app from main.py")
                traceback.print_exc()
                sys.exit(1)
            uvicorn.run(asgi_app, host=host, port=port)
        else:
            pass
    except Exception as e:
        print("CRITICAL ERROR DURING SERVER STARTUP:")
        traceback.print_exc()
        if os.environ.get("DISABLE_PORT_SCAN", "false").lower() == "true":
            sys.exit(1)
        print("\nPress Enter to exit...")
        input()


if __name__ == "__main__":
    main()
