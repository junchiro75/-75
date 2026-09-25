//+------------------------------------------------------------------+
//| XAU_M3_BB_LIVE_001_STOCH.mq5                                       |
//| M3 sibling of XAU_M2_BB_LIVE_001_STOCH_v2.mq5 / XAU_M1_BB_LIVE_001_ |
//| STOCH.mq5 -- identical logic, meant to run SIMULTANEOUSLY with the |
//| M1 and M2 versions on the same account (own Magic number, own log  |
//| file, own chart). Ground-truth MT5 tick backtest (2025.01-2026.09, |
//| TP_R=0.45) showed M3+MinR=900 as the best M3 config: NET $12,831,  |
//| PF 1.411 (highest of the three timeframes), WR 92.23%, MaxDD       |
//| 3.53%/3.62%, Recovery Factor 3.43. Daily P&L correlation with the  |
//| M2/MinR=350 sibling is only 0.063 -- essentially uncorrelated --   |
//| and 0.359 with M1/MinR=400. Combined M1+M2+M3 (all at 1x size)     |
//| backtested to the best risk-adjusted result of any combination     |
//| tried: NET $41,998 / MaxDD $9,400 (7.03%), NET/MaxDD=4.47, beating |
//| every single EA and every pair on that ratio.                      |
//|                                                                    |
//| Same M2 dual-BB signal-candle detection used throughout this      |
//| project (BB20 dev2.0 on Close + BB4 dev4.0 on Open), applied here  |
//| on PERIOD_M3 via the Timeframe input. Direction is decided by the  |
//| Stochastic reading AT THE CLOSE of that signal candle:             |
//|                                                                    |
//|   Bull signal candle (up breakout):                                |
//|     Stoch %K >= StochOverbought (70) -> SELL (countertrend, fade   |
//|       the move -- stochastic confirms it's overextended)          |
//|     Stoch %K <  StochOverbought      -> BUY  (trend-following)     |
//|   Bear signal candle (down breakout):                              |
//|     Stoch %K <  StochOversold (30)   -> BUY  (countertrend, fade) |
//|     Stoch %K >= StochOversold        -> SELL (trend-following)    |
//|                                                                    |
//| Entry is IMMEDIATE at market right when the signal candle closes   |
//| -- no Extension/Pullback staging. R is the signal candle's body    |
//| (|close-open|). Exit is a single fixed bracket, no protect-lock:   |
//| SL = entry -+ SL_R*R, TP = entry +- TP_R*R. MAX1 position at a     |
//| time (own magic number). AllowSellFade=false skips the bull+       |
//| overbought SELL-fade case (the one structurally losing direction,  |
//| consistent with gold's persistent uptrend bias found elsewhere in  |
//| this project). Includes diagnostic logging (BAR_DATA_FAIL /        |
//| COPYBUFFER_FAIL) on previously-silent failure paths.               |
//| TrendBearEuropeOnly=true (confirmed default) restricts             |
//| STOCH_TREND_BEAR to the Europe session (16-22 KST) only -- a real   |
//| backtest confirmed a clean improvement on every metric (NET, PF,   |
//| and drawdown all better); see the input's own comment for numbers. |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M3; // signal-candle timeframe
input double Lots               = 0.1;
input int    StochK_Period      = 16;   // matches user's chart setting (default MT5 is 5)
input int    StochD_Period      = 3;
input int    StochSlowing       = 3;
input double StochOverbought    = 70.0;
input double StochOversold      = 30.0;
input double SL_R               = 4.0;
input double TP_R               = 0.45;
input double MinR_Points        = 900;  // skip signal if R (=|close-open| of the M3 signal candle, in
                                         // points) is below this. 0 = no filter.
input ulong  MagicNumber        = 95016103; // distinct from the M2 (95016101) and M1 (95016102)
                                             // siblings so all three can run side by side
input int    MaxDeviationPts    = 50;
input bool   EnableLiveOrders   = false; // SAFETY: set true only after checks
input bool   AllowSellFade      = false; // false = skip the bull+overbought SELL-fade case entirely
                                          // (ground-truth backtest showed this is the one losing direction)
input bool   TrendBearEuropeOnly = true;  // A Korea-time session breakdown (2025.01-2026.09) found
                                          // STOCH_TREND_BEAR loses in BOTH Asia (06-16 KST: PF 0.586,
                                          // -$1,616.72, 46 trades) and US hours (22-06 KST: PF 0.709,
                                          // -$1,225.20, 51 trades) on M3, and is only profitable during
                                          // Europe (16-22 KST: PF 3.596, +$1,157.86, 26 trades) -- a
                                          // different pattern from M2 (Asia-only weakness) and M1 (a
                                          // different bucket entirely, left untouched by choice).
                                          // Ground-truth backtest confirmed this default: NET $16,186.37 ->
                                          // $20,749.43 (+$4,563.06), PF 1.725 -> 2.264, DD down to 1.85%/
                                          // 2.64% -- a clean improvement on every metric. Set false to
                                          // restore the old always-on TREND_BEAR behavior.
input bool   ReverseTrendBearOutsideEurope = false; // UNTESTED -- instead of SKIPPING TREND_BEAR outside the
                                          // Europe session (i.e. during Asia and US, both losers on M3),
                                          // trade the OPPOSITE direction (BUY) there instead. Takes priority
                                          // over TrendBearEuropeOnly when both would apply. A losing SELL and
                                          // a winning reversed BUY are NOT mathematically equivalent (SL/TP
                                          // distances are asymmetric and the intrabar price path matters),
                                          // so this needs its own backtest. Tagged
                                          // STOCH_TREND_BEAR_REV_NONEURO for tracking.

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE;
datetime last_m3_bar=0;
int f_log=INVALID_HANDLE;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M3_BB_LIVE_001_STOCH | ",event," | ",detail);
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
// to last Sunday of October, approximated here by date only.
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

bool InEuropeSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=16 && h<22);
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
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
}

void CheckNewM3Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m3_bar) return;
   last_m3_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

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
         if(!InEuropeSessionKST(sig))
         {
            if(ReverseTrendBearOutsideEurope){ dir=+1; tag="STOCH_TREND_BEAR_REV_NONEURO"; }
            else if(TrendBearEuropeOnly)
            { Log("SIGNAL_SKIPPED","TREND-BEAR restricted to Europe session (16-22 KST) by TrendBearEuropeOnly=true"); return; }
            else { dir=-1; tag="STOCH_TREND_BEAR"; }
         }
         else { dir=-1; tag="STOCH_TREND_BEAR"; }
      }
   }

   Log("SIGNAL",(sigdir==1?"BULL":"BEAR")+" candle | stochK="+DoubleToString(stochK,2)+
       " | R="+DoubleToString(R,_Digits)+" | decided dir="+(dir==1?"BUY":"SELL")+" | "+tag);
   OpenTrade(dir,R,tag);
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_LWMA,STO_LOWHIGH);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hStoch==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M3_BB_LIVE_001_STOCH_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
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
       " | TrendBearEuropeOnly="+(TrendBearEuropeOnly?"true":"false")+
       " | ReverseTrendBearOutsideEurope="+(ReverseTrendBearOutsideEurope?"true":"false")+
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
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckNewM3Bar();
}
//+------------------------------------------------------------------+
