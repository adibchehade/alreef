// alreef.es crypto dashboard — shared data layer (free, keyless sources only)
//  · Crypto prices: Binance public REST (fallback: data-api.binance.vision)
//  · ANT / S&P 500 prices: Hyperliquid info API, "xyz" dex (markPx vs prevDayPx)
//  · 24h liquidations: CoinBoss /api/liquidations/coins (per-coin, live, one request)
//    S&P 500 has no free liquidation source (CoinBoss "SPX" is the SPX6900 memecoin), so price only
//  · 7d / 30d liquidations: live 24h + previous days saved by the GitHub Action
//    into /crypto/data/liquidations.json
(function () {
  const ASSETS = [
    { sym: 'BTC', name: 'Bitcoin',  src: 'binance' },
    { sym: 'ETH', name: 'Ethereum', src: 'binance' },
    { sym: 'BNB', name: 'BNB',      src: 'binance' },
    { sym: 'SOL', name: 'Solana',   src: 'binance' },
    { sym: 'XRP', name: 'XRP',      src: 'binance' },
    { sym: 'ANT', name: 'Anthropic', src: 'hl', hl: ['ANT'] },
    { sym: 'SPX', name: 'S&P 500',   src: 'hl', hl: ['SP500'], noLiq: true },
  ];
  const LIQ_ASSETS = ASSETS.filter(a => !a.noLiq);
  const BINANCE = ['https://api.binance.com', 'https://data-api.binance.vision'];
  const HL = 'https://api.hyperliquid.xyz/info';
  const LIQ = 'https://www.coinboss.com/api/liquidations/coins?limit=500';
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

  // CoinBoss /liquidations/coins → {range:'24h', data:[{coin, long_usd, short_usd, total_usd, cnt}]}
  async function liq24All() {
    const d = await getJSON(LIQ);
    const out = {};
    if (d && Array.isArray(d.data)) d.data.forEach(r => {
      const c = String(r.coin || '').toUpperCase();
      const long = num(r.long_usd), short = num(r.short_usd);
      let total = num(r.total_usd); if (total === null && long !== null && short !== null) total = long + short;
      out[c] = { long, short, total };
    });
    return out;
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
    const [hist, lives] = await Promise.all([getJSON(HIST + '?t=' + Date.now()), liq24All()]);
    const H = (hist && hist.days) || {};
    const ok = Object.keys(lives).length > 0;
    const out = {};
    LIQ_ASSETS.forEach(a => {
      const live = ok ? (lives[a.sym] || { long: 0, short: 0, total: 0 }) : null;
      out[a.sym] = { '24h': live ? { ...live, have: 1, need: 1 } : { long: null, short: null, total: null, have: 0, need: 1 },
                     '7d': windowSum(H, a.sym, live, 7), '30d': windowSum(H, a.sym, live, 30) };
    });
    return out;
  }

  // ---------- Charts: candles per timeframe ----------
  // Crypto: Binance klines (fallback Hyperliquid perps). ANT / S&P 500: Hyperliquid xyz candleSnapshot.
  const TF = {
    '1h':  { label: '1H',  iv: '1m',  ms: 3600e3 },
    '4h':  { label: '4H',  iv: '5m',  ms: 4 * 3600e3 },
    '24h': { label: '24H', iv: '15m', ms: 864e5 },
    '7d':  { label: '7D',  iv: '1h',  ms: 7 * 864e5 },
    '30d': { label: '30D', iv: '4h',  ms: 30 * 864e5 },
  };
  const IV_MS = { '1m': 6e4, '5m': 3e5, '15m': 9e5, '1h': 36e5, '4h': 144e5 };
  const bar = (t, o, h, l, c, v) => ({ time: Math.floor(t / 1000), open: +o, high: +h, low: +l, close: +c, volume: +v });

  async function hlCandles(coin, tf) {
    const end = Date.now(), start = end - TF[tf].ms - IV_MS[TF[tf].iv];
    const d = await getJSON(HL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'candleSnapshot', req: { coin, interval: TF[tf].iv, startTime: start, endTime: end } }) }, 15000);
    return Array.isArray(d) ? d.map(k => bar(k.t, k.o, k.h, k.l, k.c, k.v)) : [];
  }
  async function candles(asset, tf) {
    const spec = TF[tf];
    if (asset.src === 'binance') {
      const n = Math.min(1000, Math.ceil(spec.ms / IV_MS[spec.iv]) + 1);
      const q = `/api/v3/klines?symbol=${asset.sym}USDT&interval=${spec.iv}&limit=${n}`;
      for (const base of BINANCE) {
        const d = await getJSON(base + q, {}, 15000);
        if (Array.isArray(d) && d.length) return { src: 'Binance', bars: d.map(k => bar(k[0], k[1], k[2], k[3], k[4], k[7])) };
      }
      const hl = await hlCandles(asset.sym, tf);           // fallback: Hyperliquid perp
      return { src: 'Hyperliquid', bars: hl };
    }
    return { src: 'Hyperliquid', bars: await hlCandles('xyz:' + asset.hl[0], tf) };
  }

  // Short-window liquidations straight from CoinBoss (1h / 4h); 24h, 7d, 30d come from liquidations().
  async function liqRange(range) {
    const d = await getJSON(`https://www.coinboss.com/api/liquidations/coins?range=${range}&limit=500`);
    const out = {};
    if (d && Array.isArray(d.data)) d.data.forEach(r => {
      const long = num(r.long_usd), short = num(r.short_usd);
      let total = num(r.total_usd); if (total === null && long !== null && short !== null) total = long + short;
      out[String(r.coin || '').toUpperCase()] = { long, short, total };
    });
    return Object.keys(out).length ? out : null;
  }

  // ---------- Technical analysis on the candles ----------
  function ema(vals, n) {
    if (vals.length < n) return [];
    const k = 2 / (n + 1), out = new Array(vals.length).fill(null);
    let e = vals.slice(0, n).reduce((a, b) => a + b, 0) / n; out[n - 1] = e;
    for (let i = n; i < vals.length; i++) { e = vals[i] * k + e * (1 - k); out[i] = e; }
    return out;
  }
  function rsi(c, n = 14) {
    if (c.length <= n) return null;
    let g = 0, l = 0;
    for (let i = 1; i <= n; i++) { const d = c[i] - c[i - 1]; d > 0 ? g += d : l -= d; }
    g /= n; l /= n;
    for (let i = n + 1; i < c.length; i++) { const d = c[i] - c[i - 1]; g = (g * (n - 1) + Math.max(d, 0)) / n; l = (l * (n - 1) + Math.max(-d, 0)) / n; }
    return l === 0 ? 100 : 100 - 100 / (1 + g / l);
  }
  function atrPct(b, n = 14) {
    if (b.length <= n) return null;
    const tr = b.slice(1).map((x, i) => Math.max(x.high - x.low, Math.abs(x.high - b[i].close), Math.abs(x.low - b[i].close)));
    const a = tr.slice(-n).reduce((s, v) => s + v, 0) / n;
    return a / b[b.length - 1].close * 100;
  }
  // Swing highs/lows: a bar higher (lower) than the k bars on each side.
  function pivots(b, k = 3) {
    const hi = [], lo = [];
    for (let i = k; i < b.length - k; i++) {
      const w = b.slice(i - k, i + k + 1);
      if (b[i].high === Math.max(...w.map(x => x.high))) hi.push(b[i].high);
      if (b[i].low === Math.min(...w.map(x => x.low))) lo.push(b[i].low);
    }
    return { hi, lo };
  }
  function analyze(b, liq) {
    if (!b || b.length < 5) return null;
    const c = b.map(x => x.close), last = c[c.length - 1], first = b[0].open;
    const high = Math.max(...b.map(x => x.high)), low = Math.min(...b.map(x => x.low));
    const e20 = ema(c, 20), e50 = ema(c, 50);
    const E20 = e20.length ? e20[e20.length - 1] : null, E50 = e50.length ? e50[e50.length - 1] : null;
    const E20prev = e20.length > 10 ? e20[e20.length - 11] : null;
    const R = rsi(c), ATR = atrPct(b);
    // Significant swing levels only: at least one average candle range (ATR) away from price.
    const pv = pivots(b, b.length >= 60 ? 4 : 3);
    const gap = ATR !== null ? last * ATR / 100 : last * 0.003;
    const support = Math.max(...pv.lo.filter(v => v < last - gap), -Infinity);
    const resistance = Math.min(...pv.hi.filter(v => v > last + gap), Infinity);
    const vols = b.map(x => x.volume), avgV = vols.reduce((s, v) => s + v, 0) / vols.length;
    const recentV = vols.slice(-5).reduce((s, v) => s + v, 0) / Math.min(5, vols.length);
    let score = 0, checks = 0;
    const add = cond => { if (cond === null) return; checks++; score += cond ? 1 : -1; };
    add(E20 === null ? null : last > E20);
    add(E20 === null || E50 === null ? null : E20 > E50);
    add(E20 === null || E20prev === null ? null : E20 > E20prev);
    add(last > first);
    const trend = checks === 0 ? 'Mixed' : score >= checks - 1 && score > 0 ? 'Bullish' : score <= -(checks - 1) && score < 0 ? 'Bearish' : 'Mixed';
    return {
      last, first, change: (last / first - 1) * 100, high, low,
      rangePos: high > low ? (last - low) / (high - low) * 100 : null,
      ema20: E20, ema50: E50, ema20Series: e20, ema50Series: e50,
      rsi: R, atr: ATR, trend,
      support: isFinite(support) ? support : null, resistance: isFinite(resistance) ? resistance : null,
      volRatio: avgV > 0 ? recentV / avgV : null, liq,
    };
  }
  const TF_WORDS = { '1h': ['1 hour', '1-hour'], '4h': ['4 hours', '4-hour'], '24h': ['24 hours', '24-hour'],
                     '7d': ['7 days', '7-day'], '30d': ['30 days', '30-day'] };
  function summary(a, tf, name) {
    if (!a) return 'Not enough price data for this timeframe yet.';
    const [tfLabel, tfAdj] = TF_WORDS[tf] || [tf, tf];
    const p = [];
    const dir = a.change >= 0 ? 'up' : 'down';
    const where = a.rangePos === null ? 'within' : a.rangePos > 75 ? 'near the top of' : a.rangePos < 25 ? 'near the bottom of' : 'mid-way in';
    p.push(`${name} is ${dir} ${Math.abs(a.change).toFixed(2)}% over ${tfLabel}, trading ${where} its ${tfAdj} range.`);
    const t = { Bullish: 'The trend is bullish: price is above its moving averages and they are rising.',
                Bearish: 'The trend is bearish: price is below its moving averages and they are falling.',
                Mixed: 'The trend is mixed, with no clear direction on this timeframe.' }[a.trend];
    p.push(t);
    if (a.rsi !== null) p.push(a.rsi < 30 ? `RSI ${a.rsi.toFixed(0)} is oversold, so a short-term bounce is possible, though not guaranteed.`
      : a.rsi > 70 ? `RSI ${a.rsi.toFixed(0)} is overbought, so a pullback is possible.` : `RSI ${a.rsi.toFixed(0)} is neutral.`);
    if (a.support || a.resistance) p.push(`Nearest support ${a.support ? fmtPrice(a.support) : 'not clear'}, resistance ${a.resistance ? fmtPrice(a.resistance) : 'not clear'}.`);
    if (a.volRatio !== null && (a.volRatio > 1.5 || a.volRatio < 0.6)) p.push(a.volRatio > 1.5 ? `Volume is running ${a.volRatio.toFixed(1)}× the ${tfAdj} average, so this move has conviction.` : 'Volume is light, so moves may lack follow-through.');
    const L = a.liq;
    if (L && L.total) {
      const ls = L.long / (L.long + L.short || 1) * 100;
      if (ls >= 65) p.push(`Liquidations were ${ls.toFixed(0)}% longs (${fmtUSD(L.long)}): leveraged buyers were forced out, which adds selling pressure.`);
      else if (ls <= 35) p.push(`Liquidations were ${(100 - ls).toFixed(0)}% shorts (${fmtUSD(L.short)}): a short squeeze added buying pressure.`);
      else p.push(`Liquidations were fairly balanced between longs and shorts (${fmtUSD(L.total)} total).`);
    }
    return p.join(' ');
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

  window.ALREEF = { ASSETS, LIQ_ASSETS, TF, prices, liquidations, liqRange, candles, analyze, summary,
                    fmtUSD, fmtPrice, fmtPct, spain, clock, every60 };
})();
