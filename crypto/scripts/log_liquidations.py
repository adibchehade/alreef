"""Save today's 24h liquidation totals (long/short/total USD) per asset.

Run daily at 23:55 UTC by .github/workflows/crypto-liquidations.yml.
Writes crypto/data/liquidations.json as {"updated": ..., "days": {"YYYY-MM-DD": {"BTC": {...}}}}
The dashboard pages sum the saved days with the live 24h figure for 7d / 30d.
"""
import datetime
import json
import os
import re
import urllib.request

COINS = ["BTC", "ETH", "BNB", "SOL", "XRP", "ANT", "SPX"]
URL = "https://www.coinboss.com/api/liquidations/overview?coin={c}"
FILE = os.path.join(os.path.dirname(__file__), "..", "data", "liquidations.json")
KEEP_DAYS = 60
WIN = re.compile(r"^(24h|h24|1d|day|last_?24h)$", re.I)


def num(v):
    try:
        return None if v is None or v == "" else float(v)
    except (TypeError, ValueError):
        return None


def find24(o, depth=0):
    if depth > 5 or not isinstance(o, (dict, list)):
        return None
    if isinstance(o, list):
        for x in o:
            if isinstance(x, dict) and WIN.match(str(x.get("window") or x.get("period") or x.get("interval") or "")):
                return x
        for x in o:
            r = find24(x, depth + 1)
            if r:
                return r
        return None
    for k, v in o.items():
        if WIN.match(k):
            return v
    for v in o.values():
        r = find24(v, depth + 1)
        if r:
            return r
    return None


def pick(o, keys):
    for k in keys:
        if isinstance(o, dict) and num(o.get(k)) is not None:
            return num(o[k])
    return None


def fetch(coin):
    req = urllib.request.Request(URL.format(c=coin), headers={"User-Agent": "alreef-liquidations-logger"})
    with urllib.request.urlopen(req, timeout=30) as r:
        d = json.load(r)
    b = find24(d.get("data", d) if isinstance(d, dict) else d)
    if not b:
        raise ValueError("no 24h block in response")
    long_ = pick(b, ["long_usd", "longUsd", "long_usd_total", "longs_usd", "long"])
    short = pick(b, ["short_usd", "shortUsd", "short_usd_total", "shorts_usd", "short"])
    total = pick(b, ["total_usd", "totalUsd", "total", "usd"])
    if total is None and long_ is not None and short is not None:
        total = long_ + short
    return {"long": long_, "short": short, "total": total}


def main():
    data = {}
    if os.path.exists(FILE):
        with open(FILE) as f:
            data = json.load(f) or {}
    days = data.get("days", {})
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    row = {}
    for c in COINS:
        try:
            row[c] = fetch(c)
        except Exception as e:  # keep going; one bad coin shouldn't lose the rest
            print(f"{c}: {e}")
    if not row:
        raise SystemExit("no liquidation data fetched; nothing saved")
    days[today] = row
    days = dict(sorted(days.items())[-KEEP_DAYS:])
    out = {"updated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "days": days}
    with open(FILE, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(f"saved {today}: {', '.join(row)}")


if __name__ == "__main__":
    main()
