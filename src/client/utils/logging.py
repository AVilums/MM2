# MM2/src/client/utils/logging.py
import os
import logging
import logging.handlers
from datetime import datetime
from pathlib import Path

def setup_logging(log_level: str = "INFO", log_file: str = None, 
                 max_bytes: int = 5 * 1024 * 1024, backup_count: int = 3) -> None:
    """
    Configure application logging.
    
    Args:
        log_level: Minimum log level to display (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Path to the log file, if None logs to console only
        max_bytes: Maximum size of log file before rotation
        backup_count: Number of backup logs to keep
    """
    # Create logs directory if it doesn't exist
    if log_file:
        log_dir = os.path.dirname(log_file)
        if log_dir and not os.path.exists(log_dir):
            os.makedirs(log_dir, exist_ok=True)
    else:
        # Default log file in logs directory with timestamp
        logs_dir = Path("logs")
        logs_dir.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = logs_dir / f"mm2_client_{timestamp}.log"
    
    # Get the numeric log level
    numeric_level = getattr(logging, log_level.upper(), None)
    if not isinstance(numeric_level, int):
        numeric_level = logging.INFO
        print(f"Invalid log level: {log_level}, defaulting to INFO")
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(numeric_level)
    
    # Remove existing handlers to avoid duplicates on reconfiguration
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Create formatters
    detailed_formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(name)-20s | %(message)s'
    )
    console_formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s'
    )
    
    # Console handler
    console = logging.StreamHandler()
    console.setLevel(numeric_level)
    console.setFormatter(console_formatter)
    root_logger.addHandler(console)
    
    # File handler with rotation
    if log_file:
        file_handler = logging.handlers.RotatingFileHandler(
            log_file, maxBytes=max_bytes, backupCount=backup_count
        )
        file_handler.setLevel(numeric_level)
        file_handler.setFormatter(detailed_formatter)
        root_logger.addHandler(file_handler)
        
        logging.info(f"Logging to file: {log_file}")
    
    # Log the configuration
    logging.info(f"Logging initialized at level: {log_level}")