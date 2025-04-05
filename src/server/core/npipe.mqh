//+------------------------------------------------------------------+
//|                                                        npipe.mqh |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arturs V., Rihards S."
#property link      ""

// Pipe constants
#define PIPE_BUFFER_SIZE 65536
#define PIPE_TIMEOUT 1000

#include <WinAPI/WinAPI.mqh>

class NamedPipe {
  private:
    int hPipe;
    string pipeName;
    bool connected;
      
  public:
    NamedPipe(string cPipeName = "\\\\.\\pipe\\manualmode2") {
        hPipe = -1;
        pipeName = cPipeName;
        connected = false;
    }
    
    ~NamedPipe() {
        Disconnect();
    }
    
    bool isConnected() { return connected; }
    
    int getHandle() { return hPipe; }
    
    bool Connect() {
        if (connected) return true;
        
        hPipe = FileOpen(pipeName, FILE_READ | FILE_WRITE | FILE_BIN);
        
        if (hPipe != INVALID_HANDLE) {
            connected = true;
            return true;
        }

        return false;
    }
    
    bool Disconnect() {
        if (hPipe == INVALID_HANDLE) {
            printf("Pipe already disconnected");
            return true;
        }
        
        FileClose(hPipe);
        hPipe = INVALID_HANDLE;
        connected = false;
        
        printf("Pipe disconnected");
        return true;
    }
    
    bool Send(string data) {
        if (!connected) return false;      
        
        uchar buffer[];
        StringToCharArray(data, buffer);
        uint size = ArraySize(buffer);

        uint bytesWritten = FileWriteArray(hPipe, buffer, 0, size);
        if (bytesWritten == 0) {
            printf("Failed to write to pipe. Error: %d", GetLastError());
            return false;
        }

        return bytesWritten == size;
    }
    
    string Read() {         
        if (!connected || FileSize(hPipe) <= 0) return "";

        uchar buffer[];
        ArrayResize(buffer, PIPE_BUFFER_SIZE);
        uint bytesRead = FileReadArray(hPipe, buffer, 0, PIPE_BUFFER_SIZE);

        if (bytesRead > 0) return CharArrayToString(buffer, 0, bytesRead);

        return "";
    }
};