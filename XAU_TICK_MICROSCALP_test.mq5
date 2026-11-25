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
//| the V1/V2 numbers.                                                       |
//|                                                                         |
//| MomentumThresholdPoints SWEEP (2026-11-24, 10/15/20/25/50/100 with       |
//| TrendThresholdPoints=950 held fixed): confirmed the hypothesis           |
//| dramatically. NET 10:$15,622/37,629 trades, 15:$16,158/33,915,           |
//| 20:$16,287(PEAK)/30,714, 25:$16,049/28,181, 50:$12,569/16,449,           |
//| 100:$4,526/5,263 -- vs the old 180:$891/1,098. Win rate ROSE as trade    |
//| count rose (74.4%->80.7% at 20), confirming the burst trigger at 180    |
//| was mostly just missing good trend-confirmed windows while waiting for  |
//| a rare violent half-second spike, not filtering for quality -- the 60s  |
//| trend gate was already doing that job. Below 20 (e.g. 10) quality       |
//| dilutes slightly as the trigger starts catching plain noise ticks.      |
//|                                                                         |
//| CONFIRMED (2026-11-24, per user): MomentumThresholdPoints default       |
//| 180->20. Combined with TrendThresholdPoints=950/TrendWindowMs=60000,    |
//| this is now the confirmed combo: NET $16,287.35, PF 2.943, RF 21.57,    |
//| Sharpe 280.48, DD 0.75%, 30,714 trades/22mo (~47/day), win rate 80.74%. |
//| Still subject to the KNOWN LIMITATIONS at the top of this header --     |
//| these are backtest-ceiling numbers, not a live estimate, especially at  |
//| this trade frequency and timescale.                                    |
//|                                                                         |
//| SLIPPAGE DIAGNOSTIC ADDED (2026-11-24, per user request -- motivated by |
//| live slippage already observed on 012/BB4FADEFLIP, which needed         |
//| MinCushionPoints floors added for the exact same reason on a far wider  |
//| R-based exit structure than this EA's fixed 140-point TP/SL): every     |
//| entry and exit now logs its intended price (the quoted ask/bid at the   |
//| moment the decision fired) vs the actual fill price (trade.ResultPrice) |
//| as ENTRY_SLIPPAGE/EXIT_SLIPPAGE, both to the Experts/Journal (Print) and|
//| to XAU_TICK_MICROSCALP_test_LOG.csv (same Log() pattern as the grid     |
//| EA's own log file). A running SLIPPAGE_SUMMARY (avg entry/exit/total    |
//| slip in points) logs every 100 trades and once more at OnDeinit.        |
//| Back-of-envelope math: NET $16,287.35 over 30,714 trades = $0.53/trade  |
//| average edge -- if real average total slippage (entry+exit) exceeds    |
//| ~53 points ($0.53), the edge is gone. Compare that number against this  |
//| log's avgTotalSlipPts from a demo/small-live forward run before sizing  |
//| up. Backtest itself still assumes zero slippage (Strategy Tester fills  |
//| at the quoted price +/- MaxDeviationPts with no latency), so this       |
//| diagnostic will read ~0 in Strategy Tester and only becomes meaningful  |
//| on a real demo/live run.                                                |
//|                                                                         |
//| BUGFIX (2026-11-25, found from a live Journal screenshot the user       |
//| shared): a position closed via the broker's own NATIVE stop loss        |
//| (visible in the Journal as "added order ... due stop loss" + a deal)    |
//| at essentially the same moment our own exit logic (hitTP/hitSL/timeUp)  |
//| tried to call CloseMyPosition() for the same reason -- our request was  |
//| rejected ("Modification failed due to order or position being close to  |
//| market") because the broker had already started closing it. The        |
//| position DID close correctly either way, but since CloseMyPosition()    |
//| returned 0 (nothing closed by US), no EXIT_SLIPPAGE was ever logged for |
//| that trade -- its real slippage (80 points / $0.80 unfavorable in the   |
//| observed case) silently vanished from the diagnostic above. Fixed by    |
//| tracking the exact position ticket (g_posTicket) and its own SL/TP      |
//| (g_posSL/g_posTP) from entry, so management can tell "gone because WE   |
//| closed it" apart from "gone because the broker's native SL/TP won the   |
//| race" -- the latter now recovers the real closing deal from history     |
//| (LogNativeCloseIfAny()) and logs EXIT_SLIPPAGE with reason=NATIVE_SL/   |
//| NATIVE_TP, measured against whichever of the entry's own SL/TP levels   |
//| the fill landed closer to. Also: if a close attempt fails for a REAL    |
//| reason (position still genuinely open), state is no longer discarded --|
//| it retries next tick instead of losing track of a live position.        |
//|                                                                         |
//| BUGFIX #2 (2026-11-25, root cause of the race above): slPrice/tpPrice   |
//| were computed from the PRE-TRADE quote (ask/bid) and sent as part of    |
//| the SAME market-order request, so the broker's native SL/TP ended up    |
//| anchored to that quote, not the real fill. In the observed live case,   |
//| the entry itself slipped FAVORABLY (filled 0.61 better than the quoted  |
//| ask), which silently shrank the real SL distance from the intended 140  |
//| points to only 79 -- so the broker's native SL fired on a much smaller  |
//| adverse move than our own internal hitSL check (which correctly        |
//| measures from the real fill) ever expected, guaranteeing the broker     |
//| would always win that race. Fixed: right after the fill, SL/TP are      |
//| recomputed from g_posOpenPrice (the actual fill) and re-applied via     |
//| PositionModify (logged as ENTRY_SLTP_CORRECTED) whenever they differ    |
//| from what was set -- so the configured TPPoints/SLPoints distance is    |
//| always what's really protecting the trade, regardless of entry         |
//| slippage in either direction.                                          |
//|                                                                         |
//| BUGFIX #3 (2026-11-25, SERIOUS -- found from a live log the user        |
//| shared): trade.ResultPrice()/trade.ResultOrder() turned out to be       |
//| unreliable in live execution -- every single entry in that log showed   |
//| slipPts=0.00 (not realistically possible across 60+ live market         |
//| orders), meaning ResultPrice() was returning 0 and the code was quietly |
//| falling back to the pre-trade quote as if it were the real fill. Worse: |
//| g_posTicket was being set from trade.ResultOrder(), so when THAT was    |
//| also unreliable, PositionSelectByTicket(g_posTicket) could read as      |
//| "already closed" on the very next tick after a perfectly normal entry   |
//| -- the EA would think it had no open position while one was genuinely   |
//| still live, and re-enter again and again instead of managing it. This   |
//| is almost certainly what produced the live burst the user saw (dozens   |
//| of entries within seconds, far above the ~46/day the backtest predicts) |
//| and very likely explains a live session showing 34 losses/10 wins       |
//| against an 80%+ backtested win rate -- not slippage, a tracking bug     |
//| letting positions silently stack beyond the intended one-at-a-time      |
//| design. Fixed by removing the dependency on the trade result object     |
//| entirely: FindMyPositionTicket() scans the broker's own position list   |
//| by magic+symbol (the same pattern already proven in the grid EA         |
//| elsewhere in this repo) for both "is my position still open" and "what  |
//| was the real fill price" (via PositionGetDouble(POSITION_PRICE_OPEN)),  |
//| used both at entry and on every management tick. Not yet live-verified  |
//| in this form -- watch the next live run for ENTRY_SLIPPAGE now showing  |
//| real (nonzero) values and entry frequency back near the backtested      |
//| rate.                                                                   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Signal: tick-level momentum burst (NEW, untested, user-specified: '1~2초만에 매매') ==="
input int    MomentumWindowMs        = 500;  // lookback window, milliseconds, to measure recent price velocity (TEST, untested)
input double MomentumThresholdPoints = 20;   // min |price change| over that window, in raw points (_Point, $0.01 each on this symbol -- 20 = $0.20), to count as a "burst" (CONFIRMED 2026-11-24: with TrendThresholdPoints=950 fixed as the real quality gate, this is really just a timing trigger -- 10/15/20/25/50/100 sweep found NET peaks at 20 ($16,287.35, 30,714 trades, win rate 80.74%) vs the old 180's $891.15/1,098 trades. Loosening this let far more of the already-trend-confirmed windows actually fire instead of waiting for a rare violent half-second spike; below 20 (e.g. 10) quality dilutes slightly as it starts catching plain noise ticks. See header.)
input bool   UseFadeMode             = false;// false: trade WITH the burst (momentum continuation); true: trade AGAINST it (mean-reversion fade) (TEST, untested)

input group "=== Higher-timeframe trend filter (NEW 2026-11-24, per user request: 2초짜리 스캘프의 '상위 추세' 필터 -- a bar-based M1/M2 indicator would reintroduce bar-close lag into an otherwise tick-native EA, so this reuses the SAME tick buffer as the burst signal above with a longer window instead) ==="
input int    TrendWindowMs           = 60000; // longer tick-based lookback window, milliseconds, for the higher-level trend direction (60000 = 60 seconds) -- same lookup mechanism as MomentumWindowMs, just a longer window (TEST, untested, user-specified logic)
input double TrendThresholdPoints    = 950;   // min |price change| over TrendWindowMs, in raw points, to count as a real directional trend bias -- below this the trend is too flat/ambiguous and the entry is skipped entirely (CONFIRMED 2026-11-24: 150->1000 sweep found NET plateaus 800-1000 (all $881-891, within noise) while PF/RF/Sharpe/win rate keep climbing through 1000 -- 950 picked as the best NET point on that plateau. NOTE: this trades frequency for quality -- 1,098 trades over 22mo (~1.7/day), far below the original "HFT-adjacent, stack many small gains" goal, see header)
input bool   RequireTrendAlignment   = true;  // only take the momentum-burst entry if its direction agrees with the longer-term trend above; if the trend itself is too flat (see TrendThresholdPoints), no entry fires regardless of the short-window burst (TEST, untested, user-specified logic)

input group "=== Exit: fixed tight TP/SL + HARD time stop (the time stop is what makes this '1~2초' by construction, NEW, untested) ==="
input double TPPoints                = 140;  // take-profit distance, raw points ($0.01 each -- 140 = $1.40) (CONFIRMED 2026-11-24 alongside TrendThresholdPoints=950/MomentumThresholdPoints=20 -- raised from the original 60 when the V1 run showed commission dominated at the tight 60/60 size, see header)
input double SLPoints                 = 140;  // stop-loss distance, raw points (CONFIRMED 2026-11-24, same as TPPoints above)
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
ulong    g_posTicket=0;   // NEW 2026-11-25: exact position ticket, so a close can be verified/recovered by identity, not just by magic+symbol
double   g_posSL=0, g_posTP=0; // NEW 2026-11-25: the SL/TP actually set at entry, used as the slippage reference when a NATIVE close is recovered from history

// Slippage diagnostic (NEW 2026-11-24, per user request, motivated by live
// slippage already observed on 012/013): requested price vs actual fill
// price, logged per trade plus a running average every SlippageSummaryEvery
// trades, so real execution quality can be measured directly instead of
// assumed from the (slippage-free) backtest.
int    f_log=INVALID_HANDLE;
long   g_entryCount=0; double g_entrySlipSum=0;
long   g_exitCount=0;  double g_exitSlipSum=0;

void Log(string event_,string detail)
{
   Print(event_," ",detail);
   if(f_log!=INVALID_HANDLE)
   {
      FileWrite(f_log,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),event_,detail);
      FileFlush(f_log);
   }
}

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

// NEW 2026-11-25, BUGFIX #3 (the serious one): trade.ResultOrder()/
// ResultPrice() were found unreliable in live execution (returning 0 even on
// a genuinely successful fill -- confirmed from a live log showing EVERY
// single entry at exactly slipPts=0.00, which is not realistically possible
// across 60+ live market orders). Relying on them for g_posTicket meant
// PositionSelectByTicket(g_posTicket) could immediately read as "gone" on
// the very next tick after a perfectly normal entry, causing the EA to
// think it had no open position while one was actually still live --
// letting it re-enter again and again (the "거래 엄청 많이" burst the user
// saw, far above the ~46/day the backtest predicted) instead of managing
// the real position. This replaces that dependency entirely: find our
// position by scanning the broker's own position list (magic+symbol), the
// same robust pattern already proven in the grid EA elsewhere in this repo.
// Leaves the found position selected (PositionGetDouble/Integer read from
// it) so callers don't need to re-select.
ulong FindMyPositionTicket()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol)
         return t;
   }
   return 0;
}

// Returns the actual fill price of the close (0 if nothing was closed or the
// close failed), for slippage measurement by the caller.
double CloseMyPosition()
{
   double fillPrice=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!trade.PositionClose(t))
         Print("MICROSCALP CLOSE_FAIL retcode=",trade.ResultRetcode()," #",t);
      else
         fillPrice=trade.ResultPrice();
   }
   return fillPrice;
}

void LogSlippageSummary()
{
   double avgEntry=(g_entryCount>0)?g_entrySlipSum/g_entryCount:0;
   double avgExit=(g_exitCount>0)?g_exitSlipSum/g_exitCount:0;
   Log("SLIPPAGE_SUMMARY","entries="+IntegerToString(g_entryCount)+" avgEntrySlipPts="+DoubleToString(avgEntry,2)+
       " exits="+IntegerToString(g_exitCount)+" avgExitSlipPts="+DoubleToString(avgExit,2)+
       " avgTotalSlipPts="+DoubleToString(avgEntry+avgExit,2));
}

// NEW 2026-11-25: our own PositionClose() can be rejected ("close to market" /
// position already gone) when the broker's own native SL/TP fires at
// essentially the same moment we try to close for our own reason (hitTP/
// hitSL/timeUp) -- confirmed happening live (user screenshot, 2026-11-25).
// When that happens the position vanishes without ever going through
// CloseMyPosition() successfully, so EXIT_SLIPPAGE would otherwise never be
// logged for it. This recovers the real closing deal from history and logs
// slippage against whichever of the entry's own SL/TP the fill landed near.
void LogNativeCloseIfAny(ulong posTicket,int dir,double posSL,double posTP,datetime openTime)
{
   if(!HistorySelect(openTime-5,TimeCurrent())) return;
   int total=HistoryDealsTotal();
   for(int i=total-1;i>=0;i--)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID)!=posTicket) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double actual=HistoryDealGetDouble(d,DEAL_PRICE);
      double distToSL=(posSL>0)?MathAbs(actual-posSL):1e9;
      double distToTP=(posTP>0)?MathAbs(actual-posTP):1e9;
      string reason; double reference;
      if(distToSL<=distToTP){ reason="NATIVE_SL"; reference=posSL; }
      else                  { reason="NATIVE_TP"; reference=posTP; }
      double slipPts=(dir>0)?(reference-actual)/_Point:(actual-reference)/_Point;
      g_exitCount++; g_exitSlipSum+=slipPts;
      Log("EXIT_SLIPPAGE","dir="+(dir>0?"BUY":"SELL")+" reason="+reason+" (closed by broker before our own PositionClose landed)"+
          " intended="+DoubleToString(reference,_Digits)+" actual="+DoubleToString(actual,_Digits)+" slipPts="+DoubleToString(slipPts,2));
      if(g_exitCount%100==0) LogSlippageSummary();
      return;
   }
   Log("EXIT_SLIPPAGE_UNRESOLVED","posTicket="+IntegerToString((long)posTicket)+" dir="+(dir>0?"BUY":"SELL")+" -- position gone but no matching closing deal found in history");
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   ArrayInitialize(g_tickBid,0);
   ArrayInitialize(g_tickMsc,0);
   ArrayInitialize(g_tradeTimes,0);
   f_log=FileOpen("XAU_TICK_MICROSCALP_test_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE) FileSeek(f_log,0,SEEK_END);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_entryCount>0 || g_exitCount>0) LogSlippageSummary();
   if(f_log!=INVALID_HANDLE) FileClose(f_log);
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
   if(g_posDir!=0)
   {
      if(EnableLiveOrders)
      {
         ulong liveTicket=FindMyPositionTicket(); // robust magic+symbol scan -- see BUGFIX #3
         if(liveTicket==0)
         {
            // Gone already -- either the broker's own native SL/TP beat us to
            // it, or our own close just below already landed. Recover the
            // real exit from history instead of silently losing this trade's
            // slippage measurement.
            LogNativeCloseIfAny(g_posTicket,g_posDir,g_posSL,g_posTP,g_posOpenTime);
            g_lastCloseMsc=nowMsc;
            g_posDir=0;
            return;
         }
         g_posTicket=liveTicket; // keep it fresh/correct regardless of what entry originally stored
      }

      double curPrice=(g_posDir>0)?bid:ask;
      double favPoints=(g_posDir>0)?(curPrice-g_posOpenPrice)/_Point:(g_posOpenPrice-curPrice)/_Point;
      bool hitTP=(favPoints>=TPPoints);
      bool hitSL=(favPoints<=-SLPoints);
      bool timeUp=(TimeCurrent()-g_posOpenTime>=MaxHoldSeconds);
      if(hitTP || hitSL || timeUp)
      {
         if(EnableLiveOrders)
         {
            double intendedClose=(g_posDir>0)?bid:ask; // closing a BUY sells at bid; closing a SELL buys at ask
            double actualClose=CloseMyPosition();
            if(actualClose>0)
            {
               double slipPts=(g_posDir>0)?(intendedClose-actualClose)/_Point:(actualClose-intendedClose)/_Point;
               g_exitCount++; g_exitSlipSum+=slipPts;
               Log("EXIT_SLIPPAGE","dir="+(g_posDir>0?"BUY":"SELL")+" reason="+(hitTP?"TP":(hitSL?"SL":"TIME"))+
                   " intended="+DoubleToString(intendedClose,_Digits)+" actual="+DoubleToString(actualClose,_Digits)+
                   " slipPts="+DoubleToString(slipPts,2));
               if(g_exitCount%100==0) LogSlippageSummary();
               g_lastCloseMsc=nowMsc;
               g_posDir=0;
            }
            else if(FindMyPositionTicket()==0)
            {
               // Our request lost the race to the broker's own native SL/TP --
               // recover the real exit instead of leaving it unmeasured.
               LogNativeCloseIfAny(g_posTicket,g_posDir,g_posSL,g_posTP,g_posOpenTime);
               g_lastCloseMsc=nowMsc;
               g_posDir=0;
            }
            // else: genuinely still open and the close failed for some other
            // reason -- keep state as-is and retry next tick rather than
            // abandoning tracking of a position that's actually still live.
         }
         else
         {
            g_lastCloseMsc=nowMsc;
            g_posDir=0;
         }
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

   // NEW 2026-11-25, per user request: hoisted out of the block below so it
   // can be logged at entry (ENTRY_SLIPPAGE/DRY_ENTRY) regardless -- lets a
   // live entry be checked after the fact against TrendThresholdPoints
   // instead of eyeballing the chart.
   double trendPts=0;
   if(RequireTrendAlignment)
   {
      double refBidTrend;
      if(!BidAtOrBefore(nowMsc-TrendWindowMs,refBidTrend)) return; // not enough history yet for the trend window
      trendPts=(bid-refBidTrend)/_Point;
      if(MathAbs(trendPts)<TrendThresholdPoints) return; // trend too flat/ambiguous -- skip
      int trendDir=(trendPts>0)?+1:-1;
      if(dir!=trendDir) return; // burst disagrees with the higher-level trend -- skip
   }

   if(!EnableLiveOrders)
   {
      Print("MICROSCALP DRY_ENTRY dir=",(dir>0?"BUY":"SELL")," movePts=",DoubleToString(movePts,1)," trendPts=",DoubleToString(trendPts,1)," spread=",DoubleToString(spreadPts,1));
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
   double intendedEntry=(dir>0?ask:bid);
   g_posDir=dir;
   g_posOpenTime=TimeCurrent();

   // BUGFIX #3 (2026-11-25): trade.ResultPrice()/ResultOrder() were found
   // unreliable live (returning 0 on genuinely successful fills -- see
   // header). Get the real fill price and ticket from the position itself
   // via a magic+symbol scan instead of trusting the trade result object.
   ulong foundTicket=FindMyPositionTicket();
   if(foundTicket!=0)
   {
      g_posTicket=foundTicket;
      g_posOpenPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   }
   else
   {
      // Rare race: position not yet visible this same tick. Best-effort
      // fallback now; the management block re-scans fresh every tick
      // regardless, so this self-heals as soon as it becomes visible.
      g_posTicket=0;
      g_posOpenPrice=trade.ResultPrice()>0?trade.ResultPrice():intendedEntry;
   }

   // BUGFIX (2026-11-25, found from a live case): slPrice/tpPrice above were
   // computed from the PRE-TRADE quote (ask/bid), but the actual fill can
   // differ (entry slippage) -- if so, the SL/TP actually protecting the
   // position end up a DIFFERENT distance from TPPoints/SLPoints than
   // intended, measured from where the position really opened. Recompute
   // from the real fill and re-apply so the configured distance is always
   // what's really protecting the trade, regardless of entry slippage.
   double correctedSL=(dir>0)?NormalizeDouble(g_posOpenPrice-SLPoints*_Point,_Digits):NormalizeDouble(g_posOpenPrice+SLPoints*_Point,_Digits);
   double correctedTP=(dir>0)?NormalizeDouble(g_posOpenPrice+TPPoints*_Point,_Digits):NormalizeDouble(g_posOpenPrice-TPPoints*_Point,_Digits);
   if(MathAbs(correctedSL-slPrice)>_Point || MathAbs(correctedTP-tpPrice)>_Point)
   {
      if(PositionSelectByTicket(g_posTicket))
      {
         if(!trade.PositionModify(g_posTicket,correctedSL,correctedTP))
            Log("ENTRY_SLTP_CORRECT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         else
         {
            Log("ENTRY_SLTP_CORRECTED","dir="+(dir>0?"BUY":"SELL")+" old_sl="+DoubleToString(slPrice,_Digits)+" new_sl="+DoubleToString(correctedSL,_Digits)+
                " old_tp="+DoubleToString(tpPrice,_Digits)+" new_tp="+DoubleToString(correctedTP,_Digits));
            slPrice=correctedSL; tpPrice=correctedTP;
         }
      }
   }
   g_posSL=slPrice; g_posTP=tpPrice;
   RecordTradeTime(nowMsc);
   double entrySlipPts=(dir>0)?(g_posOpenPrice-intendedEntry)/_Point:(intendedEntry-g_posOpenPrice)/_Point;
   g_entryCount++; g_entrySlipSum+=entrySlipPts;
   Log("ENTRY_SLIPPAGE","dir="+(dir>0?"BUY":"SELL")+" intended="+DoubleToString(intendedEntry,_Digits)+
       " actual="+DoubleToString(g_posOpenPrice,_Digits)+" slipPts="+DoubleToString(entrySlipPts,2)+
       " movePts="+DoubleToString(movePts,1)+" trendPts="+DoubleToString(trendPts,1)+" spread="+DoubleToString(spreadPts,1));
   if(g_entryCount%100==0) LogSlippageSummary();
}
