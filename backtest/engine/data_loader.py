"""Loads MT5 tick-export CSV files (one per month) in chronological order and
yields (ts, bid, ask) chunks for streaming into BacktestRunner.

Column format is auto-detected on the first file and then reused, since the
exact MT5 export layout hasn't been confirmed yet. Common layouts handled:

  - "<DATE>\t<TIME>\t<BID>\t<ASK>\t<LAST>\t<VOLUME>\t<FLAGS>"  (MT5 native tick export,
    DATE=YYYY.MM.DD, TIME=HH:MM:SS.mmm)
  - "Date,Time,Bid,Ask[,Volume]"  (many third-party tick tools)
  - "Timestamp,Bid,Ask"  (single combined datetime column)

If none of these match, pass explicit `columns=` / `date_format=` overrides to
`load_month`.
"""

import glob
import os
import re

import pandas as pd

_CANDIDATE_SEPS = [',', '\t', ';']


def _sniff_sep(path):
    with open(path, 'r', encoding='utf-8-sig', errors='ignore') as f:
        first = f.readline()
    counts = {sep: first.count(sep) for sep in _CANDIDATE_SEPS}
    return max(counts, key=counts.get)


def _find_col(cols, patterns):
    for pat in patterns:
        for c in cols:
            if re.search(pat, c, re.IGNORECASE):
                return c
    return None


def load_month(path: str) -> pd.DataFrame:
    """Returns a DataFrame with columns ['ts', 'bid', 'ask'], ts = float epoch seconds
    (no timezone conversion -- kept in whatever timezone the export uses, i.e.
    the MT5 server time the live EAs also operate in)."""
    sep = _sniff_sep(path)
    df = pd.read_csv(path, sep=sep, engine='python')
    df.columns = [str(c).strip().strip('<>').strip() for c in df.columns]
    cols = list(df.columns)

    date_col = _find_col(cols, [r'^date$', r'^<?date>?$'])
    time_col = _find_col(cols, [r'^time$', r'^<?time>?$'])
    ts_col = _find_col(cols, [r'timestamp', r'datetime'])
    bid_col = _find_col(cols, [r'^bid$'])
    ask_col = _find_col(cols, [r'^ask$'])

    if bid_col is None or ask_col is None:
        raise ValueError(f"{path}: could not find Bid/Ask columns among {cols}")

    if date_col and time_col:
        dt = pd.to_datetime(df[date_col].astype(str) + ' ' + df[time_col].astype(str),
                             format='mixed', errors='coerce')
    elif ts_col:
        dt = pd.to_datetime(df[ts_col], format='mixed', errors='coerce')
    else:
        raise ValueError(f"{path}: could not find a Date+Time or Timestamp column among {cols}")

    bad = dt.isna().sum()
    if bad:
        raise ValueError(f"{path}: {bad} rows failed timestamp parsing -- check format")

    out = pd.DataFrame({
        'ts': dt.astype('int64') // 10**9,  # epoch seconds, ms truncated (fine: bars/timeouts are minute+ granularity)
        'bid': df[bid_col].astype(float),
        'ask': df[ask_col].astype(float),
    })
    return out.sort_values('ts', kind='mergesort').reset_index(drop=True)


def iter_month_files(data_dir: str, pattern: str = '*_ticks_*.csv'):
    """Yields file paths sorted chronologically by the YYYY-MM in the filename."""
    files = glob.glob(os.path.join(data_dir, pattern))

    def key(f):
        m = re.search(r'(\d{4})-(\d{2})', os.path.basename(f))
        return (m.group(1), m.group(2)) if m else (os.path.basename(f), '')

    for f in sorted(files, key=key):
        yield f
