//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|            Adaptive Gold Grid EA - Preset / Configuration system  |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Central, broker-agnostic parameter table for the EA. The user  |
//|   picks ONE account preset in the EA inputs; CConfig then hands   |
//|   back a fully tuned PresetProfile struct. Every engine in later  |
//|   features (GridEngine, LotSizer, RecoveryEngine, SafetyValve)    |
//|   reads its limits from this single source of truth.             |
//|                                                                  |
//| DESIGN NOTE ON MARTINGALE (READ THIS)                            |
//|   This EA uses a grid + basket-recovery (martingale-style) lot   |
//|   progression. That progression is *always* BOUNDED:             |
//|     - lot_progression_factor scales each deeper grid lot, but     |
//|     - max_lot_cap hard-caps any single order's volume, and        |
//|     - max_basket_exposure_lots hard-caps the summed basket volume.|
//|   No preset allows unbounded doubling. Micro is the most          |
//|   conservative; Commercial is the largest but still bounded.     |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_CONFIG_MQH
#define ADAPTIVEGRID_CONFIG_MQH

//+------------------------------------------------------------------+
//| Account preset selector.                                         |
//| Ordered smallest -> largest account capitalisation.              |
//+------------------------------------------------------------------+
enum ENUM_ACCOUNT_PRESET
  {
   PRESET_MICRO,        // Smallest: micro accounts, minimal exposure
   PRESET_MEDIUM,       // Medium accounts, moderate exposure
   PRESET_LARGE,        // Large accounts, higher exposure
   PRESET_BIGLEVEL,     // Big-level accounts, aggressive but bounded
   PRESET_COMMERCIAL    // Largest: commercial / fund grade capital
  };

//+------------------------------------------------------------------+
//| PresetProfile                                                    |
//|   The tuned parameter set returned per preset. Every field is    |
//|   documented; downstream modules must never hardcode these       |
//|   values, they must read them from here.                         |
//+------------------------------------------------------------------+
struct PresetProfile
  {
   //--- Base sizing -------------------------------------------------
   double base_lot;                  // Starting/first grid order lot size (broker-normalised later)
   int    max_grid_levels;           // Max number of averaging grid levels in one basket
   double risk_percent_per_trade;    // % of equity risked to seed the first order (used by LotSizer)

   //--- Bounded martingale progression ------------------------------
   double lot_progression_factor;    // Martingale multiplier applied to each deeper grid lot (>=1.0)
   double max_lot_cap;               // HARD cap on any single order's volume (bounds the martingale)
   double max_basket_exposure_lots;  // HARD cap on the summed volume of the whole basket (total exposure)

   //--- Grid spacing ------------------------------------------------
   double atr_spacing_multiplier;    // Grid step distance = ATR * this multiplier (adaptive spacing)

   //--- Safety valve thresholds (entry-blocking only) ---------------
   double max_drawdown_percent;      // Circuit breaker: block NEW entries above this equity drawdown %
   double margin_level_floor_percent;// Block NEW entries when ACCOUNT_MARGIN_LEVEL falls below this %
   double min_free_margin_currency;  // Block NEW entries when ACCOUNT_MARGIN_FREE falls below this (acct ccy)
  };

//+------------------------------------------------------------------+
//| CConfig                                                          |
//|   Returns the tuned PresetProfile for a given ENUM_ACCOUNT_PRESET.|
//|   Values are conservative sane defaults; the user can still       |
//|   override individual inputs in the main EA if desired.          |
//+------------------------------------------------------------------+
class CConfig
  {
public:
                     CConfig(void) {}
                    ~CConfig(void) {}

   //--- Return the fully populated profile for the selected preset.
   PresetProfile     GetProfile(const ENUM_ACCOUNT_PRESET preset) const
     {
      PresetProfile p;
      switch(preset)
        {
         case PRESET_MICRO:      FillMicro(p);      break;
         case PRESET_MEDIUM:     FillMedium(p);     break;
         case PRESET_LARGE:      FillLarge(p);      break;
         case PRESET_BIGLEVEL:   FillBigLevel(p);   break;
         case PRESET_COMMERCIAL: FillCommercial(p); break;
         default:                FillMicro(p);      break; // safest fallback
        }
      return(p);
     }

   //--- Human-readable name for logging.
   string            PresetName(const ENUM_ACCOUNT_PRESET preset) const
     {
      switch(preset)
        {
         case PRESET_MICRO:      return("MICRO");
         case PRESET_MEDIUM:     return("MEDIUM");
         case PRESET_LARGE:      return("LARGE");
         case PRESET_BIGLEVEL:   return("BIGLEVEL");
         case PRESET_COMMERCIAL: return("COMMERCIAL");
         default:                return("UNKNOWN");
        }
     }

private:
   //--- PRESET_MICRO : smallest account, most conservative ----------
   void              FillMicro(PresetProfile &p) const
     {
      p.base_lot                  = 0.01;
      p.max_grid_levels           = 6;
      p.risk_percent_per_trade    = 0.25;
      p.lot_progression_factor    = 1.30;   // gentle martingale
      p.max_lot_cap               = 0.10;   // no single order beyond 0.10
      p.max_basket_exposure_lots  = 0.50;   // whole basket capped at 0.50
      p.atr_spacing_multiplier    = 1.50;
      p.max_drawdown_percent      = 25.0;
      p.margin_level_floor_percent= 400.0;
      p.min_free_margin_currency  = 20.0;
     }

   //--- PRESET_MEDIUM ----------------------------------------------
   void              FillMedium(PresetProfile &p) const
     {
      p.base_lot                  = 0.05;
      p.max_grid_levels           = 8;
      p.risk_percent_per_trade    = 0.35;
      p.lot_progression_factor    = 1.40;
      p.max_lot_cap               = 0.50;
      p.max_basket_exposure_lots  = 2.50;
      p.atr_spacing_multiplier    = 1.40;
      p.max_drawdown_percent      = 30.0;
      p.margin_level_floor_percent= 350.0;
      p.min_free_margin_currency  = 100.0;
     }

   //--- PRESET_LARGE ------------------------------------------------
   void              FillLarge(PresetProfile &p) const
     {
      p.base_lot                  = 0.10;
      p.max_grid_levels           = 10;
      p.risk_percent_per_trade    = 0.45;
      p.lot_progression_factor    = 1.45;
      p.max_lot_cap               = 1.50;
      p.max_basket_exposure_lots  = 8.00;
      p.atr_spacing_multiplier    = 1.30;
      p.max_drawdown_percent      = 35.0;
      p.margin_level_floor_percent= 300.0;
      p.min_free_margin_currency  = 500.0;
     }

   //--- PRESET_BIGLEVEL : aggressive but still bounded --------------
   void              FillBigLevel(PresetProfile &p) const
     {
      p.base_lot                  = 0.25;
      p.max_grid_levels           = 12;
      p.risk_percent_per_trade    = 0.55;
      p.lot_progression_factor    = 1.50;
      p.max_lot_cap               = 4.00;
      p.max_basket_exposure_lots  = 25.00;
      p.atr_spacing_multiplier    = 1.20;
      p.max_drawdown_percent      = 40.0;
      p.margin_level_floor_percent= 250.0;
      p.min_free_margin_currency  = 2000.0;
     }

   //--- PRESET_COMMERCIAL : largest capital, bounded exposure ------
   void              FillCommercial(PresetProfile &p) const
     {
      p.base_lot                  = 0.50;
      p.max_grid_levels           = 15;
      p.risk_percent_per_trade    = 0.65;
      p.lot_progression_factor    = 1.55;
      p.max_lot_cap               = 10.00;
      p.max_basket_exposure_lots  = 75.00;
      p.atr_spacing_multiplier    = 1.15;
      p.max_drawdown_percent      = 45.0;
      p.margin_level_floor_percent= 200.0;
      p.min_free_margin_currency  = 10000.0;
     }
  };

#endif // ADAPTIVEGRID_CONFIG_MQH
//+------------------------------------------------------------------+
