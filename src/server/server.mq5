//+------------------------------------------------------------------+
//|                                                       server.mq5 |
//+------------------------------------------------------------------+
#property copyright "Arturs V., Rihards S."
#property version   "1.00"
#property strict

#include "core/backend.mqh"

string namedPipe = "\\\\.\\pipe\\manualmode2";
Backend *backend;

int OnInit() {
   EventSetMillisecondTimer(1);
   backend = new Backend(namedPipe);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   delete backend;
   printf("Disconnected from the server");
}

void OnTimer() {
   backend.Run();
}