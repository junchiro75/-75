"""Per-strategy position/exit economics, matching each EA's REAL-account
execution path (EnableLiveOrders=true), not the research-only virtual stats.

004 and 005 share identical real-account exit mechanics (0.01 lot, SL=2R,
whole-position lock to +0.25R once +0.5R is touched, TP=+0.9R, no timeout) --
they differ only in which SignalTracker feeds them (M10 vs M2). 007 differs:
0.02 lot, TP is anchored to the signal bar's close (not entry), a genuine
50% partial close at +1.0R, and a 168h timeout force-close.

Contract: 100 oz / lot (0.01 lot = $1 P&L per $1 XAUUSD move).
Commission: $0.15 per 0.01 lot, round-turn, charged proportionally to volume
closed on every closing fill (full or partial).
"""

from dataclasses import dataclass

CONTRACT_OZ_PER_LOT = 100.0
COMMISSION_PER_0_01_LOT_ROUNDTURN = 0.15
LOT_UNIT = 0.01


@dataclass
class Trade:
    strategy: str
    entry_time: int
    entry_price: float
    exit_time: int
    exit_price: float
    dir: int
    volume: float
    r_realized: float
    gross_pnl: float
    commission: float
    net_pnl: float
    reason: str


class PositionManager:
    def __init__(self, name, lots, stop_r=2.0, protect_trigger_r=0.5, protect_r=0.25,
                 tp_r=0.9, tp_relative='entry', partial_trigger_r=None, partial_frac=0.5,
                 timeout_hours=None):
        self.name = name
        self.lots = lots
        self.stop_r = stop_r
        self.protect_trigger_r = protect_trigger_r
        self.protect_r = protect_r
        self.tp_r = tp_r
        self.tp_relative = tp_relative
        self.partial_trigger_r = partial_trigger_r
        self.partial_frac = partial_frac
        self.timeout_s = timeout_hours * 3600 if timeout_hours else None
        self.position = None

    def has_position(self):
        return self.position is not None

    def try_enter(self, event, ts, bid, ask):
        """event: signals.TriggerEvent. Returns True if a new position was opened."""
        if self.position is not None:
            return False
        dir_ = event.dir
        entry = ask if dir_ == 1 else bid
        sl = entry - dir_ * self.stop_r * event.R
        if self.tp_relative == 'entry':
            tp = entry + dir_ * self.tp_r * event.R
        else:  # 'sig_close': 007's final target is anchored to the signal bar's close
            tp = event.sig_close + dir_ * self.tp_r * event.R
        self.position = {
            'entry_time': ts, 'entry': entry, 'dir': dir_, 'R': event.R,
            'volume': self.lots, 'sl': sl, 'tp': tp, 'armed': False,
            'partial_done': self.partial_trigger_r is None,
        }
        return True

    def manage(self, ts, bid, ask, trades: list):
        p = self.position
        if p is None:
            return
        dir_ = p['dir']
        px = bid if dir_ == 1 else ask  # executable close side

        # 1) Broker-side SL/TP: executes continuously as price crosses, regardless
        #    of the EA's own tick-processing order.
        sl_hit = px <= p['sl'] if dir_ == 1 else px >= p['sl']
        if sl_hit:
            self._close(ts, p['sl'], p['volume'], 'LOCK' if p['armed'] else 'SL', trades)
            return
        tp_hit = px >= p['tp'] if dir_ == 1 else px <= p['tp']
        if tp_hit:
            self._close(ts, p['tp'], p['volume'], 'TP', trades)
            return

        # 2) Timeout force-close at market (007 only)
        if self.timeout_s is not None and ts > p['entry_time'] + self.timeout_s:
            self._close(ts, px, p['volume'], 'TIMEOUT', trades)
            return

        # 3) Arm protection: move SL to +protect_r*R once +protect_trigger_r*R touched
        if not p['armed']:
            trig = p['entry'] + dir_ * self.protect_trigger_r * p['R']
            reached = px >= trig if dir_ == 1 else px <= trig
            if reached:
                p['armed'] = True
                p['sl'] = p['entry'] + dir_ * self.protect_r * p['R']

        # 4) Partial close at +partial_trigger_r*R (007 only)
        if self.partial_trigger_r is not None and not p['partial_done']:
            trig = p['entry'] + dir_ * self.partial_trigger_r * p['R']
            reached = px >= trig if dir_ == 1 else px <= trig
            if reached:
                close_vol = round(p['volume'] * self.partial_frac, 2)
                remain = round(p['volume'] - close_vol, 2)
                p['partial_done'] = True
                if close_vol >= LOT_UNIT and remain >= LOT_UNIT:
                    self._close(ts, px, close_vol, 'PARTIAL_TP', trades, partial=True)

    def _close(self, ts, price, vol, reason, trades, partial=False):
        p = self.position
        dir_ = p['dir']
        gross = (price - p['entry']) * dir_ * vol * CONTRACT_OZ_PER_LOT
        commission = (vol / LOT_UNIT) * COMMISSION_PER_0_01_LOT_ROUNDTURN
        net = gross - commission
        r = (price - p['entry']) * dir_ / p['R'] if p['R'] else 0.0
        trades.append(Trade(self.name, p['entry_time'], p['entry'], ts, price, dir_,
                             vol, r, gross, commission, net, reason))
        if partial:
            p['volume'] = round(p['volume'] - vol, 2)
        else:
            self.position = None


def make_004():
    return PositionManager('004', lots=0.01, stop_r=2.0, protect_trigger_r=0.5,
                            protect_r=0.25, tp_r=0.9, tp_relative='entry',
                            partial_trigger_r=None, timeout_hours=None)


def make_005():
    return PositionManager('005', lots=0.01, stop_r=2.0, protect_trigger_r=0.5,
                            protect_r=0.25, tp_r=0.9, tp_relative='entry',
                            partial_trigger_r=None, timeout_hours=None)


def make_007():
    return PositionManager('007', lots=0.02, stop_r=2.0, protect_trigger_r=0.5,
                            protect_r=0.25, tp_r=0.9, tp_relative='sig_close',
                            partial_trigger_r=1.0, partial_frac=0.5, timeout_hours=168)
