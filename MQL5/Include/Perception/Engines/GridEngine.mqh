//+------------------------------------------------------------------+
//|                                                    GridEngine.mqh |
//|             001 PERCEPTION - Range grid engine (opt-in)           |
//|                                                                  |
//| A disciplined, capped scaling-in engine for genuine ranges. It   |
//| seeds a mean-reverting position and adds a bounded number of     |
//| levels as price moves against the basket, each level a fixed     |
//| ATR step apart. It is DISABLED by default because grids convert  |
//| many small wins into occasional large losses if used blindly.    |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_GRID_MQH
#define PERCEPTION_ENGINES_GRID_MQH

#include <Perception/Engines/IEngine.mqh>

class CGridEngine : public CEngine
  {
protected:
   //--- allow the adaptive variant to widen the step ----------------
   virtual double StepMultiplier(const SMarketState &st,const SConfig &cfg)
     { return cfg.gridStepAtrMult; }

public:
   CGridEngine() { m_id=ENG_GRID; m_name="Grid"; m_enabled=false; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_RANGE:    return 0.78;
         case REGIME_SIDEWAYS: return 0.72;
         case REGIME_CALM:     return 0.60;
         default:              return 0.10;      // never grid into a trend
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double step=StepMultiplier(st,cfg)*atr;
      int levels=OwnCount();

      //--- seed the basket toward the mean --------------------------
      if(levels==0)
        {
         if(st.mid<st.bbMid)
           { out.dir=SIG_BUY;  out.tp=sym.NormalizePrice(st.bbMid); }
         else
           { out.dir=SIG_SELL; out.tp=sym.NormalizePrice(st.bbMid); }
         out.confidence=0.5; out.quality=0.4; out.reason="Grid seed";
         return;
        }

      if(levels>=cfg.gridMaxLevels) return;              // basket is full

      //--- add a level once price has travelled one step -----------
      double bBuy,wBuy,bSell,wSell; int buys,sells;
      OwnExtreme(bBuy,wBuy,bSell,wSell,buys,sells);
      double lot=sym.VolMin()*MathPow(cfg.gridLotFactor,levels);

      if(buys>0 && st.mid<=wBuy-step)
        {
         out.dir=SIG_BUY; out.lots=sym.NormalizeLots(lot);
         out.tp=sym.NormalizePrice(st.bbMid); out.confidence=0.5; out.quality=0.4;
         out.reason=StringFormat("Grid add L%d",levels+1);
        }
      else if(sells>0 && st.mid>=wSell+step)
        {
         out.dir=SIG_SELL; out.lots=sym.NormalizeLots(lot);
         out.tp=sym.NormalizePrice(st.bbMid); out.confidence=0.5; out.quality=0.4;
         out.reason=StringFormat("Grid add L%d",levels+1);
        }
     }
  };

#endif // PERCEPTION_ENGINES_GRID_MQH
//+------------------------------------------------------------------+
