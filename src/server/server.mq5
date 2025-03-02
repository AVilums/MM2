#property copyright "Copyright 2025, Arturs Vilums"

#include "server.mqh"

// Create a global instance of CNamedPipe
CNamedPipe PipeServer;

// Function to start the pipe server
void StartPipeServer() {
    if (!PipeServer.Create(true)) {
        Print("Error: Failed to create named pipe.");
        return;
    }

    Print("Named pipe created ", PipeServer.GetPipeName() ,". Waiting for Python connection...");

    if (!PipeServer.Connect()) {
        Print("Error: Failed to connect named pipe.");
        return;
    }

    Print("Python connected. Ready to receive orders.");

    while (!IsStopped()) {
        string order_data = PipeServer.ReadANSI();
        if (order_data != "") {
            ProcessOrder(order_data);
            PipeServer.WriteANSI("Order Executed");
        }
    }

    PipeServer.Close();
}

// Function to process the received order
void ProcessOrder(string order_info) {
    Print("Received Order: ", order_info);

    string parts[];
    StringSplit(order_info, ' ', parts);
    if (ArraySize(parts) < 3) {
        Print("Invalid order format");
        return;
    }

    string type = parts[0]; // "BUY" or "SELL"
    double lot = StringToDouble(parts[1]);
    string symbol = parts[2];

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.type = (type == "BUY") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.symbol = symbol;
    request.volume = lot;
    request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
    request.deviation = 10;
    request.type_filling = ORDER_FILLING_IOC;
    request.type_time = ORDER_TIME_GTC;

    if (!OrderSend(request, result)) {
        Print("Order failed: ", result.comment);
    } else {
        Print("Order placed successfully: Ticket ", result.order);
    }
}

// Entry point
void OnStart() {
    StartPipeServer();
}
