//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|            Adaptive Gold Grid EA - Leveled logging utility        |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Dependency-free logger so every module can include it without  |
//|   creating circular includes. Supports ERROR/WARN/INFO/DEBUG     |
//|   with a configurable minimum level, timestamped Print() output, |
//|   and optional append-mode file logging via FileWrite.           |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_LOGGER_MQH
#define ADAPTIVEGRID_LOGGER_MQH

//+------------------------------------------------------------------+
//| Log severity levels (ordered least -> most verbose).             |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
  {
   LOG_ERROR = 0,   // Only critical failures
   LOG_WARN  = 1,   // Warnings + errors
   LOG_INFO  = 2,   // General operational info (default)
   LOG_DEBUG = 3    // Verbose diagnostic detail
  };

//+------------------------------------------------------------------+
//| CLogger                                                          |
//+------------------------------------------------------------------+
class CLogger
  {
private:
   ENUM_LOG_LEVEL    m_min_level;     // Messages below this level are suppressed
   bool              m_file_enabled;  // If true, also append to a log file
   string            m_file_name;     // Log file name (under MQL5/Files)
   string            m_prefix;        // Tag prepended to every line (e.g. EA name)

   //--- Map a level to its short text label.
   string            LevelText(const ENUM_LOG_LEVEL level) const
     {
      switch(level)
        {
         case LOG_ERROR: return("ERROR");
         case LOG_WARN:  return("WARN");
         case LOG_INFO:  return("INFO");
         case LOG_DEBUG: return("DEBUG");
         default:        return("LOG");
        }
     }

   //--- Build a timestamped, tagged line.
   string            Format(const ENUM_LOG_LEVEL level,const string msg) const
     {
      string ts = TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
      return(StringFormat("[%s] [%s] %s%s",ts,LevelText(level),
                          (m_prefix=="" ? "" : m_prefix+" "),msg));
     }

   //--- Append one line to the log file (best-effort, never throws).
   void              WriteToFile(const string line)
     {
      if(!m_file_enabled || m_file_name=="")
         return;
      int h = FileOpen(m_file_name,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE)
         return;
      FileSeek(h,0,SEEK_END);   // append mode
      FileWrite(h,line);
      FileClose(h);
     }

   //--- Core dispatch: filter by level, Print(), optionally file.
   void              Emit(const ENUM_LOG_LEVEL level,const string msg)
     {
      if(level>m_min_level)
         return;               // below configured verbosity -> suppress
      string line = Format(level,msg);
      Print(line);
      WriteToFile(line);
     }

public:
                     CLogger(void)
     {
      m_min_level    = LOG_INFO;
      m_file_enabled = false;
      m_file_name    = "";
      m_prefix       = "AdaptiveGoldGrid";
     }
                    ~CLogger(void) {}

   //--- Configuration -----------------------------------------------
   void              SetMinLevel(const ENUM_LOG_LEVEL level) { m_min_level = level; }
   ENUM_LOG_LEVEL    MinLevel(void) const                    { return(m_min_level); }
   void              SetPrefix(const string prefix)          { m_prefix = prefix; }

   //--- Enable/disable file logging. Pass an empty name to disable.
   void              EnableFile(const string file_name)
     {
      m_file_name    = file_name;
      m_file_enabled = (file_name!="");
     }
   void              DisableFile(void) { m_file_enabled = false; }

   //--- Level shortcuts ---------------------------------------------
   void              Error(const string msg) { Emit(LOG_ERROR,msg); }
   void              Warn (const string msg) { Emit(LOG_WARN ,msg); }
   void              Info (const string msg) { Emit(LOG_INFO ,msg); }
   void              Debug(const string msg) { Emit(LOG_DEBUG,msg); }
  };

#endif // ADAPTIVEGRID_LOGGER_MQH
//+------------------------------------------------------------------+
