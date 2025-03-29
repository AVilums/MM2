# MM2/src/client/client.py
import sys
import logging
from config.config import Config
from helper.gui import ManualMode
from utils.logging import setup_logging

def main():
    try:
        # Setup logging
        setup_logging()
        logger = logging.getLogger(__name__)
        
        # Initialize settings
        settings = Config()
        
        # Start the application
        logger.info("Starting Manual Mode 2 application")
        app = ManualMode(settings)
        
        return 0
    except Exception as e:
        logging.error(f'Fatal error: {e}')
        return 1
    
if __name__ == "__main__":
    sys.exit(main())