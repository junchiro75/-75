//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_001_STOCH_v2.mq5                                    |
//| New strategy (user-designed): same M2 dual-BB signal-candle       |
//| detection used throughout this project (BB20 dev2.0 on Close +   |
//| BB4 dev4.0 on Open, PERIOD_M2), but direction is decided by the   |
//| Stochastic reading AT THE CLOSE of that signal candle instead of  |
//| always countertrend:                                              |
//|                                                                    |
//|   Bull signal candle (up breakout):                                |
//|     Stoch %K >= StochOverbought (70) -> SELL (countertrend, fade   |
//|       the move -- stochastic confirms it's overextended)          |
//|     Stoch %K <  StochOverbought      -> BUY  (trend-following --  |
//|       stochastic does NOT confirm overextension, so follow it)    |
//|   Bear signal candle (down breakout):                              |
//|     Stoch %K <  StochOversold (30)   -> BUY  (countertrend, fade) |
//|     Stoch %K >= StochOversold        -> SELL (trend-following)    |
//|                                                                    |
//| Entry is IMMEDIATE at market right when the signal candle closes   |
//| -- no Extension/Pullback staging like the 005-family EAs. R is    |
//| the signal candle's body (|close-open|), same definition as       |
//| elsewhere in this project. Exit is a single fixed bracket, no      |
//| protect-lock: SL = entry -+ SL_R*R, TP = entry +- TP_R*R.          |
//| MAX1 position at a time (own magic number).                        |
//| V2: added AllowSellFade -- ground-truth backtest (2025.01-2026.09, |
//| SL_R=4.0, MinR_Points=400) showed the bull+overbought SELL-fade    |
//| case is the ONE structurally losing direction (PF 0.88, -$4,848),  |
//| consistent with gold's persistent uptrend bias found elsewhere in  |
//| this project (005's own SELL-disable finding). The other three    |
//| cases were all net profitable (combined +$15,050). Confirmed      |
//| default is now false (skips that case); set true to reproduce V1  |
//| exactly. SL_R/TP_R defaults were also corrected from a stale       |
//| 1.0/0.5 to the confirmed 4.0/0.45 used in every backtest referenced|
//| throughout this file's header.                                     |
//| _v2 build: same logic as the live XAU_M2_BB_STOCH_V2 EA this      |
//| replaces, plus diagnostic logging on previously-silent failure    |
//| paths in CheckNewM2Bar() (BAR_DATA_FAIL / COPYBUFFER_FAIL) to      |
//| catch a repeat of a multi-hour silent-signal window seen live on  |
//| 2026.09.23.                                                        |
//| SkipTrendBearAsiaSession=true (confirmed default) skips            |
//| STOCH_TREND_BEAR specifically during the Asia session (06-16 KST)  |
//| where it's a structural loser, while it's solidly profitable in    |
//| Europe (16-22) and US (22-06) hours. A real backtest confirmed a    |
//| clean improvement on every metric (NET, PF, and drawdown all       |
//| better); see the input's own comment for numbers.                  |
//| MaxMinutesWithoutProgress (default 0, disabled) closes a position   |
//| early once it's been open this many minutes, regardless of P&L --   |
//| motivated by TP-hit trades resolving in ~3min median vs SL-hit      |
//| trades taking ~36min median. UNTESTED as a live rule; see the       |
//| input's own comment for the caveat before trusting it.              |
//| MAE-milestone tracking (diagnostic only, no trading effect): logs   |
//| MAE_MILESTONE when a position's adverse excursion crosses 50%/75%   |
//| of SL_R, and MAE_OUTCOME with the final win/loss at close -- lets   |
//| the CSV log answer "given a trade reached 50%/75% of its stop,      |
//| what fraction still won" (not available from the xlsx report).     |
//| Also tags firstBarOneWay on that same MAE_OUTCOME line: true when    |
//| the very next M2 bar after entry never moved favorably by even 1     |
//| point (BUY: bar's high never exceeded entry; SELL: bar's low never  |
//| went below it) before closing -- tests whether an immediate,        |
//| zero-pullback move against the position predicts a one-way run      |
//| into the stop.                                                      |
//| threeBarOneWay extends this over the entry candle + next 2 (3        |
//| candles total): true when the running favorable extreme across all   |
//| 3 (highest high for a BUY, lowest low for a SELL) never crossed      |
//| entry -- i.e. the position was never in profit at any point during   |
//| those 3 candles, not just that each one individually closed          |
//| unfavorably.                                                          |
//| UseThreeBarExit (UNTESTED): acts on threeBarOneWay -- force-closes a  |
//| position right when the 3rd candle closes if it was never profitable  |
//| during those 3. Ground truth on the confirmed baseline (3,273         |
//| trades): 1,946 already resolved before 3 candles (TP typically hits   |
//| in ~1-2 candles); of the 1,327 that survived, threeBarOneWay=true     |
//| (111 trades) loses 30.63% of the time vs 17.11% for the rest (1,216)  |
//| -- both already far above the 7.88% overall rate, but the gap nearly  |
//| doubles conditional loss risk. Needs its own backtest before trusting |
//| it: cutting here forfeits the ~69% of threeBarOneWay=true trades that |
//| still recover to a win.                                               |
//| ComboExitDangerMin/UseComboExit (CONFIRMED=10min/true): an AND of the  |
//| two ideas above instead of either alone -- only closes when a         |
//| position is BOTH threeBarOneWay=true AND has spent ComboExitDangerMin |
//| in the danger zone. Diagnostic motivation: of the 111                 |
//| threeBarOneWay=true trades in the confirmed baseline, the small       |
//| subset (26) that ALSO spent >=5min in the danger zone lost 84.6% of   |
//| the time (18 trades at >=10min: 83.3%) vs just 28.3% for              |
//| threeBarOneWay=true trades that stayed under 30min in the danger      |
//| zone. Ground-truth backtest confirmed this holds despite the tiny     |
//| slice (only 7 trades affected, 0.2% of all 3,273): a CLEAN            |
//| improvement on every metric -- NET $26,138.92 -> $27,148.70 (+3.9%),  |
//| PF 1.363 -> 1.382, MaxDD $2,483.70 -> $2,254.80 (-9.2%), Recovery     |
//| Factor 10.524 -> 12.040 (+14.4%), WR essentially unchanged (92.09%->  |
//| 92.01%) -- unlike UseProtectStop/UseDangerTimeStop/UseThreeBarExit    |
//| above (all individually REJECTED), this surgical AND-combination is   |
//| the one idea from this whole early-exit investigation that works.     |
//| UseTrendFilter (default false, UNTESTED): skips an entry when a      |
//| strong opposing trend is already established on TrendFilterTimeframe |
//| (default M15) -- ADX >= ADXThreshold and the dominant DI points      |
//| against the intended direction. Theory: one-way losses happen when   |
//| the opposing trend was already in place before entry, not created    |
//| by the trade itself. Backtest before trusting it.                    |
//| oppSignalSeen (diagnostic, always logged regardless of                |
//| UseOppositeSignalExit): true if a NEW opposite-direction M2 signal   |
//| candle (same BB20/BB4 breakout + R filter as entries) appeared at    |
//| any point while the position was open -- answers "of trades that     |
//| hit SL, what fraction had an opposite signal candle appear before    |
//| the loss" and "of trades where an opposite signal appeared, what     |
//| fraction still hit TP anyway" straight from the CSV log.             |
//| UseOppositeSignalExit (default false, UNTESTED as of the current      |
//| reached75-gated form -- see the input's own comment): when true,     |
//| ACTS on the opposite-signal detection above, but only once the       |
//| position has ALSO reached 75% of SL_R, by closing it at market       |
//| immediately. An earlier version acted on ANY opposite signal with    |
//| no 75% gate and was ground-truth REJECTED (NET $17,746 -> $12,245,   |
//| losses 218 -> 471) because it also cut ~131 shallow-pullback trades  |
//| that had a 100% natural win rate. That test also exposed a same-tick |
//| close+reopen logging race (fixed by moving tracking from single      |
//| scalars to TRACK_SLOTS-indexed arrays keyed by ticket) -- the CSV    |
//| had silently dropped 349 trade outcomes, which is why the corrupted  |
//| CSV first looked like a huge improvement before the official xlsx    |
//| report was checked.                                                   |
//| reachedFav50/75/90 (diagnostic only, no trading effect): the MFE       |
//| (Maximum Favorable Excursion) mirror of reached50/75 -- true if price |
//| moved that fraction of the way to TP_R at any point before the        |
//| position closed. Answers "of trades that got close to TP, what        |
//| fraction still reversed all the way to a LOSS" -- tests whether a      |
//| breakeven/lock-in rule near TP would be favorable. Unlike the MAE-side |
//| cuts (all rejected), the asymmetry here should run the other way:      |
//| giving up a small remaining slice of TP_R to avoid a full SL_R loss.   |
//| SLOPE_CALC / SLOPE_SIM_OUTCOME (diagnostic only, no trading effect):   |
//| tests the user's hypothesis that the 20-period MA's slope at a BB      |
//| signal candle predicts whether the breakout continues (trade WITH the  |
//| candle's direction) or fails (trade AGAINST it). MT5 has no native     |
//| "MA angle" value -- a raw price-per-bar slope is meaningless without   |
//| a scale, since the same slope looks like 5 degrees or 60 degrees       |
//| depending on chart zoom -- so the angle here is a deliberately-defined |
//| pseudo-angle, normalized by R (this strategy's own volatility unit),   |
//| not a real chart angle: slopeDeg = arctan((MA[now]-MA[N bars ago]) /   |
//| (N*R)) in degrees. |slopeDeg| <= SlopeThresholdDeg is classified FLAT  |
//| (hypothesis: fade the breakout); above it, STEEP (hypothesis: follow   |
//| the breakout). SLOPE_CALC logs this classification for EVERY signal    |
//| candle regardless of whether Stochastic/session filters would trade    |
//| it, so goal 1 (does the hypothesis alone reach SlopeSimTargetR) can be  |
//| checked against the full signal population. A separate, independent   |
//| forward simulation (its own tracking slots, no real order placed)      |
//| checks whether price reaches SlopeSimTargetR (default 0.5R) in the     |
//| slope-implied direction, logged as SLOPE_SIM_OUTCOME once it hits or   |
//| SlopeSimExpiryHours elapses. Goal 2 (does adding this to the existing  |
//| Stochastic decision help) is answered by cross-referencing SLOPE_CALC  |
//| against the real trade's own MAE_OUTCOME on trades that did place an   |
//| order -- both logged with the same TimeCurrent() timestamp and the     |
//| same signal candle, so they join directly in the CSV.                 |
//| Ground truth on the slope hypothesis (IgnoreStochastic + cross-        |
//| referencing SLOPE_CALC against real outcomes): Stochastic itself       |
//| turned out to matter mostly for tail-risk control, not raw win rate    |
//| (IgnoreStochastic=true kept win rate at 89.26% vs baseline 90.93%, but |
//| NET fell 67% and max holding time went from ~30h to ~132h). MA slope   |
//| does NOT reproduce that role: within TREND-decided trades, FLAT vs     |
//| STEEP win rates were statistically indistinguishable (~91% both), and  |
//| skipping TREND+FLAT entirely would forfeit 763 wins to avoid only 74    |
//| losses (net +47R cost) -- rejected as a Stochastic substitute/filter.  |
//| CIRCUIT_BREAKER_TRIGGERED / CIRCUIT_BREAKER_(WOULD_)SKIP (diagnostic   |
//| always on; UseCircuitBreaker ACTS): after CircuitBreakerLossCount      |
//| consecutive LOSS outcomes (any tag), pauses new entries for            |
//| CircuitBreakerCooldownHours, on the theory that a losing streak may    |
//| flag a temporarily bad regime rather than being pure noise -- a        |
//| different mechanism from every previously-tested idea, which all       |
//| acted on individual trades rather than withholding entries during a    |
//| bad stretch. UNTESTED as a live rule.                                  |
//| Entry-parameter re-optimization (sequential 1-at-a-time sweep via MT5   |
//| Optimizer, Recovery Factor max, after every cut-early idea above was    |
//| tested and rejected): StochK_Period 16->8, StochOverbought 70->85,      |
//| StochOversold unchanged at 30, MinR_Points 400->350. Ground-truth       |
//| confirmed result: NET $16,858.10 -> $24,529.78 (+45.5%), PF 1.286,      |
//| Recovery Factor 10.33, MaxDD 4.05% -> 2.14%.                            |
//| BE_TRIGGER / BE_RETRACE / BE_STOP_MOVED (diagnostic always on;          |
//| UseBreakevenStop ACTS): tests whether moving the stop to breakeven      |
//| (entry price) once a position reaches BreakevenTriggerFrac of TP_R in   |
//| its favor can shrink the size of individual losses without giving up    |
//| much on winners -- distinct from the already-rejected MFE-based         |
//| "give up a slice of TP" idea (reachedFav50/75/90 above), since this     |
//| resets to ~$0 instead of locking in a partial profit, and the trigger   |
//| threshold is independently configurable rather than reusing those      |
//| fixed 50/75/90% milestones. BE_TRIGGER logs when the threshold is first |
//| crossed; BE_RETRACE logs if price later comes back to the entry level   |
//| (the only way this could actually matter, since SL_R >> TP_R here means |
//| a trade can only reach the real SL by first passing back through        |
//| breakeven). The key question answerable from BE_RETRACE trades' own     |
//| MAE_OUTCOME: of trades that retrace all the way back to breakeven after |
//| triggering, what fraction still recover to a WIN (the cost of this      |
//| rule, since UseBreakevenStop would have converted that WIN into ~$0)    |
//| vs continue on to the full LOSS (the benefit, since it would have been  |
//| capped at ~$0 instead). Given SL_R is roughly 9-11x TP_R here, this     |
//| rule is net positive only if the recovered-WIN fraction among retraced  |
//| trades is well below roughly TP_R/(TP_R+SL_R). UNTESTED as a live rule. |
//| Ground truth: rejected -- 90.6% of trades that retraced to breakeven    |
//| after triggering still recovered to a WIN, ~9x above the ~10.1%        |
//| breakeven threshold; going live would have cost the +$5,253 this       |
//| bucket actually made. Diagnostic-only, kept off (UseBreakevenStop=false)|
//| ProtectTriggerR/ProtectR/UseProtectStop (diagnostic always on;          |
//| UseProtectStop ACTS, UNTESTED): a different idea from the rejected      |
//| breakeven stop above -- instead of moving SL to exactly breakeven at    |
//| BreakevenTriggerFrac of TP_R, this locks in a SMALL PROFIT (ProtectR,   |
//| default 0.05R, not 0) at an earlier, TP_R-independent trigger           |
//| (ProtectTriggerR, default 0.25R -- for TP_R~0.45-0.5 this is roughly    |
//| half of TP_R, same shape as 007/005's own protect-lock stage). The      |
//| rejected breakeven test showed giving back the WHOLE favorable move     |
//| at the 50%-of-TP point was too costly (90.6% of retraces still          |
//| recovered to a win); locking a small profit instead of exactly $0,      |
//| and arming earlier, could behave differently -- needs its own           |
//| backtest (PROTECT_TRIGGER logs every arm regardless of UseProtectStop,  |
//| PROTECT_MOVED/PROTECT_MOVE_FAIL log the live SL modify outcome).        |
//| timeMildMin/timeDangerMin (diagnostic only, no trading effect):         |
//| minutes a position spends with adverse excursion below MildZoneR        |
//| (default 2.0, half of SL_R=4.0) vs at/above it. Motivated by a real     |
//| hold-time-vs-loss pattern found in the confirmed baseline (3,273        |
//| trades): losses hold far longer than wins (avg 212min vs 31min) and     |
//| the loss rate jumps sharply past a ~30min threshold (3.5% under 30min   |
//| -> 25-33% beyond it) rather than scaling smoothly with time (plain      |
//| correlation only 0.18) -- this breaks total hold time down by how much  |
//| of it was spent already deep against the position vs still mild.       |
//| DangerTimeStopMin/UseDangerTimeStop (UNTESTED): acts on the above --   |
//| force-closes a position once its cumulative timeDangerMin reaches      |
//| DangerTimeStopMin (default 20min). Ground truth on the confirmed       |
//| baseline (3,273 trades) motivating this: NO trade stays under          |
//| MildZoneR(2R) and still loses (0/2,732); of the 541 that ever cross    |
//| into the danger zone, loss rate climbs with time spent there --        |
//| 28.5% under 5min, 53.5% at 5-15min, 61.4% at 15-30min, 70.6% at        |
//| 30-60min -- far stronger than total hold time alone (corr 0.23 vs      |
//| 0.18) or mild-zone time alone (corr 0.05). Distinct from               |
//| MaxMinutesWithoutProgress (fires on total hold time regardless of      |
//| favorable/adverse) and from ProtectTriggerR/ProtectR above (price-     |
//| level based, already shown to hurt NET/WR at a shallow 0.25R trigger)  |
//| -- this is a TIME cutoff conditional on being meaningfully against     |
//| the position. Needs its own backtest before trusting it live.          |
//| ProtectStopEuropeOnly (REJECTED): the all-hours ProtectTriggerR=0.25/   |
//| ProtectR=0.05 test was REJECTED (NET -33% at 0.1-lot-equivalent, WR    |
//| 92.09%->84.19%, trade count 3,273->3,523 -- the early SL move freed    |
//| MAX1 up faster, letting in more, worse re-entries). Restricting the    |
//| SL-move to only arm while the CURRENT time (when favR crosses          |
//| ProtectTriggerR) falls in the Europe session (16-22 KST) was tested    |
//| against the ComboExit-confirmed baseline (NET $27,148.70, WR 92.01%,   |
//| n=3,273) and still REJECTED: NET $24,015.48 (-11.5%), WR 89.66%        |
//| (-2.35pp), n=3,346 (+73). Of the 866 trades where the SL actually      |
//| moved, WR was even higher than average (95.8%) -- the harm isn't from |
//| those trades themselves, it's the same faster-MAX1-turnover mechanism |
//| as the all-hours test, just reduced in scope (866 vs all 3,176         |
//| triggers) rather than eliminated. Restricting to EU hours only does    |
//| NOT recover the benefit.                                               |
//| ProtectStopAsiaOnly (UNTESTED): same mechanism, restricted instead to  |
//| the Asia session (AsiaSessionStartHour-AsiaSessionEndHour KST, default |
//| 6-16). Needs its own ground-truth backtest -- not assumed from the     |
//| Europe-only result above, since the Asia session's own entry mix       |
//| (TREND_BEAR skipped there by SkipTrendBearAsiaSession) differs.        |
//| SIGNAL's touch=BODY/WICK and MAE_OUTCOME's touch= (diagnostic always   |
//| on; SkipFadeBearOSWickTouch ACTS): the entry condition only requires   |
//| the signal candle's high/low (wick) to reach BB20; this additionally   |
//| checks whether the CLOSE (body) also broke the band ("BODY") vs        |
//| wicked through and closed back inside ("WICK") -- tests whether a body |
//| break (more conviction) behaves differently from a rejection wick.     |
//| Ground truth (2025.01-2026.09, StochK_Period=8/OB=85/OS=30/MinR=350):  |
//| BODY beat WICK consistently on every tag, both on win rate and $/trade:|
//| overall 92.32% ($10.46/trade) vs 89.70% ($0.58/trade, z=2.14) --       |
//| FADE_BEAR_OS 92.7%/+$18,282 vs 88.7%/-$325 (net NEGATIVE, the only     |
//| losing tag x touch combination), TREND_BEAR 93.8%/+$5,378 vs 89.7%/    |
//| +$109, TREND_BULL 91.3%/+$6,031 vs 90.4%/+$563. Only FADE_BEAR_OS+WICK |
//| is actually net negative, so SkipFadeBearOSWickTouch filters only that |
//| combination rather than all WICK touches (TREND_BEAR/TREND_BULL WICK   |
//| are still profitable, just weaker than BODY). CONFIRMED default=true:  |
//| ground-truth backtest showed NET $24,877.21 -> $26,237.13 (+5.5%), PF   |
//| 1.304 -> 1.342, Recovery Factor 9.14 -> 9.58, WR 91.86% -> 92.12%, DD    |
//| essentially unchanged (~2.2%) -- a clean improvement on every metric.  |
//| AsiaSessionStartHour/EndHour (default 6/16, Korea time): the           |
//| SkipTrendBearAsiaSession window bounds. An hour-by-hour breakdown of    |
//| the same data found losses actually concentrate in 06-11 KST, while     |
//| 12-17 KST is profitable -- try narrowing EndHour to 11 to test keeping  |
//| those hours active. Hourly samples are much smaller (20-45 trades/hour  |
//| vs 200+ for the 8h blocks), so treat this as a follow-up experiment,    |
//| not a confirmed result yet.                                            |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M2; // signal-candle timeframe
input double Lots               = 0.1; // Lot size
input int    StochK_Period      = 8;    // Stoch %K period
input int    StochD_Period      = 3; // Stoch %D period
input int    StochSlowing       = 3; // Stoch slowing
input double StochOverbought    = 85.0; // Stoch overbought level
input double StochOversold      = 30.0; // Stoch oversold level
input double SL_R               = 4.0;  // Stop loss (R)
input double TP_R               = 0.45; // Take profit (R)
input double MinR_Points        = 350;  // Min signal-candle body (points) to trade, 0=no filter
input ulong  MagicNumber        = 95016101; // Magic number
input int    MaxDeviationPts    = 50; // Max price deviation (points)
input bool   EnableLiveOrders   = false; // Enable live orders
input bool   AllowSellFade      = false; // Allow bull+overbought SELL-fade case (CONFIRMED false, see header)
input bool   SkipTrendBearAsiaSession = true; // Skip TREND_BEAR during Asia session (CONFIRMED, see header)
input int    AsiaSessionStartHour = 6;   // Asia-session skip window start hour, Korea time
input int    AsiaSessionEndHour   = 16;  // Asia-session skip window end hour, Korea time
input bool   ReverseTrendBearAsiaSession = false; // Reverse TREND_BEAR in Asia session to BUY (UNTESTED, see header)
input int    MaxMinutesWithoutProgress = 0; // Close position after N min regardless of P&L, 0=disabled (UNTESTED, see header)
input bool   UseTrendFilter     = false; // Skip entry if opposing trend on higher TF (UNTESTED, see header)
input ENUM_TIMEFRAMES TrendFilterTimeframe = PERIOD_M15; // Higher timeframe for UseTrendFilter
input int    ADXPeriod          = 14;    // ADX period for UseTrendFilter
input double ADXThreshold       = 25.0;  // ADX trending threshold for UseTrendFilter

input bool   UseOppositeSignalExit = false; // Close on opposite signal past 75% SL_R (UNTESTED, see header)

input int    SlopeLookbackBars  = 5;     // MA slope diagnostic: lookback bars (no trading effect)
input double SlopeThresholdDeg  = 20.0;  // MA slope diagnostic: FLAT/STEEP threshold (degrees)
input double SlopeSimTargetR    = 0.5;   // MA slope diagnostic: simulated target (R)
input double SlopeSimExpiryHours = 6.0;  // MA slope diagnostic: simulation expiry (hours)

input bool   IgnoreStochastic   = false; // Bypass Stochastic decision entirely (UNTESTED, see header)

input int    CircuitBreakerLossCount    = 2;    // Consecutive losses that trigger a pause
input double CircuitBreakerCooldownHours = 6.0; // Pause duration after circuit breaker trips (hours)
input bool   UseCircuitBreaker  = false; // Actually pause entries after a losing streak (UNTESTED, see header)

input double BreakevenTriggerFrac = 0.5; // Fraction of TP_R to arm breakeven stop
input bool   UseBreakevenStop   = false; // Move SL to breakeven once armed (REJECTED, see header)

input double ProtectTriggerR    = 0.25; // Favorable R to arm protect-lock stop (UNTESTED, see header)
input double ProtectR           = 0.05; // SL level once armed, in R (UNTESTED, see header)
input bool   UseProtectStop     = false; // Move SL to ProtectR once armed (UNTESTED, see header)
input bool   ProtectStopEuropeOnly = false; // Restrict ProtectStop arming to Europe session (16-22 KST) only (REJECTED, see header)
input bool   ProtectStopAsiaOnly = false; // Restrict ProtectStop arming to Asia session (AsiaSessionStartHour-AsiaSessionEndHour KST) only (UNTESTED, see header)

input double MildZoneR          = 2.0; // Adverse-R boundary for dwell-time diagnostic (no trading effect)
input double DangerTimeStopMin  = 20.0; // Minutes in danger zone before force-close (UNTESTED, see header)
input bool   UseDangerTimeStop  = false; // Close position once DangerTimeStopMin reached (UNTESTED, see header)

input bool   UseThreeBarExit    = false; // Close position if never profitable in first 3 candles (UNTESTED, see header)

input double ComboExitDangerMin = 10.0; // Danger-zone minutes required, combined with threeBarOneWay (CONFIRMED, see header)
input bool   UseComboExit       = true; // Close only when BOTH threeBarOneWay AND ComboExitDangerMin are met (CONFIRMED, see header)

input bool   SkipFadeBearOSWickTouch = true; // Skip FADE_BEAR_OS wick-only touches (CONFIRMED, see header)

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE,hADX=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

// -- consecutive-loss circuit breaker (diagnostic always on; ACTS only if
//    UseCircuitBreaker=true) --------------------------------------------
int      g_consecutiveLosses=0;
datetime g_breakerActiveUntil=0;

// -- MAE-milestone tracking (diagnostic only except UseOppositeSignalExit) --
// Tracks, for open position(s), whether the adverse excursion has crossed
// 50%/75% of the SL_R distance, and logs the eventual win/loss outcome
// alongside those flags -- lets us answer "given a trade reached 50%/75% of
// its stop, what fraction still won vs lost" from the CSV log, which the
// MT5 Strategy Tester xlsx report does not expose per-trade.
//
// Kept as small parallel arrays (a slot per in-flight tracked position),
// NOT a single set of scalars, because UseOppositeSignalExit can close a
// position and OpenTrade() can open its replacement within the SAME
// CheckNewM2Bar() call, before OnTradeTransaction's close notification for
// the old ticket has been delivered -- with scalars, the new position's
// StartMAETracking() call overwrote the old ticket's tracking data first,
// so the old position's own MAE_OUTCOME line never got logged (confirmed:
// 349 trades silently dropped from the CSV in one such backtest, all of
// them opposite-signal-exit closes -- the official xlsx trade/loss counts
// didn't match what the "corrupted" CSV appeared to show). Slots are found
// by ticket, not by position/order, so a same-tick close+reopen can never
// collide.
#define TRACK_SLOTS 4
ulong  g_trackTicket[TRACK_SLOTS];
double g_trackEntry[TRACK_SLOTS], g_trackR[TRACK_SLOTS];
int    g_trackDir[TRACK_SLOTS];
bool   g_reached50[TRACK_SLOTS], g_reached75[TRACK_SLOTS];
string g_trackTag[TRACK_SLOTS];

// -- first-bar-after-entry direction (diagnostic only) ----------------------
// Checks whether the very next M2 bar to close after entry moved WITH or
// AGAINST the trade's direction -- tests the hypothesis that an immediate
// opposite-direction bar predicts a one-way move into the stop.
bool   g_waitingFirstBar[TRACK_SLOTS];
bool   g_firstBarKnown[TRACK_SLOTS], g_firstBarOneWay[TRACK_SLOTS];

// -- first-3-bars-after-entry direction (diagnostic only) --------------------
// Extends the above over the entry candle plus the next 2 (3 candles total):
// tracks the running favorable extreme (highest high for a BUY, lowest low
// for a SELL) across all 3 and checks whether it EVER closed above entry
// (BUY) / below entry (SELL) at any point -- i.e. whether the position was
// ever in profit during those 3 candles, not just whether each candle
// individually closed favorably.
bool   g_waitingBar3[TRACK_SLOTS];
int    g_bar3Count[TRACK_SLOTS];
double g_bar3Extreme[TRACK_SLOTS];
bool   g_bar3Known[TRACK_SLOTS], g_bar3OneWay[TRACK_SLOTS];
bool   g_comboExited[TRACK_SLOTS]; // UseComboExit already force-closed this slot (prevents a double-close attempt)

// -- band-reentry tracking (diagnostic only) ---------------------------------
// The entry signal is a BB20 breakout; this checks whether price later
// crosses back to the OTHER side of that same (frozen, as-of-entry) BB20
// level -- i.e. the breakout "gave back" and failed to hold. Cheap to check
// every tick (no waiting for a bar close), unlike the opposite-signal-candle
// idea, which only fires on a full new breakout in the other direction and
// would already be very late. Logged as its own milestone, and also cross-
// referenced with reached50/75 on the outcome line. Ground-truth result:
// bandReentry=true overlapped 100% with reached75=true, so it added no
// separating power beyond MAE depth alone.
double g_lastBandLevel=0; // transient handoff value, set right before OpenTrade()
double g_trackBandLevel[TRACK_SLOTS];
bool   g_bandReentered[TRACK_SLOTS];

// -- BODY vs WICK touch tracking (diagnostic only, no trading effect) -------
// Tests whether a signal candle whose CLOSE also broke the band ("BODY")
// behaves differently from one where only the high/low wicked through it
// while closing back inside ("WICK") -- a body break arguably shows more
// conviction/follow-through than a rejection wick.
bool   g_lastBodyTouch=true; // transient handoff value, set right before OpenTrade()
bool   g_trackBodyTouch[TRACK_SLOTS];

// -- opposite-signal tracking (diagnostic, always on; ACTS only if
//    UseOppositeSignalExit=true AND reached75=true for that slot) ----------
// Tracks whether a NEW opposite-direction M2 signal candle (same BB20/BB4
// breakout + R filter used for entries) appeared at any point while the
// position was open. Logged regardless of UseOppositeSignalExit so we can
// ask "of trades that hit SL, what fraction had an opposite signal candle
// appear before the loss" and "of trades where it appeared, what fraction
// still hit TP anyway" with zero trading effect. Ground truth: unconditional
// opposite-signal exit (any occurrence) was net negative (NET $17,746 ->
// $12,245) because it also cut ~131 trades that never got past a shallow
// pullback and had a 100% natural win rate -- requiring reached75 too
// targets only the already-known 26%-win-rate danger zone instead.
bool   g_trackOppSignalSeen[TRACK_SLOTS];

// -- MFE (Maximum Favorable Excursion) tracking (diagnostic only, no
//    trading effect) ---------------------------------------------------
// Mirrors the MAE tracking above but for the FAVORABLE direction: tracks
// whether price moved 50%/75%/90% of the way to TP_R (in R terms) at any
// point before the position closed. Since a real TP fill closes the
// position immediately, this can only ever show "got close to TP, then
// ended in outcome X" -- not "hit TP and still lost". Answers: of trades
// that got to 75%/90% of the way to TP, what fraction still reversed all
// the way to a LOSS instead of continuing on to the TP? Given SL_R is far
// larger than TP_R here, if that reversal rate is low, a breakeven/lock-in
// rule once price is most of the way to TP could be asymmetrically
// favorable (small give-up vs a large avoided loss) -- the OPPOSITE
// asymmetry from the MAE-side cuts already tested and rejected.
bool   g_reachedFav50[TRACK_SLOTS], g_reachedFav75[TRACK_SLOTS], g_reachedFav90[TRACK_SLOTS];

// -- breakeven-stop simulation (diagnostic always on; ACTS only if
//    UseBreakevenStop=true) -- see header for the BE_TRIGGER/BE_RETRACE
//    hypothesis --------------------------------------------------------
bool   g_beTriggered[TRACK_SLOTS]; // favFrac >= BreakevenTriggerFrac reached at least once
bool   g_beRetraced[TRACK_SLOTS];  // price came back to the entry level AFTER g_beTriggered
bool   g_beMoved[TRACK_SLOTS];     // live SL was actually moved to breakeven (UseBreakevenStop only)

// -- protect-lock stop simulation (diagnostic always on; ACTS only if
//    UseProtectStop=true) -- see header for the ProtectTriggerR/ProtectR
//    hypothesis. Distinct from the already-rejected breakeven-stop above:
//    this locks a small PROFIT (ProtectR, not 0) at an earlier trigger
//    (ProtectTriggerR, independent of TP_R) rather than moving to
//    breakeven at a fraction of TP_R ----------------------------------
bool   g_protectTriggered[TRACK_SLOTS]; // favR >= ProtectTriggerR reached at least once
bool   g_protectMoved[TRACK_SLOTS];     // live SL was actually moved to the protect-lock level (UseProtectStop only)

// -- dwell-time tracking (diagnostic only, no trading effect): how many
//    minutes a position spends with adverse excursion BELOW MildZoneR
//    (default 2.0, i.e. under half of SL_R=4.0 -- "not yet dangerous") vs
//    AT/ABOVE it ("danger zone", closer to the stop). Answers: does time
//    spent in the mild zone before eventually stopping out differ from
//    winning trades, separate from total hold time? ---------------------
datetime g_trackLastSample[TRACK_SLOTS];
double   g_timeMildMin[TRACK_SLOTS];   // minutes spent with adverseR < MildZoneR
double   g_timeDangerMin[TRACK_SLOTS]; // minutes spent with adverseR >= MildZoneR

// -- MA-slope hypothesis simulation (diagnostic only, no trading effect,
//    independent of TRACK_SLOTS/real positions -- see header comment) ------
// One slot per signal candle (not per position), since this tests every
// signal regardless of whether Stochastic/session filters would trade it.
#define SLOPE_SLOTS 32
bool     g_slopeActive[SLOPE_SLOTS];
double   g_slopeEntry[SLOPE_SLOTS], g_slopeR[SLOPE_SLOTS];
int      g_slopeDir[SLOPE_SLOTS];
bool     g_slopeHit[SLOPE_SLOTS];
datetime g_slopeStart[SLOPE_SLOTS];
double   g_slopeDegVal[SLOPE_SLOTS];
string   g_slopeTag[SLOPE_SLOTS];

void StartSlopeSim(double entry,double R,int dir,double degVal,string tag)
{
   int i=-1;
   for(int k=0;k<SLOPE_SLOTS;k++) if(!g_slopeActive[k]){ i=k; break; }
   if(i<0){ Log("SLOPE_SLOTS_FULL","dropping slope simulation | "+tag); return; }
   g_slopeActive[i]=true; g_slopeEntry[i]=entry; g_slopeR[i]=R; g_slopeDir[i]=dir;
   g_slopeHit[i]=false; g_slopeStart[i]=TimeCurrent(); g_slopeDegVal[i]=degVal; g_slopeTag[i]=tag;
}

void CheckSlopeSims()
{
   bool anyActive=false;
   for(int i=0;i<SLOPE_SLOTS;i++) if(g_slopeActive[i]){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<SLOPE_SLOTS;i++)
   {
      if(!g_slopeActive[i]) continue;
      if(!g_slopeHit[i])
      {
         double favR=(g_slopeDir[i]==+1) ? (q.bid-g_slopeEntry[i])/g_slopeR[i] : (g_slopeEntry[i]-q.ask)/g_slopeR[i];
         if(favR>=SlopeSimTargetR) g_slopeHit[i]=true;
      }
      double hoursElapsed=(double)(TimeCurrent()-g_slopeStart[i])/3600.0;
      if(g_slopeHit[i] || hoursElapsed>=SlopeSimExpiryHours)
      {
         Log("SLOPE_SIM_OUTCOME","hit="+(g_slopeHit[i]?"true":"false")+" hours="+DoubleToString(hoursElapsed,2)+
             " slopeDeg="+DoubleToString(g_slopeDegVal[i],2)+" | "+g_slopeTag[i]);
         g_slopeActive[i]=false;
      }
   }
}

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
   if(i<0){ Log("TRACK_SLOTS_FULL","dropping MAE tracking for ticket="+IntegerToString((int)ticket)); return; }
   g_trackTicket[i]=ticket; g_trackEntry[i]=entry; g_trackR[i]=R; g_trackDir[i]=dir;
   g_reached50[i]=false; g_reached75[i]=false; g_trackTag[i]=tag;
   g_waitingFirstBar[i]=true; g_firstBarKnown[i]=false; g_firstBarOneWay[i]=false;
   g_waitingBar3[i]=true; g_bar3Count[i]=0; g_bar3Extreme[i]=0; g_bar3Known[i]=false; g_bar3OneWay[i]=false;
   g_comboExited[i]=false;
   g_trackBandLevel[i]=g_lastBandLevel; g_bandReentered[i]=false;
   g_trackOppSignalSeen[i]=false;
   g_reachedFav50[i]=false; g_reachedFav75[i]=false; g_reachedFav90[i]=false;
   g_beTriggered[i]=false; g_beRetraced[i]=false; g_beMoved[i]=false;
   g_protectTriggered[i]=false; g_protectMoved[i]=false;
   g_trackLastSample[i]=TimeCurrent(); g_timeMildMin[i]=0; g_timeDangerMin[i]=0;
   g_trackBodyTouch[i]=g_lastBodyTouch;
}

// Called from CheckNewM2Bar with the new bar's raw breakout direction
// (sigdir, before the stochastic fade/trend decision -- that decision only
// matters for what a NEW entry would trade, not for detecting that the
// opposite technical signal fired). If UseOppositeSignalExit is on AND the
// slot has already reached 75% of SL, also closes the position at market.
void CheckOppositeSignal(int sigdir)
{
   if(sigdir==0) return;
   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(sigdir!=-g_trackDir[i]) continue; // only the OPPOSITE of the position's direction counts

      if(!g_trackOppSignalSeen[i])
      {
         g_trackOppSignalSeen[i]=true;
         Log("MAE_MILESTONE","opposite signal candle appeared | "+g_trackTag[i]);
      }

      if(!UseOppositeSignalExit) continue;
      if(!g_reached75[i]) continue; // only act in the already-known danger zone (see input comment)
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // already closed

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("OPP_SIGNAL_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+" profit="+DoubleToString(profit,2)+
             " (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         continue;
      }
      if(trade.PositionClose(g_trackTicket[i]))
         Log("OPP_SIGNAL_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+" profit="+DoubleToString(profit,2)+
             " | "+g_trackTag[i]);
      else
         Log("OPP_SIGNAL_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
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
      double frac=adverseR/SL_R;
      if(frac>=0.5  && !g_reached50[i]){ g_reached50[i]=true; Log("MAE_MILESTONE","50% of SL reached | "+g_trackTag[i]); }
      if(frac>=0.75 && !g_reached75[i]){ g_reached75[i]=true; Log("MAE_MILESTONE","75% of SL reached | "+g_trackTag[i]); }

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
         continue;
      }

      double favR=(g_trackDir[i]==+1) ? (q.bid-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-q.ask)/g_trackR[i];
      double favFrac=favR/TP_R;
      if(favFrac>=0.5  && !g_reachedFav50[i]){ g_reachedFav50[i]=true; Log("MAE_MILESTONE","50% of TP reached (favorable) | "+g_trackTag[i]); }
      if(favFrac>=0.75 && !g_reachedFav75[i]){ g_reachedFav75[i]=true; Log("MAE_MILESTONE","75% of TP reached (favorable) | "+g_trackTag[i]); }
      if(favFrac>=0.9  && !g_reachedFav90[i]){ g_reachedFav90[i]=true; Log("MAE_MILESTONE","90% of TP reached (favorable) | "+g_trackTag[i]); }

      if(!g_protectTriggered[i] && favR>=ProtectTriggerR)
      {
         g_protectTriggered[i]=true;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
         if(UseProtectStop && (!ProtectStopEuropeOnly || InEuropeSessionKST(TimeCurrent()))
                            && (!ProtectStopAsiaOnly   || InAsiaSessionKST(TimeCurrent())))
         {
            double curTP=PositionGetDouble(POSITION_TP);
            double lock=NormalizeDouble(g_trackEntry[i]+g_trackDir[i]*ProtectR*g_trackR[i],_Digits);
            if(!EnableLiveOrders)
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

      if(!g_bandReentered[i] && g_trackBandLevel[i]!=0)
      {
         bool reentered=(g_trackDir[i]==+1) ? (q.bid<g_trackBandLevel[i]) : (q.ask>g_trackBandLevel[i]);
         if(reentered){ g_bandReentered[i]=true; Log("MAE_MILESTONE","band reentry (breakout failed) | "+g_trackTag[i]); }
      }

      if(!g_beTriggered[i] && favFrac>=BreakevenTriggerFrac)
      {
         g_beTriggered[i]=true;
         Log("BE_TRIGGER","favFrac="+DoubleToString(favFrac,3)+" | "+g_trackTag[i]);
         if(UseBreakevenStop)
         {
            double curTP=PositionGetDouble(POSITION_TP);
            double be=NormalizeDouble(g_trackEntry[i],_Digits);
            if(!EnableLiveOrders)
               Log("BE_STOP_MOVE_DRY","would move SL->"+DoubleToString(be,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],be,curTP))
            {
               g_beMoved[i]=true;
               Log("BE_STOP_MOVED","SL->"+DoubleToString(be,_Digits)+" | "+g_trackTag[i]);
            }
            else
               Log("BE_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }
      if(g_beTriggered[i] && !g_beRetraced[i])
      {
         bool retraced=(g_trackDir[i]==+1) ? (q.bid<=g_trackEntry[i]) : (q.ask>=g_trackEntry[i]);
         if(retraced){ g_beRetraced[i]=true; Log("BE_RETRACE","price returned to entry after BE trigger | "+g_trackTag[i]); }
      }
   }
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_001_STOCH_v2 | ",event," | ",detail);
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
// 01:00 UTC-ish to last Sunday of October, approximated here by date only
// (the exact hour of the switchover is immaterial at this granularity).
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
   return (h>=AsiaSessionStartHour && h<AsiaSessionEndHour);
}

bool InEuropeSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=16 && h<22);
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

// Skips an entry if a strong opposing trend is already established on
// TrendFilterTimeframe: ADX >= ADXThreshold (a trend, by the standard
// convention) AND the dominant DI is pointed against our intended direction.
bool OpposingTrendTooStrong(int dir)
{
   if(!UseTrendFilter) return false;
   double adxBuf[1],plusDI[1],minusDI[1];
   if(CopyBuffer(hADX,0,1,1,adxBuf)!=1) return false;
   if(CopyBuffer(hADX,1,1,1,plusDI)!=1) return false;
   if(CopyBuffer(hADX,2,1,1,minusDI)!=1) return false;
   if(adxBuf[0]<ADXThreshold) return false;
   if(dir==+1 && minusDI[0]>plusDI[0]) return true; // trying to BUY into a strong downtrend
   if(dir==-1 && plusDI[0]>minusDI[0]) return true; // trying to SELL into a strong uptrend
   return false;
}

void CheckTimeStop()
{
   if(MaxMinutesWithoutProgress<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      double minutesOpen=(double)(TimeCurrent()-opened)/60.0;
      if(minutesOpen<MaxMinutesWithoutProgress) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("TIME_STOP_DRY","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false)");
         continue;
      }
      if(trade.PositionClose(tk))
         Log("TIME_STOP_CLOSE","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2));
      else
         Log("TIME_STOP_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
}

// Force-closes a position once it has spent DangerTimeStopMin cumulative
// minutes with adverse excursion >= MildZoneR (see timeDangerMin header
// note) -- distinct from CheckTimeStop/MaxMinutesWithoutProgress, which
// fires on TOTAL hold time regardless of how favorable/adverse price was.
void CheckDangerTimeStop()
{
   if(!UseDangerTimeStop) return;
   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(g_timeDangerMin[i]<DangerTimeStopMin) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // already closed

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("DANGER_TIME_STOP_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
             " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+" profit="+DoubleToString(profit,2)+
             " (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         continue;
      }
      if(trade.PositionClose(g_trackTicket[i]))
         Log("DANGER_TIME_STOP_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
             " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+" profit="+DoubleToString(profit,2)+
             " | "+g_trackTag[i]);
      else
         Log("DANGER_TIME_STOP_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
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
   if(OpposingTrendTooStrong(dir)){ Log("ENTRY_SKIPPED","opposing trend too strong (ADX filter) | "+tag); return; }
   if(TimeCurrent()<g_breakerActiveUntil)
   {
      Log(UseCircuitBreaker?"CIRCUIT_BREAKER_SKIP":"CIRCUIT_BREAKER_WOULD_SKIP",
          "until="+TS(g_breakerActiveUntil)+" | "+tag);
      if(UseCircuitBreaker) return;
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

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingFirstBar[i]) continue;
      // "one-way against": price never moved favorably by even 1 point during
      // this bar -- for a BUY, the bar's high never exceeded the entry price;
      // for a SELL, the bar's low never went below it. Uses h/l (the bar's
      // extremes), not open/close, since a bar can close red while still
      // having ticked favorably first.
      g_firstBarOneWay[i]=(g_trackDir[i]==+1) ? (h<=g_trackEntry[i]) : (l>=g_trackEntry[i]);
      g_firstBarKnown[i]=true;
      g_waitingFirstBar[i]=false;
   }

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

         if(UseThreeBarExit && g_bar3OneWay[i] && PositionSelectByTicket(g_trackTicket[i]))
         {
            double profit=PositionGetDouble(POSITION_PROFIT);
            if(!EnableLiveOrders)
               Log("THREE_BAR_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionClose(g_trackTicket[i]))
               Log("THREE_BAR_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
            else
               Log("THREE_BAR_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
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
   // CLOSE (body) also closed beyond BB20, i.e. a "real" break vs a rejection
   // wick that poked through and closed back inside.
   bool bodyTouch=(sigdir==+1) ? (c>=up20[0]) : (c<=lo20[0]);

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR){ Log("SIGNAL_SKIPPED","R too small"); return; }

   CheckOppositeSignal(sigdir);

   // -- MA-slope hypothesis (diagnostic only, no trading effect) --------------
   // See header comment for the exact pseudo-angle definition and rationale.
   // Also computes the same pseudo-angle at fixed 2/3-bar lookbacks alongside
   // the configurable SlopeLookbackBars one, so a single backtest can compare
   // which lookback best separates eventual win/loss without re-running --
   // the user's own chart-watching suggests a short lookback (2-3 bars right
   // at the signal candle) may match what they see as "flat" better than a
   // longer one.
   double maNow[1];
   int rNow=CopyBuffer(hBB20,0,1,1,maNow);
   if(rNow==1)
   {
      double maPrev2[1],maPrev3[1],maPrev5[1],maPrevCfg[1];
      int r2=CopyBuffer(hBB20,0,1+2,1,maPrev2);
      int r3=CopyBuffer(hBB20,0,1+3,1,maPrev3);
      int r5=CopyBuffer(hBB20,0,1+5,1,maPrev5);
      int rCfg=CopyBuffer(hBB20,0,1+SlopeLookbackBars,1,maPrevCfg);
      double deg2=(r2==1) ? MathArctan((maNow[0]-maPrev2[0])/(2*R))*180.0/M_PI : 0;
      double deg3=(r3==1) ? MathArctan((maNow[0]-maPrev3[0])/(3*R))*180.0/M_PI : 0;
      double deg5=(r5==1) ? MathArctan((maNow[0]-maPrev5[0])/(5*R))*180.0/M_PI : 0;

      if(rCfg==1)
      {
         double slopeNorm=(maNow[0]-maPrevCfg[0])/(SlopeLookbackBars*R);
         double slopeDeg=MathArctan(slopeNorm)*180.0/M_PI;
         bool   flat=(MathAbs(slopeDeg)<=SlopeThresholdDeg);
         int    slopeDir=flat ? -sigdir : sigdir; // FLAT=fade the breakout, STEEP=follow it
         string slopeClass=flat?"FLAT":"STEEP";
         string slopeTag=(sigdir==1?"BULL":"BEAR")+string("_")+slopeClass;
         Log("SLOPE_CALC","sigdir="+(sigdir==1?"BULL":"BEAR")+" slopeDeg="+DoubleToString(slopeDeg,2)+
             " class="+slopeClass+" hypDir="+(slopeDir==1?"BUY":"SELL")+
             " deg2="+DoubleToString(deg2,2)+" deg3="+DoubleToString(deg3,2)+" deg5="+DoubleToString(deg5,2));
         MqlTick sq; if(SymbolInfoTick(_Symbol,sq)) StartSlopeSim((sq.bid+sq.ask)/2.0,R,slopeDir,slopeDeg,slopeTag);
      }
      else
         Log("SLOPE_CALC_FAIL","BB20 basis (configured lookback) CopyBuffer failed");
   }
   else
      Log("SLOPE_CALC_FAIL","BB20 basis (now) CopyBuffer failed");

   double stochK=0;
   if(!IgnoreStochastic)
   {
      double kbuf[1];
      if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
      stochK=kbuf[0];
   }

   int dir=0; string tag="";
   if(IgnoreStochastic)
   {
      // UNTESTED -- always trades the breakout's own direction (trend-following),
      // bypassing the Stochastic OB/OS branch (and AllowSellFade, which only
      // applies to that branch) entirely. Session filters on TREND_BEAR still
      // apply since those are a separate, orthogonal finding.
      if(sigdir==+1) { dir=+1; tag="TREND_BULL_NOSTOCH"; }
      else
      {
         if(InAsiaSessionKST(sig))
         {
            if(ReverseTrendBearAsiaSession){ dir=+1; tag="TREND_BEAR_REV_ASIA_NOSTOCH"; }
            else if(SkipTrendBearAsiaSession)
            { Log("SIGNAL_SKIPPED","TREND-BEAR disabled during Asia session (06-16 KST) by SkipTrendBearAsiaSession=true"); return; }
            else { dir=-1; tag="TREND_BEAR_NOSTOCH"; }
         }
         else { dir=-1; tag="TREND_BEAR_NOSTOCH"; }
      }
   }
   else if(sigdir==+1) // bull signal candle
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
         if(!bodyTouch && SkipFadeBearOSWickTouch)
         { Log("SIGNAL_SKIPPED","FADE_BEAR_OS disabled on WICK-only touch by SkipFadeBearOSWickTouch=true"); return; }
         dir=+1; tag="STOCH_FADE_BEAR_OS";
      }
      else
      {
         if(InAsiaSessionKST(sig))
         {
            if(ReverseTrendBearAsiaSession){ dir=+1; tag="STOCH_TREND_BEAR_REV_ASIA"; }
            else if(SkipTrendBearAsiaSession)
            { Log("SIGNAL_SKIPPED","TREND-BEAR disabled during Asia session (06-16 KST) by SkipTrendBearAsiaSession=true"); return; }
            else { dir=-1; tag="STOCH_TREND_BEAR"; }
         }
         else { dir=-1; tag="STOCH_TREND_BEAR"; }
      }
   }

   // Band-reentry tracking only makes sense for trend-following trades (dir
   // matches the breakout direction) -- for a fade trade, price returning
   // toward/across that same band is the EXPECTED favorable direction, not
   // a failure signal, so disable the check there (0 = disabled).
   g_lastBandLevel=(dir==sigdir) ? (sigdir==+1 ? up20[0] : lo20[0]) : 0;
   g_lastBodyTouch=bodyTouch;

   if(!IgnoreStochastic) tag=tag+"K"+IntegerToString((int)MathRound(stochK)); // comment length: keep short, MT5 caps at 31 chars

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
   hADX=iADX(_Symbol,TrendFilterTimeframe,ADXPeriod);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hStoch==INVALID_HANDLE || hADX==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_BB_LIVE_001_STOCH_v2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
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
       " | SkipTrendBearAsiaSession="+(SkipTrendBearAsiaSession?"true":"false")+
       " | AsiaWindow="+IntegerToString(AsiaSessionStartHour)+"-"+IntegerToString(AsiaSessionEndHour)+"KST"+
       " | ReverseTrendBearAsiaSession="+(ReverseTrendBearAsiaSession?"true":"false")+
       " | MaxMinutesWithoutProgress="+IntegerToString(MaxMinutesWithoutProgress)+
       " | UseTrendFilter="+(UseTrendFilter?"true":"false")+
       " | TrendFilterTF="+EnumToString(TrendFilterTimeframe)+" ADXPeriod="+IntegerToString(ADXPeriod)+
       " ADXThreshold="+DoubleToString(ADXThreshold,1)+
       " | UseOppositeSignalExit="+(UseOppositeSignalExit?"true":"false")+
       " | SlopeLookbackBars="+IntegerToString(SlopeLookbackBars)+" SlopeThresholdDeg="+DoubleToString(SlopeThresholdDeg,1)+
       " SlopeSimTargetR="+DoubleToString(SlopeSimTargetR,2)+" SlopeSimExpiryHours="+DoubleToString(SlopeSimExpiryHours,1)+
       " | IgnoreStochastic="+(IgnoreStochastic?"true":"false")+
       " | CircuitBreakerLossCount="+IntegerToString(CircuitBreakerLossCount)+
       " CircuitBreakerCooldownHours="+DoubleToString(CircuitBreakerCooldownHours,1)+
       " UseCircuitBreaker="+(UseCircuitBreaker?"true":"false")+
       " | BreakevenTriggerFrac="+DoubleToString(BreakevenTriggerFrac,2)+
       " UseBreakevenStop="+(UseBreakevenStop?"true":"false")+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+" ProtectStopEuropeOnly="+(ProtectStopEuropeOnly?"true":"false")+
       " ProtectStopAsiaOnly="+(ProtectStopAsiaOnly?"true":"false")+
       " | MildZoneR="+DoubleToString(MildZoneR,2)+" DangerTimeStopMin="+DoubleToString(DangerTimeStopMin,1)+
       " UseDangerTimeStop="+(UseDangerTimeStop?"true":"false")+
       " | UseThreeBarExit="+(UseThreeBarExit?"true":"false")+
       " | ComboExitDangerMin="+DoubleToString(ComboExitDangerMin,1)+" UseComboExit="+(UseComboExit?"true":"false")+
       " | SkipFadeBearOSWickTouch="+(SkipFadeBearOSWickTouch?"true":"false")+
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
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckDangerTimeStop();
   CheckSlopeSims();
   CheckTimeStop();
   CheckNewM2Bar();
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

   // Includes DEAL_COMMISSION -- an earlier version omitted it, so a CSV-summed
   // NET was off from the official xlsx by ~$1.50/trade (the round-turn
   // commission on a 0.1-lot XAUUSD position on this broker).
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   string outcome=(profit>0?"WIN":"LOSS");
   string firstBarStr=(!g_firstBarKnown[i] ? "unknown" : (g_firstBarOneWay[i]?"true":"false"));
   string bar3Str=(!g_bar3Known[i] ? "unknown" : (g_bar3OneWay[i]?"true":"false"));
   string bandStr=(g_trackBandLevel[i]==0 ? "n/a(fade)" : (g_bandReentered[i]?"true":"false"));
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " reached50="+(g_reached50[i]?"true":"false")+" reached75="+(g_reached75[i]?"true":"false")+
       " firstBarOneWay="+firstBarStr+" threeBarOneWay="+bar3Str+" bandReentry="+bandStr+
       " oppSignalSeen="+(g_trackOppSignalSeen[i]?"true":"false")+
       " reachedFav50="+(g_reachedFav50[i]?"true":"false")+
       " reachedFav75="+(g_reachedFav75[i]?"true":"false")+
       " reachedFav90="+(g_reachedFav90[i]?"true":"false")+
       " beTriggered="+(g_beTriggered[i]?"true":"false")+
       " beRetraced="+(g_beRetraced[i]?"true":"false")+
       " beMoved="+(g_beMoved[i]?"true":"false")+
       " protectTriggered="+(g_protectTriggered[i]?"true":"false")+
       " protectMoved="+(g_protectMoved[i]?"true":"false")+
       " timeMildMin="+DoubleToString(g_timeMildMin[i],1)+
       " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
       " touch="+(g_trackBodyTouch[i]?"BODY":"WICK")+
       " | "+g_trackTag[i]);
   g_trackTicket[i]=0; // free slot
   g_waitingFirstBar[i]=false;
   g_waitingBar3[i]=false;

   if(outcome=="LOSS")
   {
      g_consecutiveLosses++;
      if(g_consecutiveLosses>=CircuitBreakerLossCount)
      {
         g_breakerActiveUntil=TimeCurrent()+(datetime)(CircuitBreakerCooldownHours*3600);
         Log("CIRCUIT_BREAKER_TRIGGERED","consecutiveLosses="+IntegerToString(g_consecutiveLosses)+
             " cooldownUntil="+TS(g_breakerActiveUntil));
         g_consecutiveLosses=0; // require a fresh streak to trigger again after this cooldown
      }
   }
   else
      g_consecutiveLosses=0;
}
//+------------------------------------------------------------------+
