#include <NamedPipes.au3>
#include <WinAPI.au3>

Global Const $BUFSIZE = 4096

Global Const $PIPE_NAME = "ManualMode"
Global Const $PIPE_PATH = "\\.\\pipe\\" & $PIPE_NAME

Global Const $TIMEOUT = 5000
Global Const $WAIT_TIMEOUT = 258

Global Const $ERROR_IO_PENDING = 997
Global Const $ERROR_PIPE_CONNECTED = 535