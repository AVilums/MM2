//+------------------------------------------------------------------+
//| MQL5 Python Communication Script                                 |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "Your Website"
#property version   "1.00"
#property strict

// Include necessary files for WinAPI functions
#include <WinAPI/WinAPI.mqh>

// Pipe constants
#define PIPE_BUFFER_SIZE 65536

// Global variables
int g_hPipe = -1;  // Invalid handle value
bool g_isConnected = false;

// JSON handling structures - simplified for MQL5
struct JSONValue {
   string key;
   string stringValue;
   double doubleValue;
   bool boolValue;
   int valueType; // 0=string, 1=double, 2=bool
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetMillisecondTimer(1000); // Check for pipe connections every second
   Print("Python communication EA initialized. Waiting for pipe connection...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DisconnectPipe();
   Print("Python communication EA deinitialized");
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
   // Try to connect if not already connected
   if(!g_isConnected) { ConnectToPipe(); }

   // Process any pending messages
   if(g_isConnected) { 
    ProcessPipeMessages();
   }
}

//+------------------------------------------------------------------+
//| Connect to the named pipe                                        |
//+------------------------------------------------------------------+
bool ConnectToPipe() {
   if(g_isConnected) return true;
   
   // Try to connect to existing pipe
   string pipeName = "\\\\.\\pipe\\mql5_python_pipe";
   g_hPipe = FileOpen(pipeName, FILE_READ|FILE_WRITE|FILE_BIN);
   
   if(g_hPipe != INVALID_HANDLE) {
      Print("Connected to Python pipe");
      g_isConnected = true;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Disconnect from the pipe                                         |
//+------------------------------------------------------------------+
void DisconnectPipe() {
   if(g_hPipe != INVALID_HANDLE) {
      FileClose(g_hPipe);
      g_hPipe = INVALID_HANDLE;
   }
   g_isConnected = false;
   Print("Disconnected from pipe");
}

//+------------------------------------------------------------------+
//| Process pipe messages                                            |
//+------------------------------------------------------------------+
void ProcessPipeMessages() {
   if(!g_isConnected) return;
   
   // Check if there's data to read
   if(FileSize(g_hPipe) > 0) {
      // Read data
      string message = "";
      uchar buffer[];
      ArrayResize(buffer, PIPE_BUFFER_SIZE);
      uint bytesRead = FileReadArray(g_hPipe, buffer, 0, PIPE_BUFFER_SIZE);
      
      if(bytesRead > 0) {
         message = CharArrayToString(buffer, 0, bytesRead);
         Print("Received from Python: ", message);
         
         // Parse the message and process command
         string command = ParseJsonCommand(message);
         string params = ParseJsonParams(message);
         
         string response = ProcessCommand(command, params);
         
         // Send response back to Python
         SendToPipe(response);
      }
   }
}

//+------------------------------------------------------------------+
//| Simple JSON command parser                                       |
//+------------------------------------------------------------------+
string ParseJsonCommand(string jsonStr) {
   int cmdStart = StringFind(jsonStr, "\"command\":");
   if(cmdStart >= 0) {
      cmdStart = StringFind(jsonStr, "\"", cmdStart + 10) + 1;
      int cmdEnd = StringFind(jsonStr, "\"", cmdStart);
      return StringSubstr(jsonStr, cmdStart, cmdEnd - cmdStart);
   }
   return "";
}

//+------------------------------------------------------------------+
//| Simple JSON params parser                                        |
//+------------------------------------------------------------------+
string ParseJsonParams(string jsonStr) {
   int paramsStart = StringFind(jsonStr, "\"params\":");
   if(paramsStart >= 0) {
      int braceStart = StringFind(jsonStr, "{", paramsStart);
      if(braceStart < 0) return "{}";
      
      int braceCount = 1;
      int pos = braceStart + 1;
      
      while(braceCount > 0 && pos < StringLen(jsonStr)) {
         if(StringGetCharacter(jsonStr, pos) == '{') braceCount++;
         if(StringGetCharacter(jsonStr, pos) == '}') braceCount--;
         pos++;
      }
      
      return StringSubstr(jsonStr, braceStart, pos - braceStart);
   }
   return "{}";
}

//+------------------------------------------------------------------+
//| Get value from JSON params - string                              |
//+------------------------------------------------------------------+
string GetParamString(string params, string key) {
   string searchKey = "\"" + key + "\":\"";
   int start = StringFind(params, searchKey);
   if(start >= 0) {
      start += StringLen(searchKey);
      int end = StringFind(params, "\"", start);
      return StringSubstr(params, start, end - start);
   }
   return "";
}

//+------------------------------------------------------------------+
//| Get value from JSON params - double                              |
//+------------------------------------------------------------------+
double GetParamDouble(string params, string key) {
   string searchKey = "\"" + key + "\":";
   int start = StringFind(params, searchKey);
   if(start >= 0) {
      start += StringLen(searchKey);
      int end = StringFind(params, ",", start);
      if(end < 0) end = StringFind(params, "}", start);
      string valueStr = StringSubstr(params, start, end - start);
      return StringToDouble(valueStr);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get value from JSON params - boolean                             |
//+------------------------------------------------------------------+
bool GetParamBool(string params, string key) {
   string searchKey = "\"" + key + "\":";
   int start = StringFind(params, searchKey);
   if(start >= 0) {
      start += StringLen(searchKey);
      string valueStr = "";
      if(StringSubstr(params, start, 4) == "true") return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Process commands received from Python                            |
//+------------------------------------------------------------------+
string ProcessCommand(string command, string params) {
   string response = "";
   
   if(command == "refresh") {
      // Get market and account info
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      response = "{\"status\":\"success\",\"data\":{\"market_info\":{\"symbol\":\"" + _Symbol + 
                "\",\"bid\":" + DoubleToString(bid, _Digits) + 
                ",\"ask\":" + DoubleToString(ask, _Digits) + 
                "},\"account_info\":{\"balance\":" + DoubleToString(balance, 2) + 
                ",\"equity\":" + DoubleToString(equity, 2) + "}}}";
   } else if(command == "algo") {
      // Set algorithm parameters
      double range = GetParamDouble(params, "range");
      bool active = GetParamBool(params, "active");
      
      // Here you would apply algorithm settings to your chart
      // For example, draw objects or set global variables
      
      Print("Setting algorithm: range=", range, ", active=", active);
      
      if(active) {
         // Draw rectangle for visualization
         ObjectCreate(0, "AlgoRange", OBJ_RECTANGLE, 0, 
                     TimeCurrent(), SymbolInfoDouble(_Symbol, SYMBOL_BID) - range * _Point,
                     TimeCurrent() + PeriodSeconds(PERIOD_D1), SymbolInfoDouble(_Symbol, SYMBOL_BID) + range * _Point);
         ObjectSetInteger(0, "AlgoRange", OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(0, "AlgoRange", OBJPROP_FILL, true);
         ObjectSetInteger(0, "AlgoRange", OBJPROP_BACK, true);
         ObjectSetInteger(0, "AlgoRange", OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, "AlgoRange", OBJPROP_SELECTABLE, false);
      } else {
         // Remove visualization
         ObjectDelete(0, "AlgoRange");
      }
      
      response = "{\"status\":\"success\",\"message\":\"Algorithm settings updated\"}";
   } else if(command == "limit") {
      // Place limit order
      double price = GetParamDouble(params, "price");
      double size = GetParamDouble(params, "size");
      
      Print("Placing limit order: price=", price, ", size=", size);
      
      // Determine order type based on price
      ENUM_ORDER_TYPE orderType = SymbolInfoDouble(_Symbol, SYMBOL_ASK) > price ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      
      // Place the order
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = size;
      request.type = orderType;
      request.price = price;
      request.deviation = 10; // slippage in points
      request.magic = 123456; // magic number
      
      bool success = OrderSend(request, result);
      
      if(success && result.retcode == TRADE_RETCODE_DONE) {
         response = "{\"status\":\"success\",\"message\":\"Limit order placed successfully\"}";
      } else {
         response = "{\"status\":\"error\",\"message\":\"Failed to place limit order: " + 
                   IntegerToString(result.retcode) + "\"}";
      }
   } else if(command == "mid_price") {
      // Place mid-price order
      double size = GetParamDouble(params, "size");
      string side = GetParamString(params, "side");
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double midPrice = (bid + ask) / 2;
      
      Print("Placing mid-price order: side=", side, ", size=", size, ", mid-price=", midPrice);
      
      // Determine order type
      ENUM_ORDER_TYPE orderType = side == "buy" ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      
      // Place the order
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = size;
      request.type = orderType;
      request.price = midPrice;
      request.deviation = 10; // slippage in points
      request.magic = 123456; // magic number
      
      bool success = OrderSend(request, result);
      
      if(success && result.retcode == TRADE_RETCODE_DONE) {
         response = "{\"status\":\"success\",\"message\":\"Mid-price order placed successfully\"}";
      } else {
         response = "{\"status\":\"error\",\"message\":\"Failed to place mid-price order: " + 
                   IntegerToString(result.retcode) + "\"}";
      }
   } else {
      response = "{\"status\":\"error\",\"message\":\"Unknown command: " + command + "\"}";
   }
   
   return response;
}

//+------------------------------------------------------------------+
//| Send data to the pipe                                            |
//+------------------------------------------------------------------+
bool SendToPipe(string data) {
   if(!g_isConnected) return false;

   uchar buffer[];
   StringToCharArray(data, buffer);
   uint size = ArraySize(buffer);

   uint bytesWritten = FileWriteArray(g_hPipe, buffer, 0, size);

   return bytesWritten == size;
}