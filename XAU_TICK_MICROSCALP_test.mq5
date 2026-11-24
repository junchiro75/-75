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
//|                                                                         |
//| V1 BACKTEST (2026-11-24, MomentumThresholdPoints=80, TPPoints/SLPoints  |
//| =60, 2025.01-2026.10): NET -$8,071.55, PF 0.789, RF -0.386, Sharpe -5.0,|
//| DD 20.90%, 103,610 trades, win rate 50.26%, avg hold ~1s (time stop     |
//| confirmed working structurally). Raw price edge was actually slightly  |
//| POSITIVE (~+$7,470 estimated), but the fixed ~$0.15/trade commission   |
//| (0.01 lot) multiplied across 103,610 trades (~$15,540 total) overwhelmed|
//| it -- commission, not spread, was the dominant structural cost at this  |
//| trade frequency.                                                        |
//|                                                                         |
//| V2 BACKTEST (2026-11-24, MomentumThresholdPoints 80->180, TPPoints/     |
//| SLPoints 60->140, per the V1 finding): NET flipped to +$103.40, PF      |
//| 1.033, RF 0.068, Sharpe 3.40, DD 1.52%, trades 103,610->5,318 (-95%),   |
//| win rate 52.03%. Confirms the commission hypothesis, but the edge is    |
//| razor-thin (Expected Payoff $0.019/trade, RF only 0.068 -- NET is just  |
//| 7% of max DD) -- not yet a dependable "steadily accumulate profit"      |
//| engine; pure tick-momentum alone may not have enough real edge on this  |
//| symbol/feed for a retail setup.                                         |
//|                                                                         |
//| REVISION (2026-11-24, per user request, "스캘핑용 상위 추세 필터"): added |
//| TrendWindowMs/TrendThresholdPoints/RequireTrendAlignment -- a SECOND,   |
//| longer (60s default) tick-based lookback reusing the same buffer/      |
//| lookup as the short burst signal, instead of a bar-based M1/M2          |
//| indicator (which would reintroduce bar-close lag into an otherwise      |
//| tick-native EA). Only takes the burst entry if it agrees with this      |
//| longer-term direction; skips entirely if the longer-term move is too    |
//| flat to call a trend. TICKBUF_SIZE raised 4096->65536 to comfortably    |
//| span the 60s window.                                                    |
//|                                                                         |
//| TrendWindowMs SWEEP (2026-11-24, 30s/60s/120s, TrendThresholdPoints=150 |
//| held fixed): 60s beat both -- NET $283.73 (60s) vs $277.80 (30s) vs     |
//| $211.31 (120s), same ordering on every other metric. 30s is noisy, 120s |
//| is too laggy. TrendWindowMs stays at 60000 (confirmed).                 |
//|                                                                         |
//| TrendThresholdPoints SWEEP (2026-11-24, 150->1000, TrendWindowMs=60000  |
//| held fixed): monotonic improvement on PF/RF/Sharpe/win rate all the way |
//| to 1000 (150: PF 1.155/RF 0.337/Sharpe 15.67/WR 53.4%, 1000: PF 2.773/  |
//| RF 6.578/Sharpe 164.0/WR 75.0%), but NET plateaus 800-1000 (all         |
//| $881-891, within noise -- 800:$884.91, 850:$881.06, 900:$889.58,        |
//| 950:$891.15, 1000:$886.25). CONFIRMED at 950 (best NET on the plateau,  |
//| 1,098 trades/22mo).                                                     |
//|                                                                         |
//| USER CONCERN (2026-11-24, valid): 950 means ~1.7 trades/day -- nowhere  |
//| near the original "HFT-adjacent, stack many small gains" goal despite   |
//| each trade still resolving in 1-2s. The sweep shows this is a real      |
//| trade-off in THIS architecture, not a tuning miss: every attempt to     |
//| raise frequency by loosening TrendThresholdPoints pulls NET down toward |
//| the V1/V2 numbers. Next experiment to try: loosen MomentumThresholdPoints|
//| (the short 500ms burst trigger, currently 180) independently while      |
//| keeping TrendThresholdPoints=950 fixed -- the trend gate may be doing   |
//| most of the real quality filtering, so the burst trigger itself might   |
//| tolerate being less strict without giving back the quality gained here. |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Signal: tick-level momentum burst (NEW, untested, user-specified: '1~2초만에 매매') ==="
input int    MomentumWindowMs        = 500;  // lookback window, milliseconds, to measure recent price velocity (TEST, untested)
input double MomentumThresholdPoints = 80;   // min |price change| over that window, in raw points (_Point, $0.01 each on this symbol -- 80 = $0.80), to count as a "burst" (TEST, untested)
input bool   UseFadeMode             = false;// false: trade WITH the burst (momentum continuation); true: trade AGAINST it (mean-reversion fade) (TEST, untested)

input group "=== Higher-timeframe trend filter (NEW 2026-11-24, per user request: 2초짜리 스캘프의 '상위 추세' 필터 -- a bar-based M1/M2 indicator would reintroduce bar-close lag into an otherwise tick-native EA, so this reuses the SAME tick buffer as the burst signal above with a longer window instead) ==="
input int    TrendWindowMs           = 60000; // longer tick-based lookback window, milliseconds, for the higher-level trend direction (60000 = 60 seconds) -- same lookup mechanism as MomentumWindowMs, just a longer window (TEST, untested, user-specified logic)
input double TrendThresholdPoints    = 950;   // min |price change| over TrendWindowMs, in raw points, to count as a real directional trend bias -- below this the trend is too flat/ambiguous and the entry is skipped entirely (CONFIRMED 2026-11-24: 150->1000 sweep found NET plateaus 800-1000 (all $881-891, within noise) while PF/RF/Sharpe/win rate keep climbing through 1000 -- 950 picked as the best NET point on that plateau. NOTE: this trades frequency for quality -- 1,098 trades over 22mo (~1.7/day), far below the original "HFT-adjacent, stack many small gains" goal, see header)
input bool   RequireTrendAlignment   = true;  // only take the momentum-burst entry if its direction agrees with the longer-term trend above; if the trend itself is too flat (see TrendThresholdPoints), no entry fires regardless of the short-window burst (TEST, untested, user-specified logic)

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

#define TICKBUF_SIZE 65536 // RAISED 2026-11-24 from 4096: must comfortably span TrendWindowMs (60s) of ticks, not just the old 500ms MomentumWindowMs
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

   if(RequireTrendAlignment)
   {
      double refBidTrend;
      if(!BidAtOrBefore(nowMsc-TrendWindowMs,refBidTrend)) return; // not enough history yet for the trend window
      double trendPts=(bid-refBidTrend)/_Point;
      if(MathAbs(trendPts)<TrendThresholdPoints) return; // trend too flat/ambiguous -- skip
      int trendDir=(trendPts>0)?+1:-1;
      if(dir!=trendDir) return; // burst disagrees with the higher-level trend -- skip
   }

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
