# MM2/src/client/helper/npipe.py
import win32pipe, win32file
import json
import logging
import time
from typing import Dict, Any, Optional, Union

class NamedPipe:
    """Handles communication with MQL5 through a named pipe."""
    
    def __init__(self, pipe_name: str = r'\\.\pipe\mql5_python_pipe', 
                 retry_interval: int = 5, max_retries: int = 3):
        """
        Initialize the Named Pipe communication class.
        
        Args:
            pipe_name: The name of the pipe to connect to
            retry_interval: Seconds between connection retry attempts
            max_retries: Maximum number of retries before giving up
        """
        self.pipe_name = pipe_name
        self.pipe = None
        self.connected = False
        self.retry_interval = retry_interval
        self.max_retries = max_retries
        self.logger = logging.getLogger(__name__)

    def create_pipe(self) -> bool:
        """Create a named pipe for communication."""
        try:
            self.pipe = win32pipe.CreateNamedPipe(
                self.pipe_name,
                win32pipe.PIPE_ACCESS_DUPLEX,
                win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
                1, 65536, 65536, 0, None)
            self.logger.debug(f"Named pipe created: {self.pipe_name}")
            return True
        except Exception as e:
            self.logger.error(f"Error creating pipe: {e}")
            return False

    def connect(self) -> bool:
        """Connect to the named pipe."""
        if not self.pipe:
            if not self.create_pipe():
                return False
                
        self.logger.info("Waiting for MQL5 to connect to the pipe...")
        try:
            win32pipe.ConnectNamedPipe(self.pipe, None)
            self.connected = True
            self.logger.info("MQL5 connected successfully")
            return True
        except Exception as e:
            self.logger.error(f"Connection error: {e}")
            self.close()
            return False

    def send_command(self, command_type: str, params: Optional[Dict[str, Any]] = None, 
                     retry: bool = True) -> Dict[str, Any]:
        """
        Send a command to MQL5 and get the response.
        
        Args:
            command_type: The type of command to send
            params: Dictionary of parameters for the command
            retry: Whether to retry sending on failure
            
        Returns:
            Dictionary containing the response from MQL5
        """
        if not self.connected:
            if not self.connect():
                return {"status": "error", "message": "Not connected to MQL5"}
        
        command = {
            "command": command_type,
            "params": params or {}
        }
        
        retries = 0
        while retries <= self.max_retries:
            try:
                # Send command
                command_json = json.dumps(command).encode('utf-8')
                win32file.WriteFile(self.pipe, command_json)
                self.logger.debug(f"Sent: {command}")
                
                # Receive response
                data_tuple = win32file.ReadFile(self.pipe, 64*1024)
                data = data_tuple[1]  # Extract the actual byte response

                response = json.loads(data.decode('utf-8').rstrip("\x00"))
                self.logger.debug(f"Received: {response}")
                return response
            except Exception as e:
                self.logger.error(f"Error during communication: {e}")
                retries += 1
                
                if not retry or retries > self.max_retries:
                    self.close()
                    return {"status": "error", "message": str(e)}
                
                self.logger.info(f"Retrying connection ({retries}/{self.max_retries})...")
                self.close()
                time.sleep(self.retry_interval)
                self.connect()
        
        return {"status": "error", "message": "Maximum retries exceeded"}

    def close(self) -> None:
        """Close the pipe connection."""
        if self.pipe:
            try:
                win32file.CloseHandle(self.pipe)
                self.logger.debug("Pipe connection closed")
            except Exception as e:
                self.logger.error(f"Error closing pipe: {e}")
            finally:
                self.pipe = None
                self.connected = False