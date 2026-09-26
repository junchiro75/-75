//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_001_STOCH_v2.mq5                                    |
//| New strategy (user-designed): same M2 dual-BB signal-candle       |
//| detection used throughout this project (BB20 dev2.0 on Close +   |
//| BB4 dev4.0 on Open, PERIOD_M2), but direction is decided by the   |
//| Stochastic reading AT THE CLOSE of that signal candle instead of  |
//| always countertrend:                                              |
//|                                                                    |
//|   Bull signal candle (up breakout):                                |
//|     Stoch %K >= StochOverbought (70) -> SELL (countertrend, fade   |
//|       the move -- stochastic confirms it's overextended)          |
//|     Stoch %K <  StochOverbought      -> BUY  (trend-following --  |
//|       stochastic does NOT confirm overextension, so follow it)    |
//|   Bear signal candle (down breakout):                              |
//|     Stoch %K <  StochOversold (30)   -> BUY  (countertrend, fade) |
//|     Stoch %K >= StochOversold        -> SELL (trend-following)    |
//|                                                                    |
//| Entry is IMMEDIATE at market right when the signal candle closes   |
//| -- no Extension/Pullback staging like the 005-family EAs. R is    |
//| the signal candle's body (|close-open|), same definition as       |
//| elsewhere in this project. Exit is a single fixed bracket, no      |
//| protect-lock: SL = entry -+ SL_R*R, TP = entry +- TP_R*R.          |
//| MAX1 position at a time (own magic number).                        |
//| V2: added AllowSellFade -- ground-truth backtest (2025.01-2026.09, |
//| SL_R=4.0, MinR_Points=400) showed the bull+overbought SELL-fade    |
//| case is the ONE structurally losing direction (PF 0.88, -$4,848),  |
//| consistent with gold's persistent uptrend bias found elsewhere in  |
//| this project (005's own SELL-disable finding). The other three    |
//| cases were all net profitable (combined +$15,050). Default true   |
//| reproduces V1 exactly; set false to skip that one case entirely.  |
//| _v2 build: same logic as the live XAU_M2_BB_STOCH_V2 EA this      |
//| replaces, plus diagnostic logging on previously-silent failure    |
//| paths in CheckNewM2Bar() (BAR_DATA_FAIL / COPYBUFFER_FAIL) to      |
//| catch a repeat of a multi-hour silent-signal window seen live on  |
//| 2026.09.23.                                                        |
//| SkipTrendBearAsiaSession=true (confirmed default) skips            |
//| STOCH_TREND_BEAR specifically during the Asia session (06-16 KST)  |
//| where it's a structural loser, while it's solidly profitable in    |
//| Europe (16-22) and US (22-06) hours. A real backtest confirmed a    |
//| clean improvement on every metric (NET, PF, and drawdown all       |
//| better); see the input's own comment for numbers.                  |
//| MaxMinutesWithoutProgress (default 0, disabled) closes a position   |
//| early once it's been open this many minutes, regardless of P&L --   |
//| motivated by TP-hit trades resolving in ~3min median vs SL-hit      |
//| trades taking ~36min median. UNTESTED as a live rule; see the       |
//| input's own comment for the caveat before trusting it.              |
//| MAE-milestone tracking (diagnostic only, no trading effect): logs   |
//| MAE_MILESTONE when a position's adverse excursion crosses 50%/75%   |
//| of SL_R, and MAE_OUTCOME with the final win/loss at close -- lets   |
//| the CSV log answer "given a trade reached 50%/75% of its stop,      |
//| what fraction still won" (not available from the xlsx report).     |
//| Also tags firstBarOneWay on that same MAE_OUTCOME line: true when    |
//| the very next M2 bar after entry never moved favorably by even 1     |
//| point (BUY: bar's high never exceeded entry; SELL: bar's low never  |
//| went below it) before closing -- tests whether an immediate,        |
//| zero-pullback move against the position predicts a one-way run      |
//| into the stop.                                                      |
//| UseTrendFilter (default false, UNTESTED): skips an entry when a      |
//| strong opposing trend is already established on TrendFilterTimeframe |
//| (default M15) -- ADX >= ADXThreshold and the dominant DI points      |
//| against the intended direction. Theory: one-way losses happen when   |
//| the opposing trend was already in place before entry, not created    |
//| by the trade itself. Backtest before trusting it.                    |
//| oppSignalSeen (diagnostic, always logged regardless of                |
//| UseOppositeSignalExit): true if a NEW opposite-direction M2 signal   |
//| candle (same BB20/BB4 breakout + R filter as entries) appeared at    |
//| any point while the position was open -- answers "of trades that     |
//| hit SL, what fraction had an opposite signal candle appear before    |
//| the loss" and "of trades where an opposite signal appeared, what     |
//| fraction still hit TP anyway" straight from the CSV log.             |
//| UseOppositeSignalExit (default false, UNTESTED): when true, ACTS on  |
//| the same opposite-signal detection above by closing the open         |
//| position at market immediately. Unlike the time-stop / MAE-%         |
//| early exits (tested and rejected), this uses the same technical      |
//| basis (BB breakout) the strategy already trades entries on.          |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M2; // signal-candle timeframe; change to test other TFs (M1/M3/M5/...)
input double Lots               = 0.1;
input int    StochK_Period      = 16;   // matches user's chart setting (default MT5 is 5)
input int    StochD_Period      = 3;
input int    StochSlowing       = 3;
input double StochOverbought    = 70.0;
input double StochOversold      = 30.0;
input double SL_R               = 1.0;
input double TP_R               = 0.5;
input double MinR_Points        = 0;    // skip signal if R (=|close-open| of the M2 signal candle, in
                                         // points) is below this. 0 = no filter.
input ulong  MagicNumber        = 95016101;
input int    MaxDeviationPts    = 50;
input bool   EnableLiveOrders   = false; // SAFETY: set true only after checks
input bool   AllowSellFade      = true;  // false = skip the bull+overbought SELL-fade case entirely
                                          // (ground-truth backtest showed this is the one losing direction)
input bool   SkipTrendBearAsiaSession = true; // A session breakdown (2025.01-2026.09) found STOCH_TREND_BEAR
                                          // is a structural loser specifically during the Asia session
                                          // (06:00-16:00 Korea time -> PF 0.822, -$1,480.89 over 243 trades),
                                          // while the same signal is solidly profitable during Europe (16-22)
                                          // and especially US (22-06) hours. Skips TREND_BEAR only during
                                          // that Korea-time window; other signals/sessions unaffected.
                                          // Ground-truth backtest confirmed this default: NET $17,004.08 ->
                                          // $17,746.29 (+$742.21), PF 1.225 -> 1.260, DD down to 3.25%/3.96%
                                          // -- a clean improvement on every metric. Set false to restore the
                                          // old always-on TREND_BEAR behavior.
input int    AsiaSessionStartHour = 6;   // Korea-time hour the Asia-session skip window starts (inclusive).
                                          // An hour-by-hour breakdown of the same data found the losses
                                          // actually concentrate in 06-11 KST, while 12-17 KST is profitable
                                          // -- try narrowing AsiaSessionEndHour to 11 to test keeping those
                                          // hours active. Hourly samples are much smaller than the 8h-block
                                          // ones (20-45 trades/hour vs 200+), so treat this as a follow-up
                                          // experiment, not a confirmed result yet.
input int    AsiaSessionEndHour   = 16;  // Korea-time hour the Asia-session skip window ends (exclusive).
input bool   ReverseTrendBearAsiaSession = false; // UNTESTED -- instead of SKIPPING TREND_BEAR during the
                                          // Asia session, trade the OPPOSITE direction (BUY) there instead.
                                          // Takes priority over SkipTrendBearAsiaSession when both would
                                          // apply. A losing SELL and a winning reversed BUY are NOT
                                          // mathematically equivalent (SL/TP distances are asymmetric and the
                                          // intrabar price path matters), so this needs its own backtest to
                                          // know whether the Asia-session weakness is a reversible edge or
                                          // just noise to avoid. Tagged STOCH_TREND_BEAR_REV_ASIA for tracking.
input int    MaxMinutesWithoutProgress = 0; // 0 = disabled (default, no behavior change). Holding-time analysis
                                          // (2025.01-2026.09) found trades that hit TP resolve in ~3min median,
                                          // while trades that hit SL take ~36min median (9-18x longer) --
                                          // a position still open past N minutes is disproportionately likely
                                          // to end in a loss. HOWEVER: 12-26% of WINNING trades also take
                                          // longer than typical cutoffs (15-30min), and this data can't show
                                          // their intrabar P&L path at the cutoff moment, so a blind time-stop
                                          // could cut some future winners at an unknown (possibly negative)
                                          // price. UNTESTED as a live rule -- set >0 (e.g. 20/30/45) to close
                                          // any open position early once it's been open this many minutes,
                                          // and backtest the real net effect before trusting it.
input bool   UseTrendFilter     = false; // UNTESTED -- skip an entry if a strong opposing trend is already in
                                          // place on a higher timeframe (checked via ADX/DI), on the theory
                                          // that trades lost to a one-way run against the position happen when
                                          // that opposing trend was already established before entry. Default
                                          // false reproduces existing behavior exactly.
input ENUM_TIMEFRAMES TrendFilterTimeframe = PERIOD_M15; // higher timeframe to measure the opposing trend on
                                          // (not the same M2 the signal fires on, since that's noisy/local --
                                          // the idea is to detect the larger-picture regime, not the signal
                                          // candle itself).
input int    ADXPeriod          = 14;    // standard ADX period
input double ADXThreshold       = 25.0;  // ADX >= this is considered "trending" (standard convention); below
                                          // this the market is considered range-bound/no dominant trend

input bool   UseOppositeSignalExit = false; // UNTESTED -- while holding a position, close it immediately at
                                          // market if a NEW opposite-direction M2 signal candle (BB20/BB4
                                          // breakout, same R filter as entries) appears -- regardless of what
                                          // direction that new signal would itself trade (the stochastic
                                          // fade/trend decision only matters for entries, not for this check).
                                          // Rationale: unlike the time-stop or MAE-%-based early exits already
                                          // tested and rejected, this uses the SAME technical basis (BB
                                          // breakout) the strategy already trades on, so it may catch a
                                          // genuine reversal earlier than waiting for price to travel deep into
                                          // the stop. Default false reproduces existing behavior exactly.

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE,hADX=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

// -- MAE-milestone tracking (diagnostic only, no trading effect) -----------
// Tracks, for the current open position, whether the adverse excursion has
// crossed 50%/75% of the SL_R distance, and logs the eventual win/loss
// outcome alongside those flags -- lets us answer "given a trade reached
// 50%/75% of its stop, what fraction still won vs lost" from the CSV log,
// which the MT5 Strategy Tester xlsx report does not expose per-trade.
ulong  g_trackTicket=0;
double g_trackEntry=0, g_trackR=0;
int    g_trackDir=0;
bool   g_reached50=false, g_reached75=false;
string g_trackTag="";

// -- first-bar-after-entry direction (diagnostic only) ----------------------
// Checks whether the very next M2 bar to close after entry moved WITH or
// AGAINST the trade's direction -- tests the hypothesis that an immediate
// opposite-direction bar predicts a one-way move into the stop.
bool   g_waitingFirstBar=false;
bool   g_firstBarKnown=false, g_firstBarOneWay=false;

// -- band-reentry tracking (diagnostic only) ---------------------------------
// The entry signal is a BB20 breakout; this checks whether price later
// crosses back to the OTHER side of that same (frozen, as-of-entry) BB20
// level -- i.e. the breakout "gave back" and failed to hold. Cheap to check
// every tick (no waiting for a bar close), unlike the opposite-signal-candle
// idea, which only fires on a full new breakout in the other direction and
// would already be very late. Logged as its own milestone, and also cross-
// referenced with reached50/75 on the outcome line, to test the hypothesis
// that "band reentry ALONE" is noisy (many such trades still recover, same
// as firstBarOneWay) but "band reentry AND deep MAE" together might be a
// more reliable failure signal than either alone.
double g_lastBandLevel=0;
double g_trackBandLevel=0;
bool   g_bandReentered=false;

// -- opposite-signal tracking (diagnostic, always on; ACTS only if
//    UseOppositeSignalExit=true) ------------------------------------------
// Tracks whether a NEW opposite-direction M2 signal candle (same BB20/BB4
// breakout + R filter used for entries) appeared at any point while the
// current position was open. Logged regardless of UseOppositeSignalExit so
// we can first ask "of trades that hit SL, what fraction had an opposite
// signal candle appear before the loss" with zero trading effect, then
// separately test the P&L impact of actually acting on it.
bool   g_trackOppSignalSeen=false;

void StartMAETracking(ulong ticket,double entry,double R,int dir,string tag)
{
   g_trackTicket=ticket; g_trackEntry=entry; g_trackR=R; g_trackDir=dir;
   g_reached50=false; g_reached75=false; g_trackTag=tag;
   g_waitingFirstBar=true; g_firstBarKnown=false; g_firstBarOneWay=false;
   g_trackBandLevel=g_lastBandLevel; g_bandReentered=false;
   g_trackOppSignalSeen=false;
}

// Called from CheckNewM2Bar with the new bar's raw breakout direction
// (sigdir, before the stochastic fade/trend decision -- that decision only
// matters for what a NEW entry would trade, not for detecting that the
// opposite technical signal fired). If UseOppositeSignalExit is on, also
// closes the open position at market right away.
void CheckOppositeSignal(int sigdir)
{
   if(g_trackTicket==0 || sigdir==0) return;
   if(sigdir!=-g_trackDir) return; // only the OPPOSITE of our position's direction counts

   if(!g_trackOppSignalSeen)
   {
      g_trackOppSignalSeen=true;
      Log("MAE_MILESTONE","opposite signal candle appeared | "+g_trackTag);
   }

   if(!UseOppositeSignalExit) return;
   if(!PositionSelectByTicket(g_trackTicket)) return; // already closed

   double profit=PositionGetDouble(POSITION_PROFIT);
   if(!EnableLiveOrders)
   {
      Log("OPP_SIGNAL_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket)+" profit="+DoubleToString(profit,2)+
          " (would close, EnableLiveOrders=false) | "+g_trackTag);
      return;
   }
   if(trade.PositionClose(g_trackTicket))
      Log("OPP_SIGNAL_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket)+" profit="+DoubleToString(profit,2)+
          " | "+g_trackTag);
   else
      Log("OPP_SIGNAL_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
}

void CheckMAEProgress()
{
   if(g_trackTicket==0) return;
   if(!PositionSelectByTicket(g_trackTicket)) return; // closed; OnTradeTransaction logs the outcome
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   double adverseR=(g_trackDir==+1) ? (g_trackEntry-q.bid)/g_trackR : (q.ask-g_trackEntry)/g_trackR;
   double frac=adverseR/SL_R;
   if(frac>=0.5  && !g_reached50){ g_reached50=true; Log("MAE_MILESTONE","50% of SL reached | "+g_trackTag); }
   if(frac>=0.75 && !g_reached75){ g_reached75=true; Log("MAE_MILESTONE","75% of SL reached | "+g_trackTag); }

   if(!g_bandReentered && g_trackBandLevel!=0)
   {
      bool reentered=(g_trackDir==+1) ? (q.bid<g_trackBandLevel) : (q.ask>g_trackBandLevel);
      if(reentered){ g_bandReentered=true; Log("MAE_MILESTONE","band reentry (breakout failed) | "+g_trackTag); }
   }
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_001_STOCH_v2 | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

// -- Korea-time session helpers (server clock -> KST, EU-DST aware) --------
// This broker's server runs 6h behind Korea time during EU summer time
// (DST) and 7h behind during EU winter time -- measured directly (6h
// confirmed live in Sep 2026), not assumed. EU DST: last Sunday of March
// 01:00 UTC-ish to last Sunday of October, approximated here by date only
// (the exact hour of the switchover is immaterial at this granularity).
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

bool InAsiaSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=AsiaSessionStartHour && h<AsiaSessionEndHour);
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

// Skips an entry if a strong opposing trend is already established on
// TrendFilterTimeframe: ADX >= ADXThreshold (a trend, by the standard
// convention) AND the dominant DI is pointed against our intended direction.
bool OpposingTrendTooStrong(int dir)
{
   if(!UseTrendFilter) return false;
   double adxBuf[1],plusDI[1],minusDI[1];
   if(CopyBuffer(hADX,0,1,1,adxBuf)!=1) return false;
   if(CopyBuffer(hADX,1,1,1,plusDI)!=1) return false;
   if(CopyBuffer(hADX,2,1,1,minusDI)!=1) return false;
   if(adxBuf[0]<ADXThreshold) return false;
   if(dir==+1 && minusDI[0]>plusDI[0]) return true; // trying to BUY into a strong downtrend
   if(dir==-1 && plusDI[0]>minusDI[0]) return true; // trying to SELL into a strong uptrend
   return false;
}

void CheckTimeStop()
{
   if(MaxMinutesWithoutProgress<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      double minutesOpen=(double)(TimeCurrent()-opened)/60.0;
      if(minutesOpen<MaxMinutesWithoutProgress) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("TIME_STOP_DRY","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false)");
         continue;
      }
      if(trade.PositionClose(tk))
         Log("TIME_STOP_CLOSE","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2));
      else
         Log("TIME_STOP_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
}

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

void OpenTrade(int dir,double R,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }
   if(OpposingTrendTooStrong(dir)){ Log("ENTRY_SKIPPED","opposing trend too strong (ADX filter) | "+tag); return; }
   tag=TFPrefix()+tag;

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double sl=ref-dir*SL_R*R;
   double tp=ref+dir*TP_R*R;

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

   if(!EnableLiveOrders)
   {
      Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+string(" @~")+DoubleToString(ref,_Digits)+
          " R="+DoubleToString(R,_Digits)+" SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,tp,tag)
                    : trade.Sell(Lots,_Symbol,0.0,sl,tp,tag));
   if(!ok)
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   else
   {
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
         StartMAETracking(tk,ref,R,dir,tag);
         break;
      }
   }
}

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   if(g_waitingFirstBar)
   {
      // "one-way against": price never moved favorably by even 1 point during
      // this bar -- for a BUY, the bar's high never exceeded the entry price;
      // for a SELL, the bar's low never went below it. Uses h/l (the bar's
      // extremes), not open/close, since a bar can close red while still
      // having ticked favorably first.
      g_firstBarOneWay=(g_trackDir==+1) ? (h<=g_trackEntry) : (l>=g_trackEntry);
      g_firstBarKnown=true;
      g_waitingFirstBar=false;
   }

   double up20[1],lo20[1],up4[1],lo4[1];
   int r1=CopyBuffer(hBB20,1,1,1,up20), r2=CopyBuffer(hBB20,2,1,1,lo20);
   int r3=CopyBuffer(hBB4,1,1,1,up4),   r4=CopyBuffer(hBB4,2,1,1,lo4);
   if(r1!=1 || r2!=1 || r3!=1 || r4!=1)
   {
      Log("COPYBUFFER_FAIL","BB20up="+IntegerToString(r1)+" BB20lo="+IntegerToString(r2)+
          " BB4up="+IntegerToString(r3)+" BB4lo="+IntegerToString(r4)+
          " err="+IntegerToString(GetLastError()));
      return;
   }

   int sigdir=0;
   if(c>o && h>=up20[0] && h>=up4[0]) sigdir=+1;      // bull (up) signal candle
   else if(c<o && l<=lo20[0] && l<=lo4[0]) sigdir=-1; // bear (down) signal candle
   if(sigdir==0) return;

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR){ Log("SIGNAL_SKIPPED","R too small"); return; }

   CheckOppositeSignal(sigdir);

   double kbuf[1];
   if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
   double stochK=kbuf[0];

   int dir=0; string tag="";
   if(sigdir==+1) // bull signal candle
   {
      if(stochK>=StochOverbought)
      {
         if(!AllowSellFade){ Log("SIGNAL_SKIPPED","SELL-fade disabled by AllowSellFade=false"); return; }
         dir=-1; tag="STOCH_FADE_BULL_OB";
      }
      else                       { dir=+1; tag="STOCH_TREND_BULL"; }
   }
   else // bear signal candle
   {
      if(stochK<StochOversold){ dir=+1; tag="STOCH_FADE_BEAR_OS"; }
      else
      {
         if(InAsiaSessionKST(sig))
         {
            if(ReverseTrendBearAsiaSession){ dir=+1; tag="STOCH_TREND_BEAR_REV_ASIA"; }
            else if(SkipTrendBearAsiaSession)
            { Log("SIGNAL_SKIPPED","TREND-BEAR disabled during Asia session (06-16 KST) by SkipTrendBearAsiaSession=true"); return; }
            else { dir=-1; tag="STOCH_TREND_BEAR"; }
         }
         else { dir=-1; tag="STOCH_TREND_BEAR"; }
      }
   }

   // Band-reentry tracking only makes sense for trend-following trades (dir
   // matches the breakout direction) -- for a fade trade, price returning
   // toward/across that same band is the EXPECTED favorable direction, not
   // a failure signal, so disable the check there (0 = disabled).
   g_lastBandLevel=(dir==sigdir) ? (sigdir==+1 ? up20[0] : lo20[0]) : 0;

   Log("SIGNAL",(sigdir==1?"BULL":"BEAR")+" candle | stochK="+DoubleToString(stochK,2)+
       " | R="+DoubleToString(R,_Digits)+" | decided dir="+(dir==1?"BUY":"SELL")+" | "+tag);
   OpenTrade(dir,R,tag);
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_LWMA,STO_LOWHIGH);
   hADX=iADX(_Symbol,TrendFilterTimeframe,ADXPeriod);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hStoch==INVALID_HANDLE || hADX==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_BB_LIVE_001_STOCH_v2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | Stoch("+IntegerToString(StochK_Period)+","+IntegerToString(StochD_Period)+
       ","+IntegerToString(StochSlowing)+") | OB="+DoubleToString(StochOverbought,1)+
       " OS="+DoubleToString(StochOversold,1)+" | SL_R="+DoubleToString(SL_R,2)+
       " | TP_R="+DoubleToString(TP_R,2)+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | AllowSellFade="+(AllowSellFade?"true":"false")+
       " | SkipTrendBearAsiaSession="+(SkipTrendBearAsiaSession?"true":"false")+
       " | AsiaWindow="+IntegerToString(AsiaSessionStartHour)+"-"+IntegerToString(AsiaSessionEndHour)+"KST"+
       " | ReverseTrendBearAsiaSession="+(ReverseTrendBearAsiaSession?"true":"false")+
       " | MaxMinutesWithoutProgress="+IntegerToString(MaxMinutesWithoutProgress)+
       " | UseTrendFilter="+(UseTrendFilter?"true":"false")+
       " | TrendFilterTF="+EnumToString(TrendFilterTimeframe)+" ADXPeriod="+IntegerToString(ADXPeriod)+
       " ADXThreshold="+DoubleToString(ADXThreshold,1)+
       " | UseOppositeSignalExit="+(UseOppositeSignalExit?"true":"false")+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE)  IndicatorRelease(hBB4);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckTimeStop();
   CheckNewM2Bar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(g_trackTicket==0) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID)!=g_trackTicket) return;

   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   string outcome=(profit>0?"WIN":"LOSS");
   string firstBarStr=(!g_firstBarKnown ? "unknown" : (g_firstBarOneWay?"true":"false"));
   string bandStr=(g_trackBandLevel==0 ? "n/a(fade)" : (g_bandReentered?"true":"false"));
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " reached50="+(g_reached50?"true":"false")+" reached75="+(g_reached75?"true":"false")+
       " firstBarOneWay="+firstBarStr+" bandReentry="+bandStr+
       " oppSignalSeen="+(g_trackOppSignalSeen?"true":"false")+" | "+g_trackTag);
   g_trackTicket=0;
   g_waitingFirstBar=false;
}
//+------------------------------------------------------------------+
