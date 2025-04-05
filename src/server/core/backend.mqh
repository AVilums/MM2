#include <Trade\Trade.mqh>
#include "../core/npipe.mqh"
#include "../helper/json.mqh"

class Backend {
  private:
    NamedPipe *npipe;
    Json *json;
    
  public:
    Backend(string pipeName) {
        npipe = new NamedPipe(pipeName);
        json = new Json();
    }
        
    ~Backend() { 
        npipe.Disconnect();
        delete npipe;
        delete json;
    }
    
    bool Run() {
        if (npipe.isConnected() == false) {
            npipe.Connect();
        } 
            
        if (FileSize(npipe.getHandle()) <= 0) return false;
        
        string data = npipe.Read();
        if (StringLen(data) > 0) {
            // Parse the message and process command
            string command = json.ParseCommand(data);
            string params = json.ParseParams(data);

            printf("Received command: %s", command);
            printf("Received params: %s", params);

            // Handle commands
            string response = ProcessCommand(command, params);

            npipe.Send(response);
        }
        return true;
    }

    string ProcessCommand(string command, string params) {
        string response = "";

        if (command == "refresh") {
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
            double range = json.GetParamDouble(params, "range");
            bool active = json.GetParamBool(params, "active");
                        
            response = "{\"status\":\"success\",\"message\":\"Algorithm settings updated\"}";
        } else if(command == "limit") {
            // Place limit order
            double price = json.GetParamDouble(params, "price");
            double size = json.GetParamDouble(params, "size");
                        
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
            double size = json.GetParamDouble(params, "size");
            string side = json.GetParamString(params, "side");
            
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double midPrice = (bid + ask) / 2;
                        
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
};