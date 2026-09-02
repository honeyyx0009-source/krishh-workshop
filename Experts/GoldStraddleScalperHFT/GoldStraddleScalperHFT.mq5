//+------------------------------------------------------------------+
//|                                       GoldStraddleScalperHFT.mq5 |
//|                                                                  |
//|  Two-sided pending-order (straddle) breakout scalper for MT5.     |
//|                                                                  |
//|  LOGIC                                                            |
//|  1. Market ke dono side pending order lagte hain:                 |
//|        BUY STOP  = Ask + Distance                                 |
//|        SELL STOP = Bid - Distance                                 |
//|  2. Dono pending orders par SL pehle se hi opposite order ke      |
//|     level par set hota hai. Yaani jaise hi BUY STOP trigger hua,  |
//|     us position ka SL wahi hai jahan SELL STOP tha. (Broker-side  |
//|     protection - EA disconnect ho jaye to bhi position safe.)      |
//|  3. Jo order trigger hua, opposite pending order turant delete.   |
//|  4. Thoda bhi favour me move hua -> SL BREAKEVEN par shift.       |
//|     (reverse aaya to no-loss / no-profit close)                   |
//|  5. Aage move kiya to STEP-WISE LADDER TRAILING + classic trail   |
//|     se profit lock hota jaata hai.                                |
//|  6. Agar move hi nahi kiya -> SL (opposite level) hit -> loss.    |
//|  7. Position close hone ke baad dobara 2 pending orders -> LOOP.  |
//|                                                                  |
//|  Auto broker adaptation: 2 / 3 / 4 / 5 digit quotes, symbol       |
//|  suffix, filling mode, stops level, freeze level, lot step.        |
//+------------------------------------------------------------------+
#property copyright "Kiro"
#property version   "1.00"
#property description "Buy Stop + Sell Stop straddle scalper. Opposite pending level = SL."
#property description "Fast breakeven + step ladder trailing. Auto 2/3/5 digit broker handling."
#property description "Designed for XAUUSD (Gold) M1, but works on any symbol."

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_SYM_MODE
  {
   SYM_MODE_CHART     = 0,  // Use chart symbol
   SYM_MODE_AUTO_GOLD = 1   // Auto-detect Gold symbol
  };

enum ENUM_LOT_MODE
  {
   LOT_MODE_FIXED = 0,      // Fixed lot
   LOT_MODE_RISK  = 1       // Risk percent of balance
  };

enum ENUM_CYCLE_MODE
  {
   CYCLE_ALWAYS = 0,        // Loop forever
   CYCLE_LIMITED = 1        // Stop after N cycles
  };

//==================================================================
//  INPUTS
//==================================================================
input group           "========== 1. SYMBOL & CORE =========="
input ENUM_SYM_MODE   InpSymbolMode        = SYM_MODE_CHART;   // Symbol selection mode
input string          InpGoldKeywords      = "XAUUSD,GOLD,XAU"; // Gold name keywords (auto mode)
input long            InpMagic             = 26092026;         // Magic number
input string          InpTradeComment      = "GSS-HFT";        // Order comment
input double          InpMaxSlippagePts    = 20;               // Max slippage (points)
input int             InpMaxRetries        = 5;                // Max order retries
input bool            InpUseTimerEngine    = true;             // Use fast timer engine (HFT)
input int             InpTimerMs           = 100;              // Timer interval (ms)
input bool            InpVerboseLog        = true;             // Verbose logging
input bool            InpShowPanel         = true;             // Show on-chart panel

input group           "========== 2. STRADDLE SETUP =========="
input double          InpDistancePoints    = 100;              // Distance of each pending from anchor (points)
input bool            InpExactWidth        = true;             // EXACT width: anchor both legs on mid price (spread ignored)
input bool            InpRecenterPending   = true;             // Re-center pendings if price drifts
input double          InpRecenterDriftPts  = 40;               // Drift before re-centering (points)
input int             InpRecenterMinSecs   = 3;                // Min seconds between re-centers
input bool            InpUseExpiration     = false;            // Use pending expiration
input int             InpExpirationMinutes = 30;               // Expiration (minutes)
input int             InpPauseAfterCloseSecs = 1;              // Pause after a position closes (sec)
input bool            InpDeletePendingOnExit = false;          // Delete pendings when EA removed

input group           "========== 3. LOT / RISK =========="
input ENUM_LOT_MODE   InpLotMode           = LOT_MODE_FIXED;   // Lot sizing mode
input double          InpFixedLot          = 0.01;             // Fixed lot size
input double          InpRiskPercent       = 0.5;              // Risk % of balance (risk mode)
input double          InpMaxLotCap         = 5.0;              // Max lot cap

input group           "========== 4. STOP LOSS (opposite level) =========="
input bool            InpSLFromOpposite    = true;             // SL = opposite pending order level
input double          InpSLExtraBufferPts  = 0;                // Extra buffer beyond opposite level (points)
input double          InpFallbackSLPoints  = 0;                // Fallback SL points (0 = auto 2x distance)
input bool            InpUseTakeProfit     = false;            // Use a hard take profit
input double          InpTakeProfitPoints  = 400;              // Take profit (points)

input group           "========== 5. BREAKEVEN (safety) =========="
input bool            InpUseBreakeven      = true;             // Enable breakeven
input double          InpBETriggerPoints   = 15;               // Move to BE after this profit (points)
input double          InpBELockPoints      = 0;                // Points locked at BE (0 = exact entry)

input group           "========== 6. STEP LADDER TRAILING =========="
input bool            InpUseLadderTrail    = true;             // Enable step ladder locking
input string          InpLadder            = "30:5,50:20,70:40,100:68,140:105,200:160"; // trigger:lock pairs (points)
input bool            InpUseClassicTrail   = true;             // Enable classic trailing after ladder
input double          InpTrailStartPoints  = 200;              // Classic trail starts at (points profit)
input double          InpTrailDistancePts  = 40;               // Classic trail distance (points)
input double          InpTrailStepPoints   = 5;                // Min SL improvement step (points)

input group           "========== 7. FILTERS =========="
input double          InpMaxSpreadPoints   = 40;               // Max spread to place straddle (points, 0=off)
input bool            InpUseTimeFilter     = false;            // Use trading hours filter
input int             InpStartHour         = 1;                // Start hour (server time)
input int             InpEndHour           = 23;               // End hour (server time)
input bool            InpFridayStop        = true;             // Stop new cycles late Friday
input int             InpFridayStopHour    = 21;               // Friday stop hour
input bool            InpWarnTimeframe     = true;             // Warn if chart is not M1

input group           "========== 8. DAILY GUARDS =========="
input double          InpMaxDailyLossPct   = 0;                // Max daily loss % of balance (0=off)
input double          InpMaxDailyProfitPct = 0;                // Daily profit target % (0=off)
input int             InpMaxTradesPerDay   = 0;                // Max positions per day (0=off)
input ENUM_CYCLE_MODE InpCycleMode         = CYCLE_ALWAYS;     // Cycle mode
input int             InpMaxCycles         = 100;              // Max cycles (limited mode)

//==================================================================
//  GLOBALS
//==================================================================
string   g_symbol       = "";
int      g_digits       = 5;
double   g_point        = 0.00001;   // raw broker point
double   g_adjPoint     = 0.0001;    // normalized point (2/3 digit -> 0.01, 4/5 digit -> 0.0001)
double   g_tickSize     = 0.00001;
int      g_stopsLevel   = 0;
int      g_freezeLevel  = 0;
double   g_minLot       = 0.01;
double   g_maxLot       = 100.0;
double   g_lotStep      = 0.01;

ENUM_ORDER_TYPE_FILLING g_fillPending = ORDER_FILLING_RETURN;
ENUM_ORDER_TYPE_FILLING g_fillMarket  = ORDER_FILLING_FOK;

double   g_ladderTrig[];
double   g_ladderLock[];
int      g_ladderCount  = 0;

datetime g_lastCloseTime   = 0;
datetime g_lastRecenter    = 0;
datetime g_dayStamp        = 0;
double   g_dayStartBalance = 0;
int      g_tradesToday     = 0;
int      g_cycleCount      = 0;

double   g_plannedBuyStop  = 0;   // last planned straddle levels (fallback SL source)
double   g_plannedSellStop = 0;
double   g_lastWidth       = 0;   // verified width of the live straddle
double   g_lastBuySLD      = 0;   // verified buy-leg SL distance
double   g_lastSellSLD     = 0;   // verified sell-leg SL distance

bool     g_busy            = false;
bool     g_initOK          = false;
string   g_lastStatus      = "starting...";

//==================================================================
//  SMALL HELPERS
//==================================================================
void Log(string msg)
  {
   if(InpVerboseLog)
      Print("[GSS] ", msg);
  }

void LogAlways(string msg)
  {
   Print("[GSS] ", msg);
  }

double Ask() { return SymbolInfoDouble(g_symbol, SYMBOL_ASK); }
double Bid() { return SymbolInfoDouble(g_symbol, SYMBOL_BID); }

//--- convert normalized points <-> price
double PtsToPrice(double pts) { return pts * g_adjPoint; }
double PriceToPts(double pr)  { return (g_adjPoint > 0 ? pr / g_adjPoint : 0); }

//--- raw broker points (for deviation field)
int PtsToRaw(double pts)
  {
   if(g_point <= 0)
      return 10;
   return (int)MathMax(1, MathRound(PtsToPrice(pts) / g_point));
  }

double TickSz() { return (g_tickSize > 0 ? g_tickSize : (g_point > 0 ? g_point : 0.00001)); }

double NormPrice(double p)
  {
   double ts = TickSz();
   return NormalizeDouble(MathRound(p / ts) * ts, g_digits);
  }

//--- price <-> whole ticks. All straddle geometry is done in INTEGER
//--- ticks so the two legs are always an exact number of ticks apart
//--- (no floating point drift, no spread leaking into the width).
long PriceToTicks(double p)  { return (long)MathRound(p / TickSz()); }
double TicksToPrice(long t)  { return NormalizeDouble((double)t * TickSz(), g_digits); }

//--- round a distance UP to the next whole tick
long DistToTicksUp(double priceDist)
  {
   double ts = TickSz();
   long t = (long)MathCeil(priceDist / ts - 0.0000001);
   if(t < 1)
      t = 1;
   return t;
  }

double NormLot(double lot)
  {
   if(g_lotStep <= 0)
      g_lotStep = 0.01;
   double l = MathFloor(lot / g_lotStep + 0.0000001) * g_lotStep;
   if(l < g_minLot) l = g_minLot;
   if(l > g_maxLot) l = g_maxLot;
   if(InpMaxLotCap > 0 && l > InpMaxLotCap) l = InpMaxLotCap;
   int lotDigits = 2;
   if(g_lotStep >= 1.0)      lotDigits = 0;
   else if(g_lotStep >= 0.1) lotDigits = 1;
   else if(g_lotStep >= 0.01)lotDigits = 2;
   else                      lotDigits = 3;
   return NormalizeDouble(l, lotDigits);
  }

double SpreadPrice() { return MathMax(0.0, Ask() - Bid()); }
double SpreadPts()   { return PriceToPts(SpreadPrice()); }

//--- broker minimum stop distance in price
double StopLevelPrice()
  {
   double v = (double)g_stopsLevel * g_point;
   if(v < g_tickSize)
      v = g_tickSize;
   return v;
  }

double StopLevelPts() { return PriceToPts(StopLevelPrice()); }

double FreezeLevelPrice() { return (double)g_freezeLevel * g_point; }

//==================================================================
//  SYMBOL DETECTION & SETUP
//==================================================================
string FindGoldSymbol()
  {
   string keys[];
   int kn = StringSplit(InpGoldKeywords, StringGetCharacter(",", 0), keys);
   for(int k = 0; k < kn; k++)
     {
      StringTrimLeft(keys[k]);
      StringTrimRight(keys[k]);
      StringToUpper(keys[k]);
     }

   //--- keyword order = priority (XAUUSD before generic XAU)
   //--- pass 0: Market Watch symbols, pass 1: every symbol on the server
   for(int k = 0; k < kn; k++)
     {
      if(StringLen(keys[k]) < 2)
         continue;
      for(int pass = 0; pass < 2; pass++)
        {
         bool selectedOnly = (pass == 0);
         int total = SymbolsTotal(selectedOnly);
         for(int i = 0; i < total; i++)
           {
            string name = SymbolName(i, selectedOnly);
            if(name == "")
               continue;
            string up = name;
            StringToUpper(up);
            if(StringFind(up, keys[k]) < 0)
               continue;
            if(!SymbolSelect(name, true))
               continue;
            if(SymbolInfoInteger(name, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_DISABLED)
               continue;
            return name;
           }
        }
     }
   return "";
  }

bool SetupSymbol()
  {
   if(InpSymbolMode == SYM_MODE_AUTO_GOLD)
     {
      string up = _Symbol;
      StringToUpper(up);
      if(StringFind(up, "XAU") >= 0 || StringFind(up, "GOLD") >= 0)
         g_symbol = _Symbol;
      else
        {
         g_symbol = FindGoldSymbol();
         if(g_symbol == "")
           {
            LogAlways("ERROR: Gold symbol auto-detect failed. Attach EA to a Gold chart or use SYM_MODE_CHART.");
            return false;
           }
         LogAlways("Auto-detected Gold symbol: " + g_symbol);
        }
     }
   else
      g_symbol = _Symbol;

   if(!SymbolSelect(g_symbol, true))
     {
      LogAlways("ERROR: cannot select symbol " + g_symbol);
      return false;
     }

   g_digits      = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point       = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tickSize    = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   g_stopsLevel  = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevel = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_minLot      = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   g_maxLot      = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   g_lotStep     = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(g_point <= 0)
      g_point = MathPow(10, -g_digits);
   if(g_tickSize <= 0)
      g_tickSize = g_point;
   if(g_lotStep <= 0)
      g_lotStep = 0.01;
   if(g_minLot <= 0)
      g_minLot = 0.01;
   if(g_maxLot <= 0)
      g_maxLot = 100.0;

   //--- AUTO 2 / 3 / 4 / 5 DIGIT ADAPTATION -------------------------
   //  3 and 5 digit brokers quote one extra fractional digit, so we
   //  normalize "1 point" to the classic 2/4 digit convention.
   //    Gold 2 digits (1912.34)  -> 1 point = 0.01
   //    Gold 3 digits (1912.345) -> 1 point = 0.01  (10 raw points)
   //    FX   4 digits (1.2345)   -> 1 point = 0.0001
   //    FX   5 digits (1.23456)  -> 1 point = 0.0001 (10 raw points)
   double factor = 1.0;
   if(g_digits == 3 || g_digits == 5)
      factor = 10.0;
   g_adjPoint = g_point * factor;

   //--- filling modes ---------------------------------------------
   long fill = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   if((fill & (long)SYMBOL_FILLING_FOK) != 0)
      g_fillMarket = ORDER_FILLING_FOK;
   else if((fill & (long)SYMBOL_FILLING_IOC) != 0)
      g_fillMarket = ORDER_FILLING_IOC;
   else
      g_fillMarket = ORDER_FILLING_RETURN;

   //--- pending orders: RETURN is the safest default, fallback later
   g_fillPending = ORDER_FILLING_RETURN;

   LogAlways(StringFormat("Symbol=%s digits=%d rawPoint=%s adjPoint=%s (1 EA point = %s price) tick=%s",
                          g_symbol, g_digits,
                          DoubleToString(g_point, 8),
                          DoubleToString(g_adjPoint, 8),
                          DoubleToString(g_adjPoint, g_digits),
                          DoubleToString(g_tickSize, 8)));
   LogAlways(StringFormat("StopsLevel=%d (%.1f pts) FreezeLevel=%d lots[min=%.2f step=%.2f max=%.2f] spread=%.1f pts",
                          g_stopsLevel, StopLevelPts(), g_freezeLevel,
                          g_minLot, g_lotStep, g_maxLot, SpreadPts()));
   return true;
  }

//==================================================================
//  LADDER PARSING
//==================================================================
void ParseLadder(string src)
  {
   g_ladderCount = 0;
   ArrayResize(g_ladderTrig, 0);
   ArrayResize(g_ladderLock, 0);
   if(!InpUseLadderTrail || StringLen(src) < 3)
      return;

   string parts[];
   int n = StringSplit(src, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) < 3)
         continue;
      string kv[];
      int m = StringSplit(p, StringGetCharacter(":", 0), kv);
      if(m != 2)
        {
         LogAlways("Ladder entry ignored (bad format, expected trigger:lock): " + p);
         continue;
        }
      double trig = StringToDouble(kv[0]);
      double lock = StringToDouble(kv[1]);
      if(trig <= 0 || lock < 0 || lock >= trig)
        {
         LogAlways(StringFormat("Ladder entry ignored (lock must be >=0 and < trigger): %s", p));
         continue;
        }
      int idx = g_ladderCount;
      ArrayResize(g_ladderTrig, idx + 1);
      ArrayResize(g_ladderLock, idx + 1);
      g_ladderTrig[idx] = trig;
      g_ladderLock[idx] = lock;
      g_ladderCount++;
     }

   //--- sort ascending by trigger
   for(int i = 0; i < g_ladderCount - 1; i++)
      for(int j = 0; j < g_ladderCount - 1 - i; j++)
         if(g_ladderTrig[j] > g_ladderTrig[j + 1])
           {
            double t = g_ladderTrig[j];   g_ladderTrig[j] = g_ladderTrig[j + 1];   g_ladderTrig[j + 1] = t;
            double l = g_ladderLock[j];   g_ladderLock[j] = g_ladderLock[j + 1];   g_ladderLock[j + 1] = l;
           }

   string s = "Ladder steps: ";
   for(int i = 0; i < g_ladderCount; i++)
      s += StringFormat("%.0f->%.0f ", g_ladderTrig[i], g_ladderLock[i]);
   LogAlways(s);
  }

//==================================================================
//  ORDER SENDING (with retries + filling fallback)
//==================================================================
bool RetcodeOK(uint rc)
  {
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
  }

ENUM_ORDER_TYPE_FILLING NextFilling(ENUM_ORDER_TYPE_FILLING cur)
  {
   if(cur == ORDER_FILLING_RETURN) return ORDER_FILLING_IOC;
   if(cur == ORDER_FILLING_IOC)    return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

bool SendWithRetry(MqlTradeRequest &req, MqlTradeResult &res, bool isPending, string tag)
  {
   int attempts = (int)MathMax(1, InpMaxRetries);
   for(int a = 0; a < attempts; a++)
     {
      ZeroMemory(res);
      ResetLastError();
      bool ok = OrderSend(req, res);

      if(ok && RetcodeOK(res.retcode))
         return true;

      uint rc = res.retcode;
      int  le = GetLastError();
      Log(StringFormat("%s attempt %d/%d failed rc=%u err=%d (%s)", tag, a + 1, attempts, rc, le, res.comment));

      //--- unsupported filling mode -> rotate
      if(rc == TRADE_RETCODE_INVALID_FILL)
        {
         if(isPending)
           {
            g_fillPending  = NextFilling(g_fillPending);
            req.type_filling = g_fillPending;
           }
         else
           {
            g_fillMarket   = NextFilling(g_fillMarket);
            req.type_filling = g_fillMarket;
           }
         continue;
        }

      //--- price moved -> refresh and retry
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
         rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_CONNECTION ||
         rc == TRADE_RETCODE_TOO_MANY_REQUESTS)
        {
         Sleep(60);
         continue;
        }

      //--- hard errors, or errors where a retry could duplicate the order:
      //    don't retry. ProcessLogic() self-heals an incomplete straddle
      //    on the next pass anyway.
      if(rc == TRADE_RETCODE_INVALID_STOPS || rc == TRADE_RETCODE_INVALID_VOLUME ||
         rc == TRADE_RETCODE_NO_MONEY || rc == TRADE_RETCODE_TRADE_DISABLED ||
         rc == TRADE_RETCODE_MARKET_CLOSED || rc == TRADE_RETCODE_INVALID_ORDER ||
         rc == TRADE_RETCODE_ORDER_CHANGED || rc == TRADE_RETCODE_POSITION_CLOSED ||
         rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_INVALID_PRICE ||
         rc == TRADE_RETCODE_INVALID_EXPIRATION || rc == TRADE_RETCODE_LIMIT_ORDERS ||
         rc == TRADE_RETCODE_LIMIT_VOLUME)
        {
         LogAlways(StringFormat("%s aborted rc=%u (%s)", tag, rc, res.comment));
         return false;
        }

      Sleep(50);
     }
   return false;
  }

//==================================================================
//  ORDER / POSITION LOOKUP
//==================================================================
//--- collect every position that belongs to this EA on this symbol
int CollectOurPositions(ulong &tickets[])
  {
   ArrayResize(tickets, 0);
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      ArrayResize(tickets, c + 1);
      tickets[c] = t;
      c++;
     }
   return c;
  }

//--- returns count of our pending orders, fills tickets
int ScanOurOrders(ulong &buyTicket, ulong &sellTicket)
  {
   buyTicket = 0;
   sellTicket = 0;
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP)
        {
         buyTicket = t;
         c++;
        }
      else if(type == ORDER_TYPE_SELL_STOP)
        {
         sellTicket = t;
         c++;
        }
      else
        {
         c++; // some other leftover order of ours
        }
     }
   return c;
  }

//==================================================================
//  ORDER ACTIONS
//==================================================================
bool PlacePending(ENUM_ORDER_TYPE type, double price, double sl, double tp, double lot)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = g_symbol;
   req.volume       = lot;
   req.type         = type;
   req.price        = NormPrice(price);
   req.sl           = (sl > 0 ? NormPrice(sl) : 0.0);
   req.tp           = (tp > 0 ? NormPrice(tp) : 0.0);
   req.deviation    = (ulong)PtsToRaw(InpMaxSlippagePts);
   req.magic        = (ulong)InpMagic;
   req.comment      = InpTradeComment;
   req.type_filling = g_fillPending;
   req.type_time    = ORDER_TIME_GTC;

   if(InpUseExpiration && InpExpirationMinutes > 0)
     {
      long expMode = SymbolInfoInteger(g_symbol, SYMBOL_EXPIRATION_MODE);
      if((expMode & (long)SYMBOL_EXPIRATION_SPECIFIED) != 0)
        {
         req.type_time  = ORDER_TIME_SPECIFIED;
         req.expiration = TimeCurrent() + InpExpirationMinutes * 60;
        }
     }

   string tag = StringFormat("PLACE %s @%s sl=%s lot=%.2f",
                             (type == ORDER_TYPE_BUY_STOP ? "BUYSTOP" : "SELLSTOP"),
                             DoubleToString(req.price, g_digits),
                             DoubleToString(req.sl, g_digits), lot);
   bool ok = SendWithRetry(req, res, true, tag);
   if(ok)
      Log(tag + " -> OK ticket=" + IntegerToString((long)res.order));
   return ok;
  }

bool DeleteOrderTicket(ulong ticket)
  {
   if(!OrderSelect(ticket))
      return true; // already gone

   //--- freeze level check
   double fz = FreezeLevelPrice();
   if(fz > 0)
     {
      double op = OrderGetDouble(ORDER_PRICE_OPEN);
      long   ty = OrderGetInteger(ORDER_TYPE);
      double ref = (ty == ORDER_TYPE_BUY_STOP ? Ask() : Bid());
      if(MathAbs(op - ref) < fz)
        {
         Log("Delete skipped (inside freeze level) ticket=" + IntegerToString((long)ticket));
         return false;
        }
     }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   req.symbol = g_symbol;
   req.magic  = (ulong)InpMagic;

   bool ok = SendWithRetry(req, res, true, "DELETE #" + IntegerToString((long)ticket));
   if(ok)
      Log("Deleted pending #" + IntegerToString((long)ticket));
   return ok;
  }

bool ModifyPendingOrder(ulong ticket, double price, double sl, double tp)
  {
   if(!OrderSelect(ticket))
      return false;

   double curP  = OrderGetDouble(ORDER_PRICE_OPEN);
   double curSL = OrderGetDouble(ORDER_SL);
   double curTP = OrderGetDouble(ORDER_TP);
   double nP    = NormPrice(price);
   double nSL   = (sl > 0 ? NormPrice(sl) : 0.0);
   double nTP   = (tp > 0 ? NormPrice(tp) : 0.0);

   if(MathAbs(curP - nP) < g_tickSize * 0.5 &&
      MathAbs(curSL - nSL) < g_tickSize * 0.5 &&
      MathAbs(curTP - nTP) < g_tickSize * 0.5)
      return true; // nothing to do

   double fz = FreezeLevelPrice();
   if(fz > 0)
     {
      long   ty  = OrderGetInteger(ORDER_TYPE);
      double ref = (ty == ORDER_TYPE_BUY_STOP ? Ask() : Bid());
      if(MathAbs(curP - ref) < fz)
         return false;
     }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_MODIFY;
   req.order     = ticket;
   req.symbol    = g_symbol;
   req.price     = nP;
   req.sl        = nSL;
   req.tp        = nTP;
   req.type_time = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   req.expiration= (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);

   return SendWithRetry(req, res, true, "MODIFY #" + IntegerToString((long)ticket));
  }

bool ModifyPositionSL(ulong ticket, double sl, double tp, string why)
  {
   if(!PositionSelectByTicket(ticket))
      return false;

   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double nSL   = (sl > 0 ? NormPrice(sl) : 0.0);
   double nTP   = (tp > 0 ? NormPrice(tp) : NormPrice(curTP));

   if(MathAbs(curSL - nSL) < g_tickSize * 0.5 && MathAbs(curTP - nTP) < g_tickSize * 0.5)
      return true;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = g_symbol;
   req.sl       = nSL;
   req.tp       = nTP;
   req.magic    = (ulong)InpMagic;

   bool ok = SendWithRetry(req, res, false, "SLTP " + why);
   if(ok)
      LogAlways(StringFormat("SL updated (%s): %s -> %s", why,
                             DoubleToString(curSL, g_digits), DoubleToString(nSL, g_digits)));
   return ok;
  }

int DeleteAllOurPendings()
  {
   int removed = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(DeleteOrderTicket(t))
         removed++;
     }
   return removed;
  }

//==================================================================
//  LOT CALCULATION
//==================================================================
double CalcLot(double slPriceDistance)
  {
   if(InpLotMode == LOT_MODE_FIXED || slPriceDistance <= 0)
      return NormLot(InpFixedLot);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   if(riskMoney <= 0)
      return NormLot(InpFixedLot);

   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0)
      tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0 || g_tickSize <= 0)
     {
      Log("Risk sizing unavailable (tick value/size), using fixed lot.");
      return NormLot(InpFixedLot);
     }

   double lossPerLot = (slPriceDistance / g_tickSize) * tickValue;
   if(lossPerLot <= 0)
      return NormLot(InpFixedLot);

   double lot = riskMoney / lossPerLot;
   double n = NormLot(lot);
   Log(StringFormat("Risk sizing: bal=%.2f risk=%.2f slDist=%s lossPerLot=%.2f -> lot=%.2f",
                    balance, riskMoney, DoubleToString(slPriceDistance, g_digits), lossPerLot, n));
   return n;
  }

//==================================================================
//  FILTERS / GUARDS
//==================================================================
void UpdateDayStamp()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);
   if(dayStart != g_dayStamp)
     {
      g_dayStamp        = dayStart;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_tradesToday     = 0;
      Log("New trading day. Start balance = " + DoubleToString(g_dayStartBalance, 2));
     }
  }

double DailyPL()
  {
   return AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance;
  }

bool TradingAllowedNow(string &reason)
  {
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
     {
      reason = "Terminal: AutoTrading OFF";
      return false;
     }
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
     {
      reason = "EA: trading not allowed (check 'Allow Algo Trading')";
      return false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0 || AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
     {
      reason = "Account: trading/expert disabled";
      return false;
     }
   long tmode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_DISABLED || tmode == SYMBOL_TRADE_CLOSEONLY)
     {
      reason = "Symbol trade mode restricted";
      return false;
     }
   return true;
  }

bool CanOpenNewCycle(string &reason)
  {
   if(!TradingAllowedNow(reason))
      return false;

   if(InpCycleMode == CYCLE_LIMITED && g_cycleCount >= InpMaxCycles)
     {
      reason = StringFormat("Max cycles reached (%d)", InpMaxCycles);
      return false;
     }

   if(InpPauseAfterCloseSecs > 0 && g_lastCloseTime > 0 &&
      (TimeCurrent() - g_lastCloseTime) < InpPauseAfterCloseSecs)
     {
      reason = "Cooldown after close";
      return false;
     }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpUseTimeFilter)
     {
      bool inWindow;
      if(InpStartHour <= InpEndHour)
         inWindow = (dt.hour >= InpStartHour && dt.hour <= InpEndHour);
      else
         inWindow = (dt.hour >= InpStartHour || dt.hour <= InpEndHour);
      if(!inWindow)
        {
         reason = StringFormat("Outside trading hours (%02d:00-%02d:00)", InpStartHour, InpEndHour);
         return false;
        }
     }

   if(InpFridayStop && dt.day_of_week == 5 && dt.hour >= InpFridayStopHour)
     {
      reason = "Friday session stop";
      return false;
     }

   if(InpMaxSpreadPoints > 0 && SpreadPts() > InpMaxSpreadPoints)
     {
      reason = StringFormat("Spread too wide (%.1f > %.1f pts)", SpreadPts(), InpMaxSpreadPoints);
      return false;
     }

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
     {
      reason = StringFormat("Daily trade limit (%d)", InpMaxTradesPerDay);
      return false;
     }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpMaxDailyLossPct > 0 && bal > 0)
     {
      double limit = -(g_dayStartBalance * InpMaxDailyLossPct / 100.0);
      if(DailyPL() <= limit)
        {
         reason = StringFormat("Daily loss limit hit (%.2f)", DailyPL());
         return false;
        }
     }
   if(InpMaxDailyProfitPct > 0 && g_dayStartBalance > 0)
     {
      double target = g_dayStartBalance * InpMaxDailyProfitPct / 100.0;
      if(DailyPL() >= target)
        {
         reason = StringFormat("Daily profit target hit (%.2f)", DailyPL());
         return false;
        }
     }

   //--- must have a live tick
   if(Ask() <= 0 || Bid() <= 0)
     {
      reason = "No prices yet";
      return false;
     }

   reason = "";
   return true;
  }

//==================================================================
//  STRADDLE PLACEMENT
//==================================================================
bool g_warnedDistance = false;

double EffectiveDistancePts()
  {
   double d = InpDistancePoints;
   double minD = StopLevelPts() + 2.0;
   if(d < minD)
     {
      if(!g_warnedDistance)
        {
         g_warnedDistance = true;
         LogAlways(StringFormat("Distance %.1f pts is below broker stops level, auto-raised to %.1f pts", d, minD));
        }
      d = minD;
     }
   return d;
  }

//------------------------------------------------------------------
//  EXACT STRADDLE GEOMETRY
//------------------------------------------------------------------
//  Everything is computed in WHOLE TICKS from a single anchor, so:
//
//      buyPrice  = anchorTicks + dTicks
//      sellPrice = anchorTicks - dTicks
//      width     = 2 * dTicks       <-- ALWAYS exact, every single time
//
//  Old (buggy) behaviour was buy = Ask + d and sell = Bid - d, which
//  made width = 2*d + spread. Because gold's spread breathes tick by
//  tick, the SL came out 2.02 / 2.05 / 2.07 instead of a clean 2.00.
//------------------------------------------------------------------
long g_dTicksLast = 0;   // distance actually used, in ticks

bool ComputeStraddleLevels(double &buyPrice, double &sellPrice, long &dTicks)
  {
   double ask = Ask();
   double bid = Bid();
   buyPrice   = 0;
   sellPrice  = 0;
   dTicks     = 0;
   if(ask <= 0 || bid <= 0)
      return false;

   //--- requested distance, snapped to a whole number of ticks
   dTicks = DistToTicksUp(PtsToPrice(EffectiveDistancePts()));

   //--- both legs must clear the broker's minimum stop distance.
   //    Expand SYMMETRICALLY (only dTicks grows) so the width stays exact.
   double halfSpread = (ask - bid) / 2.0;
   double needed     = StopLevelPrice() + halfSpread + TickSz();
   long   neededTicks = DistToTicksUp(needed);
   if(dTicks < neededTicks)
     {
      Log(StringFormat("Distance expanded %d -> %d ticks (stops level + half spread)",
                       (int)dTicks, (int)neededTicks));
      dTicks = neededTicks;
     }

   if(InpExactWidth)
     {
      //--- ONE shared anchor (mid price) -> width is exactly 2 * dTicks
      long anchorTicks = PriceToTicks((ask + bid) / 2.0);
      buyPrice  = TicksToPrice(anchorTicks + dTicks);
      sellPrice = TicksToPrice(anchorTicks - dTicks);
     }
   else
     {
      //--- legacy: separate anchors, so the spread leaks into the width
      buyPrice  = TicksToPrice(PriceToTicks(ask) + dTicks);
      sellPrice = TicksToPrice(PriceToTicks(bid) - dTicks);
     }
   return true;
  }

//--- SL / TP derived from the two legs (buffer also tick-snapped)
void ComputeStraddleStops(double buyPrice, double sellPrice,
                          double &buySL, double &sellSL,
                          double &buyTP, double &sellTP)
  {
   long bTicks = PriceToTicks(buyPrice);
   long sTicks = PriceToTicks(sellPrice);

   if(InpSLFromOpposite)
     {
      long bufTicks = (InpSLExtraBufferPts > 0 ? DistToTicksUp(PtsToPrice(InpSLExtraBufferPts)) : 0);
      buySL  = TicksToPrice(sTicks - bufTicks);   // = sell stop level
      sellSL = TicksToPrice(bTicks + bufTicks);   // = buy stop level
     }
   else
     {
      long fbTicks = (InpFallbackSLPoints > 0 ? DistToTicksUp(PtsToPrice(InpFallbackSLPoints))
                                              : (bTicks - sTicks));
      buySL  = TicksToPrice(bTicks - fbTicks);
      sellSL = TicksToPrice(sTicks + fbTicks);
     }

   buyTP  = 0;
   sellTP = 0;
   if(InpUseTakeProfit && InpTakeProfitPoints > 0)
     {
      long tpTicks = DistToTicksUp(PtsToPrice(InpTakeProfitPoints));
      buyTP  = TicksToPrice(bTicks + tpTicks);
      sellTP = TicksToPrice(sTicks - tpTicks);
     }
  }

//--- read back the live orders and prove the width is exact
void VerifyStraddleWidth()
  {
   ulong bT = 0, sT = 0;
   if(ScanOurOrders(bT, sT) != 2 || bT == 0 || sT == 0)
      return;

   double bp = 0, sp = 0, bsl = 0, ssl = 0;
   if(OrderSelect(bT))
     {
      bp  = OrderGetDouble(ORDER_PRICE_OPEN);
      bsl = OrderGetDouble(ORDER_SL);
     }
   if(OrderSelect(sT))
     {
      sp  = OrderGetDouble(ORDER_PRICE_OPEN);
      ssl = OrderGetDouble(ORDER_SL);
     }
   if(bp <= 0 || sp <= 0)
      return;

   double width   = bp - sp;
   double wantPts = (double)g_dTicksLast * 2.0 * TickSz() / g_adjPoint;
   double gotPts  = PriceToPts(width);

   g_lastWidth   = width;
   g_lastBuySLD  = (bsl > 0 ? bp - bsl : 0);
   g_lastSellSLD = (ssl > 0 ? ssl - sp : 0);

   if(InpExactWidth && MathAbs(gotPts - wantPts) > 0.5)
      LogAlways(StringFormat("WARNING: broker adjusted the straddle! wanted width %.1f pts, got %.1f pts",
                             wantPts, gotPts));
   else
      Log(StringFormat("Width verified EXACT: %s (%.1f pts)  buySLdist=%s  sellSLdist=%s",
                       DoubleToString(width, g_digits), gotPts,
                       DoubleToString(g_lastBuySLD, g_digits),
                       DoubleToString(g_lastSellSLD, g_digits)));
  }

bool PlaceStraddle()
  {
   double ask = Ask();
   double bid = Bid();

   double buyPrice, sellPrice;
   long   dTicks;
   if(!ComputeStraddleLevels(buyPrice, sellPrice, dTicks))
      return false;

   double buySL, sellSL, buyTP, sellTP;
   ComputeStraddleStops(buyPrice, sellPrice, buySL, sellSL, buyTP, sellTP);

   double width  = buyPrice - sellPrice;
   double slDist = buyPrice - buySL;
   double lot    = CalcLot(slDist);

   g_plannedBuyStop  = buyPrice;
   g_plannedSellStop = sellPrice;
   g_dTicksLast      = dTicks;

   LogAlways(StringFormat("NEW STRADDLE  bid=%s ask=%s spread=%.1f pts | BUYSTOP %s | SELLSTOP %s | lot=%.2f",
                          DoubleToString(bid, g_digits), DoubleToString(ask, g_digits), SpreadPts(),
                          DoubleToString(buyPrice, g_digits),
                          DoubleToString(sellPrice, g_digits), lot));
   LogAlways(StringFormat("              WIDTH = %s (%.1f pts) | BUY SL %s (dist %s) | SELL SL %s (dist %s)",
                          DoubleToString(width, g_digits), PriceToPts(width),
                          DoubleToString(buySL, g_digits), DoubleToString(buyPrice - buySL, g_digits),
                          DoubleToString(sellSL, g_digits), DoubleToString(sellSL - sellPrice, g_digits)));

   bool okBuy  = PlacePending(ORDER_TYPE_BUY_STOP,  buyPrice,  buySL,  buyTP,  lot);
   bool okSell = PlacePending(ORDER_TYPE_SELL_STOP, sellPrice, sellSL, sellTP, lot);

   if(!okBuy || !okSell)
     {
      LogAlways("Straddle incomplete (buy=" + (string)okBuy + " sell=" + (string)okSell + ") - cleaning up.");
      DeleteAllOurPendings();
      return false;
     }

   //--- verify the geometry actually landed exactly where we wanted
   VerifyStraddleWidth();
   return true;
  }

//--- keep the straddle centred around price while it is waiting
void MaybeRecenter(ulong buyTicket, ulong sellTicket)
  {
   if(!InpRecenterPending)
      return;
   if(buyTicket == 0 || sellTicket == 0)
      return;
   if(TimeCurrent() - g_lastRecenter < InpRecenterMinSecs)
      return;

   double ask = Ask();
   double bid = Bid();
   if(ask <= 0 || bid <= 0)
      return;

   if(!OrderSelect(buyTicket))
      return;
   double bp = OrderGetDouble(ORDER_PRICE_OPEN);
   if(!OrderSelect(sellTicket))
      return;
   double sp = OrderGetDouble(ORDER_PRICE_OPEN);

   //--- how far has the straddle's CENTRE drifted from the current mid?
   double curCentre = (bp + sp) / 2.0;
   double mid       = (ask + bid) / 2.0;
   double drift     = MathAbs(PriceToPts(mid - curCentre));
   if(drift < InpRecenterDriftPts)
      return;

   //--- recompute with the exact same tick-integer geometry
   double newBuy, newSell;
   long   dTicks;
   if(!ComputeStraddleLevels(newBuy, newSell, dTicks))
      return;

   double newBuySL, newSellSL, newBuyTP, newSellTP;
   ComputeStraddleStops(newBuy, newSell, newBuySL, newSellSL, newBuyTP, newSellTP);

   Log(StringFormat("Re-centering straddle (centre drift %.1f pts): buy %s->%s  sell %s->%s  width=%s",
                    drift, DoubleToString(bp, g_digits), DoubleToString(newBuy, g_digits),
                    DoubleToString(sp, g_digits), DoubleToString(newSell, g_digits),
                    DoubleToString(newBuy - newSell, g_digits)));

   //--- move the FAR leg first: if we widened the near leg first the
   //    broker could reject it, leaving a lopsided straddle for a moment
   bool a = false, b = false;
   if(newBuy > bp)
     {
      a = ModifyPendingOrder(buyTicket,  newBuy,  newBuySL,  newBuyTP);
      b = ModifyPendingOrder(sellTicket, newSell, newSellSL, newSellTP);
     }
   else
     {
      b = ModifyPendingOrder(sellTicket, newSell, newSellSL, newSellTP);
      a = ModifyPendingOrder(buyTicket,  newBuy,  newBuySL,  newBuyTP);
     }

   if(a && b)
     {
      g_lastRecenter    = TimeCurrent();
      g_plannedBuyStop  = newBuy;
      g_plannedSellStop = newSell;
      g_dTicksLast      = dTicks;
      VerifyStraddleWidth();
     }
   else
     {
      //--- partial re-center = broken geometry. Rebuild from scratch so
      //    the width is guaranteed exact again.
      LogAlways("Re-center partially failed -> rebuilding straddle to keep width exact.");
      DeleteAllOurPendings();
     }
  }

//==================================================================
//  POSITION MANAGEMENT  (SL init -> breakeven -> ladder -> trail)
//==================================================================
double EffectiveBETriggerPts()
  {
   // must be far enough that SL at entry is a legal distance from market
   double minTrig = StopLevelPts() + InpBELockPoints + 2.0;
   double t = InpBETriggerPoints;
   if(t < minTrig)
      t = minTrig;
   return t;
  }

void ManageOpenPosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return;

   long   ptype  = PositionGetInteger(POSITION_TYPE);
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL  = PositionGetDouble(POSITION_SL);
   double curTP  = PositionGetDouble(POSITION_TP);
   bool   isBuy  = (ptype == POSITION_TYPE_BUY);
   double market = isBuy ? Bid() : Ask();
   if(market <= 0 || entry <= 0)
      return;

   double profitPts = isBuy ? PriceToPts(market - entry) : PriceToPts(entry - market);

   //----------------------------------------------------------------
   // STEP 0: make sure a stop loss exists (opposite level).
   //         Normally already attached to the pending order.
   //----------------------------------------------------------------
   double desiredSL = curSL;

   if(curSL <= 0)
     {
      double fb;
      if(InpFallbackSLPoints > 0)
         fb = PtsToPrice(InpFallbackSLPoints);
      else
        {
         // opposite level is roughly 2 x distance away from entry
         double opp = isBuy ? g_plannedSellStop : g_plannedBuyStop;
         if(opp > 0)
            fb = MathAbs(entry - opp);
         else
            fb = PtsToPrice(EffectiveDistancePts() * 2.0);
        }
      desiredSL = isBuy ? (entry - fb) : (entry + fb);
      LogAlways("Position #" + IntegerToString((long)ticket) +
                " had no SL -> setting protective SL at " + DoubleToString(desiredSL, g_digits));
     }

   //----------------------------------------------------------------
   // STEP 1: BREAKEVEN - thoda bhi favour me gaya to position safe
   //----------------------------------------------------------------
   double bestSL = desiredSL;

   if(InpUseBreakeven && profitPts >= EffectiveBETriggerPts())
     {
      double beSL = isBuy ? (entry + PtsToPrice(InpBELockPoints))
                          : (entry - PtsToPrice(InpBELockPoints));
      if(isBuy) { if(beSL > bestSL) bestSL = beSL; }
      else      { if(bestSL <= 0 || beSL < bestSL) bestSL = beSL; }
     }

   //----------------------------------------------------------------
   // STEP 2: STEP LADDER LOCKING - stage-wise profit lock
   //----------------------------------------------------------------
   if(InpUseLadderTrail && g_ladderCount > 0)
     {
      double lockPts = -1;
      for(int i = 0; i < g_ladderCount; i++)
         if(profitPts >= g_ladderTrig[i])
            lockPts = g_ladderLock[i];   // ladder is sorted ascending -> highest reached wins
      if(lockPts >= 0)
        {
         double lSL = isBuy ? (entry + PtsToPrice(lockPts)) : (entry - PtsToPrice(lockPts));
         if(isBuy) { if(lSL > bestSL) bestSL = lSL; }
         else      { if(bestSL <= 0 || lSL < bestSL) bestSL = lSL; }
        }
     }

   //----------------------------------------------------------------
   // STEP 3: CLASSIC AGGRESSIVE TRAILING beyond the ladder
   //----------------------------------------------------------------
   if(InpUseClassicTrail && profitPts >= InpTrailStartPoints)
     {
      double tSL = isBuy ? (market - PtsToPrice(InpTrailDistancePts))
                         : (market + PtsToPrice(InpTrailDistancePts));
      if(isBuy) { if(tSL > bestSL) bestSL = tSL; }
      else      { if(bestSL <= 0 || tSL < bestSL) bestSL = tSL; }
     }

   if(bestSL <= 0)
      return;

   //----------------------------------------------------------------
   // STEP 4: validate against broker stops level, then send
   //----------------------------------------------------------------
   double minGap = StopLevelPrice();
   if(isBuy)
     {
      double maxAllowed = NormPrice(Bid() - minGap);
      if(bestSL > maxAllowed)
         bestSL = maxAllowed;
     }
   else
     {
      double minAllowed = NormPrice(Ask() + minGap);
      if(bestSL < minAllowed)
         bestSL = minAllowed;
     }
   bestSL = NormPrice(bestSL);

   //--- freeze level guard
   double fz = FreezeLevelPrice();
   if(fz > 0 && MathAbs(market - bestSL) < fz)
      return;

   //--- only move SL in the protective direction, respecting step
   double step = PtsToPrice(MathMax(0.0, InpTrailStepPoints));
   if(curSL > 0)
     {
      if(isBuy && bestSL <= curSL + step * 0.999)
         return;
      if(!isBuy && bestSL >= curSL - step * 0.999)
         return;
     }

   //--- sanity: never place SL on the wrong side of the market
   if(isBuy && bestSL >= Bid())
      return;
   if(!isBuy && bestSL <= Ask())
      return;

   string why;
   if(curSL <= 0)
      why = "init-protect";
   else if(MathAbs(bestSL - entry) <= PtsToPrice(MathMax(1.0, InpBELockPoints)) )
      why = StringFormat("breakeven @%.1f pts", profitPts);
   else
      why = StringFormat("trail-lock @%.1f pts", profitPts);

   ModifyPositionSL(ticket, bestSL, curTP, why);
  }

//==================================================================
//  MAIN ENGINE
//==================================================================
void ProcessLogic()
  {
   if(!g_initOK || g_busy)
      return;
   g_busy = true;

   UpdateDayStamp();

   ulong posTickets[];
   int   posCnt   = CollectOurPositions(posTickets);
   ulong buyTicket = 0, sellTicket = 0;
   int   orderCnt = ScanOurOrders(buyTicket, sellTicket);

   //---------------------------------------------------------------
   // A) Position open -> OCO cleanup + management
   //---------------------------------------------------------------
   if(posCnt > 0)
     {
      if(orderCnt > 0)
        {
         // the opposite pending order is no longer needed:
         // its price level is already sitting on the position as SL
         Log("Position open -> deleting remaining pending order(s).");
         DeleteAllOurPendings();
        }

      // manage every position we own (a violent spike can fill both legs
      // on a hedging account before the OCO delete lands)
      for(int i = 0; i < posCnt; i++)
         ManageOpenPosition(posTickets[i]);

      if(PositionSelectByTicket(posTickets[0]))
        {
         long   t  = PositionGetInteger(POSITION_TYPE);
         double e  = PositionGetDouble(POSITION_PRICE_OPEN);
         double pp = (t == POSITION_TYPE_BUY) ? PriceToPts(Bid() - e) : PriceToPts(e - Ask());
         g_lastStatus = StringFormat("IN POSITION %s  entry=%s  profit=%.1f pts  SL=%s",
                                     (t == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                                     DoubleToString(e, g_digits), pp,
                                     DoubleToString(PositionGetDouble(POSITION_SL), g_digits));
         if(posCnt > 1)
            g_lastStatus += StringFormat("  (+%d more)", posCnt - 1);
        }
      g_busy = false;
      return;
     }

   //---------------------------------------------------------------
   // B) No position, both pendings alive -> wait / re-center
   //---------------------------------------------------------------
   if(buyTicket != 0 && sellTicket != 0 && orderCnt == 2)
     {
      MaybeRecenter(buyTicket, sellTicket);

      double bp = 0.0, sp = 0.0;
      if(OrderSelect(buyTicket))
         bp = OrderGetDouble(ORDER_PRICE_OPEN);
      if(OrderSelect(sellTicket))
         sp = OrderGetDouble(ORDER_PRICE_OPEN);

      g_lastStatus = StringFormat("WAITING for breakout | buystop=%s sellstop=%s | spread=%.1f pts",
                                  DoubleToString(bp, g_digits),
                                  DoubleToString(sp, g_digits),
                                  SpreadPts());
      g_busy = false;
      return;
     }

   //---------------------------------------------------------------
   // C) Broken state (0 or 1 pending, no position) -> restart cycle
   //---------------------------------------------------------------
   if(orderCnt > 0 && orderCnt != 2)
     {
      Log(StringFormat("Incomplete pending set (%d) with no position -> resetting.", orderCnt));
      DeleteAllOurPendings();
      g_busy = false;
      return;
     }

   //---------------------------------------------------------------
   // D) Clean slate -> place a fresh straddle (the LOOP)
   //---------------------------------------------------------------
   string reason = "";
   if(!CanOpenNewCycle(reason))
     {
      g_lastStatus = "IDLE: " + reason;
      g_busy = false;
      return;
     }

   if(PlaceStraddle())
      g_lastStatus = "Straddle placed, waiting for breakout";
   else
      g_lastStatus = "Straddle placement failed, will retry";

   g_busy = false;
  }

//==================================================================
//  DASHBOARD
//==================================================================
void DrawPanel()
  {
   if(!InpShowPanel)
      return;

   string ladder = "";
   for(int i = 0; i < g_ladderCount; i++)
      ladder += StringFormat("%.0f>%.0f ", g_ladderTrig[i], g_ladderLock[i]);
   if(ladder == "")
      ladder = "(off)";

   string txt = StringFormat(
                   "════ GOLD STRADDLE SCALPER (HFT) ════\n"
                   "Symbol      : %s   digits=%d   1 pt = %s\n"
                   "Bid/Ask     : %s / %s   spread = %.1f pts\n"
                   "Distance    : %.1f pts each side  ->  target width %.1f pts\n"
                   "Live width  : %s   (buy SL dist %s / sell SL dist %s)  %s\n"
                   "Breakeven   : %s @ %.1f pts (lock %.1f)\n"
                   "Ladder      : %s\n"
                   "Classic tr. : %s  start %.0f  dist %.0f  step %.0f\n"
                   "Lot         : %s\n"
                   "Cycles done : %d    Trades today : %d    Day P/L : %.2f\n"
                   "Status      : %s",
                   g_symbol, g_digits, DoubleToString(g_adjPoint, g_digits),
                   DoubleToString(Bid(), g_digits), DoubleToString(Ask(), g_digits), SpreadPts(),
                   EffectiveDistancePts(), EffectiveDistancePts() * 2.0,
                   DoubleToString(g_lastWidth, g_digits),
                   DoubleToString(g_lastBuySLD, g_digits),
                   DoubleToString(g_lastSellSLD, g_digits),
                   (InpExactWidth ? "[EXACT mode]" : "[legacy ask/bid mode]"),
                   (InpUseBreakeven ? "ON" : "OFF"), EffectiveBETriggerPts(), InpBELockPoints,
                   ladder,
                   (InpUseClassicTrail ? "ON" : "OFF"), InpTrailStartPoints, InpTrailDistancePts, InpTrailStepPoints,
                   (InpLotMode == LOT_MODE_FIXED ? "fixed " + DoubleToString(InpFixedLot, 2)
                                                 : "risk " + DoubleToString(InpRiskPercent, 2) + "%"),
                   g_cycleCount, g_tradesToday, DailyPL(),
                   g_lastStatus);
   Comment(txt);
  }

//==================================================================
//  EVENT HANDLERS
//==================================================================
int OnInit()
  {
   if(!SetupSymbol())
      return INIT_FAILED;

   ParseLadder(InpLadder);

   if(InpDistancePoints <= 0)
     {
      LogAlways("ERROR: Distance must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotMode == LOT_MODE_FIXED && InpFixedLot <= 0)
     {
      LogAlways("ERROR: Fixed lot must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBELockPoints < 0 || InpBELockPoints >= InpBETriggerPoints)
      LogAlways("WARNING: BE lock points should be smaller than the BE trigger.");

   if(InpWarnTimeframe && _Period != PERIOD_M1)
      LogAlways("NOTE: this EA is tick-driven and tuned for M1. Current chart TF is " +
                EnumToString((ENUM_TIMEFRAMES)_Period) + " - it will still work.");

   g_dayStamp        = 0;
   UpdateDayStamp();
   g_lastCloseTime   = 0;
   g_lastRecenter    = 0;
   g_cycleCount      = 0;
   g_busy            = false;
   g_initOK          = true;

   if(InpUseTimerEngine)
     {
      int ms = (int)MathMax(20, InpTimerMs);
      if(!EventSetMillisecondTimer(ms))
         LogAlways("WARNING: could not start millisecond timer, running on ticks only.");
      else
         Log("Timer engine started: " + IntegerToString(ms) + " ms");
     }

   LogAlways("Initialized on " + g_symbol + ". Magic=" + IntegerToString(InpMagic));
   DrawPanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeletePendingOnExit)
     {
      int n = DeleteAllOurPendings();
      if(n > 0)
         LogAlways("Removed " + IntegerToString(n) + " pending order(s) on deinit.");
     }
   Comment("");
   LogAlways("Stopped. Reason=" + IntegerToString(reason));
  }

void OnTick()
  {
   ProcessLogic();
   DrawPanel();
  }

void OnTimer()
  {
   ProcessLogic();
   DrawPanel();
  }

//--- react instantly when an order fills or a position closes
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_initOK)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(trans.symbol != g_symbol)
         return;
      if(!HistoryDealSelect(trans.deal))
         return;
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
         return;

      long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      long dealType  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         return;

      if(entryType == DEAL_ENTRY_IN)
        {
         g_tradesToday++;
         LogAlways(StringFormat("TRIGGERED: %s @ %s  -> deleting opposite pending, SL already at opposite level.",
                                (dealType == DEAL_TYPE_BUY ? "BUY" : "SELL"),
                                DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), g_digits)));
         DeleteAllOurPendings();   // instant OCO
         ProcessLogic();           // set/verify SL immediately
        }
      else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
        {
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                         HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                         HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         g_lastCloseTime = TimeCurrent();
         g_cycleCount++;
         LogAlways(StringFormat("CLOSED cycle #%d  result=%.2f %s  -> new straddle after %d sec.",
                                g_cycleCount, profit, AccountInfoString(ACCOUNT_CURRENCY),
                                InpPauseAfterCloseSecs));
         DeleteAllOurPendings();   // safety: nothing should be left over
        }
     }
  }
//+------------------------------------------------------------------+
