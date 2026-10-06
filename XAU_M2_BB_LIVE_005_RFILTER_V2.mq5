//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_005_RFILTER_V2.mq5                                |
//| Generalized to a Timeframe input (default PERIOD_M2, unchanged    |
//| behavior) so the same engine can run on other timeframes -- see   |
//| the M1/M3 sibling files (XAU_M1_BB_LIVE_005_RFILTER_V2.mq5 /       |
//| XAU_M3_BB_LIVE_005_RFILTER_V2.mq5), each just a copy with a        |
//| different Timeframe default and Magic Number. All ground-truth     |
//| numbers below are M2-specific; M1/M3 are UNTESTED.                 |
//| V2: added LatestSignalOnly -- when true, a new BB-breakout signal |
//| candle discards ANY still-pending earlier setup(s) instead of     |
//| letting them keep waiting alongside it. Default false reproduces  |
//| V1 exactly (multiple concurrent pending setups allowed).          |
//| CONFIRMED defaults (ground-truth MT5 tick backtest, 2025.01-      |
//| 2026.09, M2, Lots=0.1): InitialSL_R=3.5 (was stale 2.0),          |
//| MinR_Points=200 (was stale 0), LatestSignalOnly=true -- NET       |
//| $28,172.55, PF 1.61, Recovery Factor 9.80, WR 90.46% (2664W/      |
//| 281L, 2945 trades, BUY-only), MaxDD 1.07%/2.72%. Avg win +$27.92  |
//| vs avg loss -$148.70 (wide-SL/narrow-lock asymmetry, offset by    |
//| the high win rate). Supersedes the earlier InitialSL_R=2.0/       |
//| MinR_Points=0 result (NET $16,281, ported into 007/001_STOCH_v2's |
//| own LatestSignalOnly finding) which is now stale.                 |
//| SkipEntryHourKST (CONFIRMED default=true): a KST hour-of-day       |
//| breakdown of the confirmed-default backtest above found the        |
//| 20-22 KST window is the weakest of twelve 2-hour buckets -- WR     |
//| 86.3% (vs 90.46% overall) and lowest $/trade (n=291, NET only      |
//| $620.20), sitting right at the Europe/US session handoff. The      |
//| very next bucket (22-24 KST) is the STRONGEST (WR 92.2%, NET       |
//| $8,069.30), so this is a narrow dip, not a broader session         |
//| weakness. Blocks new entries while the KST hour is in              |
//| [SkipHourStartKST,SkipHourEndKST). Ground-truth backtest (same     |
//| period, Lock_R=0.30) confirmed: 2945->2657 trades (-288, the       |
//| 20-22 KST bucket removed), NET $28,172.55->$28,329.75 (~flat),     |
//| PF 1.610->1.709, WR 90.46%->90.97%, MaxDD 1.07%/2.72%->1.28%/      |
//| 2.71% -- fewer trades at the same NET with better PF/WR, so the    |
//| removed bucket was low-quality. Lock_R was also raised 0.25->0.30  |
//| in that same test (see Lock_R), so this isn't a fully isolated     |
//| A/B, but the direction is corroborated by the original hour        |
//| breakdown.                                                          |
//| BODY/WICK touch tag (diagnostic, UNTESTED, no trading effect): the    |
//| signal condition only requires the candle's high/low to reach the    |
//| bands (h>=up20/up4 or l<=lo20/lo4) -- this additionally tags whether  |
//| the CLOSE also broke the band ("BODY") or only wicked through and    |
//| closed back inside ("WICK"), appended to every live order's tag.     |
//| Mirrors the same distinction already confirmed as a real edge in the |
//| 001_STOCH family (SkipFadeBearOSWickTouch) -- never checked here     |
//| before. Needs its own backtest to see if the same pattern holds.     |
//| _P5S/_P5D tag suffix (diagnostic, UNTESTED, no trading effect):      |
//| checks the 5 candles immediately BEFORE the signal candle (shifts    |
//| 2-6) -- _P5S ("prior 5 same") when all 5 ran in the same direction   |
//| as the signal candle's own breakout; _P5D otherwise. Since 005       |
//| always fades the signal (AllowShort=false means every live trade is  |
//| a BUY after a bear/down signal candle), this directly tests whether  |
//| a longer one-way run into the signal candle (5 straight down         |
//| candles before the fade) predicts the BUY's outcome. No backtest     |
//| yet -- needs one to read the tag crosstab.                           |
//| ---- inherited from 005_RFILTER_V1.mq5 ----                       |
//| R-filter variant of 005_BUYONLY, built for symbols (e.g. NAS100+) |
//| where the unfiltered signal has a losing edge (gross PF<1) but a  |
//| large right-skewed R distribution -- same idea that turned MA120  |
//| V12 from PF 0.88 to PF 1.18 on NAS100 by keeping only the biggest  |
//| R (=M2 signal candle body) setups. Adds MinR_Points: skip signals  |
//| whose R is below this threshold. MinR_Points=0 reproduces          |
//| 005_BUYONLY exactly.                                                |
//| ---- inherited from 005_FINAL_BUYONLY.mq5 ----                     |
//| BUY-ONLY variant of 005 (AllowShort=false by default).          |
//| Real MT5 tick backtest (2025.01-2026.09): SELL trades alone were |
//| net -$540.86 vs BUY alone net +$1,697.03. Disabling SELL turns   |
//| the EA's 21-month result from +$1,156.17 to +$1,697.03. Re-enable|
//| SELL via the AllowShort input if you want the original behavior. |
//| M2 Dual-BB -> +0.95R extension -> 0.10R pullback -> countertrend |
//| LIVE FORWARD TEST EA | own-Magic MAX1                             |
//| NOTE: at 0.01 lot, 30% partial close is impossible on 0.01 step.  |
//| At TP1 this EA moves the whole position SL to +0.25R.             |
//| zoneDistATR diagnostic (ported from 001_STOCH_v2, UNTESTED here): |
//| logs the distance (in ATR units) from the ACTUAL ENTRY FILL price |
//| (not the signal candle, since this EA's entry can fire up to      |
//| MaxExtensionHours+MaxPullbackHours after the signal) to the        |
//| nearest enabled 매물대 zone (Asia/NY opening-hour boxes, today/     |
//| previous-day high-low, previous-NY-session high-low). Diagnostic   |
//| only -- does NOT block or alter any entry. Logged on every trade   |
//| close: MANAGED_EXIT (EnableLiveOrders=true, the real/managed       |
//| position -- this is the path actual backtests use since this EA's  |
//| .set ships with EnableLiveOrders=true) or VIRTUAL_EXIT_* (dry-run   |
//| virtual simulation). Per the lesson learned on 001: do NOT turn     |
//| this into an active filter until a bucketed analysis of logged      |
//| zoneDistATR vs outcome shows a robust, replicating relationship --  |
//| 001's first such attempt looked clean on a settings-drifted log     |
//| and did NOT replicate once corrected.                               |
//|                                                                     |
//| ProtectTriggerR/ProtectR/UseProtectStop (ported from 001_STOCH_v2,  |
//| UNTESTED here, default UseProtectStop=false): this EA already has  |
//| a profit-lock stage at TP1_R=0.50 (moves SL to Lock_R=0.30) -- this |
//| adds an EARLIER, smaller lock before that: once favorable R hits   |
//| ProtectTriggerR (0.25), move SL to a small locked profit (ProtectR,|
//| 0.05) rather than leaving the original InitialSL_R stop in place.  |
//| Only takes effect if TP1 hasn't already fired (TP1's own Lock_R    |
//| move supersedes it). Needs its own backtest before any verdict.    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M2; // signal-candle timeframe
input double Lots                 = 0.1; // Lot size
input double ExtensionR           = 0.95; // Extension (R) before pullback watch starts
input double PullbackR            = 0.10; // Pullback (R) from extension extreme to trigger entry
input double InitialSL_R          = 3.5; // Initial stop loss (R) (CONFIRMED, see header)
input double TP1_R                = 0.50; // Partial/lock trigger (R)
input double Lock_R               = 0.30; // Lock SL level (R) (CONFIRMED, see header)
input double TP2_R                = 0.90; // Final target (R)
input double MinR_Points          = 200; // Min signal-candle body (points) to trade, 0=no filter (CONFIRMED, see header)
input bool   LatestSignalOnly     = true; // New signal cancels older pending setups (CONFIRMED, see header)
input int    MaxExtensionHours    = 72; // Max hours waiting for extension
input int    MaxPullbackHours     = 72; // Max hours waiting for pullback
input int    MaxVirtualExitHours  = 168; // Max hours holding a position
input ulong  MagicNumber          = 95012101; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders
input bool   AllowShort           = false; // Allow SELL entries (default BUY-only, see header)
input int    SkipHourStartKST     = 20; // KST hour skip window start (see header, SkipEntryHourKST)
input int    SkipHourEndKST       = 22; // KST hour skip window end, exclusive (see header, SkipEntryHourKST)
input bool   SkipEntryHourKST     = true; // Block entries in [SkipHourStartKST,SkipHourEndKST) KST (CONFIRMED, see header)
input bool   UseFridayNarrowWindow = false; // On Friday, only allow entries 10:30-15:00 KST (ported from 001 M2_v2 where CONFIRMED; REJECTED here, see header)

input double ProtectTriggerR      = 0.25; // Favorable R to arm an early protect-lock stop, before TP1 (ported from 001_STOCH_v2, UNTESTED here)
input double ProtectR             = 0.05; // SL level once armed, in R (ported from 001_STOCH_v2, UNTESTED here)
input bool   UseProtectStop       = false; // Move SL to ProtectR once armed, before TP1/Lock fires (ported from 001_STOCH_v2, UNTESTED here)

// -- 매물대 (supply/demand zone) diagnostic (ported from 001 M2_v2): logs
//    zoneDistATR (distance from the actual entry fill to the nearest
//    enabled zone level, in ATR units) on every trade close. Diagnostic
//    ONLY -- does not block or alter any entry. Bucket zoneDistATR against
//    outcome before considering an active filter (see 001's header for why
//    gating on an untested hypothesis was wrong there).
input int    ATRPeriod             = 14; // ATR period used for zoneDistATR (does not affect SL/TP, those are R-based)
input bool   UseAsiaBoxZone        = true; // Include the Asia-session opening-hour candle's high/low
input int    AsiaOpenHourKST       = 8; // KST hour (integer) the Asia session opening candle starts
input bool   UseNYBoxZone          = true; // Include the NY/US-session opening-hour candle's high/low
input double NYOpenHourKST         = 22.5; // KST hour (decimal) the NY session opening candle starts
input bool   UseTodayHighLowZone   = true; // Include today's running high/low (so far, KST calendar day)
input bool   UsePrevDayHighLowZone = true; // Include the previous KST calendar day's high/low
input bool   UsePrevNYHighLowZone  = true; // Include the previous day's NY-session-window high/low (미국장 전일 고가저가)
input double NYSessionStartHourKST = 20.0; // KST hour (decimal) the NY session window starts, for 전일 미장 고가/저가 tracking (wraps past midnight)
input double NYSessionEndHourKST   = 6.0; // KST hour (decimal) the NY session window ends

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hATR_Sig=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

// -- supply-zone state (all in KST calendar-day terms), ported from 001 M2_v2 --
int    g_szLastDay=-1;          // KST day index of the last processed bar, -1=uninitialized
bool   g_szAsiaBoxSet=false;    // today's Asia open-hour box already captured
double g_szAsiaHigh=0, g_szAsiaLow=0;
bool   g_szNYBoxSet=false;      // today's NY open-hour box already captured
double g_szNYHigh=0, g_szNYLow=0;
double g_szTodayHigh=0, g_szTodayLow=0;
double g_szPrevDayHigh=0, g_szPrevDayLow=0;
bool   g_szHavePrevDay=false;
double g_szNYSessHigh=0, g_szNYSessLow=0;     // running NY-session-window high/low (in progress)
double g_szPrevNYHigh=0, g_szPrevNYLow=0;     // finalized previous NY-session-window high/low
bool   g_szHavePrevNY=false;
bool   g_szInNYSessPrevBar=false;             // was the previously processed bar inside the NY session window

double g_entryZoneDistATR=999.0; // zoneDistATR at the actual entry fill of the currently open trade (live or virtual)

struct Setup {
   datetime signal_time,close_time,extension_time;
   int sigdir;              // +1 bull signal, -1 bear signal
   double R,close_price,target,extreme;
   bool extension_hit;
   bool bodyTouch;          // diagnostic: did the signal candle's CLOSE also break the band, or only the high/low (see header)
   bool prior5Same;         // diagnostic: were the 5 candles before the signal candle all in the signal's own direction (see header)
};
Setup setups[];

bool managed=false;
ulong managed_ticket=0;
int managed_dir=0;          // +1 BUY, -1 SELL
double managed_R=0,managed_entry=0,managed_sl=0,managed_tp1=0,managed_lock=0,managed_tp2=0;
bool tp1_reached=false;
bool protect_reached=false; // UseProtectStop: SL already moved to the early protect-lock level

// DRY/tester virtual position: reproduces research MAX1 without sending orders.
bool v_open=false,v_tp1=false;
int v_dir=0;
double v_R=0,v_entry=0,v_sl=0,v_tp1px=0,v_lock=0,v_tp2=0;
datetime v_entry_time=0;
int v_entries=0,v_sl_n=0,v_lock_n=0,v_tp_n=0,v_timeout_n=0;
double v_totalR=0;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

string TFPrefix()
{
   switch(Timeframe)
   {
      case PERIOD_M1: return "M1_";
      case PERIOD_M2: return "M2_";
      case PERIOD_M3: return "M3_";
      case PERIOD_M4: return "M4_";
      case PERIOD_M5: return "M5_";
      default: return EnumToString(Timeframe)+"_";
   }
}

datetime LastSundayOfMonth(int year,int month,int daysInMonth)
{
   MqlDateTime dt; dt.year=year; dt.mon=month; dt.day=daysInMonth;
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime d=StructToTime(dt);
   MqlDateTime cur; TimeToStruct(d,cur);
   d-=cur.day_of_week*86400; // day_of_week: 0=Sunday
   return d;
}

bool IsEUDST(datetime server_now)
{
   MqlDateTime t; TimeToStruct(server_now,t);
   datetime dstStart=LastSundayOfMonth(t.year,3,31);
   datetime dstEnd  =LastSundayOfMonth(t.year,10,31);
   return (server_now>=dstStart && server_now<dstEnd);
}

int KST_Hour(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   return t.hour;
}

bool InSkipHourKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=SkipHourStartKST && h<SkipHourEndKST);
}

// -- Friday narrow-window filter, ported from XAU_M2_BB_LIVE_001_STOCH_v2
//    (CONFIRMED there: NET +10.6% vs baseline, +$202.40 vs an all-day
//    Friday block, same WR/MaxDD, on the 001 M2 signal). Only allow entries
//    in 10:30-15:00 KST on Friday; every other day is unaffected. REJECTED
//    on this extension/pullback signal: ground-truth backtest against this
//    file's own baseline (NET $27,814.55, WR 90.77%, PF 1.667, MaxDD
//    $1,359.10, n=2,740) gave NET $23,543.79 (-15.4%), WR 90.59%, PF
//    1.665, MaxDD $1,440.36 (+6.0%, WORSE), n=2,328 -- worse on every
//    metric. Doesn't generalize from 001 M2's BB-breakout signal to this
//    extension/pullback entry. ------------------------------------------
bool IsFridayKST(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   return (t.day_of_week==5); // MQL5 day_of_week: 0=Sunday
}

bool InFridayNarrowAllowedWindowKST(datetime server_now)
{
   if(!IsFridayKST(server_now)) return true;
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;
   return (minOfDay>=630 && minOfDay<900); // 10:30-15:00
}

// -- 매물대 (supply/demand zone) tracking, ported verbatim from 001 M2_v2 --
int KSTDayIndex(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   datetime kst=server_now+offsetHours*3600;
   return (int)(kst/86400);
}

bool InWindowKST(int minOfDay,double startHour,double endHour)
{
   int start=(int)MathRound(startHour*60);
   int end=(int)MathRound(endHour*60);
   if(start<=end) return (minOfDay>=start && minOfDay<end);
   return (minOfDay>=start || minOfDay<end); // wraps past midnight
}

// Called once per new signal-timeframe bar with that bar's own high/low --
// rolls today's running high/low into "previous day" at KST midnight,
// captures the Asia/NY session opening-hour boxes the first time each
// day's clock reaches them, and finalizes the previous NY-session-window
// high/low the moment that window closes.
void UpdateSupplyZones(datetime sig,double h,double l)
{
   int day=KSTDayIndex(sig);
   int hourKST=KST_Hour(sig);
   int offsetHours=IsEUDST(sig)?6:7;
   MqlDateTime t; TimeToStruct(sig+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;

   if(g_szLastDay<0)
   {
      g_szLastDay=day; g_szTodayHigh=h; g_szTodayLow=l;
      g_szAsiaBoxSet=false; g_szNYBoxSet=false;
   }
   else if(day!=g_szLastDay)
   {
      g_szPrevDayHigh=g_szTodayHigh; g_szPrevDayLow=g_szTodayLow; g_szHavePrevDay=true;
      g_szTodayHigh=h; g_szTodayLow=l;
      g_szAsiaBoxSet=false; g_szNYBoxSet=false;
      g_szLastDay=day;
   }
   else
   {
      if(h>g_szTodayHigh) g_szTodayHigh=h;
      if(l<g_szTodayLow)  g_szTodayLow=l;
   }

   if(!g_szAsiaBoxSet && hourKST==AsiaOpenHourKST)
   { g_szAsiaHigh=h; g_szAsiaLow=l; g_szAsiaBoxSet=true; }

   int nyOpenMin=(int)MathRound(NYOpenHourKST*60);
   if(!g_szNYBoxSet && minOfDay>=nyOpenMin && minOfDay<nyOpenMin+60)
   { g_szNYHigh=h; g_szNYLow=l; g_szNYBoxSet=true; }

   bool inNYSess=InWindowKST(minOfDay,NYSessionStartHourKST,NYSessionEndHourKST);
   if(inNYSess)
   {
      if(!g_szInNYSessPrevBar){ g_szNYSessHigh=h; g_szNYSessLow=l; }
      else { if(h>g_szNYSessHigh) g_szNYSessHigh=h; if(l<g_szNYSessLow) g_szNYSessLow=l; }
   }
   else if(g_szInNYSessPrevBar)
   {
      g_szPrevNYHigh=g_szNYSessHigh; g_szPrevNYLow=g_szNYSessLow; g_szHavePrevNY=true;
   }
   g_szInNYSessPrevBar=inNYSess;
}

// Distance from price to the NEAREST enabled zone level, in ATR units
// (999.0 = no enabled zone has a value yet).
double DistanceToNearestZone(double price,double atr)
{
   if(atr<=0) return 999.0;
   double best=999.0;

   if(UseAsiaBoxZone && g_szAsiaBoxSet)
   {
      best=MathMin(best,MathAbs(price-g_szAsiaHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szAsiaLow)/atr);
   }
   if(UseNYBoxZone && g_szNYBoxSet)
   {
      best=MathMin(best,MathAbs(price-g_szNYHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szNYLow)/atr);
   }
   if(UseTodayHighLowZone)
   {
      best=MathMin(best,MathAbs(price-g_szTodayHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szTodayLow)/atr);
   }
   if(UsePrevDayHighLowZone && g_szHavePrevDay)
   {
      best=MathMin(best,MathAbs(price-g_szPrevDayHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szPrevDayLow)/atr);
   }
   if(UsePrevNYHighLowZone && g_szHavePrevNY)
   {
      best=MathMin(best,MathAbs(price-g_szPrevNYHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szPrevNYLow)/atr);
   }
   return best;
}

// Looks up the realized profit (profit+swap+commission across all deals)
// for a position ticket that has already closed, via deal history.
double GetClosedPositionProfit(ulong posTicket)
{
   double profit=0;
   if(!HistorySelectByPosition(posTicket)) return profit;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong dt=HistoryDealGetTicket(i);
      if(dt==0) continue;
      profit+=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_SWAP)+HistoryDealGetDouble(dt,DEAL_COMMISSION);
   }
   return profit;
}

void Log(string event,string detail="")
{
   Print("LIVE005 RFILTER2 ",TFPrefix(),"| ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

void RemoveSetup(int idx)
{
   int n=ArraySize(setups);
   for(int j=idx;j<n-1;j++) setups[j]=setups[j+1];
   ArrayResize(setups,n-1);
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

bool HasOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      return true;
   }
   return false;
}

bool FindOurPosition()
{
   managed=false; managed_ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      managed=true; managed_ticket=tk;
      managed_entry=PositionGetDouble(POSITION_PRICE_OPEN);
      managed_sl=PositionGetDouble(POSITION_SL);
      managed_tp2=PositionGetDouble(POSITION_TP);
      long type=PositionGetInteger(POSITION_TYPE);
      managed_dir=(type==POSITION_TYPE_BUY ? +1 : -1);

      if(managed_tp2>0) managed_R=MathAbs(managed_tp2-managed_entry)/TP2_R;
      else if(managed_sl>0) managed_R=MathAbs(managed_sl-managed_entry)/InitialSL_R;
      else managed_R=0;

      if(managed_R>0)
      {
         managed_tp1=managed_entry+managed_dir*TP1_R*managed_R;
         managed_lock=managed_entry+managed_dir*Lock_R*managed_R;
         // If the current SL is already at/through the intended lock, preserve state after restart.
         double eps=2*_Point;
         tp1_reached=(managed_dir==+1 ? managed_sl>=managed_lock-eps
                                     : managed_sl<=managed_lock+eps && managed_sl>0);
         double managed_protect=managed_entry+managed_dir*ProtectR*managed_R;
         protect_reached=tp1_reached ||
            (managed_dir==+1 ? managed_sl>=managed_protect-eps
                             : managed_sl<=managed_protect+eps && managed_sl>0);
      }
      return true;
   }
   tp1_reached=false;
   protect_reached=false;
   return false;
}

bool SafeModifyPosition(ulong ticket,int dir,double desired_sl,double desired_tp,string context)
{
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log(context+"_FAIL","no tick"); return false; }
   double cushion=MinStopDistance()+_Point;
   double sl=desired_sl,tp=desired_tp;

   if(dir==+1) // BUY: SL below Bid, TP above Bid
   {
      if(sl>0 && sl>q.bid-cushion) sl=q.bid-cushion;
      if(tp>0 && tp<q.bid+cushion) tp=q.bid+cushion;
   }
   else // SELL: SL above Ask, TP below Ask
   {
      if(sl>0 && sl<q.ask+cushion) sl=q.ask+cushion;
      if(tp>0 && tp>q.ask-cushion) tp=q.ask-cushion;
   }

   sl=(sl>0?NormalizeDouble(sl,_Digits):0.0);
   tp=(tp>0?NormalizeDouble(tp,_Digits):0.0);
   if(trade.PositionModify(ticket,sl,tp)) return true;

   Log(context+"_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+
       trade.ResultRetcodeDescription()+" | bid="+DoubleToString(q.bid,_Digits)+
       " ask="+DoubleToString(q.ask,_Digits)+" sl="+DoubleToString(sl,_Digits)+
       " tp="+DoubleToString(tp,_Digits));
   return false;
}

void AddSignal(datetime sig,datetime close_time,int dir,double R,double c,bool bodyTouch,bool prior5Same)
{
   if(LatestSignalOnly && ArraySize(setups)>0)
   {
      Log("SIGNAL_SUPERSEDES","dropping "+IntegerToString(ArraySize(setups))+" pending setup(s) for newer signal");
      ArrayResize(setups,0);
   }
   int n=ArraySize(setups); ArrayResize(setups,n+1);
   setups[n].signal_time=sig;
   setups[n].close_time=close_time;
   setups[n].extension_time=0;
   setups[n].sigdir=dir;
   setups[n].R=R;
   setups[n].close_price=c;
   setups[n].target=c+dir*ExtensionR*R;
   setups[n].extreme=c;
   setups[n].extension_hit=false;
   setups[n].bodyTouch=bodyTouch;
   setups[n].prior5Same=prior5Same;
   Log("SIGNAL",(dir==1?"BULL":"BEAR")+" R="+DoubleToString(R,_Digits)+
       " ext="+DoubleToString(setups[n].target,_Digits)+" touch="+(bodyTouch?"BODY":"WICK")+
       " prior5Same="+(prior5Same?"true":"false"));
}

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0) return;

   UpdateSupplyZones(sig,h,l);

   double up20[1],lo20[1],up4[1],lo4[1];
   if(CopyBuffer(hBB20,1,1,1,up20)!=1 || CopyBuffer(hBB20,2,1,1,lo20)!=1 ||
      CopyBuffer(hBB4,1,1,1,up4)!=1   || CopyBuffer(hBB4,2,1,1,lo4)!=1) return;

   int dir=0;
   if(c>o && h>=up20[0] && h>=up4[0]) dir=+1;
   else if(c<o && l<=lo20[0] && l<=lo4[0]) dir=-1;
   if(dir==0) return;

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR) return;
   bool bodyTouch=(dir==+1)?(c>=up20[0]):(c<=lo20[0]);

   // Prior-5-candle-same-direction (diagnostic): were the 5 candles right
   // before the signal candle (shifts 2-6) ALL in the signal's own
   // direction (all bullish for dir=+1, all bearish for dir=-1)? Since 005
   // always fades the signal (dir=-1 signal -> BUY), this directly answers
   // the question for every one of 005's buy entries, not just a subset.
   bool prior5Same=true;
   for(int k=2;k<=6;k++)
   {
      double po=iOpen(_Symbol,Timeframe,k), pc=iClose(_Symbol,Timeframe,k);
      bool thisBarMatches=(dir==+1) ? (pc>po) : (pc<po);
      if(!thisBarMatches){ prior5Same=false; break; }
   }

   AddSignal(sig,t,dir,R,c,bodyTouch,prior5Same);
}

bool OpenCountertrend(Setup &s,MqlTick &tick)
{
   // Research-style MAX1 is ONLY for LIVE_005's own strategy.
   if(EnableLiveOrders)
   {
      if(HasOurPosition()){ Log("ENTRY_SKIPPED","LIVE005 own-Magic position already exists"); return false; }
   }
   else
   {
      if(v_open){ Log("VIRTUAL_SKIPPED","virtual MAX1 occupied"); return false; }
   }

   int dir=-s.sigdir; // bull signal -> SELL, bear signal -> BUY
   if(dir==-1 && !AllowShort)
   {
      Log("ENTRY_SKIPPED","SELL disabled by AllowShort=false (data-driven direction filter)");
      return false;
   }
   datetime entryNow=(datetime)(tick.time_msc/1000);
   bool skipHour=InSkipHourKST(entryNow);
   Log("SKIP_HOUR_CHECK","skipHour="+(skipHour?"true":"false")+" kstHour="+IntegerToString(KST_Hour(entryNow)));
   if(skipHour && SkipEntryHourKST)
   {
      Log("ENTRY_SKIPPED","blocked by SkipEntryHourKST=true (KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+"))");
      return false;
   }
   if(UseFridayNarrowWindow && !InFridayNarrowAllowedWindowKST(entryNow))
   {
      Log("ENTRY_SKIPPED","blocked by UseFridayNarrowWindow (Friday, outside 10:30-15:00 KST)");
      return false;
   }
   if(!EnableLiveOrders)
   {
      v_open=true; v_tp1=false; v_dir=dir; v_R=s.R;
      v_entry=(dir==+1 ? tick.ask : tick.bid);
      v_sl=v_entry-dir*InitialSL_R*v_R;
      v_tp1px=v_entry+dir*TP1_R*v_R;
      v_lock=v_entry+dir*Lock_R*v_R;
      v_tp2=v_entry+dir*TP2_R*v_R;
      v_entry_time=(datetime)(tick.time_msc/1000);
      v_entries++;
      {
         double atrDiag[1];
         g_entryZoneDistATR=(CopyBuffer(hATR_Sig,0,1,1,atrDiag)==1) ? DistanceToNearestZone(v_entry,atrDiag[0]) : 999.0;
      }
      Log("VIRTUAL_ACCEPT","#"+IntegerToString(v_entries)+" "+(dir==1?"BUY":"SELL")+
          " entry="+DoubleToString(v_entry,_Digits)+" R="+DoubleToString(v_R,_Digits)+
          " zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3)));
      return true;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return false; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double sl=ref-dir*InitialSL_R*s.R;
   double tp=ref+dir*TP2_R*s.R;

   {
      double atrDiag[1];
      g_entryZoneDistATR=(CopyBuffer(hATR_Sig,0,1,1,atrDiag)==1) ? DistanceToNearestZone(ref,atrDiag[0]) : 999.0;
   }

   // Make the initial protection broker-valid before the market order.
   double cushion=MinStopDistance()+_Point;
   if(dir==+1)
   {
      if(sl>q.bid-cushion) sl=q.bid-cushion;
      if(tp<q.ask+cushion) tp=q.ask+cushion;
   }
   else
   {
      if(sl<q.ask+cushion) sl=q.ask+cushion;
      if(tp>q.bid-cushion) tp=q.bid-cushion;
   }
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);

   string tag="LIVE005_"+TFPrefix()+(s.bodyTouch?"BODY":"WICK")+(s.prior5Same?"_P5S":"_P5D");
   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,tp,tag)
                    : trade.Sell(Lots,_Symbol,0.0,sl,tp,tag));
   if(!ok)
   {
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }

   // Give the terminal a chance to expose the new position; later ticks will recover it if needed.
   if(FindOurPosition())
   {
      Log("ENTRY","ticket="+IntegerToString((int)managed_ticket)+" | "+(dir==1?"BUY":"SELL")+
          " | fill="+DoubleToString(managed_entry,_Digits)+" | R="+DoubleToString(managed_R,_Digits)+
          " | SL="+DoubleToString(managed_sl,_Digits)+" | TP2="+DoubleToString(managed_tp2,_Digits)+
          " | zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3)));
   }
   else
      Log("ORDER_SENT_NO_POSITION","retcode="+IntegerToString((int)trade.ResultRetcode()));
   return true;
}

void CheckSetups(MqlTick &tick)
{
   datetime now=(datetime)(tick.time_msc/1000);

   for(int i=ArraySize(setups)-1;i>=0;i--)
   {
      if(now<setups[i].close_time) continue;

      if(!setups[i].extension_hit)
      {
         if(now>setups[i].close_time+MaxExtensionHours*3600)
         { Log("EXT_EXPIRE",TS(setups[i].signal_time)); RemoveSetup(i); continue; }

         double px=(setups[i].sigdir==+1 ? tick.bid : tick.ask);
         bool hit=(setups[i].sigdir==+1 ? px>=setups[i].target : px<=setups[i].target);
         if(!hit) continue;

         setups[i].extension_hit=true;
         setups[i].extension_time=now;
         setups[i].extreme=px;
         Log("EXT_HIT",TS(setups[i].signal_time)+" extreme="+DoubleToString(px,_Digits));
         // Deliberately do NOT continue: trusted validator can evaluate pullback
         // in the same tick after extension state is established.
      }

      if(now>setups[i].extension_time+MaxPullbackHours*3600)
      { Log("PB_EXPIRE",TS(setups[i].signal_time)); RemoveSetup(i); continue; }

      double px=(setups[i].sigdir==+1 ? tick.bid : tick.ask);
      if(setups[i].sigdir==+1)
      {
         if(px>setups[i].extreme) setups[i].extreme=px;
         double trigger=setups[i].extreme-PullbackR*setups[i].R;
         if(px>trigger) continue;
      }
      else
      {
         if(px<setups[i].extreme) setups[i].extreme=px;
         double trigger=setups[i].extreme+PullbackR*setups[i].R;
         if(px<trigger) continue;
      }

      Log("PB_CONFIRM",TS(setups[i].signal_time)+" R="+DoubleToString(setups[i].R,_Digits));
      OpenCountertrend(setups[i],tick);
      // Consume the setup whether live, dry, or MAX1-blocked: one opportunity, matching forward-test discipline.
      RemoveSetup(i);
   }
}

void CloseVirtual(string outcome,double outR,datetime now)
{
   v_totalR+=outR;
   if(outcome=="SL") v_sl_n++;
   else if(outcome=="LOCK") v_lock_n++;
   else if(outcome=="TP") v_tp_n++;
   else if(outcome=="TIMEOUT") v_timeout_n++;
   Log("VIRTUAL_EXIT_"+outcome,"R="+DoubleToString(outR,3)+" | totalR="+DoubleToString(v_totalR,3)+
       " | zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3)));
   v_open=false; v_tp1=false; v_dir=0; v_R=0; v_entry=0; v_entry_time=0;
   g_entryZoneDistATR=999.0;
}

void ManageVirtual(MqlTick &tick)
{
   if(EnableLiveOrders || !v_open) return;
   datetime now=(datetime)(tick.time_msc/1000);
   if(now<=v_entry_time) return;

   if(now>v_entry_time+MaxVirtualExitHours*3600)
   {
      // Validation FIX convention: free MAX1 slot, record TIMEOUT, fabricate no P/L.
      CloseVirtual("TIMEOUT",0.0,now);
      return;
   }

   // Executable close side: BUY closes at Bid, SELL closes at Ask.
   double px=(v_dir==+1 ? tick.bid : tick.ask);

   if(!v_tp1)
   {
      bool slhit=(v_dir==+1 ? px<=v_sl : px>=v_sl);
      if(slhit){ CloseVirtual("SL",-InitialSL_R,now); return; }

      bool tp1hit=(v_dir==+1 ? px>=v_tp1px : px<=v_tp1px);
      if(tp1hit)
      {
         v_tp1=true;
         Log("VIRTUAL_TP1","lock now active at "+DoubleToString(v_lock,_Digits));
      }
      return;
   }

   bool finalhit=(v_dir==+1 ? px>=v_tp2 : px<=v_tp2);
   if(finalhit){ CloseVirtual("TP",0.78,now); return; }

   bool lockhit=(v_dir==+1 ? px<=v_lock : px>=v_lock);
   if(lockhit){ CloseVirtual("LOCK",0.325,now); return; }
}

void ManagePosition(MqlTick &tick)
{
   if(!FindOurPosition()) return;
   if(managed_R<=0) return;

   if(UseProtectStop && !protect_reached && !tp1_reached)
   {
      double protectTriggerPx=managed_entry+managed_dir*ProtectTriggerR*managed_R;
      double px0=(managed_dir==+1 ? tick.bid : tick.ask);
      bool protectHit=(managed_dir==+1 ? px0>=protectTriggerPx : px0<=protectTriggerPx);
      if(protectHit)
      {
         double protectLevel=managed_entry+managed_dir*ProtectR*managed_R;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(ProtectTriggerR,3));
         if(!EnableLiveOrders)
         {
            protect_reached=true;
            Log("DRY_PROTECT","would move SL to "+DoubleToString(protectLevel,_Digits));
         }
         else if(SafeModifyPosition(managed_ticket,managed_dir,protectLevel,managed_tp2,"PROTECT_MODIFY"))
         {
            protect_reached=true;
            Log("PROTECT_MOVED","SL->"+DoubleToString(protectLevel,_Digits));
         }
      }
   }

   if(tp1_reached) return;

   double px=(managed_dir==+1 ? tick.bid : tick.ask); // executable close side
   bool hit=(managed_dir==+1 ? px>=managed_tp1 : px<=managed_tp1);
   if(!hit) return;

   if(!EnableLiveOrders)
   {
      tp1_reached=true;
      Log("DRY_TP1","would move whole-position SL to +0.25R");
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(SafeModifyPosition(managed_ticket,managed_dir,managed_lock,managed_tp2,"LOCK_MODIFY"))
   {
      tp1_reached=true;
      Log("TP1_LOCK","TP1 reached; 0.01 lot cannot partial-close 30%, whole SL moved to "+
          DoubleToString(managed_lock,_Digits));
   }
   // If temporarily invalid because price is too close, retry on later ticks.
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   hATR_Sig=iATR(_Symbol,Timeframe,ATRPeriod);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hATR_Sig==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_"+TFPrefix()+"LIVE_005_RFILTER2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   FindOurPosition();

   Log("START","TF="+TFPrefix()+" | PB=0.10R | SL=2R | own-Magic MAX1 | Magic="+
       IntegerToString((int)MagicNumber)+" | Lots="+DoubleToString(Lots,2)+
       " | LatestSignalOnly="+(LatestSignalOnly?"true":"false")+
       " | AllowShort="+(AllowShort?"true":"false")+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | ExtensionR="+DoubleToString(ExtensionR,2)+" PullbackR="+DoubleToString(PullbackR,2)+
       " InitialSL_R="+DoubleToString(InitialSL_R,2)+" TP1_R="+DoubleToString(TP1_R,2)+
       " Lock_R="+DoubleToString(Lock_R,2)+" TP2_R="+DoubleToString(TP2_R,2)+
       " | SkipHourStartKST="+IntegerToString(SkipHourStartKST)+" SkipHourEndKST="+IntegerToString(SkipHourEndKST)+
       " SkipEntryHourKST="+(SkipEntryHourKST?"true":"false")+
       " | UseFridayNarrowWindow="+(UseFridayNarrowWindow?"true":"false")+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY")+
       " | ATRPeriod="+IntegerToString(ATRPeriod)+
       " UseAsiaBoxZone="+(UseAsiaBoxZone?"true":"false")+" AsiaOpenHourKST="+IntegerToString(AsiaOpenHourKST)+
       " UseNYBoxZone="+(UseNYBoxZone?"true":"false")+" NYOpenHourKST="+DoubleToString(NYOpenHourKST,2)+
       " UseTodayHighLowZone="+(UseTodayHighLowZone?"true":"false")+" UsePrevDayHighLowZone="+(UsePrevDayHighLowZone?"true":"false")+
       " UsePrevNYHighLowZone="+(UsePrevNYHighLowZone?"true":"false")+
       " NYSessionWindow="+DoubleToString(NYSessionStartHourKST,2)+"-"+DoubleToString(NYSessionEndHourKST,2)+"KST");
   Log("NOTE","RFILTER2 build: 005_BUYONLY + MinR_Points filter + LatestSignalOnly (newest BB-breakout candle supersedes any pending earlier setup)");
   Log("NOTE","zoneDistATR diagnostic ported from 001 M2_v2: logs distance (ATR units) from the actual entry fill to the nearest enabled 매물대 zone on every trade close (MANAGED_EXIT / VIRTUAL_EXIT_*). Diagnostic only, does not block entries.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(!EnableLiveOrders)
      Log("VIRTUAL_SUMMARY","entries="+IntegerToString(v_entries)+" SL="+IntegerToString(v_sl_n)+
          " LOCK="+IntegerToString(v_lock_n)+" TP="+IntegerToString(v_tp_n)+
          " TIMEOUT="+IntegerToString(v_timeout_n)+" totalR="+DoubleToString(v_totalR,3)+
          " open="+(v_open?"1":"0"));
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE) IndicatorRelease(hBB4);
   if(hATR_Sig!=INVALID_HANDLE) IndicatorRelease(hATR_Sig);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;

   bool wasManaged=managed; ulong wasTicket=managed_ticket;
   int wasDir=managed_dir; double wasEntry=managed_entry;
   bool wasProtectReached=protect_reached; bool wasTp1Reached=tp1_reached;

   CheckNewM2Bar();
   CheckSetups(tick);
   ManageVirtual(tick);
   ManagePosition(tick);

   // Detect the real/managed position closing (SL/TP/manual) so the
   // same zoneDistATR diagnostic logged at entry also gets a matching
   // close-side outcome line -- this EA has no OnTradeTransaction-based
   // MAE_OUTCOME log like 001/008, so this is the only point it fires.
   if(wasManaged && !managed && wasTicket!=0)
   {
      double profit=GetClosedPositionProfit(wasTicket);
      Log("MANAGED_EXIT",(wasDir==1?"BUY":"SELL")+" ticket="+IntegerToString((int)wasTicket)+
          " entry="+DoubleToString(wasEntry,_Digits)+" profit="+DoubleToString(profit,2)+
          " zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3))+
          " protectTriggered="+(wasProtectReached?"true":"false")+
          " tp1Reached="+(wasTp1Reached?"true":"false"));
      g_entryZoneDistATR=999.0;
   }
}
//+------------------------------------------------------------------+
