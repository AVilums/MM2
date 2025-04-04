# MM2/src/client/config/config.py
import os
import json
import logging
from pathlib import Path

class Config:
    """Handles application configuration settings."""
    
    DEFAULT_CONFIG = {
        "pipe_name": r'\\.\pipe\mql5_python_pipe',
        "retry_interval": 5,
        "max_retries": 3,
        "log_level": "INFO",
        "log_file": "mm2_client.log",
        "default_order_size": 0.01,
        "default_algo_range": 10,
        "data_refresh_interval": 10,  # seconds
    }
    
    def __init__(self, config_file: str = None):
        """ Initialize configuration from file or defaults. """
        self.logger = logging.getLogger(__name__)
        self.config_data = self.DEFAULT_CONFIG.copy()
        
        # Try to find config file if not specified
        if not config_file:
            config_file = self._find_config_file()
        
        # Load configuration from file if it exists
        if config_file and os.path.exists(config_file):
            self._load_from_file(config_file)
            self.config_file = config_file
        else:
            self.logger.warning(f"Config file not found, using defaults")
            self.config_file = None
    
    def _find_config_file(self) -> str:
        """Search for configuration file in standard locations."""
        # Check current directory first
        candidates = [
            "config.json",
            os.path.join(os.path.expanduser("~"), ".mm2", "config.json"),
            os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
        ]
        
        for path in candidates:
            if os.path.exists(path):
                return path
        
        return None
    
    def _load_from_file(self, config_file: str) -> None:
        """Load configuration from a JSON file."""
        try:
            with open(config_file, 'r') as f:
                file_config = json.load(f)
                self.config_data.update(file_config)
                self.logger.info(f"Configuration loaded from {config_file}")
        except Exception as e:
            self.logger.error(f"Error loading configuration: {e}")
    
    def save(self, config_file: str = None) -> bool:
        """ Save current configuration to file. """
        target_file = config_file or self.config_file or "config.json"
        
        try:
            # Ensure directory exists
            os.makedirs(os.path.dirname(os.path.abspath(target_file)), exist_ok=True)
            
            with open(target_file, 'w') as f:
                json.dump(self.config_data, f, indent=4)
                
            self.logger.info(f"Configuration saved to {target_file}")
            return True
        except Exception as e:
            self.logger.error(f"Error saving configuration: {e}")
            return False
    
    def get(self, key: str, default=None):
        """Get a configuration value."""
        return self.config_data.get(key, default)
    
    def set(self, key: str, value) -> None:
        """Set a configuration value."""
        self.config_data[key] = value
    
    def __getitem__(self, key: str):
        """Allow dictionary-like access to configuration."""
        return self.config_data[key]
    
    def __setitem__(self, key: str, value) -> None:
        """Allow dictionary-like setting of configuration."""
        self.config_data[key] = value