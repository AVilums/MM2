# MM2/src/client/helper/gui.py
import tkinter as tk
from tkinter import ttk, messagebox
import threading
import time
import logging
from helper.npipe import NamedPipe
from models.market_data import MarketData

class ManualMode:
    def __init__(self, config):
        """
        Initialize the Manual Mode GUI application.
        
        Args:
            config: Config object containing application config
        """
        self.logger = logging.getLogger(__name__)
        self.config = config
        
        self.root = tk.Tk()
        self.root.title("Manual Mode 2")
        self.root.geometry("500x400")
        
        # Create the named pipe with config
        self.npipe = NamedPipe(
            pipe_name=config.get("pipe_name"),
            retry_interval=config.get("retry_interval"),
            max_retries=config.get("max_retries")
        )
        
        # Initialize market data
        self.market_data = None
        
        # Setup the connection status checker
        self.connection_status = tk.StringVar(value="Not Connected")
        self.create_widgets()
        
        # Start connection thread
        self.connection_thread = threading.Thread(target=self.maintain_connection, daemon=True)
        self.connection_thread.start()

        # Start data refresh thread if enabled
        self.data_refresh_interval = config.get("data_refresh_interval", 5)
        if self.data_refresh_interval > 0:
            self.refresh_thread = threading.Thread(target=self.auto_refresh_data, daemon=True)
            self.refresh_thread.start()

        # Start Main loop
        self.logger.info("Starting GUI main loop")
        self.root.mainloop()

    def create_widgets(self):
        """Create and arrange all GUI widgets."""
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
        
        refresh_buttons = ttk.Frame(refresh_frame)
        refresh_buttons.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(refresh_buttons, text="Refresh Data", command=self.refresh_market_data).pack(side=tk.LEFT, padx=5, pady=5)
        
        # Market data display
        self.market_info = tk.StringVar(value="No market data available")
        ttk.Label(refresh_frame, textvariable=self.market_info, wraplength=450).pack(padx=5, pady=5, fill=tk.X)
        
        # Algorithm controls
        algo_frame = ttk.LabelFrame(main_frame, text="Algorithm Controls")
        algo_frame.pack(fill=tk.X, padx=5, pady=5)
        
        # Algo Range
        algo_range_frame = ttk.Frame(algo_frame)
        algo_range_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(algo_range_frame, text="Range:").grid(row=0, column=0, padx=5, pady=5)
        self.range_var = tk.StringVar(value=str(self.config.get("default_algo_range", 10)))
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
        self.limit_size_var = tk.StringVar(value=str(self.config.get("default_order_size", 0.01)))
        ttk.Entry(limit_frame, textvariable=self.limit_size_var, width=10).grid(row=0, column=3, padx=5, pady=5)
        
        ttk.Button(limit_frame, text="Limit Order", command=self.place_limit_order).grid(row=0, column=4, padx=5, pady=5)
        
        # Mid-price order
        mid_frame = ttk.Frame(order_frame)
        mid_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(mid_frame, text="Size:").grid(row=0, column=0, padx=5, pady=5)
        self.mid_size_var = tk.StringVar(value=str(self.config.get("default_order_size", 0.01)))
        ttk.Entry(mid_frame, textvariable=self.mid_size_var, width=10).grid(row=0, column=1, padx=5, pady=5)
        
        self.side_var = tk.StringVar(value="buy")
        ttk.Radiobutton(mid_frame, text="Buy", variable=self.side_var, value="buy").grid(row=0, column=2, padx=5, pady=5)
        ttk.Radiobutton(mid_frame, text="Sell", variable=self.side_var, value="sell").grid(row=0, column=3, padx=5, pady=5)
        
        ttk.Button(mid_frame, text="Mid Price Order", command=self.place_mid_price_order).grid(row=0, column=4, padx=5, pady=5)

    def maintain_connection(self):
        """Thread function to maintain connection to MQL5."""
        while True:
            if not self.npipe.connected:
                self.connection_status.set("Waiting for MQL5 connection...")
                if self.npipe.connect():
                    self.connection_status.set("Connected to MQL5")
                    self.logger.info("Connected to MQL5 successfully")
                else:
                    self.connection_status.set("Connection failed")
                    self.logger.warning("Failed to connect to MQL5")
            time.sleep(1)

    def auto_refresh_data(self):
        """Thread function to automatically refresh market data."""
        while True:
            if self.npipe.connected:
                try:
                    self.refresh_market_data(show_messages=False)
                except Exception as e:
                    self.logger.error(f"Auto-refresh error: {e}")
            time.sleep(self.data_refresh_interval)

    def refresh_market_data(self, show_messages=True):
        """
        Refresh market data from MQL5.
        
        Args:
            show_messages: Whether to show success/error messages to the user
        """
        try:
            response = self.npipe.send_command("refresh")
            
            if response.get("status") == "success":
                data = response.get("data", {})
                
                # Update market info display
                market_info = data.get("market_info", {})
                account_info = data.get("account_info", {})
                
                # Format the info for display
                info_text = []
                
                if market_info:
                    if "symbol" in market_info:
                        info_text.append(f"Symbol: {market_info['symbol']}")
                    if "bid" in market_info and "ask" in market_info:
                        info_text.append(f"Bid: {market_info['bid']} | Ask: {market_info['ask']}")
                    if "last" in market_info:
                        info_text.append(f"Last price: {market_info['last']}")
                
                if account_info:
                    if "balance" in account_info:
                        info_text.append(f"Balance: {account_info['balance']}")
                    if "equity" in account_info:
                        info_text.append(f"Equity: {account_info['equity']}")
                    if "margin" in account_info:
                        info_text.append(f"Margin: {account_info['margin']}")
                
                if not info_text:
                    info_text.append("Market data received but no details available")
                
                self.market_info.set("\n".join(info_text))
                
                # Try to prepopulate the limit price field with current price
                if "last" in market_info and not self.limit_price_var.get():
                    self.limit_price_var.set(str(market_info["last"]))
                
                if show_messages:
                    messagebox.showinfo("Success", "Market data refreshed")
                
                return True
            else:
                error_msg = f"Failed to refresh data: {response.get('message', 'Unknown error')}"
                self.logger.error(error_msg)
                if show_messages:
                    messagebox.showerror("Error", error_msg)
                return False
        except Exception as e:
            error_msg = f"Error refreshing market data: {e}"
            self.logger.error(error_msg)
            if show_messages:
                messagebox.showerror("Error", error_msg)
            return False

    def set_algo_range(self):
        """Set the algorithm range and active state."""
        try:
            range_val = float(self.range_var.get())
            active = self.algo_active_var.get()
            
            self.logger.info(f"Setting algorithm: range={range_val}, active={active}")
            
            response = self.npipe.send_command("algo", {
                "range": range_val,
                "active": active
            })
            
            if response.get("status") == "success":
                messagebox.showinfo("Success", "Algorithm config updated")
            else:
                messagebox.showerror("Error", f"Failed to update algorithm: {response.get('message', 'Unknown error')}")
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid range value")

    def place_limit_order(self):
        """Place a limit order."""
        try:
            price = float(self.limit_price_var.get())
            size = float(self.limit_size_var.get())
            
            self.logger.info(f"Placing limit order: price={price}, size={size}")
            
            response = self.npipe.send_command("limit", {
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
        """Place a mid-price order."""
        try:
            size = float(self.mid_size_var.get())
            side = self.side_var.get()
            
            self.logger.info(f"Placing mid-price order: size={size}, side={side}")
            
            response = self.npipe.send_command("mid_price", {
                "size": size,
                "side": side
            })
            
            if response.get("status") == "success":
                messagebox.showinfo("Success", "Mid-price order placed")
            else:
                messagebox.showerror("Error", f"Failed to place mid-price order: {response.get('message', 'Unknown error')}")
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid size value")