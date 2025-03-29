#include <WinAPI/WinAPI.mqh>
#define PIPE_BUFFER_SIZE 65536
#define PIPE_TIMEOUT 1000
#define PIPE_NAME_PREFIX "\\\\.\\pipe\\"

class cNPipe {
    private:
        string pipeName;
  };	