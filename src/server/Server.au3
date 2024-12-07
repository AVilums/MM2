#include <ServerConfig.au3>

If (Not Init()) Then
    Exit MsgBox(16, "Error", "Failed at initialisation.")
EndIf

MsgBox(0, "", "")

Func Init()
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