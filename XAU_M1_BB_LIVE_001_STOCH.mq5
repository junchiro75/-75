//+------------------------------------------------------------------+
//| XAU_M1_BB_LIVE_001_STOCH.mq5                                       |
//| M1 sibling of XAU_M2_BB_LIVE_001_STOCH_v2.mq5 -- identical logic,  |
//| meant to run SIMULTANEOUSLY with the M2 version on the same       |
//| account (own Magic number, own log file, own chart). Ground-truth |
//| MT5 tick backtest (2025.01-2026.09, TP_R=0.45) showed M1+MinR=400  |
//| as the best M1 config: NET $12,162.27, PF 1.168, MaxDD 3.78%/3.89%,|
//| and only ~0.31 daily P&L correlation with the M2/MinR=350 variant  |
//| -- real diversification, not just doubled exposure. Running both  |
//| at 1x size together (combined MaxDD 5.92%) came out more capital- |
//| efficient (NET/MaxDD = 3.95) than running M2 alone at 2x size      |
//| (NET/MaxDD = 3.69, since 2x M2 is perfectly self-correlated).      |
//|                                                                    |
//| Same M2 dual-BB signal-candle detection used throughout this      |
//| project (BB20 dev2.0 on Close + BB4 dev4.0 on Open), applied here  |
//| on PERIOD_M1 via the Timeframe input. Direction is decided by the  |
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
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M1; // signal-candle timeframe
input double Lots               = 0.1;
input int    StochK_Period      = 16;   // matches user's chart setting (default MT5 is 5)
input int    StochD_Period      = 3;
input int    StochSlowing       = 3;
input double StochOverbought    = 70.0;
input double StochOversold      = 30.0;
input double SL_R               = 4.0;
input double TP_R               = 0.45;
input double MinR_Points        = 400;  // skip signal if R (=|close-open| of the M1 signal candle, in
                                         // points) is below this. 0 = no filter.
input ulong  MagicNumber        = 95016102; // distinct from the M2 sibling (95016101) so both can run
                                             // side by side without one seeing the other's position
input int    MaxDeviationPts    = 50;
input bool   EnableLiveOrders   = false; // SAFETY: set true only after checks
input bool   AllowSellFade      = false; // false = skip the bull+overbought SELL-fade case entirely
                                          // (ground-truth backtest showed this is the one losing direction)
input bool   AllowTrendBull     = false; // false = skip the bull+not-overbought TREND-BUY case entirely
                                          // (M1-specific finding: this bucket is a loser at SL_R=4.0-5.0
                                          // here, unlike the same bucket on M2/M3 where it's profitable)
input bool   SkipFadeBearOSAsiaSession = false; // A Korea-time session breakdown (2025.01-2026.09) found
                                          // STOCH_FADE_BEAR_OS -- M1's dominant bucket -- is a structural
                                          // loser specifically during the Asia session (06:00-16:00 KST):
                                          // PF 0.907, -$1,926.30 over 628 trades, while it's solidly
                                          // profitable in Europe (16-22 KST, PF 1.293) and US (22-06 KST,
                                          // PF 1.526) hours. This is the OPPOSITE bucket from the same
                                          // Asia-session weakness found on M2 (there it's STOCH_TREND_BEAR),
                                          // so it needs its own separate filter here. Default false
                                          // reproduces existing behavior exactly.

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE;
datetime last_m1_bar=0;
int f_log=INVALID_HANDLE;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M1_BB_LIVE_001_STOCH | ",event," | ",detail);
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

bool InAsiaSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=6 && h<16);
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

void CheckNewM1Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m1_bar) return;
   last_m1_bar=t;

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
      else
      {
         if(!AllowTrendBull){ Log("SIGNAL_SKIPPED","TREND-BUY disabled by AllowTrendBull=false"); return; }
         dir=+1; tag="STOCH_TREND_BULL";
      }
   }
   else // bear signal candle
   {
      if(stochK<StochOversold)
      {
         if(SkipFadeBearOSAsiaSession && InAsiaSessionKST(sig))
         { Log("SIGNAL_SKIPPED","FADE_BEAR_OS disabled during Asia session (06-16 KST) by SkipFadeBearOSAsiaSession=true"); return; }
         dir=+1; tag="STOCH_FADE_BEAR_OS";
      }
      else                    { dir=-1; tag="STOCH_TREND_BEAR"; }
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

   f_log=FileOpen("XAU_M1_BB_LIVE_001_STOCH_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
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
       " | AllowTrendBull="+(AllowTrendBull?"true":"false")+
       " | SkipFadeBearOSAsiaSession="+(SkipFadeBearOSAsiaSession?"true":"false")+
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
   CheckNewM1Bar();
}
//+------------------------------------------------------------------+
