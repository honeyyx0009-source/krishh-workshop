//+------------------------------------------------------------------+
//|                                                       MLHook.mqh |
//|   Adaptive Gold Grid EA - OPTIONAL Phase-2 ONNX inference hook.   |
//+------------------------------------------------------------------+
//| ===============  READ THIS BEFORE ENABLING ANYTHING  =========== |
//|                                                                  |
//|   This module is OPTIONAL and DISABLED BY DEFAULT. When it is     |
//|   off (the shipped default), the EA runs the classical Phase-1    |
//|   logic completely unchanged - this file adds nothing to the      |
//|   decision path. Turn it on only after you have supplied and      |
//|   validated your own .onnx model.                                 |
//|                                                                  |
//|   WHAT MQL5 CAN AND CANNOT DO (HONEST STATEMENT):                 |
//|     * MQL5 CANNOT train an LSTM / CNN / GRU / any neural network. |
//|       There is no training runtime in the terminal. Training must |
//|       happen OUTSIDE MT5 (e.g. Python + PyTorch/TensorFlow) and   |
//|       be exported to the ONNX format by YOU, the user.            |
//|     * MQL5 CAN only run INFERENCE on an already-trained .onnx     |
//|       model through the built-in ONNX API:                        |
//|           OnnxCreate()  -> load the model from MQL5/Files         |
//|           OnnxRun()     -> forward pass on an input tensor        |
//|           OnnxRelease() -> free the model handle                  |
//|       That is the ONLY thing this hook does. Nothing here trains, |
//|       fine-tunes, or "learns" during trading.                     |
//|                                                                  |
//|   HONEST LABELLING RULE (NON-NEGOTIABLE):                         |
//|     The classical indicators in MarketAnalysis.mqh (RSI, MACD,    |
//|     ATR, moving averages, price-action S/R) are ORDINARY          |
//|     deterministic math. They are NOT machine learning and their   |
//|     output must NEVER be relabelled, wrapped, or presented as     |
//|     "ML confidence" / "AI prediction". A genuine ML signal comes  |
//|     ONLY from OnnxRun() on a real user-trained model. If no model |
//|     is loaded, this hook reports NEUTRAL ("no opinion") - it does |
//|     not fabricate a confidence value out of the classical signal. |
//|                                                                  |
//|   AUTHORITY LIMIT (NON-NEGOTIABLE):                               |
//|     Even when enabled and loaded, this hook may only BIAS or      |
//|     CONFIRM a classical entry. It can NEVER open, modify, or      |
//|     close an order itself, and it can NEVER bypass the            |
//|     SafetyValve gate. The SafetyValve remains the sole authority  |
//|     over whether new exposure is allowed.                         |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_MLHOOK_MQH
#define ADAPTIVEGRID_MLHOOK_MQH

#include "Logger.mqh"
#include "MarketAnalysis.mqh"   // MarketContext (the inference input source)

//+------------------------------------------------------------------+
//| ML directional opinion.                                          |
//|   NEUTRAL is the safe default returned whenever ML is disabled,   |
//|   no model is loaded, or inference is not yet implemented. When   |
//|   the opinion is NEUTRAL the classical Phase-1 logic decides.     |
//+------------------------------------------------------------------+
enum ENUM_ML_OPINION
  {
   ML_NEUTRAL = 0,   // "No opinion" -> defer entirely to classical logic
   ML_BULLISH,       // Model leans long (may CONFIRM a classical BUY seed)
   ML_BEARISH        // Model leans short (may CONFIRM a classical SELL seed)
  };

//+------------------------------------------------------------------+
//| MLPrediction                                                     |
//|   The read-out consumed by the main EA. It is advisory only.     |
//+------------------------------------------------------------------+
struct MLPrediction
  {
   bool            active;      // false => ML off / no model / not ready => IGNORE this struct
   ENUM_ML_OPINION opinion;     // Directional lean (NEUTRAL when not active)
   double          confidence;  // 0..1 GENUINE model confidence. 0.0 when not active.
                                // NOTE: never populated from classical indicators.
  };

//+------------------------------------------------------------------+
//| CMLHook                                                          |
//|   Thin, self-contained wrapper around the MQL5 ONNX inference     |
//|   API. Safe to construct and even to Init() with ML disabled -    |
//|   in that state every call returns a NEUTRAL/ inactive result.    |
//+------------------------------------------------------------------+
class CMLHook
  {
private:
   CLogger        *m_log;          // Optional logger (may be NULL)
   bool            m_enabled;      // Master toggle (from EA input EnableOnnxML)
   bool            m_loaded;       // true only after a model handle was created
   long            m_handle;       // ONNX model handle (INVALID_HANDLE until loaded)
   string          m_model_file;   // .onnx file name under MQL5/Files (user-supplied)

   void            LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m);  }
   void            LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m);  }
   void            LogErr(const string m)  { if(m_log!=NULL) m_log.Error(m); }
   void            LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //--- Build a NEUTRAL / inactive prediction (the safe default path).
   MLPrediction    Neutral(void) const
     {
      MLPrediction r;
      r.active     = false;
      r.opinion    = ML_NEUTRAL;
      r.confidence = 0.0;   // deliberately 0 - we do NOT borrow classical signal here
      return(r);
     }

public:
                   CMLHook(void)
     {
      m_log        = NULL;
      m_enabled    = false;
      m_loaded     = false;
      m_handle     = INVALID_HANDLE;
      m_model_file = "";
     }
                  ~CMLHook(void) { Release(); }

   bool            IsEnabled(void) const { return(m_enabled); }
   bool            IsLoaded(void)  const { return(m_loaded);  }
   bool            IsActive(void)  const { return(m_enabled && m_loaded); }

   //================================================================//
   //  INIT                                                          //
   //  Call once from OnInit with the EA inputs. If `enable` is false //
   //  we do NOTHING (no model load) and every Predict() returns      //
   //  NEUTRAL, so the classical EA behaves exactly as before.        //
   //  Returns true when the hook is in a valid state, which INCLUDES //
   //  the "cleanly disabled" state - a disabled hook is not a error. //
   //================================================================//
   bool            Init(const bool enable,const string model_file,CLogger *logger=NULL)
     {
      m_log        = logger;
      m_enabled    = enable;
      m_model_file = model_file;
      m_loaded     = false;
      m_handle     = INVALID_HANDLE;

      if(!m_enabled)
        {
         LogInfo("MLHook: ONNX inference DISABLED (default). Classical Phase-1 logic runs unchanged.");
         return(true);   // disabled is a valid, expected state
        }

      LogWarn("MLHook: ONNX inference ENABLED. This is an optional Phase-2 feature; "
              "it can only bias/confirm classical entries and can NEVER bypass the SafetyValve.");

      if(m_model_file=="")
        {
         LogWarn("MLHook: EnableOnnxML=true but OnnxModelFile is empty. Running NEUTRAL (no model). "
                 "Provide a trained .onnx file under MQL5/Files to activate inference.");
         return(true);   // stay neutral rather than failing init
        }

      //--- Attempt to load the user-supplied model from MQL5/Files.
      //    ONNX_DEFAULT keeps the terminal's default execution options.
      m_handle = OnnxCreate(m_model_file,ONNX_DEFAULT);
      if(m_handle==INVALID_HANDLE)
        {
         LogErr(StringFormat("MLHook: OnnxCreate failed for '%s' (err=%d). Falling back to NEUTRAL; "
                             "classical logic is unaffected.",m_model_file,GetLastError()));
         return(true);   // never let a bad model break the classical EA
        }

      // TODO(Phase-2): declare the model's input/output tensor SHAPES here via
      //   OnnxSetInputShape() / OnnxSetOutputShape(). The correct dimensions
      //   depend on how YOU exported the model (e.g. [1, lookback, n_features]).
      //   Until the shapes and Run() below are implemented, keep m_loaded=false
      //   so Predict() stays NEUTRAL and the EA runs classically.

      // NOTE: we intentionally leave m_loaded=false until the Phase-2 tensor
      //       plumbing (shaping + normalization + OnnxRun parsing) is finished.
      //       A loaded handle alone is NOT enough to produce a trustworthy signal.
      LogWarn("MLHook: model handle created but Phase-2 inference plumbing is not implemented yet "
              "(see TODO markers). Staying NEUTRAL so classical logic decides.");
      return(true);
     }

   //================================================================//
   //  PREDICT                                                       //
   //  Advisory ONLY. Returns NEUTRAL/inactive whenever ML is         //
   //  disabled, no model is loaded, or the Phase-2 plumbing is not   //
   //  yet implemented - which guarantees the classical Phase-1 logic //
   //  runs unchanged in the shipped default configuration.           //
   //================================================================//
   MLPrediction    Predict(const MarketContext &mc)
     {
      //--- Fast neutral exits (the shipped default path).
      if(!m_enabled)         return(Neutral());   // ML off -> defer to classical
      if(!m_loaded)          return(Neutral());   // no usable model -> defer to classical
      if(m_handle==INVALID_HANDLE) return(Neutral());

      // ----------------------------------------------------------------
      // TODO(Phase-2): real inference. NOT implemented on purpose.
      //   1. INPUT TENSOR SHAPING: assemble the feature window the model
      //      was trained on (e.g. a rolling sequence of OHLC / ATR / RSI /
      //      MACD values) into the exact shape the .onnx expects.
      //   2. NORMALIZATION: apply the SAME scaling/standardisation used at
      //      training time (store mean/std or min/max alongside the model).
      //      Mismatched normalization silently ruins predictions.
      //   3. RUN:   float in_tensor[]; ... ; OnnxRun(m_handle,ONNX_DEFAULT,
      //             in_tensor,out_tensor);
      //   4. PARSE: map out_tensor -> ENUM_ML_OPINION + a GENUINE confidence
      //             in [0,1]. Do NOT synthesise confidence from `mc` (the
      //             classical context) - that would be mislabelling classical
      //             signals as ML, which is explicitly forbidden.
      // Until all four steps exist, we return NEUTRAL so nothing changes.
      // The `mc` parameter is intentionally unused until Phase-2 uses the
      // context for input-tensor shaping; it stays in the signature as it
      // is part of the public API.
      // ----------------------------------------------------------------
      return(Neutral());
     }

   //================================================================//
   //  RELEASE : free the ONNX handle. Safe to call repeatedly.      //
   //================================================================//
   void            Release(void)
     {
      if(m_handle!=INVALID_HANDLE)
        {
         OnnxRelease(m_handle);
         m_handle = INVALID_HANDLE;
        }
      m_loaded = false;
     }
  };

#endif // ADAPTIVEGRID_MLHOOK_MQH
//+------------------------------------------------------------------+
