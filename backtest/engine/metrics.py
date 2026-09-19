"""Performance metrics from a trade list: returns, MDD, Sharpe/Sortino, etc."""

from datetime import datetime, timezone
import math

import pandas as pd


def trades_to_df(trades) -> pd.DataFrame:
    if not trades:
        return pd.DataFrame(columns=[
            'strategy', 'entry_time', 'entry_price', 'exit_time', 'exit_price',
            'dir', 'volume', 'r_realized', 'gross_pnl', 'commission', 'net_pnl', 'reason'])
    df = pd.DataFrame([t.__dict__ for t in trades])
    df['entry_dt'] = pd.to_datetime(df['entry_time'], unit='s', utc=True)
    df['exit_dt'] = pd.to_datetime(df['exit_time'], unit='s', utc=True)
    df['hold_hours'] = (df['exit_time'] - df['entry_time']) / 3600.0
    return df.sort_values('exit_time').reset_index(drop=True)


def equity_curve(df: pd.DataFrame, initial_capital: float) -> pd.Series:
    if df.empty:
        return pd.Series(dtype=float)
    s = df.set_index('exit_dt')['net_pnl'].cumsum() + initial_capital
    return s


def max_drawdown(equity: pd.Series):
    if equity.empty:
        return 0.0, 0.0, pd.Timedelta(0)
    running_max = equity.cummax()
    dd = equity - running_max
    dd_pct = dd / running_max
    trough_idx = dd.idxmin()
    mdd_abs = dd.loc[trough_idx]
    mdd_pct = dd_pct.loc[trough_idx]

    peak_idx = equity.loc[:trough_idx].idxmax()
    after_peak = equity.loc[peak_idx:]
    recovery = after_peak[after_peak >= equity.loc[peak_idx]]
    if len(recovery) > 1:
        recovery_idx = recovery.index[1]
        duration = recovery_idx - peak_idx
    else:
        duration = equity.index[-1] - peak_idx  # not yet recovered
    return mdd_abs, mdd_pct, duration


def daily_returns(equity: pd.Series) -> pd.Series:
    if equity.empty:
        return pd.Series(dtype=float)
    daily = equity.resample('1D').last().ffill()
    return daily.pct_change().dropna()


def sharpe_sortino(daily_ret: pd.Series, periods_per_year=252):
    if daily_ret.empty or daily_ret.std(ddof=0) == 0:
        return 0.0, 0.0
    mean = daily_ret.mean()
    std = daily_ret.std(ddof=0)
    sharpe = (mean / std) * math.sqrt(periods_per_year) if std > 0 else 0.0
    downside = daily_ret[daily_ret < 0]
    dstd = downside.std(ddof=0) if len(downside) > 0 else 0.0
    sortino = (mean / dstd) * math.sqrt(periods_per_year) if dstd > 0 else 0.0
    return sharpe, sortino


def summarize(df: pd.DataFrame, initial_capital: float, strategy_name: str) -> dict:
    if df.empty:
        return {'strategy': strategy_name, 'n_trades': 0}

    # For strategies with partial closes, group by entry_time to get "round trip" stats
    # alongside the raw fill-level stats used for $ P&L (which already sums correctly).
    gross = df['gross_pnl'].sum()
    commission = df['commission'].sum()
    net = df['net_pnl'].sum()

    wins = df[df['net_pnl'] > 0]
    losses = df[df['net_pnl'] <= 0]
    win_rate = len(wins) / len(df) if len(df) else 0.0
    avg_win = wins['net_pnl'].mean() if len(wins) else 0.0
    avg_loss = losses['net_pnl'].mean() if len(losses) else 0.0
    profit_factor = (wins['net_pnl'].sum() / abs(losses['net_pnl'].sum())
                      if losses['net_pnl'].sum() != 0 else float('inf'))
    expectancy = df['net_pnl'].mean()

    eq = equity_curve(df, initial_capital)
    mdd_abs, mdd_pct, mdd_dur = max_drawdown(eq)
    dret = daily_returns(eq)
    sharpe, sortino = sharpe_sortino(dret)

    start = df['entry_dt'].min()
    end = df['exit_dt'].max()
    years = max((end - start).days / 365.25, 1e-9)
    total_return_pct = net / initial_capital
    cagr = (1 + total_return_pct) ** (1 / years) - 1 if total_return_pct > -1 else -1.0

    return {
        'strategy': strategy_name,
        'n_trades': len(df),
        'n_round_trips': df['entry_time'].nunique(),
        'gross_pnl': gross,
        'commission': commission,
        'net_pnl': net,
        'total_return_pct': total_return_pct,
        'cagr_pct': cagr,
        'win_rate_pct': win_rate,
        'avg_win': avg_win,
        'avg_loss': avg_loss,
        'profit_factor': profit_factor,
        'expectancy': expectancy,
        'mdd_abs': mdd_abs,
        'mdd_pct': mdd_pct,
        'mdd_duration_days': mdd_dur.days if hasattr(mdd_dur, 'days') else None,
        'sharpe': sharpe,
        'sortino': sortino,
        'avg_hold_hours': df['hold_hours'].mean(),
        'start': start,
        'end': end,
    }


def portfolio_summary(all_trades: list, initial_capital: float) -> dict:
    df = trades_to_df(all_trades)
    return summarize(df, initial_capital, 'PORTFOLIO(004+005+007)')
