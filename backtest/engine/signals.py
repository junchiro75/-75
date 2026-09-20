"""Signal detection + extension/pullback tracking, shared by all three EAs.

Replicates: bar breakout of dual BB -> wait for +ExtensionR beyond the signal
close -> wait for -PullbackR pullback off the extreme -> emit a countertrend
trigger event. One setup = one opportunity (consumed whether or not the
receiving strategy actually has a free MAX1 slot), matching the MQL EAs
(DelS/RemoveSetup/DS called unconditionally once the pullback confirms).
"""

from dataclasses import dataclass, field


@dataclass
class Setup:
    sig_time: int
    close_time: int  # time at which the signal bar's close became actionable (= next bar start)
    ext_expire: int
    pb_expire: int = 0
    sigdir: int = 0  # +1 bull bar, -1 bear bar
    R: float = 0.0
    sig_close: float = 0.0
    extreme: float = 0.0
    extended: bool = False


@dataclass
class TriggerEvent:
    time: int
    dir: int  # trade direction to open: -sigdir (countertrend)
    R: float
    sig_close: float
    origin: str = 'mechanical'  # 'mechanical' (extension+pullback wait) or 'fast' (next-bar confirm)


class SignalTracker:
    def __init__(self, period_seconds, extension_r=0.95, pullback_r=0.10,
                 max_extension_hours=72, max_pullback_hours=72):
        self.period = period_seconds
        self.ext_r = extension_r
        self.pb_r = pullback_r
        self.max_ext_s = max_extension_hours * 3600
        self.max_pb_s = max_pullback_hours * 3600
        self.setups: list[Setup] = []

    def on_bar_close(self, bar, bands):
        """bar: Bar (the just-closed bar). bands: (u20,l20,u4,l4) or None."""
        if bands is None:
            return
        u20, l20, u4, l4 = bands
        o, h, l, c = bar.o, bar.h, bar.l, bar.c
        bull = c > o and h >= u20 and h >= u4
        bear = c < o and l <= l20 and l <= l4
        if not (bull or bear):
            return
        R = abs(c - o)
        if R <= 0:
            return
        close_time = bar.start + self.period
        self.setups.append(Setup(
            sig_time=bar.start,
            close_time=close_time,
            ext_expire=close_time + self.max_ext_s,
            sigdir=1 if bull else -1,
            R=R,
            sig_close=c,
            extreme=c,
        ))

    def on_tick(self, ts: int, bid: float, ask: float):
        """Advance all pending setups. Returns a list of TriggerEvents fired
        on this tick (usually 0 or 1)."""
        events = []
        i = 0
        while i < len(self.setups):
            s = self.setups[i]
            if ts <= s.close_time:
                i += 1
                continue
            px = bid if s.sigdir == 1 else ask

            if not s.extended:
                if ts > s.ext_expire:
                    del self.setups[i]
                    continue
                target = s.sig_close + s.sigdir * self.ext_r * s.R
                hit = px >= target if s.sigdir == 1 else px <= target
                if hit:
                    s.extended = True
                    s.extreme = px
                    s.pb_expire = ts + self.max_pb_s
                # fall through: allow same-tick pullback evaluation once extended,
                # matching the MQL EAs' deliberate no-`continue` after EXT_HIT.
                if not s.extended:
                    i += 1
                    continue

            if ts > s.pb_expire:
                del self.setups[i]
                continue

            if s.sigdir == 1 and px > s.extreme:
                s.extreme = px
            if s.sigdir == -1 and px < s.extreme:
                s.extreme = px

            trigger = s.extreme - s.sigdir * self.pb_r * s.R
            reversed_ = px <= trigger if s.sigdir == 1 else px >= trigger
            if not reversed_:
                i += 1
                continue

            events.append(TriggerEvent(time=ts, dir=-s.sigdir, R=s.R, sig_close=s.sig_close))
            del self.setups[i]
            # do not advance i; list shrank
        return events
