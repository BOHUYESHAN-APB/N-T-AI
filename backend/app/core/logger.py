import logging
import sys
from app.core.config import settings

def setup_logging():
    """
    Configures the logging system for the application.
    """
    log_level = logging.INFO
    
    # Create logger
    logger = logging.getLogger("astra_me")
    logger.setLevel(log_level)
    
    # Create console handler and set level to debug
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(log_level)
    
    # Create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    # Add formatter to ch
    ch.setFormatter(formatter)
    
    # Add ch to logger
    if not logger.handlers:
        logger.addHandler(ch)
        
    # Set root logger level as well to capture uvicorn/fastapi logs if needed
    logging.getLogger().setLevel(log_level)
    
    return logger

logger = setup_logging()
