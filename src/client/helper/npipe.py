import win32pipe, win32file
import json

class NamedPipe:
    def __init__(self, pipe_name=r'\\.\pipe\mql5_python_pipe'):
        self.pipe_name = pipe_name
        self.pipe = None
        self.connected = False

    def create_pipe(self):
        try:
            self.pipe = win32pipe.CreateNamedPipe(
                self.pipe_name,
                win32pipe.PIPE_ACCESS_DUPLEX,
                win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
                1, 65536, 65536, 0, None)
            return True
        except Exception as e:
            print(f"Error creating pipe: {e}")
            return False

    def connect(self):
        if not self.pipe:
            if not self.create_pipe():
                return False
                
        print("Waiting for MQL5 to connect to the pipe...")
        try:
            win32pipe.ConnectNamedPipe(self.pipe, None)
            self.connected = True
            print("MQL5 connected")
            return True
        except Exception as e:
            print(f"Connection error: {e}")
            self.close()
            return False

    def send_command(self, command_type, params=None):
        if not self.connected:
            if not self.connect():
                return {"status": "error", "message": "Not connected to MQL5"}
        
        command = {
            "command": command_type,
            "params": params or {}
        }
        
        try:
            # Send command
            command_json = json.dumps(command).encode('utf-8')
            win32file.WriteFile(self.pipe, command_json)
            print(f"Sent: {command}")
            
            # Receive response
            result, data = win32file.ReadFile(self.pipe, 64*1024)
            response = json.loads(data.decode('utf-8'))
            print(f"Received: {response}")
            return response
        except Exception as e:
            print(f"Error during communication: {e}")
            self.close()
            return {"status": "error", "message": str(e)}

    def close(self):
        if self.pipe:
            try:
                win32file.CloseHandle(self.pipe)
            except:
                pass
            self.pipe = None
            self.connected = False