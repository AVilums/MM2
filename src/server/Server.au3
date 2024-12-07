#include <ServerConfig.au3>

Global $g_hEvent, $g_iEdit, $g_pOverlap, $g_tOverlap, $g_hPipe, $g_hReadPipe, $g_iState, $g_iToWrite

If (Not InitGui()) Then
    Exit MsgBox(16, "Error", "Failed at GUI initialisation. Error: " & @error & " Extended: " & @extended & @CRLF)
EndIf

If (Not InitEventHandle()) Then
    Exit MsgBox(16, "Error", "Failed at Event Handle initialisation. Error: " & @error & " Extended: " & @extended & @CRLF)
EndIf

If (Not InitNPipe()) Then
    Exit MsgBox(16, "Error", "Failed at Named Pipe initialisation. Error: " & @error & " Extended: " & @extended & @CRLF)
EndIf

If (Not HandleNPipe()) Then
    Exit MsgBox(16, "Error", "Failed at Named Pipe transcation. Error: " & @error & " Extended: " & @extended & @CRLF)
EndIf

#Region Main Functions

Func InitGui()
    $hGUI = GUICreate($PIPE_NAME, 500, 400, -1, -1, 0x00040000); $WS_SIZEBOX
	If ($hGUI == 0) Then
        Return SetError(1, 1, 0)
    EndIf
    
    $iEdit = GUICtrlCreateEdit("", 0, 0, _WinAPI_GetClientWidth($hGUI), _WinAPI_GetClientHeight($hGUI))
	If ($iEdit == 0) Then
        Return SetError(1, 2, 0)
    EndIf

    If (GUICtrlSetFont($iEdit, Default) == 0) Then
        Return SetError(2, 1, 0)
    EndIf

	If (GUISetState() == 0) Then
        Return SetError(3, 1, 0)
    EndIf

    Return 1
EndFunc

Func InitEventHandle()
	; Create structure for event handling
    ; $tagOVERLAPPED = ulong_ptr Internal;ulong_ptr InternalHigh;struct;dword Offset;dword OffsetHigh;endstruct;handle hEvent
    $g_tOverlap = DllStructCreate($tagOVERLAPPED)
    If @error Then
        ConsoleWriteError("Error: DllStructCreate($tagOVERLAPPED) failed..." & @CRLF)
        Return SetError(1, 1, 0)
    EndIf

    ; Set global to struct. pointer
	$g_pOverlap = DllStructGetPtr($g_tOverlap)
    If @error Then
        ConsoleWriteError("Error: DllStructGetPtr($g_tOverlap) failed..." & @CRLF)
        Return SetError(1, 2, 0)
    EndIf

    ; Create event obj. https://learn.microsoft.com/en-us/windows/win32/sync/event-objects
    $g_hEvent = _WinAPI_CreateEvent()
	If $g_hEvent = 0 Then
		ConsoleWriteError("Error: _WinAPI_CreateEvent() failed..." & @CRLF)
		Return SetError(2, 1, 0)
	EndIf
    
    ; Set event handle to data struct.
    DllStructSetData($g_tOverlap, "hEvent", $g_hEvent)
    If @error Then
        ConsoleWriteError("Error: DllStructSetData($g_tOverlap, 'hEvent', $g_hEvent) failed..." & @CRLF)
        Return SetError(3, 1, 0)
    EndIf

    Return 1
EndFunc

Func InitNPipe()
    ; https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipes
	$g_hPipe = _NamedPipes_CreateNamedPipe($PIPE_PATH, _ ; Pipe name
        2, _ ; The pipe is bi-directional
        2, _ ; Overlapped mode is enabled
        0, _ ; No security ACL flags
        1, _ ; Data is written to the pipe as a stream of messages
        1, _ ; Data is read from the pipe as a stream of messages
        0, _ ; Blocking mode is enabled
        1, _ ; Maximum instance count
        $BUFSIZE, _ ; Output buffer size
        $BUFSIZE, _ ; Input buffer size
        $TIMEOUT, _ ; Client time out
        0) ; Default security attributes

    If $g_hPipe = -1 Then; Failed creating pipe
        ConsoleWriteError("Error: Failed creating named pipe..." & @CRLF)
        Return SetError(1, 1, 0)
    EndIf

    ; Connect pipe instance to client and signal it by setting event
    If (Not _ConnectClient()) Then
        ConsoleWriteError("Error: Failed to connect client..." & @CRLF)
        Return SetError(@error, @extended, 0)
    EndIf

    Return 1
EndFunc

Func HandleNPipe()
    Local $iEvent

    ; While not closed or no error
    While (GUIGetMsg() <> -3 Or Not @error); $GUI_EVENT_CLOSE
        $iEvent = _WinAPI_WaitForSingleObject($g_hEvent, 0)
        If ($iEvent == 0) Then; No event
            ConsoleWriteError("Error: Failed to wait for single object..." & @CRLF)
            Return SetError(1, 1, 0)
        EndIf

        If ($iEvent == $WAIT_TIMEOUT) Then; Timed out
            ConsoleWrite("Warning: Timeout when waiting for event..." & @CRLF)
            ContinueLoop
        EndIf

        Switch $g_iState
            Case 0
                _ConnectionCheck()
                If @error Then
                    Return SetError(1, 1, 0)
                EndIf
            Case 1
                Return
            Case 2
                Return
            Case 3
                Return
        EndSwitch
    WEnd
    
    Return 1
EndFunc

#EndRegion Main Functions

#Region Support Functions

Func _ConnectClient()
	$g_iState = 0
	
    ; Start an overlapped connection
	If (_NamedPipes_ConnectNamedPipe($g_hPipe, $g_pOverlap)) Then
		ConsoleWriteError("Error: _NamedPipes_ConnectNamedPipe($g_hPipe, $g_pOverlap) failed..." & @CRLF)
        Return SetError(1, 1, 0)
    Else; The overlapped connection is in progress)
        Switch @error
			Case $ERROR_IO_PENDING; Client connection is pending
				ConsoleWrite("Warning: Client connection pending..." & @CRLF)

			Case $ERROR_PIPE_CONNECTED; Client is connected signal an event
				$g_iState = 1

				If (Not _WinAPI_SetEvent(DllStructGetData($g_tOverlap, "hEvent"))) Then
					ConsoleWriteError("Error: _WinAPI_SetEvent() failed..."  & @CRLF)
                    Return SetError(2, 1, 0)
                EndIf
                
                ConsoleWrite("Info: Client connected..." & @CRLF)

			Case Else; Error occurred during the connection event
				ConsoleWriteError("Error: Overlapped connection failed..." & @CRLF)
                ; Return SetError(3, 1, 0)
		EndSwitch
	EndIf

    Return 1
EndFunc

Func _ConnectionCheck()
    Local $iBytes

    ; Try getting data, reconnect if failed
    If (Not _WinAPI_GetOverlappedResult($g_hPipe, $g_pOverlap, $iBytes)) Then
        ConsoleWriteError("Warning: Failed connecting, reconnecting..." & @CRLF)
        
        _ReconnectClient(); Try reconnecting
        If @error Then
            ConsoleWriteError("Warning: Failed reconnecting..." & @CRLF)
            Return SetError(1, 1, 0)
        EndIf
    EndIf

    $g_iState = 1; change state
    ConsoleWrite("Info: Client connected..." & @CRLF)
    Return 1
EndFunc

Func _ReconnectClient()
	; Disconnect the current pipe
	If (Not _NamedPipes_DisconnectNamedPipe($g_hPipe)) Then
		ConsoleWriteError("Error: Failed disconnecting the pipe..." & @CRLF)
		Return SetError(1, 1, 0)
	EndIf

	; Connect to a new client
	_ConnectClient()
    If @error Then
        ConsoleWriteError("Error: Failed reconnecting the client..." & @CRLF)
        Return SetError(1, 1, 0)
    EndIf

    Return 1
EndFunc

#EndRegion Support Functions