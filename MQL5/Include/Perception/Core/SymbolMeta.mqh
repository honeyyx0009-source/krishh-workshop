//+------------------------------------------------------------------+
//|                                                   SymbolMeta.mqh |
//|            001 PERCEPTION - Automatic symbol / broker detection   |
//|                                                                  |
//| One of the promises of 001 PERCEPTION is "no manual              |
//| configuration". This class interrogates the terminal for every   |
//| property that matters and exposes clean helpers so the rest of   |
//| the framework can size trades, normalise prices and respect      |
//| broker constraints without ever hard-coding a symbol assumption. |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_SYMBOLMETA_MQH
#define PERCEPTION_CORE_SYMBOLMETA_MQH

#include <Perception/Core/Utils.mqh>

class CSymbolMeta
  {
private:
   string   m_symbol;
   int      m_digits;
   double   m_point;
   double   m_tickSize;
   double   m_tickValue;
   double   m_contractSize;
   double   m_volMin;
   double   m_volMax;
   double   m_volStep;
   int      m_stopLevel;      // points
   int      m_freezeLevel;    // points
   double   m_swapLong;
   double   m_swapShort;
   double   m_valuePerPoint;  // account currency per 1 point per 1.0 lot
   double   m_pipSize;        // price move of one "pip"
   int      m_pipPoints;      // points in one pip (1, 10 ...)
   double   m_estCommission;  // per lot per side, learned from deals
   int      m_gmtOffsetHours;
   ENUM_SYMBOL_TRADE_EXECUTION m_execMode;
   ENUM_ORDER_TYPE_FILLING     m_filling;
   bool     m_loaded;

public:
                     CSymbolMeta(): m_loaded(false), m_estCommission(0.0) {}

   //--- read every static property of the symbol ---------------------
   bool Load(const string symbol)
     {
      m_symbol=symbol;
      if(!SymbolSelect(m_symbol,true)) return false;

      m_digits      = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      m_point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      m_tickSize    = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      m_tickValue   = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      m_contractSize= SymbolInfoDouble(m_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      m_volMin      = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      m_volMax      = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      m_volStep     = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      m_stopLevel   = (int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel = (int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      m_swapLong    = SymbolInfoDouble(m_symbol,SYMBOL_SWAP_LONG);
      m_swapShort   = SymbolInfoDouble(m_symbol,SYMBOL_SWAP_SHORT);
      m_execMode    = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_EXEMODE);

      if(m_point<=0.0) m_point=MathPow(10,-m_digits);
      if(m_tickSize<=0.0) m_tickSize=m_point;

      //--- value of a single point move for one lot -----------------
      m_valuePerPoint = PU::SafeDiv(m_tickValue*m_point,m_tickSize,m_tickValue);
      if(m_valuePerPoint<=0.0) m_valuePerPoint=m_tickValue;

      //--- a "pip" is 10 points on 3/5-digit fx, else 1 point -------
      m_pipPoints = ((m_digits==3 || m_digits==5) ? 10 : 1);
      m_pipSize   = m_point*m_pipPoints;

      ResolveFilling();
      EstimateGmtOffset();

      m_loaded=true;
      return true;
     }

   //--- pick a filling mode the broker actually accepts --------------
   void ResolveFilling()
     {
      int modes=(int)SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((modes & SYMBOL_FILLING_FOK)!=0)      m_filling=ORDER_FILLING_FOK;
      else if((modes & SYMBOL_FILLING_IOC)!=0) m_filling=ORDER_FILLING_IOC;
      else                                     m_filling=ORDER_FILLING_RETURN;
     }

   //--- best-effort broker GMT offset in hours -----------------------
   void EstimateGmtOffset()
     {
      datetime server=TimeTradeServer();
      datetime gmt=TimeGMT();
      if(server>0 && gmt>0)
         m_gmtOffsetHours=(int)MathRound((double)(server-gmt)/3600.0);
      else
         m_gmtOffsetHours=0;
     }

   //--- refresh volatile quotes --------------------------------------
   double Bid() const { return SymbolInfoDouble(m_symbol,SYMBOL_BID); }
   double Ask() const { return SymbolInfoDouble(m_symbol,SYMBOL_ASK); }
   double Mid() const { return 0.5*(Bid()+Ask()); }
   double SpreadPoints() const
     {
      double a=Ask(),b=Bid();
      return PU::SafeDiv(a-b,m_point,0.0);
     }

   //--- learn commission from a closed deal (per lot per side) -------
   void ObserveCommission(const double commissionMoney,const double lots)
     {
      if(lots<=0.0 || commissionMoney>=0.0) return; // commission is negative
      double perLotPerSide=MathAbs(commissionMoney)/(lots*2.0);
      if(m_estCommission<=0.0) m_estCommission=perLotPerSide;
      else                     m_estCommission=PU::EmaUpdate(m_estCommission,perLotPerSide,0.25);
     }

   //--- volume normalisation to broker rules -------------------------
   double NormalizeLots(const double lots) const
     {
      double v=PU::RoundToStep(lots,m_volStep);
      v=PU::Clamp(v,m_volMin,m_volMax);
      return v;
     }

   //--- price helpers ------------------------------------------------
   double NormalizePrice(const double price) const { return NormalizeDouble(price,m_digits); }
   double PointsToPrice(const double pts)    const { return pts*m_point; }
   double PriceToPoints(const double price)  const { return PU::SafeDiv(price,m_point,0.0); }

   //--- accessors ----------------------------------------------------
   bool     IsLoaded()      const { return m_loaded; }
   string   Symbol()        const { return m_symbol; }
   int      Digits()        const { return m_digits; }
   double   Point()         const { return m_point; }
   double   TickSize()      const { return m_tickSize; }
   double   TickValue()     const { return m_tickValue; }
   double   ContractSize()  const { return m_contractSize; }
   double   VolMin()        const { return m_volMin; }
   double   VolMax()        const { return m_volMax; }
   double   VolStep()       const { return m_volStep; }
   int      StopLevel()     const { return m_stopLevel; }
   int      FreezeLevel()   const { return m_freezeLevel; }
   double   SwapLong()      const { return m_swapLong; }
   double   SwapShort()     const { return m_swapShort; }
   double   ValuePerPoint() const { return m_valuePerPoint; }
   double   PipSize()       const { return m_pipSize; }
   int      PipPoints()     const { return m_pipPoints; }
   double   Commission()    const { return m_estCommission; }
   int      GmtOffset()     const { return m_gmtOffsetHours; }
   ENUM_ORDER_TYPE_FILLING Filling() const { return m_filling; }
   ENUM_SYMBOL_TRADE_EXECUTION ExecMode() const { return m_execMode; }

   //--- money value of a stop distance (points) for a given volume ---
   double RiskMoney(const double stopPoints,const double lots) const
     {
      return stopPoints*m_valuePerPoint*lots;
     }

   //--- lots required to risk `money` over `stopPoints` --------------
   double LotsForRisk(const double money,const double stopPoints) const
     {
      double perLot=stopPoints*m_valuePerPoint;
      if(perLot<=0.0) return m_volMin;
      return NormalizeLots(money/perLot);
     }

   //--- human readable one-liner for the dashboard -------------------
   string Describe() const
     {
      return StringFormat("%s  d=%d pt=%.5g tick=%.5g/%.5g lot[%.2f..%.2f/%.2f] stop=%d",
                          m_symbol,m_digits,m_point,m_tickSize,m_tickValue,
                          m_volMin,m_volMax,m_volStep,m_stopLevel);
     }
  };

#endif // PERCEPTION_CORE_SYMBOLMETA_MQH
//+------------------------------------------------------------------+
