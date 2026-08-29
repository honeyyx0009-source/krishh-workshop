//+------------------------------------------------------------------+
//|                                             001_PERCEPTION.mq5    |
//|                              001 PERCEPTION - Adaptive Framework  |
//|                                                                  |
//| An adaptive, autonomous, multi-strategy trading framework for    |
//| MetaTrader 5. This file is intentionally tiny: it declares the   |
//| user inputs (via Params.mqh) and forwards the terminal's event   |
//| callbacks to the CPerception orchestrator, which owns all logic. |
//|                                                                  |
//| Dashboard hotkeys (click the chart first): 1 = Compact,          |
//| 2 = Professional, 3 = Research.                                  |
//|                                                                  |
//| DISCLAIMER: This software automates trading decisions and risk   |
//| management; it does NOT guarantee profit. Validate thoroughly in |
//| the Strategy Tester and on a demo account before any live use.   |
//+------------------------------------------------------------------+
#property copyright "001 PERCEPTION"
#property link      "https://github.com/honeyyx0009-source/krishh-workshop"
#property version   "1.00"
#property description "001 PERCEPTION - adaptive autonomous multi-strategy EA framework."
#property description "Modular engines + internal AI selection + institutional risk + multi-mode dashboard."

#include <Perception/Params.mqh>
#include <Perception/Perception.mqh>

//--- the single application instance --------------------------------
CPerception g_app;

//+------------------------------------------------------------------+
int OnInit()
  {
   SConfig        cfg = BuildConfig();
   SEngineToggles tog = BuildToggles();
   return g_app.OnInitApp(cfg,tog,InpScannerSymbols,InpScannerTF);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_app.OnDeinitApp(reason);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   g_app.OnTickApp();
  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   g_app.OnTimerApp();
  }
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   g_app.OnChartEventApp(id,lparam,dparam,sparam);
  }
//+------------------------------------------------------------------+
