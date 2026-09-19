"""A genuinely different signal from 004/005/007: trend-following Donchian
channel breakout with an ATR trailing exit (Turtle-style), instead of the
countertrend BB-breakout-extension-pullback logic.

Rationale: 004/005/007 all fade a breakout after a short pullback -- their
edge lives in a 10-30 second mean-reversion window (measured separately),
making them fragile to execution latency and mutually correlated (004/007
share the same M10 signal). A multi-bar trend-following system instead:

  - Enters on a genuine N1-bar Donchian breakout (new N1-bar high/low),
    trading WITH the move, not against it.
  - Exits on either a shorter N2-bar opposite breakout (trend exhaustion)
    or an ATR-multiple trailing stop, whichever hits first -- no fixed
    take-profit, so a real multi-day trend is not capped early.
  - Holding periods are hours-to-days, not seconds, so a few seconds of
    order latency is immaterial to the edge (unlike the BB-countertrend
    family).

All levels are computed causally from fully-closed bars (shifted by one),
and every stop/breakout is resolved tick-by-tick in real chronological
bid/ask order, exactly like the rest of this engine.
"""

from collections import deque

from .strategies import Trade, CONTRACT_OZ_PER_LOT, COMMISSION_PER_0_01_LOT_ROUNDTURN, LOT_UNIT


class DonchianATR:
    def __init__(self, entry_n, exit_n, atr_n=14):
        self.entry_n = entry_n
        self.exit_n = exit_n
        self.atr_n = atr_n
        maxlen = max(entry_n, exit_n)
        self.highs = deque(maxlen=maxlen)
        self.lows = deque(maxlen=maxlen)
        self.prev_close = None
        self.atr = None

    def on_bar_close(self, o, h, l, c):
        """Returns (entry_high, entry_low, exit_high, exit_low, atr) computed
        from bars STRICTLY BEFORE this one (no lookahead), then rolls this
        bar into history for the next call."""
        entry_high = max(list(self.highs)[-self.entry_n:]) if len(self.highs) >= self.entry_n else None
        entry_low = min(list(self.lows)[-self.entry_n:]) if len(self.lows) >= self.entry_n else None
        exit_high = max(list(self.highs)[-self.exit_n:]) if len(self.highs) >= self.exit_n else None
        exit_low = min(list(self.lows)[-self.exit_n:]) if len(self.lows) >= self.exit_n else None

        tr = (h - l) if self.prev_close is None else max(h - l, abs(h - self.prev_close), abs(l - self.prev_close))
        self.atr = tr if self.atr is None else (self.atr * (self.atr_n - 1) + tr) / self.atr_n

        self.highs.append(h)
        self.lows.append(l)
        self.prev_close = c
        return entry_high, entry_low, exit_high, exit_low, self.atr


class TrendBreakoutTracker:
    """Bar-driven breakout detector + tick-driven trailing-exit position
    manager, single position at a time (MAX1, like the other strategies)."""

    def __init__(self, name, period_seconds, entry_n=20, exit_n=10, atr_n=14,
                 stop_atr_mult=2.0, lots=0.01, allow_short=True):
        self.name = name
        self.period = period_seconds
        self.lots = lots
        self.stop_atr_mult = stop_atr_mult
        self.allow_short = allow_short
        self.donchian = DonchianATR(entry_n, exit_n, atr_n)

        self.entry_high = None
        self.entry_low = None
        self.exit_high = None
        self.exit_low = None

        self.position = None  # {'dir','entry','entry_time','stop','atr','highest_close','lowest_close'}

    def on_bar_close(self, o, h, l, c):
        eh, el, xh, xl, atr = self.donchian.on_bar_close(o, h, l, c)
        self.entry_high, self.entry_low, self.exit_high, self.exit_low = eh, el, xh, xl
        self._last_atr = atr
        if self.position is not None:
            if self.position['dir'] == 1:
                self.position['highest_close'] = max(self.position['highest_close'], c)
            else:
                self.position['lowest_close'] = min(self.position['lowest_close'], c)

    def manage(self, ts, bid, ask, trades):
        # 1) manage existing position: trailing/opposite-breakout exit or ATR stop
        p = self.position
        if p is not None:
            dir_ = p['dir']
            px = bid if dir_ == 1 else ask  # executable close side
            stop_hit = px <= p['stop'] if dir_ == 1 else px >= p['stop']
            exit_signal = (self.exit_low is not None and dir_ == 1 and px <= self.exit_low) or \
                          (self.exit_high is not None and dir_ == -1 and px >= self.exit_high)
            if stop_hit or exit_signal:
                self._close(ts, px, 'STOP' if stop_hit else 'TREND_EXIT', trades)
                return

        # 2) look for a fresh breakout entry (only if flat)
        if self.position is None and self.entry_high is not None and self.entry_low is not None:
            if ask >= self.entry_high:
                self._open(1, ts, ask)
            elif self.allow_short and bid <= self.entry_low:
                self._open(-1, ts, bid)

    def _open(self, dir_, ts, entry_price):
        atr = self._last_atr or 0.0
        stop = entry_price - dir_ * self.stop_atr_mult * atr
        self.position = {
            'dir': dir_, 'entry': entry_price, 'entry_time': ts, 'stop': stop, 'atr': atr,
            'highest_close': entry_price, 'lowest_close': entry_price,
        }

    def _close(self, ts, price, reason, trades):
        p = self.position
        dir_ = p['dir']
        gross = (price - p['entry']) * dir_ * self.lots * CONTRACT_OZ_PER_LOT
        commission = (self.lots / LOT_UNIT) * COMMISSION_PER_0_01_LOT_ROUNDTURN
        net = gross - commission
        r = (price - p['entry']) * dir_ / p['atr'] / self.stop_atr_mult if p['atr'] else 0.0
        trades.append(Trade(self.name, p['entry_time'], p['entry'], ts, price, dir_,
                             self.lots, r, gross, commission, net, reason))
        self.position = None
