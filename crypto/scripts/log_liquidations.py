"""Save today's 24h liquidation totals (long/short/total USD) per asset.

Run daily at 23:55 UTC by .github/workflows/crypto-liquidations.yml.
Writes crypto/data/liquidations.json as {"updated": ..., "days": {"YYYY-MM-DD": {"BTC": {...}}}}
The dashboard pages sum the saved days with the live 24h figure for 7d / 30d.
"""
import datetime
import json
import os
import urllib.request

# S&P 500 is not included: CoinBoss "SPX" is the SPX6900 memecoin, not the index.
COINS = ["BTC", "ETH", "BNB", "SOL", "XRP", "PEPE", "ANT"]  # Purple Bitcoin has no futures market
URL = "https://www.coinboss.com/api/liquidations/coins?limit=500"
FILE = os.path.join(os.path.dirname(__file__), "..", "data", "liquidations.json")
KEEP_DAYS = 60


def num(v):
    try:
        return None if v is None or v == "" else float(v)
    except (TypeError, ValueError):
        return None


def fetch_all():
    """CoinBoss /liquidations/coins: {"range": "24h", "data": [{coin, long_usd, short_usd, total_usd, cnt}]}"""
    req = urllib.request.Request(URL, headers={"User-Agent": "alreef-liquidations-logger"})
    with urllib.request.urlopen(req, timeout=30) as r:
        d = json.load(r)
    if d.get("range") not in (None, "24h"):
        raise SystemExit(f"unexpected range {d.get('range')!r}")
    out = {}
    for r in d.get("data") or []:
        c = str(r.get("coin", "")).upper()
        long_, short = num(r.get("long_usd")), num(r.get("short_usd"))
        total = num(r.get("total_usd"))
        if total is None and long_ is not None and short is not None:
            total = long_ + short
        out[c] = {"long": long_, "short": short, "total": total}
    return out


def main():
    data = {}
    if os.path.exists(FILE):
        with open(FILE) as f:
            data = json.load(f) or {}
    days = data.get("days", {})
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    live = fetch_all()
    if not live:
        raise SystemExit("no liquidation data fetched; nothing saved")
    # a coin missing from the list had no liquidations in the last 24h
    row = {c: live.get(c, {"long": 0.0, "short": 0.0, "total": 0.0}) for c in COINS}
    days[today] = row
    days = dict(sorted(days.items())[-KEEP_DAYS:])
    out = {"updated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "days": days}
    with open(FILE, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(f"saved {today}: {', '.join(row)}")


if __name__ == "__main__":
    main()
