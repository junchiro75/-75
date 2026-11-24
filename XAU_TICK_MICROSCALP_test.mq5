//+------------------------------------------------------------------+
//| XAU_TICK_MICROSCALP_test.mq5                                       |
//+------------------------------------------------------------------+
//| NEW (2026-11-24, per user request): "HFT와 비슷한 느낌으로 1~2초만에     |
//| 매매하면서 차곡차곡 이익을 쌓는 모델". This is NOT real HFT (no            |
//| colocation/FIX API is possible on this retail MT5 setup -- see chat     |
//| discussion) -- it is a genuinely tick-driven, ultra-short-hold          |
//| prototype that is structurally different from every other EA in this    |
//| repo: those all react to bar closes (M1/M3) and use R-multiple          |
//| trailing stops that can hold for minutes to days. This one reacts to    |
//| raw ticks (MqlTick.time_msc, millisecond precision) and FORCES every    |
//| position flat within MaxHoldSeconds regardless of P&L -- that hard      |
//| timer is what makes "1~2초" a guarantee by construction, not a          |
//| byproduct of the signal.                                                |
//|                                                                         |
//| Core idea (momentum-burst continuation, UseFadeMode flips it to a       |
//| mean-reversion fade instead): if price has moved at least                |
//| MomentumThresholdPoints within the last MomentumWindowMs milliseconds,  |
//| enter betting the burst keeps going (or reverts) for one more moment,   |
//| with a small fixed TPPoints/SLPoints and the hard time stop as a        |
//| backstop if neither is hit first.                                       |
//|                                                                         |
//| KNOWN LIMITATIONS (read before trusting any backtest number):           |
//| (1) MT5 Strategy Tester's "every tick based on real ticks" mode         |
//| replays historical ticks but assumes INSTANT fill at the quoted price   |
//| (+/- MaxDeviationPts) with no network/server latency and no requotes -- |
//| a real live fill at this timescale will be slower and worse, so         |
//| backtest numbers here are a CEILING on live performance, not an         |
//| estimate of it. (2) Spread is the dominant cost at this scale --        |
//| TPPoints must clear the round-trip spread by a healthy margin or the    |
//| strategy is structurally negative no matter how good the signal is;     |
//| MaxSpreadPoints exists to refuse entries when spread has widened.       |
//| (3) Not yet backtested in any form -- every input below is a first-     |
//| guess starting point, not a confirmed value.                           |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Signal: tick-level momentum burst (NEW, untested, user-specified: '1~2초만에 매매') ==="
input int    MomentumWindowMs        = 500;  // lookback window, milliseconds, to measure recent price velocity (TEST, untested)
input double MomentumThresholdPoints = 80;   // min |price change| over that window, in raw points (_Point, $0.01 each on this symbol -- 80 = $0.80), to count as a "burst" (TEST, untested)
input bool   UseFadeMode             = false;// false: trade WITH the burst (momentum continuation); true: trade AGAINST it (mean-reversion fade) (TEST, untested)

input group "=== Exit: fixed tight TP/SL + HARD time stop (the time stop is what makes this '1~2초' by construction, NEW, untested) ==="
input double TPPoints                = 60;   // take-profit distance, raw points ($0.01 each -- 60 = $0.60) (TEST, untested)
input double SLPoints                = 60;   // stop-loss distance, raw points (TEST, untested)
input int    MaxHoldSeconds          = 2;    // force-close the position after this many seconds regardless of P&L -- the core "1~2초" guarantee (TEST, untested, user-specified logic)

input group "=== Entry gating / cost control (NEW, untested) ==="
input double MaxSpreadPoints         = 15;   // skip entry if the current ask-bid spread exceeds this (raw points) -- refuses to trade when spread has widened past what TPPoints can absorb (TEST, untested)
input int    MinReEntryGapMs         = 300;  // minimum milliseconds between closing one trade and opening the next (TEST, untested)
input int    MaxTradesPerMinute      = 0;    // 0 = unlimited; otherwise a hard cap on new entries per rolling 60s window, as a safety brake (TEST, untested)

input group "=== Sizing / misc ==="
input double Lots                    = 0.01; // lot size per trade (TEST, untested)
input ulong  MagicNumber             = 95020001;
input int    MaxDeviationPts         = 20;
input bool   EnableLiveOrders        = true;

#define TICKBUF_SIZE 4096
double  g_tickBid[TICKBUF_SIZE];
long    g_tickMsc[TICKBUF_SIZE];
int     g_tickHead=0;   // next write slot
int     g_tickCount=0;  // how many valid slots filled (caps at TICKBUF_SIZE)

long    g_lastCloseMsc=0;
long    g_tradeTimes[600]; // ring buffer of recent entry times (msc/1000 = sec) for the per-minute cap
int     g_tradeTimesHead=0, g_tradeTimesCount=0;

datetime g_posOpenTime=0;
double   g_posOpenPrice=0;
int      g_posDir=0; // +1 buy, -1 sell

//+------------------------------------------------------------------+
void PushTick(double bid,long msc)
{
   g_tickBid[g_tickHead]=bid;
   g_tickMsc[g_tickHead]=msc;
   g_tickHead=(g_tickHead+1)%TICKBUF_SIZE;
   if(g_tickCount<TICKBUF_SIZE) g_tickCount++;
}

// Find the bid price from approximately windowMs milliseconds ago.
// Returns false if the buffer doesn't go back far enough yet.
bool BidAtOrBefore(long targetMsc,double &outBid)
{
   int idx=(g_tickHead-1+TICKBUF_SIZE)%TICKBUF_SIZE;
   int scanned=0;
   while(scanned<g_tickCount)
   {
      if(g_tickMsc[idx]<=targetMsc){ outBid=g_tickBid[idx]; return true; }
      idx=(idx-1+TICKBUF_SIZE)%TICKBUF_SIZE;
      scanned++;
   }
   return false; // buffer doesn't reach back far enough -- don't guess
}

bool WithinTradeCap()
{
   if(MaxTradesPerMinute<=0) return true;
   return g_tradeTimesCount<MaxTradesPerMinute;
}

void RecordTradeTime(long msc)
{
   if(MaxTradesPerMinute<=0) return;
   g_tradeTimes[g_tradeTimesHead]=msc;
   g_tradeTimesHead=(g_tradeTimesHead+1)%600;
   if(g_tradeTimesCount<600) g_tradeTimesCount++;
}

// Drop entries older than 60s from the rolling trade-time window.
void PruneTradeCap(long nowMsc)
{
   if(MaxTradesPerMinute<=0) return;
   while(g_tradeTimesCount>0)
   {
      int oldestIdx=(g_tradeTimesHead-g_tradeTimesCount+600)%600;
      if(nowMsc-g_tradeTimes[oldestIdx]>60000) g_tradeTimesCount--;
      else break;
   }
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
   }
   return false;
}

void CloseMyPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!trade.PositionClose(t))
         Print("MICROSCALP CLOSE_FAIL retcode=",trade.ResultRetcode()," #",t);
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   ArrayInitialize(g_tickBid,0);
   ArrayInitialize(g_tickMsc,0);
   ArrayInitialize(g_tradeTimes,0);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double bid=tick.bid, ask=tick.ask;
   long   nowMsc=tick.time_msc;
   PushTick(bid,nowMsc);
   PruneTradeCap(nowMsc);

   //--- manage an already-open position: TP/SL + hard time stop ---
   if(HasOpenPosition())
   {
      double curPrice=(g_posDir>0)?bid:ask;
      double favPoints=(g_posDir>0)?(curPrice-g_posOpenPrice)/_Point:(g_posOpenPrice-curPrice)/_Point;
      bool hitTP=(favPoints>=TPPoints);
      bool hitSL=(favPoints<=-SLPoints);
      bool timeUp=(TimeCurrent()-g_posOpenTime>=MaxHoldSeconds);
      if(hitTP || hitSL || timeUp)
      {
         if(EnableLiveOrders) CloseMyPosition();
         g_lastCloseMsc=nowMsc;
         g_posDir=0;
      }
      return; // one position at a time -- never stack while one is open
   }

   //--- entry gating ---
   if(nowMsc-g_lastCloseMsc<MinReEntryGapMs) return;
   if(!WithinTradeCap()) return;
   double spreadPts=(ask-bid)/_Point;
   if(spreadPts>MaxSpreadPoints) return;

   double refBid;
   if(!BidAtOrBefore(nowMsc-MomentumWindowMs,refBid)) return; // not enough history yet
   double movePts=(bid-refBid)/_Point;
   if(MathAbs(movePts)<MomentumThresholdPoints) return;

   int dir=(movePts>0)?+1:-1;
   if(UseFadeMode) dir=-dir;

   if(!EnableLiveOrders)
   {
      Print("MICROSCALP DRY_ENTRY dir=",(dir>0?"BUY":"SELL")," movePts=",DoubleToString(movePts,1)," spread=",DoubleToString(spreadPts,1));
      g_posDir=dir; g_posOpenPrice=(dir>0?ask:bid); g_posOpenTime=TimeCurrent();
      RecordTradeTime(nowMsc);
      return;
   }

   double lot=Lots;
   double slPrice,tpPrice;
   bool ok;
   if(dir>0)
   {
      slPrice=NormalizeDouble(ask-SLPoints*_Point,_Digits);
      tpPrice=NormalizeDouble(ask+TPPoints*_Point,_Digits);
      ok=trade.Buy(lot,_Symbol,0.0,slPrice,tpPrice,"MICROSCALP");
   }
   else
   {
      slPrice=NormalizeDouble(bid+SLPoints*_Point,_Digits);
      tpPrice=NormalizeDouble(bid-TPPoints*_Point,_Digits);
      ok=trade.Sell(lot,_Symbol,0.0,slPrice,tpPrice,"MICROSCALP");
   }
   if(!ok)
   {
      Print("MICROSCALP ENTRY_FAIL retcode=",trade.ResultRetcode()," | ",trade.ResultRetcodeDescription());
      return;
   }
   g_posDir=dir;
   g_posOpenPrice=trade.ResultPrice()>0?trade.ResultPrice():(dir>0?ask:bid);
   g_posOpenTime=TimeCurrent();
   RecordTradeTime(nowMsc);
   Print("MICROSCALP ENTRY dir=",(dir>0?"BUY":"SELL")," @",DoubleToString(g_posOpenPrice,_Digits)," movePts=",DoubleToString(movePts,1)," spread=",DoubleToString(spreadPts,1));
}
