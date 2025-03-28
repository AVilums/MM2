import tkinter as tk
from tkinter import ttk, messagebox
import win32pipe, win32file, pywintypes
import json
import threading
import os
import time
import sys

class MQL5Communicator:
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

class TradingGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("MQL5 Trading Interface")
        self.root.geometry("500x400")
        
        self.communicator = MQL5Communicator()
        
        # Setup the connection status checker
        self.connection_status = tk.StringVar(value="Not Connected")
        self.create_widgets()
        
        # Start connection thread
        self.connection_thread = threading.Thread(target=self.maintain_connection, daemon=True)
        self.connection_thread.start()

    def create_widgets(self):
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Connection status
        status_frame = ttk.LabelFrame(main_frame, text="Connection Status")
        status_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(status_frame, textvariable=self.connection_status).pack(padx=5, pady=5)
        
        # Refresh market data section
        refresh_frame = ttk.LabelFrame(main_frame, text="Market Data")
        refresh_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(refresh_frame, text="Refresh Data", command=self.refresh_market_data).pack(padx=5, pady=5)
        
        # Algorithm controls
        algo_frame = ttk.LabelFrame(main_frame, text="Algorithm Controls")
        algo_frame.pack(fill=tk.X, padx=5, pady=5)
        
        # Algo Range
        algo_range_frame = ttk.Frame(algo_frame)
        algo_range_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(algo_range_frame, text="Range:").grid(row=0, column=0, padx=5, pady=5)
        self.range_var = tk.StringVar(value="10")
        ttk.Entry(algo_range_frame, textvariable=self.range_var, width=10).grid(row=0, column=1, padx=5, pady=5)
        
        self.algo_active_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(algo_range_frame, text="Activate Algorithm", variable=self.algo_active_var).grid(row=0, column=2, padx=5, pady=5)
        
        ttk.Button(algo_range_frame, text="Apply", command=self.set_algo_range).grid(row=0, column=3, padx=5, pady=5)
        
        # Order controls
        order_frame = ttk.LabelFrame(main_frame, text="Order Controls")
        order_frame.pack(fill=tk.X, padx=5, pady=5)
        
        # Limit Order
        limit_frame = ttk.Frame(order_frame)
        limit_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(limit_frame, text="Price:").grid(row=0, column=0, padx=5, pady=5)
        self.limit_price_var = tk.StringVar()
        ttk.Entry(limit_frame, textvariable=self.limit_price_var, width=10).grid(row=0, column=1, padx=5, pady=5)
        
        ttk.Label(limit_frame, text="Size:").grid(row=0, column=2, padx=5, pady=5)
        self.limit_size_var = tk.StringVar(value="0.01")
        ttk.Entry(limit_frame, textvariable=self.limit_size_var, width=10).grid(row=0, column=3, padx=5, pady=5)
        
        ttk.Button(limit_frame, text="Limit Order", command=self.place_limit_order).grid(row=0, column=4, padx=5, pady=5)
        
        # Mid-price order
        mid_frame = ttk.Frame(order_frame)
        mid_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(mid_frame, text="Size:").grid(row=0, column=0, padx=5, pady=5)
        self.mid_size_var = tk.StringVar(value="0.01")
        ttk.Entry(mid_frame, textvariable=self.mid_size_var, width=10).grid(row=0, column=1, padx=5, pady=5)
        
        self.side_var = tk.StringVar(value="buy")
        ttk.Radiobutton(mid_frame, text="Buy", variable=self.side_var, value="buy").grid(row=0, column=2, padx=5, pady=5)
        ttk.Radiobutton(mid_frame, text="Sell", variable=self.side_var, value="sell").grid(row=0, column=3, padx=5, pady=5)
        
        ttk.Button(mid_frame, text="Mid Price Order", command=self.place_mid_price_order).grid(row=0, column=4, padx=5, pady=5)

    def maintain_connection(self):
        while True:
            if not self.communicator.connected:
                self.connection_status.set("Waiting for MQL5 connection...")
                if self.communicator.connect():
                    self.connection_status.set("Connected to MQL5")
                else:
                    self.connection_status.set("Connection failed")
            time.sleep(1)

    def refresh_market_data(self):
        try:
            response = self.communicator.send_command("refresh")
        except Exception as e:
            print('Error: Failed sending message": {e} \n')
            
        if response.get("status") == "success":
            data = response.get("data", {})
            market_info = data.get("market_info", {})
            account_info = data.get("account_info", {})
            
            info = f"Market: {market_info}\nAccount: {account_info}"
            messagebox.showinfo("Market Data", info)
        else:
            messagebox.showerror("Error", f"Failed to refresh data: {response.get('message', 'Unknown error')}")

    def set_algo_range(self):
        try:
            range_val = float(self.range_var.get())
            active = self.algo_active_var.get()
            
            response = self.communicator.send_command("algo", {
                "range": range_val,
                "active": active
            })
            
            if response.get("status") == "success":
                messagebox.showinfo("Success", "Algorithm settings updated")
            else:
                messagebox.showerror("Error", f"Failed to update algorithm: {response.get('message', 'Unknown error')}")
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid range value")

    def place_limit_order(self):
        try:
            price = float(self.limit_price_var.get())
            size = float(self.limit_size_var.get())
            
            response = self.communicator.send_command("limit", {
                "price": price,
                "size": size
            })
            
            if response.get("status") == "success":
                messagebox.showinfo("Success", "Limit order placed")
            else:
                messagebox.showerror("Error", f"Failed to place limit order: {response.get('message', 'Unknown error')}")
        except ValueError:
            messagebox.showerror("Error", "Please enter valid price and size values")

    def place_mid_price_order(self):
        try:
            size = float(self.mid_size_var.get())
            side = self.side_var.get()
            
            response = self.communicator.send_command("mid_price", {
                "size": size,
                "side": side
            })
            
            if response.get("status") == "success":
                messagebox.showinfo("Success", "Mid-price order placed")
            else:
                messagebox.showerror("Error", f"Failed to place mid-price order: {response.get('message', 'Unknown error')}")
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid size value")

def main():
    try:
        root = tk.Tk()
        app = TradingGUI(root)
        root.mainloop()
    except Exception as e:
        print('Fatal error {e} \n')
        return 0
    
    return 1
    
if __name__ == "__main__":
    print(main())