//+------------------------------------------------------------------+
//| Python Pipe Communication Script                                 |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "Your Website"
#property version   "1.00"
#property strict

#include <WinAPI/winapi.mqh>

// Pipe constants
#define PIPE_NAME "\\\\.\\pipe\\mql5_python_pipe"
#define BUFFER_SIZE 65536

// Global variables
int hPipe = INVALID_HANDLE_VALUE;
bool isConnected = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    EventSetMillisecondTimer(1000); // Check for pipe connections every second
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DisconnectPipe();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Try to connect if not already connected
    if(!isConnected)
    {
        ConnectToPipe();
    }
    
    // Process any pending messages
    if(isConnected)
    {
        ProcessPipeMessages();
    }
}

//+------------------------------------------------------------------+
//| Connect to the named pipe                                        |
//+------------------------------------------------------------------+
bool ConnectToPipe()
{
    if(isConnected) return true;
    
    // Try to connect to existing pipe
    hPipe = CreateFileA(PIPE_NAME, GENERIC_READ | GENERIC_WRITE, 
                      0, NULL, OPEN_EXISTING, 0, NULL);
                      
    if(hPipe != INVALID_HANDLE_VALUE)
    {
        Print("Connected to Python pipe");
        isConnected = true;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Disconnect from the pipe                                         |
//+------------------------------------------------------------------+
void DisconnectPipe()
{
    if(hPipe != INVALID_HANDLE_VALUE)
    {
        CloseHandle(hPipe);
        hPipe = INVALID_HANDLE_VALUE;
    }
    isConnected = false;
}

//+------------------------------------------------------------------+
//| Process pipe messages                                            |
//+------------------------------------------------------------------+
void ProcessPipeMessages()
{
    if(!isConnected) return;
    
    DWORD bytesAvailable = 0;
    
    // Check if there's data to read
    if(!PeekNamedPipe(hPipe, NULL, 0, NULL, &bytesAvailable, NULL) || bytesAvailable == 0)
    {
        // No data or error
        return;
    }
    
    // Read and process data
    char buffer[BUFFER_SIZE];
    DWORD bytesRead = 0;
    
    if(ReadFile(hPipe, buffer, BUFFER_SIZE, &bytesRead, NULL) && bytesRead > 0)
    {
        string message = CharArrayToString(buffer, 0, bytesRead);
        Print("Received from Python: ", message);
        
        // Parse the JSON message
        JSONParser parser;
        JSONValue jValue;
        
        if(parser.parse(message, jValue))
        {
            string command = jValue["command"].getString();
            JSONValue params = jValue["params"];
            
            string response = ProcessCommand(command, params);
            
            // Send response back to Python
            SendToPipe(response);
        }
    }
    else
    {
        // Error reading or pipe closed
        DisconnectPipe();
    }
}

//+------------------------------------------------------------------+
//| Process commands received from Python                            |
//+------------------------------------------------------------------+
string ProcessCommand(string command, JSONValue &params)
{
    JSONValue responseObj;
    
    if(command == "refresh")
    {
        // Get market and account info
        responseObj["status"] = "success";
        
        JSONValue marketInfo;
        marketInfo["symbol"] = Symbol();
        marketInfo["bid"] = DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), Digits());
        marketInfo["ask"] = DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_ASK), Digits());
        
        JSONValue accountInfo;
        accountInfo["balance"] = DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
        accountInfo["equity"] = DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
        
        JSONValue data;
        data["market_info"] = marketInfo;
        data["account_info"] = accountInfo;
        
        responseObj["data"] = data;
    }
    else if(command == "algo")
    {
        // Set algorithm parameters
        double range = params["range"].getDouble();
        bool active = params["active"].getBool();
        
        // Apply algo settings
        // ... your implementation ...
        
        responseObj["status"] = "success";
    }
    else if(command == "limit")
    {
        // Place limit order
        double price = params["price"].getDouble();
        double size = params["size"].getDouble();
        
        // Place order
        // ... your implementation ...
        
        responseObj["status"] = "success";
    }
    else if(command == "mid_price")
    {
        // Place mid-price order
        double size = params["size"].getDouble();
        string side = params["side"].getString();
        
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double midPrice = (bid + ask) / 2;
        
        // Place order at mid price
        // ... your implementation ...
        
        responseObj["status"] = "success";
    }
    else
    {
        responseObj["status"] = "error";
        responseObj["message"] = "Unknown command: " + command;
    }
    
    return responseObj.toString();
}

//+------------------------------------------------------------------+
//| Send data to the pipe                                            |
//+------------------------------------------------------------------+
bool SendToPipe(string data)
{
    if(!isConnected) return false;
    
    uchar buffer[];
    StringToCharArray(data, buffer);
    uint size = ArraySize(buffer);
    
    DWORD bytesWritten = 0;
    bool result = WriteFile(hPipe, buffer, size, &bytesWritten, NULL);
    
    return result && bytesWritten == size;
}