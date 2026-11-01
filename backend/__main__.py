import os
import sys

# Ensure the directory containing this file (backend) is in sys.path
# This allows 'serve.py' to import 'main.py' using 'from main import app'
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

try:
    import serve
except ImportError:
    # Fallback: try importing as backend.serve if running from outside
    try:
        from backend import serve
    except ImportError:
        # Last resort: try adding parent to path?
        # If we are here, something is weird.
        raise

if __name__ == "__main__":
    serve.main()
