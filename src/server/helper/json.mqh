//+------------------------------------------------------------------+
//|                                                         json.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arturs V., Rihards S."
#property link      ""

class Json {
    public:
        Json() {}
        ~Json() {}

    string ParseCommand(string jsonStr) {
        int cmdStart = StringFind(jsonStr, "\"command\":");
        if(cmdStart >= 0) {
            cmdStart = StringFind(jsonStr, "\"", cmdStart + 10) + 1;
            int cmdEnd = StringFind(jsonStr, "\"", cmdStart);
            return StringSubstr(jsonStr, cmdStart, cmdEnd - cmdStart);
        }
        return "";
    }

    string ParseParams(string jsonStr) {
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
};
