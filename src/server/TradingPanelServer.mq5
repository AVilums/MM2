//+------------------------------------------------------------------+
//|                                              TradingPanelMT5.mq5 |
//|                                       Trading Panel MQL5 Backend |
//+------------------------------------------------------------------+
#property copyright "Trading Panel"
#property version   "1.00"
#property strict

// Include required libraries
#include <WinAPI\winapi.mqh>
#include <JSON\json.mqh>
#include <Arrays\ArrayString.mqh>

// Named pipe constants
#define PIPE_ACCESS_DUPLEX 0x00000003
#define PIPE_READMODE_MESSAGE 0x00000002
#define PIPE_TYPE_MESSAGE 0x00000004
#define PIPE_WAIT 0x00000000
#define ERROR_PIPE_BUSY 231
#define BUFFER_SIZE 65536

// Global variables
string readPipeName = "\\\\.\\pipe\\python_to_mt5";  // Read from Python
string writePipeName = "\\\\.\\pipe\\mt5_to_python"; // Write to Python
int readPipeHandle = INVALID_HANDLE;
int writePipeHandle = INVALID_HANDLE;
bool isConnected = false;
int lastHeartbeatTime = 0;
int heartbeatInterval = 10; // Seconds
bool isRunning = true;

// Order tracking
CArrayString pendingOrderIds;
CArrayString activeOrderIds;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Trading Panel Backend initializing...");
    
    // Initialize named pipes
    if (!InitializePipes())
    {
        Print("Failed to initialize pipes. Exiting.");
        return INIT_FAILED;
    }
    
    // Start background execution
    EventSetTimer(1);  // 1 second timer for regular checks
    
    Print("Trading Panel Backend initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    isRunning = false;
    ClosePipes();
    EventKillTimer();
    Print("Trading Panel Backend stopped");
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Check and maintain connection
    if (!isConnected && isRunning)
    {
        if (!InitializePipes())
        {
            Print("Still waiting for Python client...");
            return;
        }
    }
    
    // Process incoming messages
    ProcessIncomingMessages();
    
    // Send heartbeat if needed
    int currentTime = (int)TimeLocal();
    if (currentTime - lastHeartbeatTime >= heartbeatInterval)
    {
        SendHeartbeat();
        lastHeartbeatTime = currentTime;
    }
    
    // Send market data updates
    SendMarketData();
}

//+------------------------------------------------------------------+
//| Initialize the named pipes                                       |
//+------------------------------------------------------------------+
bool InitializePipes()
{
    if (isConnected)
        return true;
        
    // Close pipes if they're already open
    ClosePipes();
    
    // Create write pipe (to Python)
    writePipeHandle = CreateNamedPipe(
        writePipeName,            // Pipe name
        PIPE_ACCESS_DUPLEX,       // Read/write access
        PIPE_TYPE_MESSAGE |       // Message-type pipe
        PIPE_READMODE_MESSAGE |   // Message-read mode
        PIPE_WAIT,                // Blocking mode
        1,                        // Max instances
        BUFFER_SIZE,              // Output buffer size
        BUFFER_SIZE,              // Input buffer size
        0,                        // Client timeout
        NULL                      // Default security attributes
    );
    
    if (writePipeHandle == INVALID_HANDLE)
    {
        Print("Failed to create write pipe: ", GetLastError());
        return false;
    }
    
    Print("Waiting for Python client to connect...");
    
    // Wait for client to connect to write pipe
    if (!ConnectNamedPipe(writePipeHandle, NULL) && GetLastError() != ERROR_PIPE_CONNECTED)
    {
        Print("Failed to connect write pipe: ", GetLastError());
        CloseHandle(writePipeHandle);
        writePipeHandle = INVALID_HANDLE;
        return false;
    }
    
    // Connect to read pipe (from Python)
    readPipeHandle = CreateFile(
        readPipeName,             // Pipe name
        GENERIC_READ | GENERIC_WRITE, // Read/write access
        0,                        // No sharing
        NULL,                     // Default security attributes
        OPEN_EXISTING,            // Opens existing pipe
        0,                        // Default attributes
        NULL                      // No template file
    );
    
    if (readPipeHandle == INVALID_HANDLE)
    {
        Print("Failed to connect to read pipe: ", GetLastError());
        CloseHandle(writePipeHandle);
        writePipeHandle = INVALID_HANDLE;
        return false;
    }
    
    isConnected = true;
    lastHeartbeatTime = (int)TimeLocal();
    Print("Pipe connection established with Python");
    
    return true;
}

//+------------------------------------------------------------------+
//| Close the named pipes                                            |
//+------------------------------------------------------------------+
void ClosePipes()
{
    if (readPipeHandle != INVALID_HANDLE)
    {
        CloseHandle(readPipeHandle);
        readPipeHandle = INVALID_HANDLE;
    }
    
    if (writePipeHandle != INVALID_HANDLE)
    {
        CloseHandle(writePipeHandle);
        writePipeHandle = INVALID_HANDLE;
    }
    
    isConnected = false;
}

//+------------------------------------------------------------------+
//| Process incoming messages from Python                            |
//+------------------------------------------------------------------+
void ProcessIncomingMessages()
{
    if (!isConnected || readPipeHandle == INVALID_HANDLE)
        return;
    
    string message = "";
    if (ReadFromPipe(message))
    {
        // Parse JSON message
        CJAVal jsonData;
        if (!jsonData.Deserialize(message))
        {
            Print("Failed to parse JSON message: ", message);
            return;
        }
        
        // Process based on message type
        string msgType = jsonData["type"].ToStr();
        
        if (msgType == "order_request")
        {
            ProcessOrderRequest(jsonData["data"]);
        }
        else if (msgType == "heartbeat")
        {
            // Just acknowledge heartbeat
            lastHeartbeatTime = (int)TimeLocal();
        }
    }
}

//+------------------------------------------------------------------+
//| Read a message from the pipe                                     |
//+------------------------------------------------------------------+
bool ReadFromPipe(string &message)
{
    if (readPipeHandle == INVALID_HANDLE)
        return false;
    
    uint bytesAvailable = 0;
    if (!PeekNamedPipe(readPipeHandle, NULL, 0, NULL, bytesAvailable, NULL))
    {
        // Check if pipe was closed or broken
        if (GetLastError() == ERROR_BROKEN_PIPE || GetLastError() == ERROR_NO_DATA)
        {
            Print("Pipe disconnected: ", GetLastError());
            isConnected = false;
            return false;
        }
        return false;
    }
    
    if (bytesAvailable == 0)
        return false;
    
    uchar buffer[];
    ArrayResize(buffer, BUFFER_SIZE);
    ZeroMemory(buffer);
    
    uint bytesRead = 0;
    if (!ReadFile(readPipeHandle, buffer, BUFFER_SIZE, bytesRead, NULL))
    {
        Print("Failed to read from pipe: ", GetLastError());
        return false;
    }
    
    if (bytesRead > 0)
    {
        message = CharArrayToString(buffer, 0, bytesRead, CP_UTF8);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Send a message to the pipe                                       |
//+------------------------------------------------------------------+
bool WriteToPipe(const string message)
{
    if (!isConnected || writePipeHandle == INVALID_HANDLE)
        return false;
    
    uchar buffer[];
    int stringLength = StringToCharArray(message, buffer, 0, WHOLE_ARRAY, CP_UTF8);
    
    uint bytesWritten = 0;
    if (!WriteFile(writePipeHandle, buffer, stringLength, bytesWritten, NULL))
    {
        Print("Failed to write to pipe: ", GetLastError());
        isConnected = false;
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Send heartbeat message to Python                                 |
//+------------------------------------------------------------------+
void SendHeartbeat()
{
    if (!isConnected)
        return;
    
    CJAVal jsonData;
    jsonData["type"] = "heartbeat";
    jsonData["timestamp"] = TimeLocal();
    jsonData["data"]["status"] = "alive";
    
    string message = jsonData.Serialize();
    WriteToPipe(message);
}

//+------------------------------------------------------------------+
//| Send market data updates to Python                               |
//+------------------------------------------------------------------+
void SendMarketData()
{
    if (!isConnected)
        return;
    
    // List of symbols to send updates for
    string symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "XAUUSD"};
    
    for (int i = 0; i < ArraySize(symbols); i++)
    {
        string symbol = symbols[i];
        
        MqlTick tick;
        if (SymbolInfoTick(symbol, tick))
        {
            CJAVal jsonData, data;
            
            jsonData["type"] = "market_data";
            jsonData["timestamp"] = TimeLocal();
            
            data["symbol"] = symbol;
            data["bid"] = tick.bid;
            data["ask"] = tick.ask;
            data["spread"] = (tick.ask - tick.bid) / _Point;
            data["time"] = tick.time;
            data["volume"] = tick.volume;
            data["flags"] = tick.flags;
            
            jsonData["data"] = data;
            
            string message = jsonData.Serialize();
            WriteToPipe(message);
        }
    }
}

//+------------------------------------------------------------------+
//| Process order requests from Python                               |
//+------------------------------------------------------------------+
void ProcessOrderRequest(CJAVal &data)
{
    string orderId = data["order_id"].ToStr();
    string action = data["action"].ToStr();
    
    // Check if it's a cancel request
    if (action == "cancel")
    {
        CancelOrder(orderId);
        return;
    }
    
    // Otherwise, it's a new order request
    string symbol = data["symbol"].ToStr();
    string type = data["type"].ToStr();
    string direction = data["direction"].ToStr();
    double price = data["price"].ToDbl();
    double volume = data["volume"].ToDbl();
    double stopLoss = data["stop_loss"].ToDbl();
    double takeProfit = data["take_profit"].ToDbl();
    
    // Place the order
    if (type == "limit")
    {
        PlaceLimitOrder(orderId, symbol, direction, price, volume, stopLoss, takeProfit);
    }
}

//+------------------------------------------------------------------+
//| Place a limit order                                              |
//+------------------------------------------------------------------+
void PlaceLimitOrder(const string orderId, const string symbol, const string direction, 
                     double price, double volume, double stopLoss, double takeProfit)
{
    // Initialize trade object
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    
    // Setup order parameters
    request.action = TRADE_ACTION_PENDING;
    request.symbol = symbol;
    request.volume = volume;
    request.price = price;
    
    // Set order type based on direction
    if (direction == "buy")
    {
        request.type = ORDER_TYPE_BUY_LIMIT;
    }
    else if (direction == "sell")
    {
        request.type = ORDER_TYPE_SELL_LIMIT;
    }
    else
    {
        // Invalid direction
        SendOrderResponse(orderId, "rejected", "Invalid direction: " + direction);
        return;
    }
    
    // Set stop loss and take profit if provided
    if (stopLoss > 0)
    {
        request.sl = stopLoss;
    }
    
    if (takeProfit > 0)
    {
        request.tp = takeProfit;
    }
    
    // Additional parameters
    request.deviation = 10; // Maximum price slippage in points
    request.type_filling = ORDER_FILLING_IOC; // Immediate or cancel
    request.comment = "Order ID: " + orderId;
    
    // Send the order
    bool success = OrderSend(request, result);
    
    // Handle order result
    if (success && result.retcode == TRADE_RETCODE_DONE)
    {
        // Add to pending orders list
        AddToPendingOrders(orderId);
        
        // Send success response
        CJAVal responseData;
        responseData["mt5_ticket"] = result.order;
        responseData["status"] = "pending";
        
        SendOrderResponse(orderId, "pending", responseData);
    }
    else
    {
        // Send error response
        SendOrderResponse(orderId, "rejected", "Error code: " + IntegerToString(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Add order ID to pending list                                     |
//+------------------------------------------------------------------+
void AddToPendingOrders(const string orderId)
{
    pendingOrderIds.Add(orderId);
}

//+------------------------------------------------------------------+
//| Add order ID to active list                                      |
//+------------------------------------------------------------------+
void AddToActiveOrders(const string orderId)
{
    activeOrderIds.Add(orderId);
}

//+------------------------------------------------------------------+
//| Remove order ID from pending list                                |
//+------------------------------------------------------------------+
void RemoveFromPendingOrders(const string orderId)
{
    for (int i = 0; i < pendingOrderIds.Total(); i++)
    {
        if (pendingOrderIds.At(i) == orderId)
        {
            pendingOrderIds.Delete(i);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Remove order ID from active list                                 |
//+------------------------------------------------------------------+
void RemoveFromActiveOrders(const string orderId)
{
    for (int i = 0; i < activeOrderIds.Total(); i++)
    {
        if (activeOrderIds.At(i) == orderId)
        {
            activeOrderIds.Delete(i);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Cancel a pending order                                           |
//+------------------------------------------------------------------+
void CancelOrder(const string orderId)
{
    // Find the MT5 ticket for this order ID
    int ticket = FindTicketByOrderId(orderId);
    
    if (ticket <= 0)
    {
        SendOrderResponse(orderId, "error", "Order not found: " + orderId);
        return;
    }
    
    // Initialize trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    
    // Setup cancel parameters
    request.action = TRADE_ACTION_REMOVE;
    request.order = ticket;
    
    // Send the cancel request
    bool success = OrderSend(request, result);
    
    // Handle result
    if (success && result.retcode == TRADE_RETCODE_DONE)
    {
        // Remove from tracking lists
        RemoveFromPendingOrders(orderId);
        RemoveFromActiveOrders(orderId);
        
        // Send success response
        SendOrderResponse(orderId, "canceled", "Order successfully canceled");
    }
    else
    {
        // Send error response
        SendOrderResponse(orderId, "error", "Failed to cancel order: " + IntegerToString(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Find MT5 ticket by order ID                                      |
//+------------------------------------------------------------------+
int FindTicketByOrderId(const string orderId)
{
    // Search in open orders
    int totalOrders = OrdersTotal();
    for (int i = 0; i < totalOrders; i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (OrderSelect(ticket))
        {
            string comment = OrderGetString(ORDER_COMMENT);
            if (StringFind(comment, "Order ID: " + orderId) >= 0)
            {
                return (int)ticket;
            }
        }
    }
    
    // Search in open positions
    int totalPositions = PositionsTotal();
    for (int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "Order ID: " + orderId) >= 0)
            {
                return (int)ticket;
            }
        }
    }
    
    return 0; // Not found
}

//+------------------------------------------------------------------+
//| Send order response back to Python                               |
//+------------------------------------------------------------------+
void SendOrderResponse(const string orderId, const string status, const string message)
{
    CJAVal jsonData, data;
    
    jsonData["type"] = "order_response";
    jsonData["timestamp"] = TimeLocal();
    
    data["order_id"] = orderId;
    data["status"] = status;
    data["message"] = message;
    
    jsonData["data"] = data;
    
    string jsonMessage = jsonData.Serialize();
    WriteToPipe(jsonMessage);
}

//+------------------------------------------------------------------+
//| Overloaded: Send order response with JSON data                   |
//+------------------------------------------------------------------+
void SendOrderResponse(const string orderId, const string status, CJAVal &additionalData)
{
    CJAVal jsonData, data;
    
    jsonData["type"] = "order_response";
    jsonData["timestamp"] = TimeLocal();
    
    data["order_id"] = orderId;
    data["status"] = status;
    
    // Add all additional data fields
    for (int i = 0; i < additionalData.Size(); i++)
    {
        string key = additionalData.Key(i);
        if (key != "")
        {
            data[key] = additionalData[key];
        }
    }
    
    jsonData["data"] = data;
    
    string jsonMessage = jsonData.Serialize();
    WriteToPipe(jsonMessage);
}

//+------------------------------------------------------------------+
//| OnTrade event handler                                           |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Check for order status changes
    CheckOrderStatuses();
}

//+------------------------------------------------------------------+
//| Check status of all tracked orders                               |
//+------------------------------------------------------------------+
void CheckOrderStatuses()
{
    // Check pending orders
    for (int i = 0; i < pendingOrderIds.Total(); i++)
    {
        string orderId = pendingOrderIds.At(i);
        int ticket = FindTicketByOrderId(orderId);
        
        // If ticket not found, order might have been filled or canceled
        if (ticket <= 0)
        {
            // Check if it's now an active position
            bool isActive = false;
            int totalPositions = PositionsTotal();
            for (int j = 0; j < totalPositions; j++)
            {
                ulong posTicket = PositionGetTicket(j);
                if (PositionSelectByTicket(posTicket))
                {
                    string comment = PositionGetString(POSITION_COMMENT);
                    if (StringFind(comment, "Order ID: " + orderId) >= 0)
                    {
                        // Order was filled and is now a position
                        RemoveFromPendingOrders(orderId);
                        AddToActiveOrders(orderId);
                        
                        // Send filled notification
                        CJAVal responseData;
                        responseData["mt5_ticket"] = (int)posTicket;
                        responseData["price"] = PositionGetDouble(POSITION_PRICE_OPEN);
                        responseData["volume"] = PositionGetDouble(POSITION_VOLUME);
                        
                        SendOrderResponse(orderId, "filled", responseData);
                        isActive = true;
                        break;
                    }
                }
            }
            
            // If not active and not found, assume it was canceled
            if (!isActive)
            {
                RemoveFromPendingOrders(orderId);
                SendOrderResponse(orderId, "canceled", "Order was canceled or expired");
            }
        }
    }
    
    // Check active orders
    for (int i = 0; i < activeOrderIds.Total(); i++)
    {
        string orderId = activeOrderIds.At(i);
        int ticket = FindTicketByOrderId(orderId);
        
        // If ticket not found, position might have been closed
        if (ticket <= 0)
        {
            RemoveFromActiveOrders(orderId);
            SendOrderResponse(orderId, "closed", "Position was closed");
        }
    }
}