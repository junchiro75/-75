//+------------------------------------------------------------------+
//| BTC_M2_BB_LIVE_001_STOCH.mq5                                       |
//| Bitcoin (BTCUSD+) port of the gold 001 strategy (XAU_M2_BB_LIVE_   |
//| 001_STOCH_v2.mq5). Same logic, UNTUNED defaults -- this instrument |
//| has never been backtested with this strategy before, so nothing   |
//| from gold's tuning (SL_R=4.0, TP_R=0.45, MinR_Points, AllowSell    |
//| Fade=false) is assumed to transfer. In particular MinR_Points is a |
//| raw point threshold and BTC's price scale/point value is very     |
//| different from gold's (and from NAS100's) -- it needs its own     |
//| fresh sweep from 0, based on BTC's own candle-body distribution.  |
//| AllowSellFade defaults to true (unbiased) until BTC's own          |
//| directional bias is verified by backtest, the same way gold's     |
//| SELL-fade weakness was discovered empirically rather than assumed.|
//|                                                                    |
//| Same M2 dual-BB signal-candle detection used throughout this      |
//| project (BB20 dev2.0 on Close + BB4 dev4.0 on Open), Timeframe     |
//| input for testing other TFs (M1/M3/M5/...). Direction is decided   |
//| by the Stochastic reading AT THE CLOSE of that signal candle:      |
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
//| time (own magic number, distinct from all gold/NAS 001 variants so |
//| all symbols can run on the same account without collision).        |
//| Includes diagnostic logging (BAR_DATA_FAIL / COPYBUFFER_FAIL) on   |
//| previously-silent failure paths, ported from the gold version.     |
//| Default Lots=0.1 -- margin-equivalent to gold's 0.1-lot benchmark  |
//| size (BTCUSD+ margin/lot ~$419.78 vs gold ~$427.72 for 0.1 lot;    |
//| re-check with the account's own Specification dialog before going  |
//| live). Re-verify, do not assume it stays optimal after tuning.     |
//| AllowBuyFade added after a MinR_Points=38000 test (SL_R=1.0,       |
//| TP_R=0.5) showed win rate jumps from ~55% (unfiltered) to ~66% at   |
//| that R level, and STOCH_FADE_BEAR_OS is the one losing case there   |
//| while both trend buckets are already profitable -- see the input's |
//| own comment for the numbers. Still an open question whether this    |
//| holds at other MinR_Points levels; re-verify before trusting it.   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M2; // signal-candle timeframe; change to test other TFs (M1/M3/M5/...)
input double Lots               = 0.1;  // margin-equivalent to gold's 0.1-lot benchmark; re-check via Specification
input int    StochK_Period      = 16;   // matches gold/NAS chart setting (default MT5 is 5); re-check on BTC's own chart
input int    StochD_Period      = 3;
input int    StochSlowing       = 3;
input double StochOverbought    = 70.0;
input double StochOversold      = 30.0;
input double SL_R               = 1.0;  // UNTUNED -- gold converged on 4.0, but re-verify for BTC
input double TP_R               = 0.5;  // UNTUNED -- gold converged on 0.45
input double MinR_Points        = 0;    // UNTUNED -- gold/NAS values do NOT transfer; BTC's price
                                         // scale/point value is different again. Start at 0 (no filter) and
                                         // sweep from scratch based on BTC's own candle-body distribution.
input ulong  MagicNumber        = 97016101; // distinct from all gold (950161xx) and NAS (960161xx) 001
                                             // variants so all symbols can run on the same account without collision
input int    MaxDeviationPts    = 50;
input bool   EnableLiveOrders   = false; // SAFETY: set true only after checks
input bool   AllowSellFade      = true;  // UNBIASED default -- gold's AllowSellFade=false came from its
                                          // own empirical finding (persistent uptrend bias); do not assume
                                          // it transfers to BTC without separately verifying by backtest
input bool   AllowBuyFade       = true;  // gates the OTHER fade case (bear signal + oversold -> BUY,
                                          // STOCH_FADE_BEAR_OS) -- distinct from AllowSellFade, which only
                                          // gates the bull+overbought SELL-fade case. A MinR_Points=38000 test
                                          // (2025.01-2026.09) found STOCH_FADE_BEAR_OS is BTC's own structurally
                                          // losing case at that R level (PF 0.867, -$805.42 over 295 trades)
                                          // while both trend-following buckets were already profitable
                                          // (TREND_BULL PF 1.218, TREND_BEAR PF 1.153) -- set false to skip it.

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("BTC_M2_BB_LIVE_001_STOCH | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
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

void OpenTrade(int dir,double R,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }

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

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

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
      if(stochK<StochOversold)
      {
         if(!AllowBuyFade){ Log("SIGNAL_SKIPPED","BUY-fade disabled by AllowBuyFade=false"); return; }
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

   f_log=FileOpen("BTC_M2_BB_LIVE_001_STOCH_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
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
       " | AllowBuyFade="+(AllowBuyFade?"true":"false")+
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
   CheckNewM2Bar();
}
//+------------------------------------------------------------------+
