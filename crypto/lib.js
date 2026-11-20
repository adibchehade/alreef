// alreef.es crypto dashboard — shared data layer (free, keyless sources only)
//  · Crypto prices: Binance public REST (fallback: data-api.binance.vision)
//  · ANT / S&P 500 prices: Hyperliquid info API, "xyz" dex (markPx vs prevDayPx)
//  · 24h liquidations: CoinBoss liquidations overview (live)
//  · 7d / 30d liquidations: live 24h + previous days saved by the GitHub Action
//    into /crypto/data/liquidations.json
(function () {
  const ASSETS = [
    { sym: 'BTC', name: 'Bitcoin',  src: 'binance' },
    { sym: 'ETH', name: 'Ethereum', src: 'binance' },
    { sym: 'BNB', name: 'BNB',      src: 'binance' },
    { sym: 'SOL', name: 'Solana',   src: 'binance' },
    { sym: 'XRP', name: 'XRP',      src: 'binance' },
    { sym: 'ANT', name: 'Anthropic', src: 'hl', hl: ['ANT', 'ANTHROPIC'] },
    { sym: 'SPX', name: 'S&P 500',   src: 'hl', hl: ['SP500', 'SPX', 'US500', 'SPY', 'S&P500'] },
  ];
  const BINANCE = ['https://api.binance.com', 'https://data-api.binance.vision'];
  const HL = 'https://api.hyperliquid.xyz/info';
  const LIQ = c => `https://www.coinboss.com/api/liquidations/overview?coin=${c}`;
  const HIST = '/crypto/data/liquidations.json';

  async function getJSON(url, opt = {}, ms = 12000) {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), ms);
    try {
      const r = await fetch(url, { ...opt, signal: ctl.signal, cache: 'no-store' });
      if (!r.ok) throw new Error(r.status);
      return await r.json();
    } catch (e) { return null; } finally { clearTimeout(t); }
  }
  const num = v => (v === null || v === undefined || v === '' || isNaN(+v)) ? null : +v;

  async function binance() {
    const syms = ASSETS.filter(a => a.src === 'binance').map(a => a.sym + 'USDT');
    const q = '/api/v3/ticker/24hr?symbols=' + encodeURIComponent(JSON.stringify(syms));
    for (const base of BINANCE) {
      const d = await getJSON(base + q);
      if (Array.isArray(d) && d.length) return d;
    }
    return [];
  }
  async function hyperliquid() {
    const d = await getJSON(HL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'metaAndAssetCtxs', dex: 'xyz' }) });
    const out = {};
    if (Array.isArray(d) && d[0] && d[0].universe && Array.isArray(d[1])) {
      d[0].universe.forEach((u, i) => {
        const key = String(u.name || '').replace(/^[a-z0-9]+:/i, '').toUpperCase();
        out[key] = d[1][i];
      });
    }
    return out;
  }

  async function prices() {
    const [b, h] = await Promise.all([binance(), hyperliquid()]);
    return ASSETS.map(a => {
      if (a.src === 'binance') {
        const t = b.find(x => x.symbol === a.sym + 'USDT');
        return { ...a, price: t ? num(t.lastPrice) : null, chg: t ? num(t.priceChangePercent) : null,
                 high: t ? num(t.highPrice) : null, low: t ? num(t.lowPrice) : null,
                 vol: t ? num(t.quoteVolume) : null };
      }
      const k = a.hl.find(n => h[n]);
      const c = k ? h[k] : null;
      const px = c ? num(c.markPx) : null, pv = c ? num(c.prevDayPx) : null;
      return { ...a, price: px, chg: px && pv ? (px / pv - 1) * 100 : null, high: null, low: null,
               vol: c ? num(c.dayNtlVlm) : null };
    });
  }

  // CoinBoss returns windows (1h, 4h, 12h, 24h). Find the 24h block whatever the nesting.
  function find24(o, depth = 0) {
    if (!o || typeof o !== 'object' || depth > 5) return null;
    if (Array.isArray(o)) {
      const w = o.find(x => x && /^(24h|1d|day)$/i.test(String(x.window || x.period || x.interval || '')));
      if (w) return w;
      for (const x of o) { const r = find24(x, depth + 1); if (r) return r; }
      return null;
    }
    for (const k of Object.keys(o)) if (/^(24h|h24|1d|day|last_?24h)$/i.test(k)) return o[k];
    for (const k of Object.keys(o)) { const r = find24(o[k], depth + 1); if (r) return r; }
    return null;
  }
  const pick = (o, ks) => { for (const k of ks) if (o && num(o[k]) !== null) return num(o[k]); return null; };
  function parseLiq(o) {
    if (!o) return null;
    const long = pick(o, ['long_usd', 'longUsd', 'long_usd_total', 'longs_usd', 'long']);
    const short = pick(o, ['short_usd', 'shortUsd', 'short_usd_total', 'shorts_usd', 'short']);
    let total = pick(o, ['total_usd', 'totalUsd', 'total', 'usd']);
    if (total === null && long !== null && short !== null) total = long + short;
    return (long === null && short === null && total === null) ? null : { long, short, total };
  }
  async function liq24(sym) {
    const d = await getJSON(LIQ(sym));
    return d ? parseLiq(find24(d.data ?? d)) : null;
  }

  // 7d / 30d = today's live 24h + the previous (n-1) saved days.
  function windowSum(hist, sym, live, n) {
    const today = new Date().toISOString().slice(0, 10);
    const days = Object.keys(hist || {}).filter(d => d < today).sort().slice(-(n - 1));
    const rows = days.map(d => hist[d] && hist[d][sym]).filter(Boolean);
    if (live) rows.push(live);
    if (!rows.length) return { long: null, short: null, total: null, have: 0, need: n };
    const s = k => rows.reduce((a, r) => a + (num(r[k]) || 0), 0);
    return { long: s('long'), short: s('short'), total: s('total'), have: rows.length, need: n };
  }

  async function liquidations() {
    const [hist, lives] = await Promise.all([
      getJSON(HIST + '?t=' + Date.now()),
      Promise.all(ASSETS.map(a => liq24(a.sym))),
    ]);
    const H = (hist && hist.days) || hist || {};
    const out = {};
    ASSETS.forEach((a, i) => {
      const live = lives[i];
      out[a.sym] = { '24h': live ? { ...live, have: 1, need: 1 } : { long: null, short: null, total: null, have: 0, need: 1 },
                     '7d': windowSum(H, a.sym, live, 7), '30d': windowSum(H, a.sym, live, 30) };
    });
    return out;
  }

  const fmtUSD = v => v === null || v === undefined ? '—'
    : Math.abs(v) >= 1e9 ? '$' + (v / 1e9).toFixed(2) + 'B'
    : Math.abs(v) >= 1e6 ? '$' + (v / 1e6).toFixed(1) + 'M'
    : Math.abs(v) >= 1e3 ? '$' + (v / 1e3).toFixed(1) + 'K' : '$' + Math.round(v);
  const fmtPrice = v => {
    if (v === null || v === undefined) return '—';
    const d = v >= 1000 ? 2 : v >= 10 ? 2 : v >= 1 ? 3 : 4;
    return '$' + v.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
  };
  const fmtPct = v => v === null || v === undefined ? '—' : (v >= 0 ? '+' : '') + v.toFixed(2) + '%';
  const spain = (opts = { hour: '2-digit', minute: '2-digit', second: '2-digit' }) =>
    new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Madrid', hour12: false, ...opts }).format(new Date());
  function clock(el, dateEl) {
    const tick = () => {
      if (el) el.textContent = spain();
      if (dateEl) dateEl.textContent = spain({ weekday: 'short', day: 'numeric', month: 'short' }) + ' · Spain';
    };
    tick(); setInterval(tick, 1000);
  }
  // Run fn now and every 60 s; refresh straight away when the tab becomes visible again.
  function every60(fn) {
    let busy = false;
    const run = async () => { if (busy) return; busy = true; try { await fn(); } finally { busy = false; } };
    run(); setInterval(run, 60000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) run(); });
  }

  window.ALREEF = { ASSETS, prices, liquidations, fmtUSD, fmtPrice, fmtPct, spain, clock, every60 };
})();
