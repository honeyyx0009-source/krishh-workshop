//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|            Adaptive Gold Grid EA - Preset / Configuration system  |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Central, broker-agnostic parameter table for the EA. The user  |
//|   picks ONE account preset in the EA inputs; CConfig then hands   |
//|   back a fully tuned PresetProfile struct. Every engine reads its  |
//|   limits from this single source of truth.                        |
//|                                                                  |
//| ================  v2 RETUNE - WHY THE NUMBERS CHANGED  ========== |
//|                                                                  |
//|   v1 blew up a $1000 demo account on XAUUSD in two days using     |
//|   PRESET_MICRO. That was a genuine sizing defect, and this is the  |
//|   arithmetic behind the fix.                                      |
//|                                                                  |
//|   GOLD CONTRACT MATH (the number that matters):                   |
//|     1.00 lot XAUUSD = 100 oz  =>  a $1 gold move = $100 P&L       |
//|     therefore        0.01 lot =>  a $1 gold move = $1   P&L       |
//|     basket loss  ~=  exposure_lots * 100 * adverse_move_in_dollars |
//|                                                                  |
//|   v1 PRESET_MICRO allowed max_basket_exposure_lots = 0.50 and      |
//|   6 grid levels. On a $1000 account that permitted roughly 0.13    |
//|   lots of real exposure, so a $77 adverse gold move was already    |
//|   a full account. Gold routinely travels $100-150 in a couple of   |
//|   days, so the blow-up was arithmetic, not bad luck.               |
//|                                                                  |
//|   v2 sizes every preset to a CONSISTENT exposure density of        |
//|   approximately 0.02 lots per $1000 of equity (see                 |
//|   exposure_lots_per_1k). At that density a $100 adverse gold move  |
//|   costs about 20% of equity, which the basket stop cuts into long  |
//|   before it becomes fatal. Grid depth, progression factors and      |
//|   per-order caps were all reduced to match.                        |
//|                                                                  |
//|   HONEST CONSEQUENCE: smaller exposure means smaller absolute      |
//|   profit. On a $1000 account a completed basket is worth single-   |
//|   digit dollars. That is arithmetic, not a defect. Small capital   |
//|   cannot produce large absolute returns without the risk of ruin   |
//|   that destroyed the v1 test.                                     |
//|                                                                  |
//| DESIGN NOTE ON MARTINGALE (READ THIS)                            |
//|   This EA uses a grid + basket-recovery (martingale-style) lot     |
//|   progression. That progression is *always* BOUNDED:               |
//|     - lot_progression_factor scales each deeper grid lot, but      |
//|     - max_lot_cap hard-caps any single order's volume, and         |
//|     - max_basket_exposure_lots hard-caps the summed basket volume. |
//|   No preset allows unbounded doubling. PRESET_NANO is the most     |
//|   conservative (flat 1.0 progression - no martingale at all);      |
//|   PRESET_COMMERCIAL is the largest but still bounded.              |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_CONFIG_MQH
#define ADAPTIVEGRID_CONFIG_MQH

//+------------------------------------------------------------------+
//| Account preset selector.                                         |
//| Ordered smallest -> largest account capitalisation.              |
//+------------------------------------------------------------------+
enum ENUM_ACCOUNT_PRESET
  {
   PRESET_NANO,         // ~$500-1500 : flat lots, no martingale at all
   PRESET_MICRO,        // ~$1500-5000 : micro accounts, minimal exposure
   PRESET_MEDIUM,       // ~$5k-15k : moderate exposure
   PRESET_LARGE,        // ~$15k-50k : higher exposure
   PRESET_BIGLEVEL,     // ~$50k-150k : aggressive but bounded
   PRESET_COMMERCIAL    // ~$150k+ : commercial / fund grade capital
  };

//+------------------------------------------------------------------+
//| PresetProfile                                                    |
//|   The tuned parameter set returned per preset. Every field is     |
//|   documented; downstream modules must never hardcode these        |
//|   values, they must read them from here.                         |
//+------------------------------------------------------------------+
struct PresetProfile
  {
   //--- Base sizing -------------------------------------------------
   double base_lot;                  // Starting/first grid order lot size (broker-normalised later)
   int    max_grid_levels;           // Max number of averaging grid levels in one basket
   double risk_percent_per_trade;    // % of equity risked to seed the first order (used by LotSizer)

   //--- Bounded martingale progression ------------------------------
   double lot_progression_factor;    // Martingale multiplier per deeper grid lot (>=1.0; 1.0 = flat)
   double max_lot_cap;               // HARD cap on any single order's volume (bounds the martingale)
   double max_basket_exposure_lots;  // HARD cap on the summed volume of the whole basket

   //--- Grid spacing ------------------------------------------------
   double atr_spacing_multiplier;    // Grid step distance = ATR * this multiplier (adaptive spacing)

   //--- Safety valve thresholds (entry-blocking only) ---------------
   double max_drawdown_percent;      // Circuit breaker: block NEW entries above this equity drawdown %
   double margin_level_floor_percent;// Block NEW entries when ACCOUNT_MARGIN_LEVEL falls below this %
   double min_free_margin_currency;  // Block NEW entries when ACCOUNT_MARGIN_FREE falls below this

   //--- v2: BASKET STOP (bounded loss backstop) ---------------------
   //  Closes the WHOLE basket at a bounded loss and starts fresh.
   //  This is a deliberate reversal of the v1 "profit-only close"
   //  rule: without it, a basket on the wrong side of a trend simply
   //  holds until the account dies (exactly what the v1 test showed).
   bool   enable_basket_stop;        // Master switch for the basket stop
   double basket_stop_loss_percent;  // Close basket when floating loss >= this % of equity

   //--- v2: TIME-DECAY GROUP TAKE-PROFIT ---------------------------
   //  The group profit target SHRINKS as the basket ages, so an old
   //  basket escapes at a small profit instead of being stuck for
   //  weeks waiting for a full-size target.
   double tp_decay_start_hours;      // Age (hours) after which the target starts shrinking
   double tp_decay_full_hours;       // Age (hours) at which the target reaches its floor
   double tp_decay_floor_fraction;   // Floor as a fraction of the original target (0..1)

   //--- v2: ACTIVE MANAGEMENT --------------------------------------
   bool   enable_partial_harvest;    // Allow banking profitable legs to cut exposure
   double harvest_min_leg_profit_ccy;// A leg must be at least this profitable to harvest
   double trail_activate_fraction;   // Arm basket trailing at this fraction of the target
   double trail_giveback_fraction;   // Close if basket gives back this fraction of peak profit

   //--- v2: CAPITAL-AWARE AUTO-SIZING ------------------------------
   double exposure_lots_per_1k;      // Target basket exposure density (lots per $1000 equity)
   double recommended_min_equity;    // Below this, the EA warns the preset is over-sized
  };

//+------------------------------------------------------------------+
//| CConfig                                                          |
//|   Returns the tuned PresetProfile for a given ENUM_ACCOUNT_PRESET.|
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
         case PRESET_NANO:       FillNano(p);       break;
         case PRESET_MICRO:      FillMicro(p);      break;
         case PRESET_MEDIUM:     FillMedium(p);     break;
         case PRESET_LARGE:      FillLarge(p);      break;
         case PRESET_BIGLEVEL:   FillBigLevel(p);   break;
         case PRESET_COMMERCIAL: FillCommercial(p); break;
         default:                FillNano(p);       break; // safest fallback
        }
      return(p);
     }

   //--- Human-readable name for logging.
   string            PresetName(const ENUM_ACCOUNT_PRESET preset) const
     {
      switch(preset)
        {
         case PRESET_NANO:       return("NANO");
         case PRESET_MICRO:      return("MICRO");
         case PRESET_MEDIUM:     return("MEDIUM");
         case PRESET_LARGE:      return("LARGE");
         case PRESET_BIGLEVEL:   return("BIGLEVEL");
         case PRESET_COMMERCIAL: return("COMMERCIAL");
         default:                return("UNKNOWN");
        }
     }

private:
   //--- Shared v2 active-management defaults. Individual presets
   //    override what they need after calling this.
   void              FillCommonV2(PresetProfile &p) const
     {
      p.enable_basket_stop         = true;
      p.tp_decay_start_hours       = 12.0;
      p.tp_decay_full_hours        = 96.0;   // 4 days -> target at its floor
      p.tp_decay_floor_fraction    = 0.15;   // decays to 15% of the original target
      p.enable_partial_harvest     = true;
      p.harvest_min_leg_profit_ccy = 0.50;
      p.trail_activate_fraction    = 0.70;   // arm trailing at 70% of target
      p.trail_giveback_fraction    = 0.35;   // close if 35% of peak profit is given back
      p.exposure_lots_per_1k       = 0.02;   // ~0.02 lots per $1000 equity
     }

   //--- PRESET_NANO : ~$500-1500. FLAT lots, no martingale at all.
   //    This is the preset for the $1000 account that v1 destroyed.
   void              FillNano(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.01;
      p.max_grid_levels           = 3;
      p.risk_percent_per_trade    = 0.15;
      p.lot_progression_factor    = 1.00;   // FLAT: every level the same size
      p.max_lot_cap               = 0.01;
      p.max_basket_exposure_lots  = 0.03;   // ~$3 per $1 gold move, total
      p.atr_spacing_multiplier    = 2.00;   // wide spacing -> fewer levels trigger
      p.max_drawdown_percent      = 15.0;
      p.margin_level_floor_percent= 600.0;
      p.min_free_margin_currency  = 10.0;
      p.basket_stop_loss_percent  = 8.0;    // cut a bad basket early
      p.tp_decay_start_hours      = 8.0;    // escape stuck baskets sooner
      p.tp_decay_full_hours       = 48.0;
      p.harvest_min_leg_profit_ccy= 0.30;
      p.exposure_lots_per_1k      = 0.03;
      p.recommended_min_equity    = 500.0;
     }

   //--- PRESET_MICRO : ~$1500-5000 (retuned; v1 value blew up $1000)
   void              FillMicro(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.01;
      p.max_grid_levels           = 4;
      p.risk_percent_per_trade    = 0.20;
      p.lot_progression_factor    = 1.15;   // very gentle
      p.max_lot_cap               = 0.02;
      p.max_basket_exposure_lots  = 0.06;
      p.atr_spacing_multiplier    = 1.80;
      p.max_drawdown_percent      = 18.0;
      p.margin_level_floor_percent= 500.0;
      p.min_free_margin_currency  = 20.0;
      p.basket_stop_loss_percent  = 10.0;
      p.recommended_min_equity    = 1500.0;
     }

   //--- PRESET_MEDIUM : ~$5k-15k
   void              FillMedium(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.02;
      p.max_grid_levels           = 5;
      p.risk_percent_per_trade    = 0.25;
      p.lot_progression_factor    = 1.20;
      p.max_lot_cap               = 0.05;
      p.max_basket_exposure_lots  = 0.20;
      p.atr_spacing_multiplier    = 1.60;
      p.max_drawdown_percent      = 20.0;
      p.margin_level_floor_percent= 450.0;
      p.min_free_margin_currency  = 100.0;
      p.basket_stop_loss_percent  = 10.0;
      p.recommended_min_equity    = 5000.0;
     }

   //--- PRESET_LARGE : ~$15k-50k
   void              FillLarge(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.05;
      p.max_grid_levels           = 6;
      p.risk_percent_per_trade    = 0.30;
      p.lot_progression_factor    = 1.25;
      p.max_lot_cap               = 0.15;
      p.max_basket_exposure_lots  = 0.60;
      p.atr_spacing_multiplier    = 1.50;
      p.max_drawdown_percent      = 22.0;
      p.margin_level_floor_percent= 400.0;
      p.min_free_margin_currency  = 300.0;
      p.basket_stop_loss_percent  = 12.0;
      p.recommended_min_equity    = 15000.0;
     }

   //--- PRESET_BIGLEVEL : ~$50k-150k, aggressive but still bounded
   void              FillBigLevel(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.10;
      p.max_grid_levels           = 7;
      p.risk_percent_per_trade    = 0.35;
      p.lot_progression_factor    = 1.30;
      p.max_lot_cap               = 0.40;
      p.max_basket_exposure_lots  = 1.80;
      p.atr_spacing_multiplier    = 1.40;
      p.max_drawdown_percent      = 25.0;
      p.margin_level_floor_percent= 350.0;
      p.min_free_margin_currency  = 1000.0;
      p.basket_stop_loss_percent  = 12.0;
      p.recommended_min_equity    = 50000.0;
     }

   //--- PRESET_COMMERCIAL : ~$150k+, largest capital, bounded exposure
   void              FillCommercial(PresetProfile &p) const
     {
      FillCommonV2(p);
      p.base_lot                  = 0.25;
      p.max_grid_levels           = 8;
      p.risk_percent_per_trade    = 0.40;
      p.lot_progression_factor    = 1.30;
      p.max_lot_cap               = 1.00;
      p.max_basket_exposure_lots  = 5.00;
      p.atr_spacing_multiplier    = 1.35;
      p.max_drawdown_percent      = 28.0;
      p.margin_level_floor_percent= 300.0;
      p.min_free_margin_currency  = 3000.0;
      p.basket_stop_loss_percent  = 15.0;
      p.recommended_min_equity    = 150000.0;
     }
  };

#endif // ADAPTIVEGRID_CONFIG_MQH
//+------------------------------------------------------------------+
