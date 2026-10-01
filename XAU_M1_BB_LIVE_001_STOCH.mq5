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
//| Entry-parameter re-optimization (sequential 1-at-a-time sweep via   |
//| MT5 Optimizer, Recovery Factor max, same procedure as M2/M3):       |
//| StochK_Period 16->17 (genuine 2-point plateau), StochOversold       |
//| 30->25, StochOverbought unchanged (confirmed dead parameter here -- |
//| see its own input comment), MinR_Points unchanged at 400, SL_R      |
//| confirmed at 5.0 (M1-specific -- M2/M3 use 4.0). Ground-truth       |
//| confirmed result: NET $17,285.37 -> $19,734.96, PF 1.358, Recovery  |
//| Factor 7.336, WR 93.58%, MaxDD 2.19%/2.63%.                          |
//| SkipFadeBearOSWickTouch: every signal's tag now carries _BODY/_WICK  |
//| depending on whether the CLOSE also broke BB20 or only the high/low  |
//| wicked through it. CONFIRMED default=true: NET $19,734.96 ->         |
//| $20,871.16 (+5.8%), PF 1.358 -> 1.405, Recovery Factor 7.336 ->      |
//| 8.211, WR 93.58% -> 93.73%, DD 2.19%/2.63% -> 1.92%/2.17% -- a clean  |
//| improvement on every metric despite FADE_BEAR_OS being M1's          |
//| dominant bucket, same pattern as M2_v2/M3.                            |
//| SkipFadeBearOSAsiaSession (default false): a Korea-time session       |
//| breakdown (2025.01-2026.09) found STOCH_FADE_BEAR_OS -- M1's          |
//| dominant bucket -- is a structural loser specifically during the      |
//| Asia session (06:00-16:00 KST): PF 0.907, -$1,926.30 over 628 trades, |
//| while solidly profitable in Europe (PF 1.293) and US (PF 1.526)       |
//| hours. Opposite bucket from the same Asia weakness found on M2        |
//| (there it's STOCH_TREND_BEAR), so it needs its own filter here.       |
//| Default false reproduces existing behavior exactly.                   |
//| SkipHourEntryKST (CONFIRMED default=true): a KST 2h-bucket breakdown  |
//| of the confirmed-default backtest (2025.01-2026.09, 2168 trades, WR   |
//| 93.73%, NET $20,871.16) found 14-16 KST is the only clearly negative  |
//| bucket with a real sample (172 trades, NET -$2,506.40) -- 06-08       |
//| (-$318.82, 65 trades) and 10-12 (-$590.16, 253 trades) are smaller    |
//| dips. Blocks new entries while the KST hour is in                     |
//| [SkipHourStartKST,SkipHourEndKST). Ground-truth backtest confirmed:   |
//| 2168->2008 trades (-7.4%), NET $20,771.59->$22,906.29 (+10.3%), PF    |
//| 1.403->1.509, Recovery Factor 8.171->9.488, WR 93.73%->93.92%, DD     |
//| 1.92%/2.17%->1.71%/1.98% -- a clean improvement on every metric.      |
//| threeBarOneWay/timeMildMin/timeDangerMin/ComboExitDangerMin/           |
//| UseComboExit: ported from XAU_M2_BB_LIVE_001_STOCH_v2.mq5, where a    |
//| CONFIRMED result found that force-closing a position once it's BOTH   |
//| never been profitable in its first 3 candles AND spent >=10min with   |
//| adverse excursion >=2R improved NET/PF/MaxDD/RF on a tiny slice of    |
//| trades (see that file's header). UNTESTED here (UseComboExit=false)   |
//| -- M1's own SL_R=5.0/TP_R=0.45 differ from M2's, so this needs its    |
//| own ground-truth backtest before confirming, not a blind port of     |
//| M2's thresholds.                                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M1; // signal-candle timeframe
input double Lots               = 0.1; // Lot size
input int    StochK_Period      = 17;   // Stoch %K period
input int    StochD_Period      = 3; // Stoch %D period
input int    StochSlowing       = 3; // Stoch slowing
input double StochOverbought    = 70.0; // Stoch overbought level (dead param on M1, see header)
input double StochOversold      = 25.0; // Stoch oversold level
input double SL_R               = 5.0;  // Stop loss (R)
input double TP_R               = 0.45; // Take profit (R)
input double MinR_Points        = 400;  // Min signal-candle body (points) to trade, 0=no filter
input ulong  MagicNumber        = 95016102; // Magic number
input int    MaxDeviationPts    = 50; // Max price deviation (points)
input bool   EnableLiveOrders   = false; // Enable live orders
input bool   AllowSellFade      = false; // Allow bull+overbought SELL-fade case
input bool   AllowTrendBull     = false; // Allow bull+not-overbought TREND-BUY case
input bool   SkipFadeBearOSAsiaSession = false; // Skip FADE_BEAR_OS during Asia session (see header)
input bool   SkipFadeBearOSWickTouch = true; // Skip FADE_BEAR_OS wick-only touches (CONFIRMED, see header)
input int    SkipHourStartKST   = 14; // Hour-dip window start, KST (see header, SkipHourEntryKST)
input int    SkipHourEndKST     = 16; // Hour-dip window end, KST, exclusive (see header, SkipHourEntryKST)
input bool   SkipHourEntryKST   = true; // Block entries in [SkipHourStartKST,SkipHourEndKST) KST (CONFIRMED, see header)

input double MildZoneR          = 2.0;  // Adverse-R boundary for dwell-time diagnostic (no trading effect)
input double ComboExitDangerMin = 10.0; // Danger-zone minutes required, combined with threeBarOneWay (UNTESTED, see header)
input bool   UseComboExit       = false; // Close only when BOTH threeBarOneWay AND ComboExitDangerMin are met (UNTESTED, see header)

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE;
datetime last_m1_bar=0;
int f_log=INVALID_HANDLE;

// -- ported from XAU_M2_BB_LIVE_001_STOCH_v2.mq5: threeBarOneWay + danger-
//    zone dwell-time diagnostic, and the AND-combined early exit it
//    motivated there (see that file's header for the full ground truth
//    this is based on). UNTESTED here -- M1 has its own SL_R/TP_R and
//    needs its own backtest before the combo exit can be CONFIRMED. -----
#define TRACK_SLOTS 4
ulong    g_trackTicket[TRACK_SLOTS];
double   g_trackEntry[TRACK_SLOTS], g_trackR[TRACK_SLOTS];
int      g_trackDir[TRACK_SLOTS];
string   g_trackTag[TRACK_SLOTS];
bool     g_waitingBar3[TRACK_SLOTS];
int      g_bar3Count[TRACK_SLOTS];
double   g_bar3Extreme[TRACK_SLOTS];
bool     g_bar3Known[TRACK_SLOTS], g_bar3OneWay[TRACK_SLOTS];
datetime g_trackLastSample[TRACK_SLOTS];
double   g_timeMildMin[TRACK_SLOTS], g_timeDangerMin[TRACK_SLOTS];
bool     g_comboExited[TRACK_SLOTS];

int FindTrackSlot(ulong ticket)
{
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]==ticket) return i;
   return -1;
}

int FindFreeTrackSlot()
{
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]==0) return i;
   return -1;
}

void StartMAETracking(ulong ticket,double entry,double R,int dir,string tag)
{
   int i=FindFreeTrackSlot();
   if(i<0){ Log("TRACK_SLOTS_FULL","dropping tracking for ticket="+IntegerToString((int)ticket)); return; }
   g_trackTicket[i]=ticket; g_trackEntry[i]=entry; g_trackR[i]=R; g_trackDir[i]=dir; g_trackTag[i]=tag;
   g_waitingBar3[i]=true; g_bar3Count[i]=0; g_bar3Extreme[i]=0; g_bar3Known[i]=false; g_bar3OneWay[i]=false;
   g_trackLastSample[i]=TimeCurrent(); g_timeMildMin[i]=0; g_timeDangerMin[i]=0;
   g_comboExited[i]=false;
}

void CheckMAEProgress()
{
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // closed; OnTradeTransaction logs the outcome
      double adverseR=(g_trackDir[i]==+1) ? (g_trackEntry[i]-q.bid)/g_trackR[i] : (q.ask-g_trackEntry[i])/g_trackR[i];

      datetime now=TimeCurrent();
      double elapsedMin=(double)(now-g_trackLastSample[i])/60.0;
      if(elapsedMin>0)
      {
         if(adverseR<MildZoneR) g_timeMildMin[i]+=elapsedMin;
         else                   g_timeDangerMin[i]+=elapsedMin;
         g_trackLastSample[i]=now;
      }

      if(UseComboExit && !g_comboExited[i] && g_bar3Known[i] && g_bar3OneWay[i] && g_timeDangerMin[i]>=ComboExitDangerMin)
      {
         g_comboExited[i]=true;
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(!EnableLiveOrders)
            Log("COMBO_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         else if(trade.PositionClose(g_trackTicket[i]))
            Log("COMBO_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
         else
            Log("COMBO_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      }
   }
}

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

int CountOurPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      n++;
   }
   return n;
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
   if(CountOurPositions()>0){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }
   int kstHour=KST_Hour(TimeCurrent());
   bool inSkipHour=(kstHour>=SkipHourStartKST && kstHour<SkipHourEndKST);
   Log("SKIP_HOUR_CHECK","kstHour="+IntegerToString(kstHour)+" inSkipHour="+(inSkipHour?"true":"false"));
   if(inSkipHour && SkipHourEntryKST)
   {
      Log("ENTRY_SKIPPED","KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+") by SkipHourEntryKST=true");
      return;
   }
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

void CheckNewM1Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m1_bar) return;
   last_m1_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingBar3[i]) continue;
      if(g_bar3Count[i]==0) g_bar3Extreme[i]=(g_trackDir[i]==+1 ? h : l);
      else g_bar3Extreme[i]=(g_trackDir[i]==+1 ? MathMax(g_bar3Extreme[i],h) : MathMin(g_bar3Extreme[i],l));
      g_bar3Count[i]++;
      if(g_bar3Count[i]>=3)
      {
         g_bar3OneWay[i]=(g_trackDir[i]==+1) ? (g_bar3Extreme[i]<=g_trackEntry[i]) : (g_bar3Extreme[i]>=g_trackEntry[i]);
         g_bar3Known[i]=true;
         g_waitingBar3[i]=false;
      }
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

   // BODY vs WICK touch (diagnostic): the entry condition above only requires
   // the candle's high/low (wick) to reach BB20 -- this checks whether the
   // CLOSE (body) also closed beyond BB20. Appended to the trade tag so it
   // shows up in the xlsx report's own comment column (M1 has no separate
   // CSV log infrastructure like M2_v2) -- see M2_v2's header for the
   // ground-truth finding this is testing here.
   bool bodyTouch=(sigdir==+1) ? (c>=up20[0]) : (c<=lo20[0]);
   string touchTag=bodyTouch?"_BODY":"_WICK";

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
         if(!bodyTouch && SkipFadeBearOSWickTouch)
         { Log("SIGNAL_SKIPPED","FADE_BEAR_OS disabled on WICK-only touch by SkipFadeBearOSWickTouch=true"); return; }
         dir=+1; tag="STOCH_FADE_BEAR_OS";
      }
      else                    { dir=-1; tag="STOCH_TREND_BEAR"; }
   }
   tag=tag+touchTag;

   Log("SIGNAL",(sigdir==1?"BULL":"BEAR")+" candle | stochK="+DoubleToString(stochK,2)+
       " | R="+DoubleToString(R,_Digits)+" | touch="+(bodyTouch?"BODY":"WICK")+
       " | decided dir="+(dir==1?"BUY":"SELL")+" | "+tag);
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
       " | SkipFadeBearOSWickTouch="+(SkipFadeBearOSWickTouch?"true":"false")+
       " | MildZoneR="+DoubleToString(MildZoneR,2)+" ComboExitDangerMin="+DoubleToString(ComboExitDangerMin,1)+
       " UseComboExit="+(UseComboExit?"true":"false")+
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

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   int i=FindTrackSlot(posId);
   if(i<0) return; // not a ticket we're tracking (or already logged)

   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   string outcome=(profit>0?"WIN":"LOSS");
   string bar3Str=(!g_bar3Known[i] ? "unknown" : (g_bar3OneWay[i]?"true":"false"));
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " threeBarOneWay="+bar3Str+
       " timeMildMin="+DoubleToString(g_timeMildMin[i],1)+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
       " | "+g_trackTag[i]);
   g_trackTicket[i]=0; // free slot
   g_waitingBar3[i]=false;
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckNewM1Bar();
}
//+------------------------------------------------------------------+
