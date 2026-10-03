//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_008_SSANGBI.mq5                                    |
//| Mechanical "쌍비" (double-bottom/double-top) entry strategy, first  |
//| from a discretionary gold-trading reference document reviewed      |
//| this project (주노짜앙/지킬 공통분석), now redesigned (v3) after a    |
//| TradingView Pine Script reference ("W/M REVERSAL + MULTI BB + 1M   |
//| SSANGBI PRESET") the user shared turned up two structural gaps in   |
//| v1/v2. Standalone entry signal -- not a filter/exit bolted onto     |
//| 001's existing BB20+BB4 trend/fade logic.                           |
//|                                                                     |
//| v1 (fixed points): n=6,773, WR 37.47%, NET -$12,477.64, PF 0.876,   |
//| MaxDD $12,744.30. REJECTED -- root cause: gold moved ~$2,600 to     |
//| ~$4,100 (+58%) over the backtest window, so fixed-point thresholds  |
//| were badly miscalibrated; the SL floor also dominated almost every  |
//| trade, so the intended "tight structural stop" never actually       |
//| governed sizing.                                                    |
//| v2 (ATR-relative sizing, same shape logic as v1): never backtested  |
//| separately -- superseded by v3 below once the reference script      |
//| revealed the shape logic itself (not just the sizing) was wrong.    |
//|                                                                     |
//| What the reference script does differently, now adopted here:       |
//|  1. TOUCH 1/2 must be genuine PIVOT lows/highs (price strictly       |
//|     below/above PivotLeft bars before AND PivotRight bars after),   |
//|     not just "any bar whose low/high crossed a band" -- v1/v2       |
//|     treated ordinary noise wiggles as touches.                      |
//|  2. CONFIRMATION requires a NECKLINE BREAK: the high (for a W) or    |
//|     low (for an M) BETWEEN the two pivots must be broken by a       |
//|     later close, not just "the second-touch bar itself closed in    |
//|     the reversal direction" -- v1/v2 entered on a guess, not a       |
//|     confirmed break. This was almost certainly the main missing      |
//|     ingredient behind v1's 37% WR.                                   |
//| Kept from this project's own design (the reference script doesn't   |
//| anchor to a band or use Stochastic at all): pivot 1 must still sit   |
//| at/beyond the BB20 band (the "매물대" anchor the source document      |
//| emphasizes), and Stochastic must be oversold/overbought AT pivot 2   |
//| (combining the band/structure condition with the momentum           |
//| condition, per this project's own earlier design choice).           |
//|                                                                      |
//| Mechanical definition (v3):                                          |
//|  1. PIVOT 1: a confirmed pivot low (PivotLeft/PivotRight bars) at or  |
//|     beyond the BB20 lower band (buy) / pivot high at or beyond the    |
//|     BB20 upper band (sell). Start tracking the "live neckline" = the  |
//|     highest high (buy) / lowest low (sell) seen since pivot 1.        |
//|  2. PIVOT 2: a second confirmed pivot low/high, occurring             |
//|     MinPatternBars-MaxPatternBars after pivot 1, within               |
//|     ToleranceATR*ATR of pivot 1's price, AND with Stochastic          |
//|     oversold/overbought at that bar. The neckline freezes at          |
//|     whatever the live neckline reached by then.                       |
//|  3. CONFIRMATION: within MaxConfirmBars after pivot 2, price must      |
//|     CLOSE back through the frozen neckline (above it for a buy,       |
//|     below it for a sell) -- that close is the entry trigger.          |
//|     Invalidated if price closes beyond pivot 1's own extreme first    |
//|     (support/resistance failed) or the window times out.              |
//|  4. ENTRY: at market, right after the confirming bar closes.          |
//|  5. STOP: beyond the tighter of pivot 1/pivot 2's own extreme, minus   |
//|     SLBufferATR*ATR further, floored at MinStopATR*ATR. TARGET:       |
//|     TP_R multiple of that stop distance (R=|entry-SL|).               |
//|                                                                      |
//| Diagnostic fields in MAE_OUTCOME (gapATR, rawR_ATR, flooredR_ATR,    |
//| barsPivot1ToPivot2, barsPivot2ToConfirm) for bucketed tuning.         |
//|                                                                      |
//| v3 RESULT: n=989, WR 40.85%, NET $3,967.74, PF 1.078, MaxDD          |
//| $4,073.53 -- the neckline-break fix flipped this from a clear loser  |
//| (v1: NET -$12,477.64) to a thin net winner, confirming that was the  |
//| main missing piece. Still far short of the reference document's      |
//| claimed high manual win rate, and Recovery Factor <1 (MaxDD > NET)   |
//| means it's fragile. Bucketing the diagnostics found 3 sub-ranges     |
//| that carry nearly all the profit: gapATR 0.1-0.2 (a small but        |
//| non-trivial difference between the two pivots -- NEAR-EXACT matches  |
//| <0.1 ATR apart were net NEGATIVE, -$4,412 over 343 trades, maybe      |
//| just chop rather than a real structure), barsP1toP2>=5 (very fast    |
//| double-touches <5 bars apart were net NEGATIVE, -$2,705 over 446     |
//| trades), and barsP2toConfirm>=4 (neckline breaks confirmed within    |
//| 2-3 bars of pivot 2 were net NEGATIVE, -$1,522 over 117 trades --     |
//| likely whipsaws/false breaks rather than genuine follow-through).    |
//| Applying all three as a post-hoc filter on the SAME v3 data (so this  |
//| is an in-sample estimate, not yet forward-validated) gave n=356, WR   |
//| 43.82%, NET $7,970.16 (+101% vs unfiltered), PF 1.393. MinGapATR,     |
//| the MinPatternBars default (3->5), and MinBarsToConfirm below         |
//| implement these three findings as actual entry gates for a proper    |
//| ground-truth backtest, not just a retroactive filter.                 |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M2; // signal timeframe
input double Lots                 = 0.1; // Lot size
input int    BBPeriod             = 20; // Bollinger Bands period (the "매물대" band)
input double BBDev                = 2.0; // Bollinger Bands deviation
input int    StochK_Period        = 8; // Stoch %K period
input int    StochD_Period        = 3; // Stoch %D period
input int    StochSlowing         = 3; // Stoch slowing
input double StochOverbought      = 70.0; // Stoch overbought level (pivot-2 condition for sell)
input double StochOversold        = 30.0; // Stoch oversold level (pivot-2 condition for buy)
input int    ATRPeriod            = 14; // ATR period used to scale every distance threshold below
input int    PivotLeft            = 2; // Bars before the pivot that must be less extreme (ported from reference preset)
input int    PivotRight           = 1; // Bars after the pivot that must be less extreme (ported from reference preset)
input int    MinPatternBars       = 5; // Min bars between pivot 1 and pivot 2 (CONFIRMED from v3 bucketing, see header)
input int    MaxPatternBars       = 25; // Max bars between pivot 1 and pivot 2
input double ToleranceATR         = 0.40; // Max distance between pivot 1 and pivot 2 extremes, as ATR multiple
input double MinGapATR            = 0.10; // Min distance between pivot 1 and pivot 2 extremes, as ATR multiple (CONFIRMED from v3 bucketing, see header)
input double BandAnchorATR        = 0.50; // Max distance pivot 1 may sit short of the BB20 band, as ATR multiple (0=must touch/pierce exactly)
input int    MaxConfirmBars       = 20; // Max bars after pivot 2 to wait for the neckline break
input int    MinBarsToConfirm     = 4; // Min bars after pivot 2 before a neckline break is accepted (CONFIRMED from v3 bucketing, see header)
input double NecklineBreakBufferATR = 0.0; // Extra buffer beyond the neckline required for a break, as ATR multiple
input double SLBufferATR          = 0.3; // Extra buffer beyond pivot 1/2's tighter extreme for the stop, as ATR multiple
input double TP_R                 = 1.5; // Take profit as a multiple of the stop distance (R)
input double MinStopATR           = 1.0; // Floor on the stop distance, as ATR multiple, 0=no floor
input ulong  MagicNumber          = 95016108; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

int hBB=INVALID_HANDLE, hStoch=INVALID_HANDLE, hATR=INVALID_HANDLE;
datetime last_bar=0;
int f_log=INVALID_HANDLE;

// -- buy (double-bottom / "W") setup state machine --
// stage: 0=waiting for pivot1, 1=waiting for pivot2, 2=waiting for neckline break
int    g_buyStage=0;
double g_buyPivot1=0, g_buyPivot2=0, g_buyNeckline=0;
int    g_buyPivot1Bar=0, g_buyPivot2Bar=0; // bar_index-equivalent counters (ever-increasing tick of new bars)
int    g_buyBarsSincePivot1=0, g_buyBarsSincePivot2=0;

// -- sell (double-top / "M") setup state machine --
int    g_sellStage=0;
double g_sellPivot1=0, g_sellPivot2=0, g_sellNeckline=0;
int    g_sellPivot1Bar=0, g_sellPivot2Bar=0;
int    g_sellBarsSincePivot1=0, g_sellBarsSincePivot2=0;

int    g_barCounter=0; // increments once per new bar, used as a simple bar-index clock

// -- outcome tracking (one in-flight position at a time, own-Magic MAX1) --
ulong  g_trackTicket=0;
double g_trackEntry=0, g_trackR=0;
double g_trackGapATR=0, g_trackRawR_ATR=0, g_trackFlooredR_ATR=0;
int    g_trackBarsP1toP2=0, g_trackBarsP2toConfirm=0;
int    g_trackDir=0;
string g_trackTag="";

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_008_SSANGBI | ",event," | ",detail);
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

void ResetBuySetup(){ g_buyStage=0; g_buyPivot1=0; g_buyPivot2=0; g_buyNeckline=0; g_buyBarsSincePivot1=0; g_buyBarsSincePivot2=0; }
void ResetSellSetup(){ g_sellStage=0; g_sellPivot1=0; g_sellPivot2=0; g_sellNeckline=0; g_sellBarsSincePivot1=0; g_sellBarsSincePivot2=0; }

// Confirmed pivot low/high at shift = PivotRight+1 relative to the bar that just closed
// (shift 1 in iLow/iHigh terms) -- needs PivotRight bars after it (shifts 1..PivotRight)
// and PivotLeft bars before it (shifts PivotRight+2..PivotRight+1+PivotLeft) to be confirmed.
bool IsPivotLow(double &outLow)
{
   int pivotShift=1+PivotRight;
   double val=iLow(_Symbol,Timeframe,pivotShift);
   for(int k=1;k<=PivotRight;k++) if(iLow(_Symbol,Timeframe,pivotShift-k)<val) return false;
   for(int k=1;k<=PivotLeft;k++)  if(iLow(_Symbol,Timeframe,pivotShift+k)<val) return false;
   outLow=val;
   return true;
}

bool IsPivotHigh(double &outHigh)
{
   int pivotShift=1+PivotRight;
   double val=iHigh(_Symbol,Timeframe,pivotShift);
   for(int k=1;k<=PivotRight;k++) if(iHigh(_Symbol,Timeframe,pivotShift-k)>val) return false;
   for(int k=1;k<=PivotLeft;k++)  if(iHigh(_Symbol,Timeframe,pivotShift+k)>val) return false;
   outHigh=val;
   return true;
}

void OpenTrade(int dir,double sl,double atr,double gapATR,int barsP1toP2,int barsP2toConfirm,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double R=MathAbs(ref-sl);
   double rawR_ATR=(atr>0) ? R/atr : 0;
   if(MinStopATR>0 && atr>0 && R<MinStopATR*atr)
   {
      double need=MinStopATR*atr-R;
      sl=sl-dir*need;
      R=MathAbs(ref-sl);
   }
   double flooredR_ATR=(atr>0) ? R/atr : 0;
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
   R=MathAbs(ref-sl);

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
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+" ATR="+DoubleToString(atr,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
         g_trackTicket=tk; g_trackEntry=ref; g_trackR=R; g_trackDir=dir; g_trackTag=tag;
         g_trackGapATR=gapATR; g_trackRawR_ATR=rawR_ATR; g_trackFlooredR_ATR=flooredR_ATR;
         g_trackBarsP1toP2=barsP1toP2; g_trackBarsP2toConfirm=barsP2toConfirm;
         break;
      }
   }
}

void CheckNewBar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_bar) return;
   last_bar=t;
   g_barCounter++;

   double o=iOpen(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);

   double upper[1],lower[1];
   if(CopyBuffer(hBB,1,1,1,upper)!=1 || CopyBuffer(hBB,2,1,1,lower)!=1)
   { Log("COPYBUFFER_FAIL","BB bands"); return; }

   double kbuf[1];
   if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
   double stochK=kbuf[0];

   double atrbuf[1];
   if(CopyBuffer(hATR,0,1,1,atrbuf)!=1){ Log("ATR_FAIL","no ATR value"); return; }
   double atr=atrbuf[0];
   if(atr<=0) return;

   bool haveOpenPos=HasOurPosition();

   double pivLow, pivHigh;
   bool gotPivotLow=IsPivotLow(pivLow);
   bool gotPivotHigh=IsPivotHigh(pivHigh);
   // the confirmed pivot bar is PivotRight+1 bars back from the one that just closed
   int pivotBarIndex=g_barCounter-PivotRight;

   // ============================= BUY (W) =============================
   if(g_buyStage==0)
   {
      if(gotPivotLow && pivLow<=lower[0]+BandAnchorATR*atr)
      {
         g_buyStage=1; g_buyPivot1=pivLow; g_buyPivot1Bar=pivotBarIndex;
         g_buyNeckline=iHigh(_Symbol,Timeframe,1); g_buyBarsSincePivot1=0;
         Log("SSANGBI_PIVOT1_BUY","low="+DoubleToString(pivLow,_Digits)+" lowerBB="+DoubleToString(lower[0],_Digits));
      }
   }
   else if(g_buyStage==1)
   {
      g_buyBarsSincePivot1=g_barCounter-g_buyPivot1Bar;
      if(iHigh(_Symbol,Timeframe,1)>g_buyNeckline) g_buyNeckline=iHigh(_Symbol,Timeframe,1);

      if(g_buyBarsSincePivot1>MaxPatternBars){ Log("SSANGBI_EXPIRE_BUY","no pivot2 within MaxPatternBars"); ResetBuySetup(); }
      else if(gotPivotLow && pivLow<g_buyPivot1 && (g_barCounter-PivotRight)<=g_buyPivot1Bar+MaxPatternBars)
      {
         // a new, more extreme low before pivot2 forms -- rebase pivot1 to it
         g_buyPivot1=pivLow; g_buyPivot1Bar=pivotBarIndex; g_buyBarsSincePivot1=0;
         g_buyNeckline=iHigh(_Symbol,Timeframe,1);
      }
      else if(gotPivotLow && g_buyBarsSincePivot1>=MinPatternBars &&
              MathAbs(pivLow-g_buyPivot1)>=MinGapATR*atr && MathAbs(pivLow-g_buyPivot1)<=ToleranceATR*atr && pivotBarIndex>g_buyPivot1Bar)
      {
         bool stochOk=(stochK<=StochOversold);
         if(stochOk)
         {
            g_buyPivot2=pivLow; g_buyPivot2Bar=pivotBarIndex; g_buyBarsSincePivot2=0; g_buyStage=2;
            Log("SSANGBI_PIVOT2_BUY","pivot1="+DoubleToString(g_buyPivot1,_Digits)+" pivot2="+DoubleToString(g_buyPivot2,_Digits)+
                " neckline="+DoubleToString(g_buyNeckline,_Digits)+" stochK="+DoubleToString(stochK,2)+
                " barsP1toP2="+IntegerToString(g_buyPivot2Bar-g_buyPivot1Bar));
         }
      }
   }
   else if(g_buyStage==2)
   {
      g_buyBarsSincePivot2=g_barCounter-g_buyPivot2Bar;
      bool invalid=(c<g_buyPivot1-ToleranceATR*atr);
      bool timeout=(g_buyBarsSincePivot2>MaxConfirmBars);
      bool brokeNeckline=(c>g_buyNeckline+NecklineBreakBufferATR*atr);

      if(invalid || timeout)
      {
         Log("SSANGBI_EXPIRE_BUY",(invalid?"support broken":"neckline break timeout"));
         ResetBuySetup();
      }
      else if(brokeNeckline && g_buyBarsSincePivot2>=MinBarsToConfirm)
      {
         double gapATR=MathAbs(g_buyPivot2-g_buyPivot1)/atr;
         int barsP1toP2=g_buyPivot2Bar-g_buyPivot1Bar;
         int barsP2toConfirm=g_buyBarsSincePivot2;
         Log("SSANGBI_NECKBREAK_BUY","neckline="+DoubleToString(g_buyNeckline,_Digits)+
             " close="+DoubleToString(c,_Digits)+" gapATR="+DoubleToString(gapATR,2));
         if(!haveOpenPos)
         {
            double sl=MathMin(g_buyPivot1,g_buyPivot2)-SLBufferATR*atr;
            OpenTrade(+1,sl,atr,gapATR,barsP1toP2,barsP2toConfirm,"SSANGBI_BUY");
         }
         else
            Log("ENTRY_SKIPPED","SSANGBI_BUY neckline break but position already open");
         ResetBuySetup();
      }
   }

   // ============================= SELL (M) =============================
   if(g_sellStage==0)
   {
      if(gotPivotHigh && pivHigh>=upper[0]-BandAnchorATR*atr)
      {
         g_sellStage=1; g_sellPivot1=pivHigh; g_sellPivot1Bar=pivotBarIndex;
         g_sellNeckline=iLow(_Symbol,Timeframe,1); g_sellBarsSincePivot1=0;
         Log("SSANGBI_PIVOT1_SELL","high="+DoubleToString(pivHigh,_Digits)+" upperBB="+DoubleToString(upper[0],_Digits));
      }
   }
   else if(g_sellStage==1)
   {
      g_sellBarsSincePivot1=g_barCounter-g_sellPivot1Bar;
      if(iLow(_Symbol,Timeframe,1)<g_sellNeckline) g_sellNeckline=iLow(_Symbol,Timeframe,1);

      if(g_sellBarsSincePivot1>MaxPatternBars){ Log("SSANGBI_EXPIRE_SELL","no pivot2 within MaxPatternBars"); ResetSellSetup(); }
      else if(gotPivotHigh && pivHigh>g_sellPivot1 && (g_barCounter-PivotRight)<=g_sellPivot1Bar+MaxPatternBars)
      {
         g_sellPivot1=pivHigh; g_sellPivot1Bar=pivotBarIndex; g_sellBarsSincePivot1=0;
         g_sellNeckline=iLow(_Symbol,Timeframe,1);
      }
      else if(gotPivotHigh && g_sellBarsSincePivot1>=MinPatternBars &&
              MathAbs(pivHigh-g_sellPivot1)>=MinGapATR*atr && MathAbs(pivHigh-g_sellPivot1)<=ToleranceATR*atr && pivotBarIndex>g_sellPivot1Bar)
      {
         bool stochOk=(stochK>=StochOverbought);
         if(stochOk)
         {
            g_sellPivot2=pivHigh; g_sellPivot2Bar=pivotBarIndex; g_sellBarsSincePivot2=0; g_sellStage=2;
            Log("SSANGBI_PIVOT2_SELL","pivot1="+DoubleToString(g_sellPivot1,_Digits)+" pivot2="+DoubleToString(g_sellPivot2,_Digits)+
                " neckline="+DoubleToString(g_sellNeckline,_Digits)+" stochK="+DoubleToString(stochK,2)+
                " barsP1toP2="+IntegerToString(g_sellPivot2Bar-g_sellPivot1Bar));
         }
      }
   }
   else if(g_sellStage==2)
   {
      g_sellBarsSincePivot2=g_barCounter-g_sellPivot2Bar;
      bool invalid=(c>g_sellPivot1+ToleranceATR*atr);
      bool timeout=(g_sellBarsSincePivot2>MaxConfirmBars);
      bool brokeNeckline=(c<g_sellNeckline-NecklineBreakBufferATR*atr);

      if(invalid || timeout)
      {
         Log("SSANGBI_EXPIRE_SELL",(invalid?"resistance broken":"neckline break timeout"));
         ResetSellSetup();
      }
      else if(brokeNeckline && g_sellBarsSincePivot2>=MinBarsToConfirm)
      {
         double gapATR=MathAbs(g_sellPivot2-g_sellPivot1)/atr;
         int barsP1toP2=g_sellPivot2Bar-g_sellPivot1Bar;
         int barsP2toConfirm=g_sellBarsSincePivot2;
         Log("SSANGBI_NECKBREAK_SELL","neckline="+DoubleToString(g_sellNeckline,_Digits)+
             " close="+DoubleToString(c,_Digits)+" gapATR="+DoubleToString(gapATR,2));
         if(!haveOpenPos)
         {
            double sl=MathMax(g_sellPivot1,g_sellPivot2)+SLBufferATR*atr;
            OpenTrade(-1,sl,atr,gapATR,barsP1toP2,barsP2toConfirm,"SSANGBI_SELL");
         }
         else
            Log("ENTRY_SKIPPED","SSANGBI_SELL neckline break but position already open");
         ResetSellSetup();
      }
   }
}

int OnInit()
{
   hBB=iBands(_Symbol,Timeframe,BBPeriod,0,BBDev,PRICE_CLOSE);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_SMA,STO_LOWHIGH);
   hATR=iATR(_Symbol,Timeframe,ATRPeriod);
   if(hBB==INVALID_HANDLE || hStoch==INVALID_HANDLE || hATR==INVALID_HANDLE){ Print("Indicator handle creation failed"); return INIT_FAILED; }

   f_log=FileOpen("XAU_M2_BB_LIVE_008_SSANGBI_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE) FileSeek(f_log,0,SEEK_END);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START","TF="+EnumToString(Timeframe)+" | BB("+IntegerToString(BBPeriod)+","+DoubleToString(BBDev,1)+")"+
       " | Stoch("+IntegerToString(StochK_Period)+","+IntegerToString(StochD_Period)+","+IntegerToString(StochSlowing)+")"+
       " OB="+DoubleToString(StochOverbought,1)+" OS="+DoubleToString(StochOversold,1)+
       " | ATRPeriod="+IntegerToString(ATRPeriod)+
       " | PivotLeft="+IntegerToString(PivotLeft)+" PivotRight="+IntegerToString(PivotRight)+
       " MinPatternBars="+IntegerToString(MinPatternBars)+" MaxPatternBars="+IntegerToString(MaxPatternBars)+
       " | ToleranceATR="+DoubleToString(ToleranceATR,2)+" MinGapATR="+DoubleToString(MinGapATR,2)+
       " BandAnchorATR="+DoubleToString(BandAnchorATR,2)+
       " MaxConfirmBars="+IntegerToString(MaxConfirmBars)+" MinBarsToConfirm="+IntegerToString(MinBarsToConfirm)+
       " NecklineBreakBufferATR="+DoubleToString(NecklineBreakBufferATR,2)+
       " | SLBufferATR="+DoubleToString(SLBufferATR,2)+" TP_R="+DoubleToString(TP_R,2)+" MinStopATR="+DoubleToString(MinStopATR,2)+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB!=INVALID_HANDLE) IndicatorRelease(hBB);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
}

void OnTick()
{
   CheckNewBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(g_trackTicket==0 || posId!=g_trackTicket) return;

   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   string outcome=(profit>0?"WIN":"LOSS");
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+" R="+DoubleToString(g_trackR,_Digits)+
       " gapATR="+DoubleToString(g_trackGapATR,2)+" rawR_ATR="+DoubleToString(g_trackRawR_ATR,2)+
       " flooredR_ATR="+DoubleToString(g_trackFlooredR_ATR,2)+
       " barsP1toP2="+IntegerToString(g_trackBarsP1toP2)+" barsP2toConfirm="+IntegerToString(g_trackBarsP2toConfirm)+
       " | "+g_trackTag);
   g_trackTicket=0;
}
