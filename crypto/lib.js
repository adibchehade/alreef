// alreef.es crypto dashboard — shared data layer (free, keyless sources only)
//  · Crypto prices: Binance public REST (fallback: data-api.binance.vision)
//  · ANT / S&P 500 prices: Hyperliquid info API, "xyz" dex (markPx vs prevDayPx)
//  · Purple Bitcoin (Solana memecoin): DexScreener price, GeckoTerminal candles
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
    // PEPE: Binance spot; Hyperliquid fallback trades it as kPEPE (price × 1000)
    { sym: 'PEPE', name: 'Pepe',    src: 'binance', hlCoin: 'kPEPE', hlScale: 1e-3 },
    // Purple Bitcoin: Solana memecoin, spot only (no futures, so no liquidations).
    // Price: DexScreener · charts: GeckoTerminal, main Raydium PBTC/SOL pool.
    { sym: 'PBTC', name: 'Purple Bitcoin', src: 'dex', chain: 'solana',
      mint: 'HfMbPyDdZH6QMaDDUokjYCkHxzjoGBMpgaUvpLWGbF5p', pool: 'ATH32pbLRupjq8YNUHQWaJbgBbGPRbrw2GZw5jdZXiRr',
      noLiq: 'no futures market' },
    { sym: 'ANT', name: 'Anthropic', src: 'hl', hl: ['ANT'] },
    { sym: 'SPX', name: 'S&P 500',   src: 'hl', hl: ['SP500'], noLiq: 'no free source' },
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

  // DexScreener: free, keyless, CORS. Pick the most liquid pair for the token.
  async function dex(a) {
    const d = await getJSON(`https://api.dexscreener.com/latest/dex/tokens/${a.mint}`);
    const pairs = (d && d.pairs || []).filter(p => p.baseToken && p.baseToken.address === a.mint);
    pairs.sort((x, y) => ((y.liquidity || {}).usd || 0) - ((x.liquidity || {}).usd || 0));
    return pairs[0] || null;
  }

  async function prices() {
    const [b, h, ...dx] = await Promise.all([binance(), hyperliquid(), ...ASSETS.filter(a => a.src === 'dex').map(dex)]);
    const D = {}; ASSETS.filter(a => a.src === 'dex').forEach((a, i) => D[a.sym] = dx[i]);
    return ASSETS.map(a => {
      if (a.src === 'dex') {
        const p = D[a.sym];
        return { ...a, price: p ? num(p.priceUsd) : null, chg: p && p.priceChange ? num(p.priceChange.h24) : null,
                 high: null, low: null, vol: p && p.volume ? num(p.volume.h24) : null };
      }
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
      const today = new Date().toISOString().slice(0, 10);
      const past = Object.keys(H).filter(d => d < today).sort().slice(-30).map(d => H[d] && H[d][a.sym]).filter(r => r && num(r.total) !== null);
      out[a.sym] = { '24h': live ? { ...live, have: 1, need: 1 } : { long: null, short: null, total: null, have: 0, need: 1 },
                     '7d': windowSum(H, a.sym, live, 7), '30d': windowSum(H, a.sym, live, 30),
                     avgDay: past.length ? { avg: past.reduce((s, r) => s + num(r.total), 0) / past.length, days: past.length } : null };
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

  async function hlCandles(coin, tf, scale = 1) {
    const end = Date.now(), start = end - TF[tf].ms - IV_MS[TF[tf].iv];
    const d = await getJSON(HL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'candleSnapshot', req: { coin, interval: TF[tf].iv, startTime: start, endTime: end } }) }, 15000);
    return Array.isArray(d) ? d.map(k => bar(k.t, k.o * scale, k.h * scale, k.l * scale, k.c * scale, k.v / scale)) : [];
  }
  // GeckoTerminal pool OHLCV (USD, newest first). Thin pools skip minutes with no trades.
  const GT_IV = { '1m': ['minute', 1], '5m': ['minute', 5], '15m': ['minute', 15], '1h': ['hour', 1], '4h': ['hour', 4] };
  async function gtCandles(a, tf) {
    const [unit, agg] = GT_IV[TF[tf].iv], n = Math.min(1000, Math.ceil(TF[tf].ms / IV_MS[TF[tf].iv]) + 1);
    const d = await getJSON(`https://api.geckoterminal.com/api/v2/networks/${a.chain}/pools/${a.pool}/ohlcv/${unit}?aggregate=${agg}&limit=${n}&currency=usd&token=base`, { headers: { Accept: 'application/json' } }, 15000);
    const list = d && d.data && d.data.attributes && d.data.attributes.ohlcv_list;
    const since = Date.now() - TF[tf].ms;
    return Array.isArray(list) ? list.map(k => bar(k[0] * 1000, k[1], k[2], k[3], k[4], k[5])).filter(b => b.time * 1000 >= since).reverse() : [];
  }
  async function candles(asset, tf) {
    const spec = TF[tf];
    if (asset.src === 'dex') return { src: 'GeckoTerminal', bars: await gtCandles(asset, tf) };
    if (asset.src === 'binance') {
      const n = Math.min(1000, Math.ceil(spec.ms / IV_MS[spec.iv]) + 1);
      const q = `/api/v3/klines?symbol=${asset.sym}USDT&interval=${spec.iv}&limit=${n}`;
      for (const base of BINANCE) {
        const d = await getJSON(base + q, {}, 15000);
        if (Array.isArray(d) && d.length) return { src: 'Binance', bars: d.map(k => bar(k[0], k[1], k[2], k[3], k[4], k[7])) };
      }
      const hl = await hlCandles(asset.hlCoin || asset.sym, tf, asset.hlScale || 1);   // fallback: Hyperliquid perp
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
  const mean = a => a.reduce((s, v) => s + v, 0) / (a.length || 1);
  function ema(vals, n) {
    if (vals.length < n) return [];
    const k = 2 / (n + 1), out = new Array(vals.length).fill(null);
    let e = mean(vals.slice(0, n)); out[n - 1] = e;
    for (let i = n; i < vals.length; i++) { e = vals[i] * k + e * (1 - k); out[i] = e; }
    return out;
  }
  function rsiSeries(c, n = 14) {
    const out = new Array(c.length).fill(null);
    if (c.length <= n) return out;
    let g = 0, l = 0;
    for (let i = 1; i <= n; i++) { const d = c[i] - c[i - 1]; d > 0 ? g += d : l -= d; }
    g /= n; l /= n; out[n] = l === 0 ? 100 : 100 - 100 / (1 + g / l);
    for (let i = n + 1; i < c.length; i++) {
      const d = c[i] - c[i - 1]; g = (g * (n - 1) + Math.max(d, 0)) / n; l = (l * (n - 1) + Math.max(-d, 0)) / n;
      out[i] = l === 0 ? 100 : 100 - 100 / (1 + g / l);
    }
    return out;
  }
  function atrPct(b, n = 14) {
    if (b.length <= n) return null;
    const tr = b.slice(1).map((x, i) => Math.max(x.high - x.low, Math.abs(x.high - b[i].close), Math.abs(x.low - b[i].close)));
    return mean(tr.slice(-n)) / b[b.length - 1].close * 100;
  }
  // Swing highs/lows: a bar higher (lower) than the k bars on each side. Returns {price, i}.
  function pivots(b, k = 3) {
    const hi = [], lo = [];
    for (let i = k; i < b.length - k; i++) {
      const w = b.slice(i - k, i + k + 1);
      if (b[i].high === Math.max(...w.map(x => x.high))) hi.push({ price: b[i].high, i });
      if (b[i].low === Math.min(...w.map(x => x.low))) lo.push({ price: b[i].low, i });
    }
    return { hi, lo };
  }
  // Nearest distinct levels on one side of price; levels closer than `merge` collapse into one.
  function levels(list, last, side, gap, merge) {
    const c = list.map(p => p.price).filter(v => side < 0 ? v < last - gap : v > last + gap)
      .sort((a, b) => side < 0 ? b - a : a - b);
    const out = [];
    for (const v of c) if (!out.some(x => Math.abs(x - v) < merge)) out.push(v);
    return out.slice(0, 2);
  }
  function macd(c) {
    const e12 = ema(c, 12), e26 = ema(c, 26);
    if (!e26.length) return null;
    const line = c.map((_, i) => e12[i] !== null && e26[i] !== null ? e12[i] - e26[i] : null);
    const valid = line.filter(v => v !== null);
    if (valid.length < 9) return null;
    const sig = ema(valid, 9), off = line.length - valid.length;
    const signal = line.map((_, i) => i >= off ? sig[i - off] : null);
    const n = c.length - 1, hist = i => line[i] - signal[i];
    let cross = null;
    for (let i = n; i > n - 4 && i > off + 9; i--) {
      if (signal[i] === null || signal[i - 1] === null) break;
      if (hist(i) > 0 && hist(i - 1) <= 0) { cross = 'up'; break; }
      if (hist(i) < 0 && hist(i - 1) >= 0) { cross = 'down'; break; }
    }
    return { line: line[n], signal: signal[n], hist: hist(n), rising: hist(n) > hist(n - 1), cross };
  }
  function bollinger(c, n = 20) {
    if (c.length < n + 5) return null;
    const bw = [];
    let mid, up, lo;
    for (let i = n - 1; i < c.length; i++) {
      const w = c.slice(i - n + 1, i + 1), m = mean(w), sd = Math.sqrt(mean(w.map(v => (v - m) ** 2)));
      bw.push((4 * sd) / m); mid = m; up = m + 2 * sd; lo = m - 2 * sd;
    }
    const last = c[c.length - 1];
    return { mid, upper: up, lower: lo, pctB: up > lo ? (last - lo) / (up - lo) : 0.5,
             width: bw[bw.length - 1], squeeze: bw[bw.length - 1] < 0.75 * mean(bw) };
  }
  // Simple RSI divergence between the last two swing lows / highs.
  function divergence(b, r, pv) {
    const two = (arr) => arr.filter(p => r[p.i] !== null).slice(-2);
    const L = two(pv.lo), H = two(pv.hi);
    if (L.length === 2 && L[1].i - L[0].i >= 4 && L[1].price < L[0].price && r[L[1].i] > r[L[0].i] + 2) return 'bullish';
    if (H.length === 2 && H[1].i - H[0].i >= 4 && H[1].price > H[0].price && r[H[1].i] < r[H[0].i] - 2) return 'bearish';
    return null;
  }

  function analyze(b, liq) {
    if (!b || b.length < 10) return null;
    const c = b.map(x => x.close), n = c.length - 1, last = c[n], first = b[0].open;
    const hiI = b.reduce((m, x, i) => x.high > b[m].high ? i : m, 0), loI = b.reduce((m, x, i) => x.low < b[m].low ? i : m, 0);
    const high = b[hiI].high, low = b[loI].low;
    const e20 = ema(c, 20), e50 = ema(c, 50);
    const E20 = e20.length ? e20[n] : null, E50 = e50.length ? e50[n] : null;
    const E20prev = e20.length && n >= 30 ? e20[n - 10] : null;
    const rs = rsiSeries(c), R = rs[n], ATR = atrPct(b);
    const pv = pivots(b, b.length >= 60 ? 4 : 3);
    const gap = ATR !== null ? last * ATR / 100 : last * 0.003;
    const sup = levels(pv.lo, last, -1, gap, gap), res = levels(pv.hi, last, 1, gap, gap);
    const vols = b.map(x => x.volume), totV = vols.reduce((s, v) => s + v, 0);
    const avgV = totV / vols.length, recentV = mean(vols.slice(-5));
    const upV = b.reduce((s, x) => s + (x.close >= x.open ? x.volume : 0), 0);
    const vwap = totV > 0 ? b.reduce((s, x) => s + (x.high + x.low + x.close) / 3 * x.volume, 0) / totV : null;
    const M = macd(c), BB = bollinger(c);
    // Fibonacci of the window's main swing (low→high if the high came last, else high→low)
    const upSwing = hiI > loI, span = high - low;
    const fibs = [0.236, 0.382, 0.5, 0.618, 0.786].map(r => ({ r, price: upSwing ? high - r * span : low + r * span }));
    const fibNear = span > 0 ? fibs.reduce((a, f) => Math.abs(f.price - last) < Math.abs(a.price - last) ? f : a) : null;
    // Trend & momentum scorecard
    const sig = [];
    const add = (key, cond) => { if (cond !== null && cond !== undefined) sig.push({ key, bull: !!cond }); };
    add('ema20', E20 === null ? null : last > E20);
    add('emaStack', E20 === null || E50 === null ? null : E20 > E50);
    add('emaSlope', E20 === null || E20prev === null ? null : E20 > E20prev);
    add('macd', M ? M.line > M.signal : null);
    add('vwap', vwap === null ? null : last > vwap);
    add('rsi50', R === null ? null : R > 50);
    add('flow', totV > 0 ? upV / totV > 0.5 : null);
    const bulls = sig.filter(s => s.bull).length, score = sig.length ? (bulls / sig.length) * 2 - 1 : 0;   // -1 … +1
    const bias = score >= 0.6 ? 'strongBull' : score >= 0.2 ? 'bull' : score <= -0.6 ? 'strongBear' : score <= -0.2 ? 'bear' : 'neutral';
    const trend = bias.includes('Bull') || bias === 'bull' ? 'Bullish' : bias.includes('Bear') || bias === 'bear' ? 'Bearish' : 'Mixed';
    return {
      last, first, change: (last / first - 1) * 100, high, low, hiI, loI, upSwing,
      rangePos: span > 0 ? (last - low) / span * 100 : null,
      fromHigh: (last / high - 1) * 100, fromLow: (last / low - 1) * 100,
      ema20: E20, ema50: E50, ema20Series: e20, ema50Series: e50,
      rsi: R, rsiDiv: divergence(b, rs, pv), atr: ATR, macd: M, bb: BB, vwap,
      support: sup[0] ?? null, support2: sup[1] ?? null, resistance: res[0] ?? null, resistance2: res[1] ?? null,
      fib: fibNear, volRatio: avgV > 0 ? recentV / avgV : null, buyShare: totV > 0 ? upV / totV : null,
      signals: sig, bulls, score, bias, trend, liq, bars: b.length,
    };
  }

  // Futures positioning from Hyperliquid (free): funding (hourly rate), open interest, premium.
  const HL_PERP = { BTC: 'BTC', ETH: 'ETH', BNB: 'BNB', SOL: 'SOL', XRP: 'XRP', PEPE: 'kPEPE', ANT: 'xyz:ANT', SPX: 'xyz:SP500' };
  let hlCtx = { at: 0, map: null };
  async function positioning(sym) {
    const name = HL_PERP[sym];
    if (!name) return null;
    if (!hlCtx.map || Date.now() - hlCtx.at > 55000) {
      const post = body => getJSON(HL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const [m, x] = await Promise.all([post({ type: 'metaAndAssetCtxs' }), post({ type: 'metaAndAssetCtxs', dex: 'xyz' })]);
      const map = {};
      for (const d of [m, x]) if (Array.isArray(d) && d[0] && Array.isArray(d[1])) d[0].universe.forEach((u, i) => map[u.name] = d[1][i]);
      hlCtx = { at: Date.now(), map };
    }
    const c = hlCtx.map[name];
    if (!c) return null;
    const f = num(c.funding), oi = num(c.openInterest), px = num(c.markPx);
    return { funding8h: f === null ? null : f * 8 * 100, fundingYear: f === null ? null : f * 24 * 365 * 100,
             oiUsd: oi !== null && px !== null ? oi * px : null, premium: num(c.premium) === null ? null : num(c.premium) * 100 };
  }

  const fmtUSD = v => v === null || v === undefined ? '—'
    : Math.abs(v) >= 1e12 ? '$' + (v / 1e12).toFixed(2) + 'T'
    : Math.abs(v) >= 1e9 ? '$' + (v / 1e9).toFixed(2) + 'B'
    : Math.abs(v) >= 1e6 ? '$' + (v / 1e6).toFixed(1) + 'M'
    : Math.abs(v) >= 1e3 ? '$' + (v / 1e3).toFixed(1) + 'K' : '$' + Math.round(v);
  const fmtPrice = v => {
    if (v === null || v === undefined) return '—';
    if (v > 0 && v < 0.01) return '$' + v.toLocaleString('en-US', { maximumSignificantDigits: 4 });   // e.g. PEPE $0.000003448
    const d = v >= 10 ? 2 : v >= 1 ? 3 : 4;
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

  window.ALREEF = { ASSETS, LIQ_ASSETS, TF, prices, liquidations, liqRange, candles, analyze, positioning,
                    fmtUSD, fmtPrice, fmtPct, spain, clock, every60 };
})();
