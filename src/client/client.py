import time
import win32file
import win32pipe

PIPE_NAME = r'\\.\pipe\mt1'  # Adjust based on your MQL5 setup
TIMEOUT_MS = 5000  # 5 seconds

def connect_to_pipe():
    """Attempts to connect to the MQL5 named pipe."""
    try:
        print(f"Connecting to MQL5 pipe: {PIPE_NAME}")
        pipe = win32file.CreateFile(
            PIPE_NAME,
            win32file.GENERIC_WRITE | win32file.GENERIC_READ,
            0, None, win32file.OPEN_EXISTING, 0, None
        )
        print("Connected to MQL5 pipe.")
        return pipe
    except Exception as e:
        print(f"Failed to connect: {e}")
        return None

def send_order(order_info):
    """Sends an order to MQL5 via the named pipe and waits for a response."""
    pipe = connect_to_pipe()
    if not pipe:
        return
    
    try:
        print(f"Sending order: {order_info}")
        win32file.WriteFile(pipe, order_info.encode("utf-8"))

        # Read response from MQL5
        _, response = win32file.ReadFile(pipe, 256)
        print(f"Response from MQL5: {response.decode('utf-8')}")

    except Exception as e:
        print(f"Error during communication: {e}")
    
    finally:
        win32file.CloseHandle(pipe)

if __name__ == "__main__":
    time.sleep(2)  # Allow MQL5 to start
    send_order("BUY 1.0 EURUSD")  # Example order format
