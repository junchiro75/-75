//+------------------------------------------------------------------+
//| XAU_M5_PULLBACKTREND_test.mq5                                       |
//+------------------------------------------------------------------+
//| NEW MODEL, FIRST VERSION (2026-11-21), NOT the 010-013 BB-touch      |
//| family, NOT yet confirmed. Built from scratch after the user asked   |
//| whether a ~2:1 reward:risk model with a real edge is possible --      |
//| today's experiments (012 WICK_TREND isolation, 001 IgnoreStochastic)  |
//| confirmed the existing BB-touch signal is structurally a short-term   |
//| mean-reversion edge: widening exits to chase a bigger payoff ratio     |
//| destroyed the edge every time (win rate collapsed toward 50%, PF       |
//| toward ~1.0) regardless of which direction (fade or trend) it was       |
//| traded. So this is a genuinely different signal concept, not a          |
//| reparameterization of 010-013.                                           |
//|                                                                           |
//| SIGNAL: higher-timeframe (H1) trend direction via EMA(TrendEMAPeriod)     |
//| vs H1 close, then on the signal timeframe (default M5) wait for a         |
//| pullback that dips through a faster EMA(PullbackEMAPeriod) against the    |
//| H1 trend and then closes back in the trend's own direction (reclaim) --   |
//| BUY in an uptrend when the signal candle's low touches/crosses below the  |
//| fast EMA but its close ends back above it (and close>open); mirrored      |
//| SELL in a downtrend. R (stop-loss sizing unit) is ATR(ATRPeriod) at the    |
//| signal bar, replacing the BB-touch models' candle-body R since there is   |
//| no body-size signal here.                                                 |
//|                                                                            |
//| EXIT: same ProtectStop/TrailingStop/TrailingTP architecture ported from    |
//| 001/010-013, but with WIDER first-guess trigger/distance values than the   |
//| fade models' ultra-tight ones (TrailStopTriggerR=0.4/TrailStopDistanceR=   |
//| 0.25, TrailTPTriggerR=1.0/TrailTPDistanceR=0.3) -- today's diagnostic on    |
//| 012's WICK_TREND fork found fade-tuned tight trailing (0.09/0.05) was      |
//| capping trend trades under 0.5R before they could develop; this starts     |
//| from a deliberately looser profile instead of reusing those values          |
//| unchanged. SL_R=1.0/TP_R=2.0 for a nominal 2:1 target.                      |
//|                                                                             |
//| ALL OF THIS IS A FIRST-PASS GUESS, COMPLETELY UNTESTED. Nothing here is    |
//| confirmed -- it is a starting point to react to once real backtest         |
//| numbers come back, same as every other _test fork this session.            |
//|                                                                             |
//| FIRST BACKTEST (2026-11-21, REJECTED as-is): bare "low<=ema"/"high>=ema"    |
//| touch condition was far too loose -- 12,443 trades over the test window     |
//| (129,971 M5 bars, i.e. ~9.6% of ALL bars fired a signal), NET -$10,377.51,  |
//| PF 0.932612 (losing), DD 15.94%, payoff ratio 0.37:1 (avg win $15.59 vs     |
//| avg loss -$41.89). An EMA graze on M5 is just normal price noise, not a     |
//| real pullback. Added MinPullbackDepthR/MinReclaimR to require a minimum     |
//| penetration past the EMA and a minimum reclaim margin, in ATR(R) units --   |
//| untested, first guess at fixing the selectivity problem before judging      |
//| the core thesis.                                                            |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M5; // signal-candle timeframe (pullback detected here)
input double Lots                 = 0.1; // Lot size
input int    TrendEMAPeriod       = 50;  // H1 EMA period deciding trend direction (TEST, untested)
input int    PullbackEMAPeriod    = 20;  // Signal-timeframe EMA period the pullback dips through (TEST, untested)
input int    ATRPeriod            = 14;  // ATR period on signal timeframe, used as R (stop-loss sizing unit) (TEST, untested)
input double MinPullbackDepthR    = 0.3; // TEST: minimum penetration past the pullback EMA, in R (ATR) units -- rejects shallow EMA grazes, added after a too-frequent/no-edge first pass (12,443 trades, PF 0.93)
input double MinReclaimR          = 0.1; // TEST: minimum close distance back past the pullback EMA, in R units -- rejects weak reclaims
input double SL_R                 = 1.0;  // Stop loss (R, in ATR units) (TEST, untested)
input double TP_R                 = 2.0; // Take profit (R) -- structurally inert once UseTrailingTP arms (TEST, untested, nominal 2:1 target)
input ulong  MagicNumber          = 95016200; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

input int    SkipHourStartKST     = 14; // KST hour skip window start (TEST, untested on this signal, default off)
input int    SkipHourEndKST       = 16; // KST hour skip window end, exclusive
input bool   SkipHourEntryKST     = false; // Block entries in [SkipHourStartKST,SkipHourEndKST) KST (TEST: off by default, untested)

input double MildZoneR            = 2.0;  // Adverse-R boundary for dwell-time diagnostic (no trading effect)

input double ProtectTriggerR      = 0.3; // Favorable R to arm protect-lock stop (TEST, untested first guess)
input double ProtectR             = 0.1; // SL level once armed, in R (TEST, untested first guess)
input bool   UseProtectStop       = true; // Move SL to ProtectR once armed (TEST, untested first guess)

input bool   UseTrailingStop      = true; // Continuously trail SL behind price once armed (TEST, untested first guess)
input double TrailStopTriggerR    = 0.4; // Favorable R to arm the trailing stop (TEST: much later than the BB-touch models' 0.09, gives a trend trade room before trailing starts)
input double TrailStopDistanceR   = 0.25; // Distance maintained between price and the trailing SL, in R (TEST: much wider than the BB-touch models' 0.05)
input bool   UseTrailingTP        = true; // Once price reaches TrailTPTriggerR, widen the broker TP and trail SL instead (TEST, untested first guess)
input double TrailTPTriggerR      = 1.0; // Favorable R to arm the trailing TP -- must be strictly less than TP_R or the broker's own TP fires first (TEST: arms after the nominal 1R mark)
input double TrailTPDistanceR     = 0.3; // Distance maintained between price and the trailing SL once UseTrailingTP arms, in R (TEST: wide, avoids choking a trending move)

int hTrendEMA=INVALID_HANDLE,hPullbackEMA=INVALID_HANDLE,hATR=INVALID_HANDLE;
datetime last_bar=0;
int f_log=INVALID_HANDLE;

#define TRACK_SLOTS 4
ulong    g_trackTicket[TRACK_SLOTS];
double   g_trackEntry[TRACK_SLOTS], g_trackR[TRACK_SLOTS];
int      g_trackDir[TRACK_SLOTS];
string   g_trackTag[TRACK_SLOTS];
datetime g_trackLastSample[TRACK_SLOTS];
double   g_timeMildMin[TRACK_SLOTS], g_timeDangerMin[TRACK_SLOTS];
bool     g_protectTriggered[TRACK_SLOTS];
bool     g_protectMoved[TRACK_SLOTS];
double   g_trailStopLevel[TRACK_SLOTS];
bool     g_trailTPArmed[TRACK_SLOTS];
double   g_trailTPStopLevel[TRACK_SLOTS];

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
   g_trackLastSample[i]=TimeCurrent(); g_timeMildMin[i]=0; g_timeDangerMin[i]=0;
   g_protectTriggered[i]=false; g_protectMoved[i]=false;
   g_trailStopLevel[i]=0; g_trailTPArmed[i]=false; g_trailTPStopLevel[i]=0;
}

void AdoptOrphanPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(FindTrackSlot(tk)>=0) continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      if(sl<=0 || SL_R<=0) continue;
      double R=MathAbs(entry-sl)/SL_R;
      if(R<=0) continue;

      StartMAETracking(tk,entry,R,dir,"ADOPTED_ORPHAN");
      Log("ORPHAN_ADOPTED","ticket="+IntegerToString((int)tk)+" entry="+DoubleToString(entry,_Digits)+
          " R="+DoubleToString(R,_Digits)+" dir="+(dir==1?"BUY":"SELL"));
   }
}

void CheckMAEProgress()
{
   AdoptOrphanPositions();
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue;
      double adverseR=(g_trackDir[i]==+1) ? (g_trackEntry[i]-q.bid)/g_trackR[i] : (q.ask-g_trackEntry[i])/g_trackR[i];

      datetime now=TimeCurrent();
      double elapsedMin=(double)(now-g_trackLastSample[i])/60.0;
      if(elapsedMin>0)
      {
         if(adverseR<MildZoneR) g_timeMildMin[i]+=elapsedMin;
         else                   g_timeDangerMin[i]+=elapsedMin;
         g_trackLastSample[i]=now;
      }

      double favR=(g_trackDir[i]==+1) ? (q.bid-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-q.ask)/g_trackR[i];
      if(!g_protectTriggered[i] && favR>=ProtectTriggerR)
      {
         g_protectTriggered[i]=true;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
         if(UseProtectStop)
         {
            double curTP=PositionGetDouble(POSITION_TP);
            double lock=NormalizeDouble(g_trackEntry[i]+g_trackDir[i]*ProtectR*g_trackR[i],_Digits);
            double curSLforProtect=PositionGetDouble(POSITION_SL);
            if(g_trailStopLevel[i]>0) curSLforProtect=(g_trackDir[i]==+1 ? MathMax(curSLforProtect,g_trailStopLevel[i]) : MathMin(curSLforProtect,g_trailStopLevel[i]));
            if(g_trailTPStopLevel[i]>0) curSLforProtect=(g_trackDir[i]==+1 ? MathMax(curSLforProtect,g_trailTPStopLevel[i]) : MathMin(curSLforProtect,g_trailTPStopLevel[i]));
            bool protectImproves=(curSLforProtect==0) || (g_trackDir[i]==+1 ? lock>curSLforProtect : lock<curSLforProtect);
            if(!protectImproves)
               Log("PROTECT_SKIPPED_WORSE","lock="+DoubleToString(lock,_Digits)+" curSL="+DoubleToString(curSLforProtect,_Digits)+" (trailing already ahead) | "+g_trackTag[i]);
            else if(!EnableLiveOrders)
               Log("PROTECT_MOVE_DRY","would move SL->"+DoubleToString(lock,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],lock,curTP))
            {
               g_protectMoved[i]=true;
               Log("PROTECT_MOVED","SL->"+DoubleToString(lock,_Digits)+" | "+g_trackTag[i]);
            }
            else
               Log("PROTECT_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }

      if(UseTrailingStop && favR>=TrailStopTriggerR)
      {
         double curPrice=(g_trackDir[i]==+1)?q.bid:q.ask;
         double effDist1=TrailStopDistanceR*g_trackR[i];
         double candidateSL=NormalizeDouble(curPrice-g_trackDir[i]*effDist1,_Digits);
         double curSL=PositionGetDouble(POSITION_SL);
         if(g_trailStopLevel[i]>0) curSL=(g_trackDir[i]==+1 ? MathMax(curSL,g_trailStopLevel[i]) : MathMin(curSL,g_trailStopLevel[i]));
         bool improves=(curSL==0) || (g_trackDir[i]==+1 ? candidateSL>curSL : candidateSL<curSL);
         if(improves)
         {
            double cushion=MinStopDistance()+_Point;
            double sl=candidateSL;
            if(g_trackDir[i]==+1){ if(sl>q.bid-cushion) sl=q.bid-cushion; }
            else                 { if(sl<q.ask+cushion) sl=q.ask+cushion; }
            sl=NormalizeDouble(sl,_Digits);
            double curTPforTrail=PositionGetDouble(POSITION_TP);
            if(!EnableLiveOrders)
               Log("TRAIL_STOP_DRY","would move SL->"+DoubleToString(sl,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],sl,curTPforTrail))
            {
               g_trailStopLevel[i]=sl;
               Log("TRAIL_STOP_MOVED","SL->"+DoubleToString(sl,_Digits)+" favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
            }
            else
               Log("TRAIL_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }

      if(UseTrailingTP)
      {
         if(!g_trailTPArmed[i] && favR>=TrailTPTriggerR)
         {
            double curSLforArm=PositionGetDouble(POSITION_SL);
            if(!EnableLiveOrders)
            {
               g_trailTPArmed[i]=true;
               Log("TRAIL_TP_ARM_DRY","would widen TP and start trailing (EnableLiveOrders=false) | "+g_trackTag[i]);
            }
            else if(trade.PositionModify(g_trackTicket[i],curSLforArm,0.0))
            {
               g_trailTPArmed[i]=true;
               Log("TRAIL_TP_ARMED","TP removed, now trailing | favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
            }
            else
               Log("TRAIL_TP_ARM_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }

         if(g_trailTPArmed[i])
         {
            double curPriceTP=(g_trackDir[i]==+1)?q.bid:q.ask;
            double effDist2=TrailTPDistanceR*g_trackR[i];
            double candidateSL2=NormalizeDouble(curPriceTP-g_trackDir[i]*effDist2,_Digits);
            double curSL2=PositionGetDouble(POSITION_SL);
            if(g_trailTPStopLevel[i]>0) curSL2=(g_trackDir[i]==+1 ? MathMax(curSL2,g_trailTPStopLevel[i]) : MathMin(curSL2,g_trailTPStopLevel[i]));
            bool improves2=(curSL2==0) || (g_trackDir[i]==+1 ? candidateSL2>curSL2 : candidateSL2<curSL2);
            if(improves2)
            {
               double cushion2=MinStopDistance()+_Point;
               double sl2=candidateSL2;
               if(g_trackDir[i]==+1){ if(sl2>q.bid-cushion2) sl2=q.bid-cushion2; }
               else                 { if(sl2<q.ask+cushion2) sl2=q.ask+cushion2; }
               sl2=NormalizeDouble(sl2,_Digits);
               if(!EnableLiveOrders)
                  Log("TRAIL_TP_STOP_DRY","would move SL->"+DoubleToString(sl2,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
               else if(trade.PositionModify(g_trackTicket[i],sl2,0.0))
               {
                  g_trailTPStopLevel[i]=sl2;
                  Log("TRAIL_TP_STOP_MOVED","SL->"+DoubleToString(sl2,_Digits)+" favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
               }
               else
                  Log("TRAIL_TP_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M5_PULLBACKTREND_test | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

datetime LastSundayOfMonth(int year,int month,int daysInMonth)
{
   MqlDateTime dt; dt.year=year; dt.mon=month; dt.day=daysInMonth;
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime d=StructToTime(dt);
   MqlDateTime cur; TimeToStruct(d,cur);
   d-=cur.day_of_week*86400;
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

void OpenTrade(int dir,double R,string tag)
{
   if(CountOurPositions()>0){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }
   int kstHour=KST_Hour(TimeCurrent());
   bool inSkipHour=(kstHour>=SkipHourStartKST && kstHour<SkipHourEndKST);
   if(inSkipHour && SkipHourEntryKST)
   {
      Log("ENTRY_SKIPPED","KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+") by SkipHourEntryKST=true");
      return;
   }
   tag="PBT_"+tag;

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
      ulong posId=0;
      ulong orderTicket=trade.ResultOrder();
      if(orderTicket!=0 && PositionSelectByTicket(orderTicket)) posId=orderTicket;
      if(posId==0)
      {
         ulong dealTicket=trade.ResultDeal();
         if(dealTicket!=0 && HistoryDealSelect(dealTicket))
         {
            ulong pid=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
            if(pid!=0 && PositionSelectByTicket(pid)) posId=pid;
         }
      }
      if(posId!=0)
         StartMAETracking(posId,ref,R,dir,tag);
      else
      {
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
}

void CheckNewBar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_bar) return;
   last_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   // H1 trend direction: EMA(TrendEMAPeriod) vs H1 close, last CLOSED H1 bar.
   double h1ema[1];
   if(CopyBuffer(hTrendEMA,0,1,1,h1ema)!=1){ Log("H1EMA_FAIL","no H1 EMA value"); return; }
   double h1Close1=iClose(_Symbol,PERIOD_H1,1);
   if(h1Close1==0){ Log("H1_DATA_FAIL","no H1 close"); return; }
   bool trendUp=(h1Close1>h1ema[0]);
   bool trendDown=(h1Close1<h1ema[0]);
   if(!trendUp && !trendDown) return; // exactly flat, skip

   // Pullback-EMA on the signal timeframe, at the signal bar.
   double pbEma[1];
   if(CopyBuffer(hPullbackEMA,0,1,1,pbEma)!=1){ Log("PBEMA_FAIL","no pullback EMA value"); return; }
   double emaVal=pbEma[0];

   double atrBuf[1];
   if(CopyBuffer(hATR,0,1,1,atrBuf)!=1){ Log("ATR_FAIL","no ATR value"); return; }
   double R=atrBuf[0];
   if(R<=0){ Log("SIGNAL_SKIPPED","ATR<=0"); return; }

   int dir=0; string tag="";
   if(trendUp)
   {
      bool pulledBack=(emaVal-l)>=MinPullbackDepthR*R;
      bool reclaimed=(c-emaVal)>=MinReclaimR*R && (c>o);
      if(pulledBack && reclaimed){ dir=+1; tag="PULLBACK_TREND_BULL"; }
   }
   else // trendDown
   {
      bool pulledBack=(h-emaVal)>=MinPullbackDepthR*R;
      bool reclaimed=(emaVal-c)>=MinReclaimR*R && (c<o);
      if(pulledBack && reclaimed){ dir=-1; tag="PULLBACK_TREND_BEAR"; }
   }
   if(dir==0) return;

   Log("SIGNAL","H1 trend="+(trendUp?"UP":"DOWN")+" | R(ATR)="+DoubleToString(R,_Digits)+
       " ema="+DoubleToString(emaVal,_Digits)+" | decided dir="+(dir==1?"BUY":"SELL")+" | "+tag);
   OpenTrade(dir,R,tag);
}

int OnInit()
{
   hTrendEMA   =iMA(_Symbol,PERIOD_H1,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   hPullbackEMA=iMA(_Symbol,Timeframe,PullbackEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   hATR        =iATR(_Symbol,Timeframe,ATRPeriod);
   if(hTrendEMA==INVALID_HANDLE || hPullbackEMA==INVALID_HANDLE || hATR==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M5_PULLBACKTREND_test_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | TrendEMAPeriod="+IntegerToString(TrendEMAPeriod)+
       " PullbackEMAPeriod="+IntegerToString(PullbackEMAPeriod)+" ATRPeriod="+IntegerToString(ATRPeriod)+
       " MinPullbackDepthR="+DoubleToString(MinPullbackDepthR,2)+" MinReclaimR="+DoubleToString(MinReclaimR,2)+
       " | SL_R="+DoubleToString(SL_R,2)+" TP_R="+DoubleToString(TP_R,2)+
       " | SkipHourStartKST="+IntegerToString(SkipHourStartKST)+" SkipHourEndKST="+IntegerToString(SkipHourEndKST)+
       " SkipHourEntryKST="+(SkipHourEntryKST?"true":"false")+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+
       " | UseTrailingStop="+(UseTrailingStop?"true":"false")+" TrailStopTriggerR="+DoubleToString(TrailStopTriggerR,2)+
       " TrailStopDistanceR="+DoubleToString(TrailStopDistanceR,2)+
       " | UseTrailingTP="+(UseTrailingTP?"true":"false")+" TrailTPTriggerR="+DoubleToString(TrailTPTriggerR,2)+
       " TrailTPDistanceR="+DoubleToString(TrailTPDistanceR,2)+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hTrendEMA!=INVALID_HANDLE)    IndicatorRelease(hTrendEMA);
   if(hPullbackEMA!=INVALID_HANDLE) IndicatorRelease(hPullbackEMA);
   if(hATR!=INVALID_HANDLE)         IndicatorRelease(hATR);
}

double SumPositionProfit(ulong posId)
{
   double sum=0;
   if(HistorySelectByPosition(posId))
   {
      int total=HistoryDealsTotal();
      for(int d=0;d<total;d++)
      {
         ulong dealTicket=HistoryDealGetTicket(d);
         if(dealTicket==0) continue;
         sum+=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
              HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
      }
   }
   return sum;
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
   if(i<0) return;

   double profit=SumPositionProfit(posId);
   string outcome=(profit>0?"WIN":"LOSS");
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " timeMildMin="+DoubleToString(g_timeMildMin[i],1)+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
       " protectTriggered="+(g_protectTriggered[i]?"true":"false")+
       " protectMoved="+(g_protectMoved[i]?"true":"false")+
       " trailStopLevel="+DoubleToString(g_trailStopLevel[i],_Digits)+
       " trailTPArmed="+(g_trailTPArmed[i]?"true":"false")+
       " trailTPStopLevel="+DoubleToString(g_trailTPStopLevel[i],_Digits)+
       " | "+g_trackTag[i]);
   g_trackTicket[i]=0;
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckNewBar();
}
