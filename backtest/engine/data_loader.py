"""Loads MT5 tick-export CSV/ZIP files (one per month) in chronological order
and yields (ts, bid, ask) chunks for streaming into BacktestRunner.

Confirmed layout (Infinox XAUUSD+ tick export):
    DATE_TIME,TIME_MSC,BID,ASK,LAST,VOLUME,VOLUME_REAL,FLAGS
    2025.01.02 01:00:00.000,1735779600000,2625.14,2625.42,2625.14,0,0.00000000,14

TIME_MSC (epoch milliseconds) is used directly when present -- far cheaper and
unambiguous compared to parsing DATE_TIME strings. Files may be plain .csv or
a .zip containing a single .csv (pandas reads either transparently).
"""

import glob
import os
import re
import zipfile

import pandas as pd

_CANDIDATE_SEPS = [',', '\t', ';']


def _first_line(path):
    if path.lower().endswith('.zip'):
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            if len(names) != 1:
                raise ValueError(f"{path}: expected exactly one file inside the zip, found {names}")
            with z.open(names[0]) as f:
                return f.readline().decode('utf-8-sig', errors='ignore')
    with open(path, 'r', encoding='utf-8-sig', errors='ignore') as f:
        return f.readline()


def _sniff_sep(path):
    first = _first_line(path)
    counts = {sep: first.count(sep) for sep in _CANDIDATE_SEPS}
    return max(counts, key=counts.get)


def _find_col(cols, patterns):
    for pat in patterns:
        for c in cols:
            if re.search(pat, c, re.IGNORECASE):
                return c
    return None


def load_month(path: str) -> pd.DataFrame:
    """Returns a DataFrame with columns ['ts', 'bid', 'ask'], ts = int epoch seconds
    (no timezone conversion -- kept in whatever timezone the export uses, i.e.
    the MT5 server time the live EAs also operate in)."""
    sep = _sniff_sep(path)
    df = pd.read_csv(path, sep=sep)  # pandas infers .zip compression from the extension
    df.columns = [str(c).strip().strip('<>').strip() for c in df.columns]
    cols = list(df.columns)

    msc_col = _find_col(cols, [r'^time_msc$'])
    date_col = _find_col(cols, [r'^date$', r'^<?date>?$'])
    time_col = _find_col(cols, [r'^time$', r'^<?time>?$'])
    dt_col = _find_col(cols, [r'^date_time$', r'timestamp', r'datetime'])
    bid_col = _find_col(cols, [r'^bid$'])
    ask_col = _find_col(cols, [r'^ask$'])

    if bid_col is None or ask_col is None:
        raise ValueError(f"{path}: could not find Bid/Ask columns among {cols}")

    if msc_col is not None:
        ts = (df[msc_col].astype('int64') // 1000)
    elif date_col and time_col:
        dt = pd.to_datetime(df[date_col].astype(str) + ' ' + df[time_col].astype(str),
                             format='mixed', errors='coerce')
        if dt.isna().any():
            raise ValueError(f"{path}: {dt.isna().sum()} rows failed timestamp parsing")
        ts = dt.astype('int64') // 10**9
    elif dt_col:
        dt = pd.to_datetime(df[dt_col], format='mixed', errors='coerce')
        if dt.isna().any():
            raise ValueError(f"{path}: {dt.isna().sum()} rows failed timestamp parsing")
        ts = dt.astype('int64') // 10**9
    else:
        raise ValueError(f"{path}: could not find TIME_MSC / Date+Time / Timestamp column among {cols}")

    out = pd.DataFrame({
        'ts': ts,
        'bid': df[bid_col].astype(float),
        'ask': df[ask_col].astype(float),
    })
    return out.sort_values('ts', kind='mergesort').reset_index(drop=True)


_YEARMON_RE = re.compile(r'(20\d{2})(0[1-9]|1[0-2])(?!\d)')


def iter_month_files(data_dir: str, pattern: str = '*XAUUSD*'):
    """Yields file paths (.csv or .zip) sorted chronologically by the YYYYMM
    (or YYYY-MM) found in the filename."""
    files = [f for f in glob.glob(os.path.join(data_dir, pattern))
             if f.lower().endswith(('.csv', '.zip'))]

    def key(f):
        base = os.path.basename(f)
        m = _YEARMON_RE.search(base) or re.search(r'(\d{4})-(\d{2})', base)
        return (m.group(1), m.group(2)) if m else (base, '')

    matched = [f for f in files if key(f)[1]]
    return sorted(matched, key=key)
