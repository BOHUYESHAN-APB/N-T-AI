import logging
import sys
import os
from app.core.config import settings

class _RecentErrorHandler(logging.Handler):
    def __init__(self, max_errors: int):
        super().__init__(level=logging.ERROR)
        self.max_errors = max_errors
        self.recent_errors = []

    def emit(self, record: logging.LogRecord):
        try:
            entry = {
                "timestamp": record.created,
                "level": record.levelname,
                "message": record.getMessage(),
            }
            if record.exc_info:
                entry["exception"] = self.formatter.formatException(record.exc_info) if hasattr(self, "formatter") else str(record.exc_info)
            self.recent_errors.append(entry)
            if len(self.recent_errors) > self.max_errors:
                self.recent_errors = self.recent_errors[-self.max_errors:]
        except Exception:
            pass

_error_handler = _RecentErrorHandler(settings.LOG_MAX_ERRORS)

def setup_logging():
    """
    Configures the logging system for the application.
    """
    log_level = logging.INFO
    
    # Create logger
    logger = logging.getLogger("astra_me")
    logger.setLevel(log_level)
    
    # Create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Create console handler
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(log_level)
    ch.setFormatter(formatter)
    
    # Create file handler
    log_dir = "logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)
    fh = logging.FileHandler(os.path.join(log_dir, "app.log"), encoding='utf-8')
    fh.setLevel(log_level)
    fh.setFormatter(formatter)

    if not logger.handlers:
        logger.addHandler(ch)
        logger.addHandler(fh)
        logger.addHandler(_error_handler)
        
    # Set root logger level as well to capture uvicorn/fastapi logs if needed
    logging.getLogger().setLevel(log_level)
    
    return logger

logger = setup_logging()

def get_recent_errors():
    return list(_error_handler.recent_errors)

def set_recent_error_max(n: int):
    try:
        n = int(n)
    except Exception:
        return
    if n <= 0:
        return
    _error_handler.max_errors = n
    if len(_error_handler.recent_errors) > n:
        _error_handler.recent_errors = _error_handler.recent_errors[-n:]
