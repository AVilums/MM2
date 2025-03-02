"""
Trading Panel - Core Implementation
--------------------------------
A modular trading platform with Python frontend and MQL5 backend
connected via named pipes for efficient real-time communication.
"""

import os
import json
import time
import asyncio
import threading
import panel as pn
import pandas as pd
from enum import Enum
import win32pipe, win32file, pywintypes


# ============ Communication Layer ============

class MessageType(Enum):
    MARKET_DATA = "market_data"
    ORDER_REQUEST = "order_request"
    ORDER_RESPONSE = "order_response"
    ERROR = "error"
    HEARTBEAT = "heartbeat"


class PipeManager:
    """Manages named pipe communication between Python and MQL5"""
    
    def __init__(self, read_pipe_name=r'\\.\pipe\mt5_to_python', write_pipe_name=r'\\.\pipe\python_to_mt5'):
        self.read_pipe_name = read_pipe_name
        self.write_pipe_name = write_pipe_name
        self.read_pipe = None
        self.write_pipe = None
        self.is_connected = False
        self.callbacks = {msg_type: [] for msg_type in MessageType}
        self._last_heartbeat = time.time()
        self._running = False
        
    async def create_pipes(self):
        """Create named pipes if they don't exist"""
        try:
            # Create read pipe (from MT5)
            self.read_pipe = win32pipe.CreateNamedPipe(
                self.read_pipe_name,
                win32pipe.PIPE_ACCESS_INBOUND,
                win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
                1, 65536, 65536, 0, None)
            
            print("Waiting for MQL5 client to connect...")
            win32pipe.ConnectNamedPipe(self.read_pipe, None)
            
            # Connect to write pipe (to MT5)
            while True:
                try:
                    self.write_pipe = win32file.CreateFile(
                        self.write_pipe_name,
                        win32file.GENERIC_WRITE,
                        0, None,
                        win32file.OPEN_EXISTING,
                        0, None)
                    break
                except pywintypes.error as e:
                    await asyncio.sleep(1)
                    continue
            
            self.is_connected = True
            print("Pipe connection established with MQL5")
            return True
            
        except Exception as e:
            print(f"Error creating pipes: {e}")
            return False
            
    async def start_listening(self):
        """Start listening for messages from MQL5"""
        self._running = True
        reader_thread = threading.Thread(target=self._read_pipe_loop)
        reader_thread.daemon = True
        reader_thread.start()
        
        # Start heartbeat monitor
        heartbeat_thread = threading.Thread(target=self._heartbeat_monitor)
        heartbeat_thread.daemon = True
        heartbeat_thread.start()
        
        return True
    
    def _read_pipe_loop(self):
        """Background thread for reading from the pipe"""
        while self._running and self.is_connected:
            try:
                # Read message from pipe
                result, data = win32file.ReadFile(self.read_pipe, 64*1024)
                message = data.decode('utf-8')
                
                # Parse and dispatch message
                try:
                    msg_obj = json.loads(message)
                    msg_type = MessageType(msg_obj.get('type', 'error'))
                    
                    # Update heartbeat time for non-heartbeat messages
                    self._last_heartbeat = time.time()
                    
                    # Dispatch to appropriate callbacks
                    for callback in self.callbacks.get(msg_type, []):
                        callback(msg_obj)
                        
                except json.JSONDecodeError:
                    print(f"Invalid JSON message: {message}")
                except Exception as e:
                    print(f"Error processing message: {e}")
                    
            except pywintypes.error as e:
                if e.args[0] == 109:  # Broken pipe
                    print("Pipe connection broken")
                    self.is_connected = False
                    break
                print(f"Error reading from pipe: {e}")
                time.sleep(1)
    
    def _heartbeat_monitor(self):
        """Monitor heartbeats to ensure connection is alive"""
        while self._running:
            if time.time() - self._last_heartbeat > 30:  # 30 seconds timeout
                print("No heartbeat received for 30 seconds, reconnecting...")
                self.is_connected = False
                # TODO: Implement reconnection logic
            time.sleep(5)
    
    async def send_message(self, msg_type, data):
        """Send a message to MQL5"""
        if not self.is_connected:
            print("Cannot send message: not connected")
            return False
            
        try:
            message = {
                'type': msg_type.value,
                'timestamp': time.time(),
                'data': data
            }
            
            message_bytes = json.dumps(message).encode('utf-8')
            win32file.WriteFile(self.write_pipe, message_bytes)
            return True
            
        except Exception as e:
            print(f"Error sending message: {e}")
            self.is_connected = False
            return False
    
    def register_callback(self, msg_type, callback):
        """Register a callback for a specific message type"""
        if msg_type in self.callbacks:
            self.callbacks[msg_type].append(callback)
    
    def close(self):
        """Close the pipe connection"""
        self._running = False
        if self.read_pipe:
            win32file.CloseHandle(self.read_pipe)
        if self.write_pipe:
            win32file.CloseHandle(self.write_pipe)
        self.is_connected = False


# ============ Trading Engine ============

class TradingEngine:
    """Core trading logic that interfaces with MQL5"""
    
    def __init__(self, pipe_manager):
        self.pipe_manager = pipe_manager
        self.market_data = {}
        self.order_history = []
        self.pending_orders = {}
        self.active_orders = {}
        
        # Register callbacks
        self.pipe_manager.register_callback(MessageType.MARKET_DATA, self._handle_market_data)
        self.pipe_manager.register_callback(MessageType.ORDER_RESPONSE, self._handle_order_response)
        self.pipe_manager.register_callback(MessageType.ERROR, self._handle_error)
        
        # Events for UI subscribers
        self.on_market_data_updated = []
        self.on_order_updated = []
        
    def _handle_market_data(self, message):
        """Process incoming market data"""
        data = message.get('data', {})
        symbol = data.get('symbol')
        
        if symbol:
            self.market_data[symbol] = data
            # Notify subscribers
            for callback in self.on_market_data_updated:
                callback(symbol, data)
    
    def _handle_order_response(self, message):
        """Process order response from MQL5"""
        data = message.get('data', {})
        order_id = data.get('order_id')
        
        if order_id:
            if order_id in self.pending_orders:
                # Move from pending to active or completed
                order_status = data.get('status')
                if order_status == 'filled' or order_status == 'partially_filled':
                    self.active_orders[order_id] = data
                    self.pending_orders.pop(order_id)
                elif order_status == 'rejected' or order_status == 'canceled':
                    self.order_history.append(data)
                    self.pending_orders.pop(order_id)
                
                # Notify subscribers
                for callback in self.on_order_updated:
                    callback(order_id, data)
    
    def _handle_error(self, message):
        """Handle error messages from MQL5"""
        error = message.get('data', {})
        print(f"Error from MQL5: {error.get('message', 'Unknown error')}")
        # Could dispatch to error handlers/UI here
    
    async def place_limit_order(self, symbol, direction, price, volume, stop_loss=None, take_profit=None):
        """Place a limit order through MQL5"""
        order_id = f"order_{int(time.time()*1000)}"
        
        order_data = {
            'order_id': order_id,
            'symbol': symbol,
            'type': 'limit',
            'direction': direction,  # 'buy' or 'sell'
            'price': price,
            'volume': volume,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'timestamp': time.time()
        }
        
        # Store in pending orders
        self.pending_orders[order_id] = order_data
        
        # Send to MQL5
        success = await self.pipe_manager.send_message(MessageType.ORDER_REQUEST, order_data)
        
        if not success:
            self.pending_orders.pop(order_id)
            return None
        
        return order_id
    
    async def cancel_order(self, order_id):
        """Cancel a pending order"""
        if order_id in self.pending_orders:
            cancel_data = {
                'order_id': order_id,
                'action': 'cancel'
            }
            
            success = await self.pipe_manager.send_message(MessageType.ORDER_REQUEST, cancel_data)
            return success
        
        return False
    
    def get_market_data(self, symbol=None):
        """Get current market data for a symbol or all symbols"""
        if symbol:
            return self.market_data.get(symbol)
        return self.market_data
    
    def get_order_info(self, order_id):
        """Get information about a specific order"""
        if order_id in self.active_orders:
            return self.active_orders[order_id]
        if order_id in self.pending_orders:
            return self.pending_orders[order_id]
        
        # Check history
        for order in self.order_history:
            if order.get('order_id') == order_id:
                return order
                
        return None


# ============ Panel UI ============

class TradingPanel:
    """Panel-based UI for the trading application"""
    
    def __init__(self, trading_engine):
        self.trading_engine = trading_engine
        self.pipe_manager = trading_engine.pipe_manager
        
        # Set theme
        pn.extension(sizing_mode='stretch_width')
        pn.config.sizing_mode = 'stretch_width'
        
        # Register callbacks
        self.trading_engine.on_market_data_updated.append(self._update_market_data_ui)
        self.trading_engine.on_order_updated.append(self._update_order_ui)
        
        # Create UI components
        self._create_ui_components()
        
    def _create_ui_components(self):
        """Create all UI components"""
        # Main layout with tabs
        self.tabs = pn.Tabs(
            sizing_mode='stretch_both'
        )
        
        # --- Order Entry Tab ---
        self.symbol_input = pn.widgets.Select(name='Symbol', options=['EURUSD', 'GBPUSD', 'USDJPY'], width=150)
        self.direction_input = pn.widgets.RadioButtonGroup(name='Direction', options=['Buy', 'Sell'], button_type='success')
        self.price_input = pn.widgets.FloatInput(name='Price', value=1.0, step=0.0001, width=150)
        self.volume_input = pn.widgets.FloatInput(name='Volume (lots)', value=0.1, step=0.01, width=150)
        self.sl_input = pn.widgets.FloatInput(name='Stop Loss', value=None, step=0.0001, width=150)
        self.tp_input = pn.widgets.FloatInput(name='Take Profit', value=None, step=0.0001, width=150)
        
        self.submit_button = pn.widgets.Button(name='Place Order', button_type='primary', width=150)
        self.submit_button.on_click(self._handle_order_submit)
        
        self.order_status = pn.widgets.StaticText(name='Status', value='Ready')
        
        order_form = pn.Column(
            pn.pane.Markdown("## Order Entry"),
            pn.Row(self.symbol_input, self.direction_input),
            pn.Row(self.price_input, self.volume_input),
            pn.Row(self.sl_input, self.tp_input),
            self.submit_button,
            self.order_status,
            sizing_mode='fixed'
        )
        
        # --- Market Data Tab ---
        self.market_data_table = pn.widgets.DataFrame(pd.DataFrame(columns=['Symbol', 'Bid', 'Ask', 'Spread', 'Time']))
        
        market_data_panel = pn.Column(
            pn.pane.Markdown("## Market Data"),
            self.market_data_table
        )
        
        # --- Orders Tab ---
        self.pending_orders_table = pn.widgets.DataFrame(pd.DataFrame())
        self.active_orders_table = pn.widgets.DataFrame(pd.DataFrame())
        
        orders_panel = pn.Column(
            pn.pane.Markdown("## Pending Orders"),
            self.pending_orders_table,
            pn.pane.Markdown("## Active Orders"),
            self.active_orders_table
        )
        
        # --- Settings Tab ---
        self.connection_status = pn.indicators.BooleanStatus(value=False, name='MQL5 Connection')
        
        settings_panel = pn.Column(
            pn.pane.Markdown("## Settings"),
            self.connection_status,
            pn.widgets.Button(name='Reconnect', button_type='warning')
        )
        
        # Add tabs to main layout
        self.tabs.append(('Order Entry', order_form))
        self.tabs.append(('Market Data', market_data_panel))
        self.tabs.append(('Orders', orders_panel))
        self.tabs.append(('Settings', settings_panel))
        
        # Create main layout
        self.main_layout = pn.Template(
            """
            <div class="container">
                <div class="header">
                    <h1>Trading Panel</h1>
                    {% content %}
                </div>
            </div>
            """
        ).add_panel('content', self.tabs)
    
    async def _handle_order_submit(self, event):
        """Handle order submission"""
        self.order_status.value = "Submitting order..."
        
        try:
            order_id = await self.trading_engine.place_limit_order(
                symbol=self.symbol_input.value,
                direction=self.direction_input.value.lower(),
                price=self.price_input.value,
                volume=self.volume_input.value,
                stop_loss=self.sl_input.value,
                take_profit=self.tp_input.value
            )
            
            if order_id:
                self.order_status.value = f"Order submitted: {order_id}"
            else:
                self.order_status.value = "Order submission failed"
                
        except Exception as e:
            self.order_status.value = f"Error: {str(e)}"
    
    def _update_market_data_ui(self, symbol, data):
        """Update market data in UI"""
        # Get current data
        df = self.market_data_table.value
        
        # Check if symbol exists
        symbol_idx = df[df['Symbol'] == symbol].index
        
        new_row = {
            'Symbol': symbol,
            'Bid': data.get('bid', 0),
            'Ask': data.get('ask', 0),
            'Spread': data.get('spread', 0),
            'Time': pd.to_datetime(data.get('time', 0), unit='s')
        }
        
        if len(symbol_idx) > 0:
            # Update existing row
            for col, value in new_row.items():
                df.at[symbol_idx[0], col] = value
        else:
            # Add new row
            df = pd.concat([df, pd.DataFrame([new_row])], ignore_index=True)
            
        self.market_data_table.value = df
    
    def _update_order_ui(self, order_id, data):
        """Update orders in UI"""
        # Update pending orders
        pending_df = pd.DataFrame([v for k, v in self.trading_engine.pending_orders.items()])
        if not pending_df.empty:
            self.pending_orders_table.value = pending_df
        else:
            self.pending_orders_table.value = pd.DataFrame()
            
        # Update active orders
        active_df = pd.DataFrame([v for k, v in self.trading_engine.active_orders.items()])
        if not active_df.empty:
            self.active_orders_table.value = active_df
        else:
            self.active_orders_table.value = pd.DataFrame()
    
    def update_connection_status(self, is_connected):
        """Update connection status indicator"""
        self.connection_status.value = is_connected
    
    def serve(self, port=5006):
        """Serve the Panel application"""
        return pn.serve(self.main_layout, port=port, show=True)


# ============ Main Application ============

async def main():
    # Initialize pipe manager
    pipe_manager = PipeManager()
    
    # Create pipes and wait for connection
    connected = await pipe_manager.create_pipes()
    if not connected:
        print("Failed to create pipes. Exiting.")
        return
    
    # Start pipe listener
    await pipe_manager.start_listening()
    
    # Initialize trading engine
    trading_engine = TradingEngine(pipe_manager)
    
    # Initialize UI
    ui = TradingPanel(trading_engine)
    ui.update_connection_status(pipe_manager.is_connected)
    
    # Start the application
    ui.serve()

if __name__ == "__main__":
    asyncio.run(main())