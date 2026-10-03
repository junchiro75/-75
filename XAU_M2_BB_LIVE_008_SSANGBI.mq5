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
//| touch's reversal confirmation, not the first. This is the opposite  |
//| of 001's immediate entry on the first breakout/touch -- the whole    |
//| point is a TIGHTER, more precise stop (right at the confirmed       |
//| double-bottom/top) instead of 001's fixed SL_R=4, directly aimed at  |
//| the R:R asymmetry problem the document's philosophy flagged.        |
//|                                                                      |
//| Mechanical definition used here (first cut, UNTESTED -- every        |
//| threshold below is a starting guess, not yet backtest-validated):    |
//|  1. TOUCH 1: price (bar low) pierces the BB20 LOWER band (bull/buy   |
//|     setup) or (bar high) pierces the BB20 UPPER band (bear/sell      |
//|     setup). Record that extreme as the setup's reference level.      |
//|  2. BOUNCE: within SsangbiWindowBars, price must move away from      |
//|     that extreme by >=SsangbiMinBounceP points, confirming it        |
//|     wasn't just a single continuous move (this is the "W"/"M" shape  |
//|     requirement -- two distinct legs, not one).                      |
//|  3. If price makes a NEW, more extreme low/high before bouncing,     |
//|     the setup re-bases to that new extreme (only a genuine reversal  |
//|     back up/down counts as the first leg of the W/M).                |
//|  4. TOUCH 2: after bouncing, price returns to within                 |
//|     SsangbiToleranceP points of the original extreme (roughly equal  |
//|     bottoms/tops -- the actual "쌍비" shape) AND, on that same bar,   |
//|     Stochastic is oversold (buy) / overbought (sell) AND the bar     |
//|     itself closes in the reversal direction (bullish for buy,        |
//|     bearish for sell) -- both the band-retouch condition AND the     |
//|     stochastic condition must hold together (user's explicit         |
//|     choice over either alone).                                       |
//|  5. ENTRY: at market, right after that confirming bar closes.        |
//|  6. STOP: placed just beyond TOUCH 2's own extreme (SsangbiSLBufferP |
//|     points further), not a fixed R multiple like 001 -- this is the  |
//|     whole point of the tighter-stop approach. TARGET: TP_R multiple  |
//|     of that tight stop distance (R = |entry-SL|), configurable.      |
//|                                                                      |
//| Deliberately NOT yet implemented (left for a later iteration once    |
//| this core shape is validated): no 매물대 multi-timeframe check (document|
//| wants higher-TF structure context, this only uses one timeframe),    |
//| no session/day filters, no 더블비(BB4) confirmation on top of BB20,   |
//| no partial exits -- keeping the first backtest as simple as possible  |
//| to isolate whether the core double-touch idea has any edge at all     |
//| before layering anything else on.                                    |
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
input int    SsangbiWindowBars    = 15; // Max bars allowed between touch 1 and touch 2
input double SsangbiMinBounceP    = 100.0; // Min points price must bounce away from touch 1 before a retest counts (points)
input double SsangbiToleranceP    = 150.0; // Max points between touch 1 and touch 2 extremes to count as "roughly equal" (points)
input double SsangbiSLBufferP     = 50.0; // Extra buffer beyond touch 2's own extreme for the stop (points)
input double TP_R                 = 1.5; // Take profit as a multiple of the stop distance (R)
input double MinStopPoints        = 150.0; // Floor on the stop distance in points, 0=no floor
input ulong  MagicNumber          = 95016108; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

int hBB=INVALID_HANDLE, hStoch=INVALID_HANDLE;
datetime last_bar=0;
int f_log=INVALID_HANDLE;

// -- buy (double-bottom / "W") setup state --
bool   g_buyActive=false, g_buyBounced=false;
double g_buyTouch1Low=0;
int    g_buyBarsSince=0;

// -- sell (double-top / "M") setup state --
bool   g_sellActive=false, g_sellBounced=false;
double g_sellTouch1High=0;
int    g_sellBarsSince=0;

// -- outcome tracking (one in-flight position at a time, own-Magic MAX1) --
ulong  g_trackTicket=0;
double g_trackEntry=0, g_trackR=0;
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

void ResetBuySetup(){ g_buyActive=false; g_buyBounced=false; g_buyTouch1Low=0; g_buyBarsSince=0; }
void ResetSellSetup(){ g_sellActive=false; g_sellBounced=false; g_sellTouch1High=0; g_sellBarsSince=0; }

void OpenTrade(int dir,double sl,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double R=MathAbs(ref-sl);
   if(MinStopPoints>0 && R<MinStopPoints*_Point)
   {
      double need=MinStopPoints*_Point-R;
      sl=sl-dir*need; // push the stop further out to meet the floor
      R=MathAbs(ref-sl);
   }
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
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
         g_trackTicket=tk; g_trackEntry=ref; g_trackR=R; g_trackDir=dir; g_trackTag=tag;
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

   bool haveOpenPos=HasOurPosition();

   // ---- buy (W / double-bottom) setup ----
   if(!g_buyActive)
   {
      if(l<=lower[0])
      {
         g_buyActive=true; g_buyTouch1Low=l; g_buyBarsSince=0; g_buyBounced=false;
         Log("SSANGBI_TOUCH1_BUY","low="+DoubleToString(l,_Digits)+" lowerBB="+DoubleToString(lower[0],_Digits));
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
         if(h>=g_buyTouch1Low+SsangbiMinBounceP*_Point)
         {
            g_buyBounced=true;
            Log("SSANGBI_BOUNCE_BUY","touch1Low="+DoubleToString(g_buyTouch1Low,_Digits)+" high="+DoubleToString(h,_Digits));
         }
      }
      else if(l<=g_buyTouch1Low+SsangbiToleranceP*_Point)
      {
         bool stochOk=(stochK<=StochOversold);
         bool closeOk=(c>o);
         Log("SSANGBI_TOUCH2_CHECK_BUY","touch1Low="+DoubleToString(g_buyTouch1Low,_Digits)+
             " touch2Low="+DoubleToString(l,_Digits)+" stochK="+DoubleToString(stochK,2)+
             " stochOk="+(stochOk?"true":"false")+" closeOk="+(closeOk?"true":"false"));
         if(stochOk && closeOk)
         {
            if(!haveOpenPos)
            {
               double sl=l-SsangbiSLBufferP*_Point;
               OpenTrade(+1,sl,"SSANGBI_BUY");
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
         Log("SSANGBI_TOUCH1_SELL","high="+DoubleToString(h,_Digits)+" upperBB="+DoubleToString(upper[0],_Digits));
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
         if(l<=g_sellTouch1High-SsangbiMinBounceP*_Point)
         {
            g_sellBounced=true;
            Log("SSANGBI_BOUNCE_SELL","touch1High="+DoubleToString(g_sellTouch1High,_Digits)+" low="+DoubleToString(l,_Digits));
         }
      }
      else if(h>=g_sellTouch1High-SsangbiToleranceP*_Point)
      {
         bool stochOk=(stochK>=StochOverbought);
         bool closeOk=(c<o);
         Log("SSANGBI_TOUCH2_CHECK_SELL","touch1High="+DoubleToString(g_sellTouch1High,_Digits)+
             " touch2High="+DoubleToString(h,_Digits)+" stochK="+DoubleToString(stochK,2)+
             " stochOk="+(stochOk?"true":"false")+" closeOk="+(closeOk?"true":"false"));
         if(stochOk && closeOk)
         {
            if(!haveOpenPos)
            {
               double sl=h+SsangbiSLBufferP*_Point;
               OpenTrade(-1,sl,"SSANGBI_SELL");
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
   if(hBB==INVALID_HANDLE || hStoch==INVALID_HANDLE){ Print("Indicator handle creation failed"); return INIT_FAILED; }

   f_log=FileOpen("XAU_M2_BB_LIVE_008_SSANGBI_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE) FileSeek(f_log,0,SEEK_END);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START","TF="+EnumToString(Timeframe)+" | BB("+IntegerToString(BBPeriod)+","+DoubleToString(BBDev,1)+")"+
       " | Stoch("+IntegerToString(StochK_Period)+","+IntegerToString(StochD_Period)+","+IntegerToString(StochSlowing)+")"+
       " OB="+DoubleToString(StochOverbought,1)+" OS="+DoubleToString(StochOversold,1)+
       " | SsangbiWindowBars="+IntegerToString(SsangbiWindowBars)+
       " SsangbiMinBounceP="+DoubleToString(SsangbiMinBounceP,1)+
       " SsangbiToleranceP="+DoubleToString(SsangbiToleranceP,1)+
       " SsangbiSLBufferP="+DoubleToString(SsangbiSLBufferP,1)+
       " | TP_R="+DoubleToString(TP_R,2)+" MinStopPoints="+DoubleToString(MinStopPoints,1)+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB!=INVALID_HANDLE) IndicatorRelease(hBB);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
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
       " | "+g_trackTag);
   g_trackTicket=0;
}
