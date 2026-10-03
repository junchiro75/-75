//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_008_SSANGBI.mq5                                    |
//| First mechanical attempt at "쌍비" (double-bottom/double-top at a  |
//| band level) from a discretionary gold-trading reference document   |
//| reviewed this project (주노짜앙/지킬 공통분석). Unlike every other    |
//| strategy in this project (001/005/007), this is a completely NEW,  |
//| STANDALONE entry signal -- not a filter or exit bolted onto the     |
//| existing BB20+BB4 trend/fade logic.                                 |
//|                                                                     |
//| Concept (from the reference document): "쌍비 = 매물(원비·더블비)에서  |
//| 바닥·꼭대기를 두 번 찍은 자리(W·M)를 짧게 먹는 매매" -- price touches a  |
//| band level once, bounces away, comes back to RETEST roughly the     |
//| same level a second time, and the entry is taken on that SECOND     |
//| touch's reversal confirmation, not the first.                       |
//|                                                                      |
//| v1 RESULT (REJECTED, fixed-points version): ground-truth backtest   |
//| (2025.01-2026.10) gave n=6,773, WR 37.47%, NET -$12,477.64, PF       |
//| 0.876, MaxDD $12,744.30 -- a clear loser, and WR well under 50%      |
//| suggests the raw entry condition has no edge at this granularity,    |
//| not just a sizing problem. Root cause diagnosed: the stop was        |
//| ALMOST ALWAYS exactly at the MinStopPoints floor (150pts=$1.50),     |
//| meaning the intended "tight structural stop at touch 2's own         |
//| extreme" never actually governed sizing -- and gold moved from       |
//| ~$2,600 to ~$4,100 (+58%) over the backtest window, so any FIXED     |
//| dollar/point threshold is badly miscalibrated across that range      |
//| (reasonable near $2,600, noise-level near $4,100). All thresholds    |
//| below were rewritten from fixed points to ATR(ATRPeriod) multiples   |
//| so they scale with the instrument's actual volatility regardless of  |
//| price level. This v2 is STILL UNTESTED -- the ATR multiples below    |
//| are a fresh first guess, not yet backtest-validated, and the raw     |
//| edge question (does the double-touch condition predict direction at  |
//| all) remains open regardless of sizing.                              |
//|                                                                      |
//| Mechanical definition (v2, ATR-relative):                            |
//|  1. TOUCH 1: price (bar low) pierces the BB20 LOWER band (bull/buy   |
//|     setup) or (bar high) pierces the BB20 UPPER band (bear/sell      |
//|     setup). Record that extreme as the setup's reference level.      |
//|  2. BOUNCE: within SsangbiWindowBars, price must move away from      |
//|     that extreme by >=SsangbiMinBounceATR * ATR, confirming two      |
//|     distinct legs (the W/M shape), not one continuous move.          |
//|  3. If price makes a NEW, more extreme low/high before bouncing,     |
//|     the setup re-bases to that new extreme.                          |
//|  4. TOUCH 2: after bouncing, price returns to within                 |
//|     SsangbiToleranceATR * ATR of the original extreme AND, on that   |
//|     same bar, Stochastic is oversold (buy) / overbought (sell) AND   |
//|     the bar itself closes in the reversal direction -- both the      |
//|     band-retouch condition AND the stochastic condition must hold    |
//|     together.                                                        |
//|  5. ENTRY: at market, right after that confirming bar closes.        |
//|  6. STOP: touch 2's own extreme, minus SsangbiSLBufferATR * ATR       |
//|     further, floored at MinStopATR * ATR (so the floor itself now    |
//|     scales with volatility instead of being a fixed, stale number).  |
//|     TARGET: TP_R multiple of that stop distance (R=|entry-SL|).      |
//|                                                                      |
//| Diagnostic fields added to MAE_OUTCOME this version (bounceATR,      |
//| gapATR, rawR_ATR, flooredR_ATR) so a losing/breakeven run can still   |
//| be bucketed afterward to look for any sub-range with a real edge,    |
//| rather than only being able to re-guess blindly again.                |
//|                                                                      |
//| Deliberately NOT yet implemented: no 매물대 multi-timeframe check,    |
//| no session/day filters, no 더블비(BB4) confirmation on top of BB20,   |
//| no partial exits -- keeping this isolated to the core double-touch   |
//| shape until it shows SOME edge before layering anything else on.     |
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
input double StochOverbought      = 70.0; // Stoch overbought level (sell setup's touch-2 condition)
input double StochOversold        = 30.0; // Stoch oversold level (buy setup's touch-2 condition)
input int    ATRPeriod            = 14; // ATR period used to scale every distance threshold below
input int    SsangbiWindowBars    = 15; // Max bars allowed between touch 1 and touch 2
input double SsangbiMinBounceATR  = 1.0; // Min bounce away from touch 1 before a retest counts, as ATR multiple
input double SsangbiToleranceATR  = 1.0; // Max distance between touch 1 and touch 2 extremes, as ATR multiple
input double SsangbiSLBufferATR   = 0.3; // Extra buffer beyond touch 2's own extreme for the stop, as ATR multiple
input double TP_R                 = 1.5; // Take profit as a multiple of the stop distance (R)
input double MinStopATR           = 1.0; // Floor on the stop distance, as ATR multiple, 0=no floor
input ulong  MagicNumber          = 95016108; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

int hBB=INVALID_HANDLE, hStoch=INVALID_HANDLE, hATR=INVALID_HANDLE;
datetime last_bar=0;
int f_log=INVALID_HANDLE;

// -- buy (double-bottom / "W") setup state --
bool   g_buyActive=false, g_buyBounced=false;
double g_buyTouch1Low=0, g_buyBounceATR=0;
int    g_buyBarsSince=0;

// -- sell (double-top / "M") setup state --
bool   g_sellActive=false, g_sellBounced=false;
double g_sellTouch1High=0, g_sellBounceATR=0;
int    g_sellBarsSince=0;

// -- outcome tracking (one in-flight position at a time, own-Magic MAX1) --
ulong  g_trackTicket=0;
double g_trackEntry=0, g_trackR=0;
double g_trackGapATR=0, g_trackBounceATR=0, g_trackRawR_ATR=0, g_trackFlooredR_ATR=0;
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

void ResetBuySetup(){ g_buyActive=false; g_buyBounced=false; g_buyTouch1Low=0; g_buyBarsSince=0; g_buyBounceATR=0; }
void ResetSellSetup(){ g_sellActive=false; g_sellBounced=false; g_sellTouch1High=0; g_sellBarsSince=0; g_sellBounceATR=0; }

void OpenTrade(int dir,double sl,double atr,double gapATR,double bounceATR,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double R=MathAbs(ref-sl);
   double rawR_ATR=(atr>0) ? R/atr : 0;
   if(MinStopATR>0 && atr>0 && R<MinStopATR*atr)
   {
      double need=MinStopATR*atr-R;
      sl=sl-dir*need; // push the stop further out to meet the floor
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
         g_trackGapATR=gapATR; g_trackBounceATR=bounceATR;
         g_trackRawR_ATR=rawR_ATR; g_trackFlooredR_ATR=flooredR_ATR;
         break;
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

   double upper[1],lower[1];
   if(CopyBuffer(hBB,1,1,1,upper)!=1 || CopyBuffer(hBB,2,1,1,lower)!=1)
   { Log("COPYBUFFER_FAIL","BB bands"); return; }

   double kbuf[1];
   if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
   double stochK=kbuf[0];

   double atrbuf[1];
   if(CopyBuffer(hATR,0,1,1,atrbuf)!=1){ Log("ATR_FAIL","no ATR value"); return; }
   double atr=atrbuf[0];
   if(atr<=0){ return; } // can't scale thresholds without a valid ATR yet (warmup period)

   bool haveOpenPos=HasOurPosition();

   // ---- buy (W / double-bottom) setup ----
   if(!g_buyActive)
   {
      if(l<=lower[0])
      {
         g_buyActive=true; g_buyTouch1Low=l; g_buyBarsSince=0; g_buyBounced=false;
         Log("SSANGBI_TOUCH1_BUY","low="+DoubleToString(l,_Digits)+" lowerBB="+DoubleToString(lower[0],_Digits)+" ATR="+DoubleToString(atr,_Digits));
      }
   }
   else
   {
      g_buyBarsSince++;
      if(g_buyBarsSince>SsangbiWindowBars)
      {
         Log("SSANGBI_EXPIRE_BUY","barsSince="+IntegerToString(g_buyBarsSince));
         ResetBuySetup();
      }
      else if(l<g_buyTouch1Low)
      {
         g_buyTouch1Low=l; g_buyBarsSince=0; g_buyBounced=false; // rebase to the new, lower low
      }
      else if(!g_buyBounced)
      {
         if(h>=g_buyTouch1Low+SsangbiMinBounceATR*atr)
         {
            g_buyBounced=true;
            g_buyBounceATR=(h-g_buyTouch1Low)/atr;
            Log("SSANGBI_BOUNCE_BUY","touch1Low="+DoubleToString(g_buyTouch1Low,_Digits)+" high="+DoubleToString(h,_Digits)+
                " bounceATR="+DoubleToString(g_buyBounceATR,2));
         }
      }
      else if(l<=g_buyTouch1Low+SsangbiToleranceATR*atr)
      {
         bool stochOk=(stochK<=StochOversold);
         bool closeOk=(c>o);
         double gapATR=(l-g_buyTouch1Low)/atr;
         Log("SSANGBI_TOUCH2_CHECK_BUY","touch1Low="+DoubleToString(g_buyTouch1Low,_Digits)+
             " touch2Low="+DoubleToString(l,_Digits)+" gapATR="+DoubleToString(gapATR,2)+
             " stochK="+DoubleToString(stochK,2)+" stochOk="+(stochOk?"true":"false")+" closeOk="+(closeOk?"true":"false"));
         if(stochOk && closeOk)
         {
            if(!haveOpenPos)
            {
               double sl=l-SsangbiSLBufferATR*atr;
               OpenTrade(+1,sl,atr,gapATR,g_buyBounceATR,"SSANGBI_BUY");
            }
            else
               Log("ENTRY_SKIPPED","SSANGBI_BUY signal but position already open");
            ResetBuySetup();
         }
      }
   }

   // ---- sell (M / double-top) setup ----
   if(!g_sellActive)
   {
      if(h>=upper[0])
      {
         g_sellActive=true; g_sellTouch1High=h; g_sellBarsSince=0; g_sellBounced=false;
         Log("SSANGBI_TOUCH1_SELL","high="+DoubleToString(h,_Digits)+" upperBB="+DoubleToString(upper[0],_Digits)+" ATR="+DoubleToString(atr,_Digits));
      }
   }
   else
   {
      g_sellBarsSince++;
      if(g_sellBarsSince>SsangbiWindowBars)
      {
         Log("SSANGBI_EXPIRE_SELL","barsSince="+IntegerToString(g_sellBarsSince));
         ResetSellSetup();
      }
      else if(h>g_sellTouch1High)
      {
         g_sellTouch1High=h; g_sellBarsSince=0; g_sellBounced=false; // rebase to the new, higher high
      }
      else if(!g_sellBounced)
      {
         if(l<=g_sellTouch1High-SsangbiMinBounceATR*atr)
         {
            g_sellBounced=true;
            g_sellBounceATR=(g_sellTouch1High-l)/atr;
            Log("SSANGBI_BOUNCE_SELL","touch1High="+DoubleToString(g_sellTouch1High,_Digits)+" low="+DoubleToString(l,_Digits)+
                " bounceATR="+DoubleToString(g_sellBounceATR,2));
         }
      }
      else if(h>=g_sellTouch1High-SsangbiToleranceATR*atr)
      {
         bool stochOk=(stochK>=StochOverbought);
         bool closeOk=(c<o);
         double gapATR=(g_sellTouch1High-h)/atr;
         Log("SSANGBI_TOUCH2_CHECK_SELL","touch1High="+DoubleToString(g_sellTouch1High,_Digits)+
             " touch2High="+DoubleToString(h,_Digits)+" gapATR="+DoubleToString(gapATR,2)+
             " stochK="+DoubleToString(stochK,2)+" stochOk="+(stochOk?"true":"false")+" closeOk="+(closeOk?"true":"false"));
         if(stochOk && closeOk)
         {
            if(!haveOpenPos)
            {
               double sl=h+SsangbiSLBufferATR*atr;
               OpenTrade(-1,sl,atr,gapATR,g_sellBounceATR,"SSANGBI_SELL");
            }
            else
               Log("ENTRY_SKIPPED","SSANGBI_SELL signal but position already open");
            ResetSellSetup();
         }
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
       " | SsangbiWindowBars="+IntegerToString(SsangbiWindowBars)+
       " SsangbiMinBounceATR="+DoubleToString(SsangbiMinBounceATR,2)+
       " SsangbiToleranceATR="+DoubleToString(SsangbiToleranceATR,2)+
       " SsangbiSLBufferATR="+DoubleToString(SsangbiSLBufferATR,2)+
       " | TP_R="+DoubleToString(TP_R,2)+" MinStopATR="+DoubleToString(MinStopATR,2)+
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
       " gapATR="+DoubleToString(g_trackGapATR,2)+" bounceATR="+DoubleToString(g_trackBounceATR,2)+
       " rawR_ATR="+DoubleToString(g_trackRawR_ATR,2)+" flooredR_ATR="+DoubleToString(g_trackFlooredR_ATR,2)+
       " | "+g_trackTag);
   g_trackTicket=0;
}
