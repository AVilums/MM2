# MM2/src/client/models/market_data.py
from dataclasses import dataclass
from typing import Dict, List, Optional, Any
from datetime import datetime

@dataclass
class OrderBookEntry:
    """Represents a single price level in the order book."""
    price: float
    size: float
    count: int = 1  # Number of orders at this price level
    
    def __post_init__(self):
        """Validate and convert types after initialization."""
        self.price = float(self.price)
        self.size = float(self.size)
        self.count = int(self.count)

@dataclass
class OrderBook:
    """Represents the current state of the order book."""
    bids: List[OrderBookEntry]  # Buy orders, sorted by price (descending)
    asks: List[OrderBookEntry]  # Sell orders, sorted by price (ascending)
    timestamp: datetime = None
    
    def __post_init__(self):
        """Set timestamp if not provided and sort entries."""
        if self.timestamp is None:
            self.timestamp = datetime.now()
            
        # Ensure proper sorting
        self.bids.sort(key=lambda x: x.price, reverse=True)  # Highest bids first
        self.asks.sort(key=lambda x: x.price)  # Lowest asks first
    
    @property
    def spread(self) -> float:
        """Calculate the current bid-ask spread."""
        if not self.bids or not self.asks:
            return float('inf')
        return self.asks[0].price - self.bids[0].price
    
    @property
    def mid_price(self) -> float:
        """Calculate the mid-price in the order book."""
        if not self.bids or not self.asks:
            return 0.0
        return (self.asks[0].price + self.bids[0].price) / 2
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'OrderBook':
        """Create an OrderBook instance from a dictionary."""
        bids = [OrderBookEntry(**item) for item in data.get('bids', [])]
        asks = [OrderBookEntry(**item) for item in data.get('asks', [])]
        timestamp = datetime.fromtimestamp(data.get('timestamp', datetime.now().timestamp()))
        return cls(bids=bids, asks=asks, timestamp=timestamp)

@dataclass
class Trade:
    """Represents a single trade that has occurred."""
    price: float
    size: float
    side: str  # 'buy' or 'sell'
    timestamp: datetime = None
    trade_id: str = None
    
    def __post_init__(self):
        """Validate and convert types after initialization."""
        self.price = float(self.price)
        self.size = float(self.size)
        if self.timestamp is None:
            self.timestamp = datetime.now()

@dataclass
class MarketData:
    """Holds current market data and analytics."""
    symbol: str
    order_book: OrderBook
    last_trade: Optional[Trade] = None
    recent_trades: List[Trade] = None
    timestamp: datetime = None
    
    def __post_init__(self):
        """Initialize empty containers if None provided."""
        if self.recent_trades is None:
            self.recent_trades = []
        if self.timestamp is None:
            self.timestamp = datetime.now()
    
    @property
    def is_valid(self) -> bool:
        """Check if the market data is valid and usable."""
        return bool(self.order_book and self.order_book.bids and self.order_book.asks)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'MarketData':
        """Create a MarketData instance from a dictionary."""
        order_book = OrderBook.from_dict(data.get('order_book', {'bids': [], 'asks': []}))
        
        # Process last trade if available
        last_trade = None
        if 'last_trade' in data and data['last_trade']:
            last_trade = Trade(**data['last_trade'])
        
        # Process recent trades if available
        recent_trades = []
        if 'recent_trades' in data and data['recent_trades']:
            recent_trades = [Trade(**trade) for trade in data['recent_trades']]
        
        # Get timestamp or default to now
        timestamp = datetime.fromtimestamp(data.get('timestamp', datetime.now().timestamp()))
        
        return cls(
            symbol=data.get('symbol', 'unknown'),
            order_book=order_book,
            last_trade=last_trade,
            recent_trades=recent_trades,
            timestamp=timestamp
        )