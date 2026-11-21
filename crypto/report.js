// alreef.es crypto — analysis report in English, Spanish and Arabic.
// Built from templates (no translation service), using the numbers from ALREEF.analyze().
(function () {
  const A = window.ALREEF;
  const P = v => A.fmtPrice(v), U = v => A.fmtUSD(v);
  const pc = (v, d = 2) => (v >= 0 ? '+' : '') + v.toFixed(d) + '%';
  const ab = (v, d = 1) => Math.abs(v).toFixed(d) + '%';
  const dist = (lvl, last) => pc((lvl / last - 1) * 100, 1);

  const L = {
    en: {
      dir: 'ltr', name: 'English',
      tf: { '1h': ['1 hour', '1-hour'], '4h': ['4 hours', '4-hour'], '24h': ['24 hours', '24-hour'], '7d': ['7 days', '7-day'], '30d': ['30 days', '30-day'] },
      h: { verdict: 'Verdict', trend: 'Trend', mom: 'Momentum', vol: 'Volatility', flow: 'Volume & flows', pos: 'Positioning', lv: 'Key levels', sc: 'Scenarios', note: 'Note' },
      bias: { strongBull: 'Strong bullish', bull: 'Bullish', neutral: 'Neutral', bear: 'Bearish', strongBear: 'Strong bearish' },
      trendW: { Bullish: 'bullish', Bearish: 'bearish', Mixed: 'mixed' },
      verdict: (a, nm, tf, adj) => `${a.biasL}: ${a.bulls} of ${a.n} trend and momentum signals are bullish. ${nm} is ${a.change >= 0 ? 'up' : 'down'} ${ab(a.change, 2)} over ${tf}, ${ab(a.fromHigh)} below the ${adj} high and ${ab(a.fromLow)} above the low.`,
      ema: (a) => a.ema20 === null ? 'Not enough candles yet for moving averages.'
        : `Price is ${a.last > a.ema20 ? 'above' : 'below'} its 20-period average (${P(a.ema20)})` +
          (a.ema50 !== null ? ` and the 20 is ${a.ema20 > a.ema50 ? 'above' : 'below'} the 50 (${P(a.ema50)})` : '') +
          `, a ${a.last > a.ema20 && (a.ema50 === null || a.ema20 > a.ema50) ? 'bullish' : a.last < a.ema20 && (a.ema50 === null || a.ema20 < a.ema50) ? 'bearish' : 'mixed'} structure.`,
      mtf: (m, agree) => `Across timeframes: ${m}. ` + (agree === 'all' ? 'All timeframes agree, which makes the trend more reliable.'
        : agree === 'split' ? 'Short-term and longer-term trends disagree, so expect choppy, two-way moves.' : 'Timeframes are mixed.'),
      rsiZone: { os: 'oversold', weak: 'weak', neu: 'neutral', firm: 'firm', ob: 'overbought' },
      rsi: (r, z) => `RSI is ${r.toFixed(0)} (${z})` + (z === 'oversold' ? ': sellers may be exhausted, so a relief bounce is possible.' : z === 'overbought' ? ': buyers may be stretched, so a pullback is possible.' : '.'),
      div: { bullish: 'A bullish divergence (price made a lower low while RSI made a higher low) suggests selling pressure is fading.', bearish: 'A bearish divergence (price made a higher high while RSI made a lower high) suggests buying pressure is fading.' },
      macd: (m) => `MACD is ${m.line > m.signal ? 'above' : 'below'} its signal line${m.cross ? `, with a fresh ${m.cross === 'up' ? 'bullish' : 'bearish'} crossover` : ''}; ${m.line > m.signal ? (m.rising ? 'bullish momentum is building' : 'bullish momentum is fading') : (m.rising ? 'bearish momentum is easing' : 'bearish momentum is growing')}.`,
      atr: (v, iv) => `The average ${iv} candle moves ${v.toFixed(2)}%.`,
      bb: { above: 'Price is above the upper Bollinger band: stretched, and often followed by a pause.', below: 'Price is below the lower Bollinger band: stretched to the downside, where bounces often start.', nearUp: 'Price is pressing the upper Bollinger band.', nearLo: 'Price is hugging the lower Bollinger band.', mid: 'Price sits mid-band.', squeeze: 'The bands are squeezed (low volatility), which often comes before a sharp move.' },
      volR: (x, adj) => `Recent volume is ${x.toFixed(1)}× the ${adj} average` + (x > 1.5 ? ', heavy enough to give the move conviction.' : x < 0.6 ? ', light, so moves may not follow through.' : ', about normal.'),
      flow: (s) => `${(s * 100).toFixed(0)}% of volume traded on rising candles: ` + (s > 0.55 ? 'buyers are in control.' : s < 0.45 ? 'sellers are in control.' : 'buyers and sellers are balanced.'),
      vwap: (a, adj) => `Price is ${a.last > a.vwap ? 'above' : 'below'} the ${adj} volume-weighted average price (${P(a.vwap)}), so recent ${a.last > a.vwap ? 'buyers are in profit on average' : 'buyers are under water on average'}.`,
      fund: (f, y) => `Funding is ${f.toFixed(4)}% per 8 hours (${y.toFixed(1)}% a year)` + (f > 0.01 ? ': longs pay shorts, the market leans long, and sharp drops can trigger long liquidations.' : f < -0.01 ? ': shorts pay longs, the market leans short, and rallies can trigger a short squeeze.' : ', close to neutral.'),
      oi: (v) => `Open interest on Hyperliquid is ${U(v)}.`,
      liq: (l, tf) => `In the last ${tf}, ${U(l.total)} was liquidated, ${(l.share * 100).toFixed(0)}% of it longs` +
        (l.share >= 0.65 ? ': leveraged buyers were forced to sell, which added to selling pressure.' : l.share <= 0.35 ? ': short sellers were forced to buy back, which added to buying pressure.' : ', fairly balanced.'),
      liqAvg: (x, n) => `That is ${x.toFixed(1)}× the average day of the last ${n} days.`,
      noLiq: (nm, why) => `${nm} has no liquidation data (${why}).`,
      sup: (s) => `Support: ${s}.`, res: (s) => `Resistance: ${s}.`,
      noSup: (v) => `No clear swing support below price in this window; the window low ${P(v)} is the nearest reference.`,
      noRes: (v) => `No clear swing resistance above price in this window; the window high ${P(v)} is the nearest reference.`,
      fib: (r, p, up, adj) => `Price is near the ${(r * 100).toFixed(1)}% Fibonacci retracement (${P(p)}) of the ${adj} ${up ? 'rally' : 'drop'}.`,
      bull: (s, r1, t, m) => `Bullish case: holding ${P(s)} and breaking above ${P(r1)} targets ${P(t)}${m ? ' (a measured-move projection, as there is no higher level in this window)' : ''}.`,
      bear: (s1, t, m) => `Bearish case: losing ${P(s1)} targets ${P(t)}${m ? ' (a measured-move projection, as there is no lower level in this window)' : ''}.`,
      bullHi: (s, h) => `Bullish case: holding ${P(s)} and breaking the window high ${P(h)} would put the price in new territory for this period.`,
      bearLo: (l) => `Bearish case: losing the window low ${P(l)} would mean new lows for this period, with no nearby support underneath.`,
      noise: (v) => `Moves smaller than about ${v.toFixed(2)}% (one average candle) are noise, not a signal.`,
      thin: 'Purple Bitcoin trades only in small Solana DEX pools: single trades can move the price, and some candles are missing.',
      none: 'Not enough price data for this timeframe yet.',
    },

    es: {
      dir: 'ltr', name: 'Español',
      tf: { '1h': ['1 hora', 'de 1 hora'], '4h': ['4 horas', 'de 4 horas'], '24h': ['24 horas', 'de 24 horas'], '7d': ['7 días', 'de 7 días'], '30d': ['30 días', 'de 30 días'] },
      h: { verdict: 'Veredicto', trend: 'Tendencia', mom: 'Momento', vol: 'Volatilidad', flow: 'Volumen y flujos', pos: 'Posicionamiento', lv: 'Niveles clave', sc: 'Escenarios', note: 'Nota' },
      bias: { strongBull: 'Muy alcista', bull: 'Alcista', neutral: 'Neutral', bear: 'Bajista', strongBear: 'Muy bajista' },
      trendW: { Bullish: 'alcista', Bearish: 'bajista', Mixed: 'mixta' },
      verdict: (a, nm, tf, adj) => `${a.biasL}: ${a.bulls} de ${a.n} señales de tendencia y momento son alcistas. ${nm} ${a.change >= 0 ? 'sube' : 'baja'} un ${ab(a.change, 2)} en ${tf}, un ${ab(a.fromHigh)} por debajo del máximo ${adj} y un ${ab(a.fromLow)} por encima del mínimo.`,
      ema: (a) => a.ema20 === null ? 'Aún no hay velas suficientes para las medias móviles.'
        : `El precio está ${a.last > a.ema20 ? 'por encima' : 'por debajo'} de su media de 20 periodos (${P(a.ema20)})` +
          (a.ema50 !== null ? ` y la de 20 está ${a.ema20 > a.ema50 ? 'por encima' : 'por debajo'} de la de 50 (${P(a.ema50)})` : '') +
          `: una estructura ${a.last > a.ema20 && (a.ema50 === null || a.ema20 > a.ema50) ? 'alcista' : a.last < a.ema20 && (a.ema50 === null || a.ema20 < a.ema50) ? 'bajista' : 'mixta'}.`,
      mtf: (m, agree) => `Por marcos temporales: ${m}. ` + (agree === 'all' ? 'Todos coinciden, lo que hace la tendencia más fiable.'
        : agree === 'split' ? 'El corto y el largo plazo no coinciden: cabe esperar movimientos bruscos en ambos sentidos.' : 'Los marcos temporales están mezclados.'),
      rsiZone: { os: 'sobrevendido', weak: 'débil', neu: 'neutral', firm: 'firme', ob: 'sobrecomprado' },
      rsi: (r, z) => `El RSI está en ${r.toFixed(0)} (${z})` + (z === 'sobrevendido' ? ': los vendedores pueden estar agotados, así que es posible un rebote.' : z === 'sobrecomprado' ? ': los compradores pueden estar al límite, así que es posible un retroceso.' : '.'),
      div: { bullish: 'Una divergencia alcista (el precio marcó un mínimo más bajo y el RSI uno más alto) sugiere que la presión vendedora se agota.', bearish: 'Una divergencia bajista (el precio marcó un máximo más alto y el RSI uno más bajo) sugiere que la presión compradora se agota.' },
      macd: (m) => `El MACD está ${m.line > m.signal ? 'por encima' : 'por debajo'} de su línea de señal${m.cross ? `, con un cruce ${m.cross === 'up' ? 'alcista' : 'bajista'} reciente` : ''}; ${m.line > m.signal ? (m.rising ? 'el impulso alcista aumenta' : 'el impulso alcista se debilita') : (m.rising ? 'el impulso bajista se modera' : 'el impulso bajista aumenta')}.`,
      atr: (v, iv) => `La vela media de ${iv} se mueve un ${v.toFixed(2)}%.`,
      bb: { above: 'El precio está por encima de la banda superior de Bollinger: estirado, y suele seguir una pausa.', below: 'El precio está por debajo de la banda inferior de Bollinger: estirado a la baja, donde suelen empezar los rebotes.', nearUp: 'El precio presiona la banda superior de Bollinger.', nearLo: 'El precio se pega a la banda inferior de Bollinger.', mid: 'El precio está en la zona media de las bandas.', squeeze: 'Las bandas están estrechas (poca volatilidad), lo que suele anticipar un movimiento fuerte.' },
      volR: (x, adj) => `El volumen reciente es ${x.toFixed(1)}× la media ${adj}` + (x > 1.5 ? ': alto, lo que da convicción al movimiento.' : x < 0.6 ? ': bajo, así que los movimientos pueden no tener continuidad.' : ': normal.'),
      flow: (s) => `El ${(s * 100).toFixed(0)}% del volumen se negoció en velas alcistas: ` + (s > 0.55 ? 'dominan los compradores.' : s < 0.45 ? 'dominan los vendedores.' : 'compradores y vendedores están equilibrados.'),
      vwap: (a, adj) => `El precio está ${a.last > a.vwap ? 'por encima' : 'por debajo'} del precio medio ponderado por volumen ${adj} (${P(a.vwap)}): ${a.last > a.vwap ? 'los compradores recientes ganan de media' : 'los compradores recientes pierden de media'}.`,
      fund: (f, y) => `La financiación es del ${f.toFixed(4)}% cada 8 horas (${y.toFixed(1)}% al año)` + (f > 0.01 ? ': los largos pagan a los cortos, el mercado se inclina al alza y las caídas bruscas pueden liquidar largos.' : f < -0.01 ? ': los cortos pagan a los largos, el mercado se inclina a la baja y las subidas pueden provocar un short squeeze.' : ', casi neutral.'),
      oi: (v) => `El interés abierto en Hyperliquid es de ${U(v)}.`,
      liq: (l, tf) => `En las últimas ${tf} se liquidaron ${U(l.total)}, un ${(l.share * 100).toFixed(0)}% en largos` +
        (l.share >= 0.65 ? ': compradores apalancados forzados a vender, lo que añadió presión vendedora.' : l.share <= 0.35 ? ': vendedores en corto forzados a recomprar, lo que añadió presión compradora.' : ', bastante equilibrado.'),
      liqAvg: (x, n) => `Es ${x.toFixed(1)}× el día medio de los últimos ${n} días.`,
      noLiq: (nm, why) => `${nm} no tiene datos de liquidaciones (${why === 'no futures market' ? 'no tiene mercado de futuros' : 'no hay fuente gratuita'}).`,
      sup: (s) => `Soporte: ${s}.`, res: (s) => `Resistencia: ${s}.`,
      noSup: (v) => `No hay un soporte claro por debajo en este periodo; el mínimo ${P(v)} es la referencia más cercana.`,
      noRes: (v) => `No hay una resistencia clara por encima en este periodo; el máximo ${P(v)} es la referencia más cercana.`,
      fib: (r, p, up, adj) => `El precio está cerca del retroceso de Fibonacci del ${(r * 100).toFixed(1)}% (${P(p)}) de la ${up ? 'subida' : 'caída'} ${adj}.`,
      bull: (s, r1, t, m) => `Escenario alcista: mantener ${P(s)} y superar ${P(r1)} apunta a ${P(t)}${m ? ' (proyección por la amplitud del rango, ya que no hay un nivel superior en este periodo)' : ''}.`,
      bear: (s1, t, m) => `Escenario bajista: perder ${P(s1)} apunta a ${P(t)}${m ? ' (proyección por la amplitud del rango, ya que no hay un nivel inferior en este periodo)' : ''}.`,
      bullHi: (s, h) => `Escenario alcista: mantener ${P(s)} y superar el máximo del periodo ${P(h)} llevaría el precio a terreno nuevo.`,
      bearLo: (l) => `Escenario bajista: perder el mínimo del periodo ${P(l)} supondría nuevos mínimos, sin soporte cercano por debajo.`,
      noise: (v) => `Los movimientos menores de un ${v.toFixed(2)}% (una vela media) son ruido, no una señal.`,
      thin: 'Purple Bitcoin solo cotiza en pequeños pools DEX de Solana: una sola operación puede mover el precio y faltan algunas velas.',
      none: 'Aún no hay datos de precio suficientes para este marco temporal.',
    },

    ar: {
      dir: 'rtl', name: 'العربية',
      tf: { '1h': ['ساعة واحدة', 'لساعة واحدة'], '4h': ['4 ساعات', 'لـ4 ساعات'], '24h': ['24 ساعة', 'لـ24 ساعة'], '7d': ['7 أيام', 'لـ7 أيام'], '30d': ['30 يومًا', 'لـ30 يومًا'] },
      h: { verdict: 'الخلاصة', trend: 'الاتجاه', mom: 'الزخم', vol: 'التقلّب', flow: 'الحجم والتدفقات', pos: 'مراكز العقود', lv: 'المستويات الرئيسية', sc: 'السيناريوهات', note: 'ملاحظة' },
      bias: { strongBull: 'صعودي قوي', bull: 'صعودي', neutral: 'محايد', bear: 'هبوطي', strongBear: 'هبوطي قوي' },
      trendW: { Bullish: 'صعودي', Bearish: 'هبوطي', Mixed: 'متذبذب' },
      verdict: (a, nm, tf, adj) => `${a.biasL}: ${a.bulls} من أصل ${a.n} إشارات للاتجاه والزخم إيجابية. ${nm} ${a.change >= 0 ? 'مرتفع' : 'منخفض'} بنسبة ${ab(a.change, 2)} خلال ${tf}، وهو أدنى من أعلى سعر ${adj} بنسبة ${ab(a.fromHigh)} وأعلى من أدنى سعر بنسبة ${ab(a.fromLow)}.`,
      ema: (a) => a.ema20 === null ? 'لا توجد شموع كافية بعد لحساب المتوسطات المتحركة.'
        : `السعر ${a.last > a.ema20 ? 'فوق' : 'تحت'} متوسطه لـ20 فترة (${P(a.ema20)})` +
          (a.ema50 !== null ? `، ومتوسط الـ20 ${a.ema20 > a.ema50 ? 'فوق' : 'تحت'} متوسط الـ50 (${P(a.ema50)})` : '') +
          `، وهذه بنية ${a.last > a.ema20 && (a.ema50 === null || a.ema20 > a.ema50) ? 'صعودية' : a.last < a.ema20 && (a.ema50 === null || a.ema20 < a.ema50) ? 'هبوطية' : 'متذبذبة'}.`,
      mtf: (m, agree) => `حسب الأطر الزمنية: ${m}. ` + (agree === 'all' ? 'جميع الأطر الزمنية متفقة، ما يجعل الاتجاه أكثر موثوقية.'
        : agree === 'split' ? 'الاتجاه قصير المدى يخالف الاتجاه الأطول، لذا يُتوقع تذبذب في الاتجاهين.' : 'الأطر الزمنية متباينة.'),
      rsiZone: { os: 'تشبّع بيعي', weak: 'ضعيف', neu: 'محايد', firm: 'قوي', ob: 'تشبّع شرائي' },
      rsi: (r, z) => `مؤشر القوة النسبية RSI عند ${r.toFixed(0)} (${z})` + (z === 'تشبّع بيعي' ? '؛ قد يكون البائعون قد استُنزفوا، لذا يُحتمل ارتداد مؤقت.' : z === 'تشبّع شرائي' ? '؛ قد يكون المشترون قد بالغوا، لذا يُحتمل تراجع.' : '.'),
      div: { bullish: 'هناك انحراف إيجابي (السعر سجّل قاعًا أدنى بينما سجّل RSI قاعًا أعلى)، ما يشير إلى ضعف ضغط البيع.', bearish: 'هناك انحراف سلبي (السعر سجّل قمة أعلى بينما سجّل RSI قمة أدنى)، ما يشير إلى ضعف ضغط الشراء.' },
      macd: (m) => `مؤشر MACD ${m.line > m.signal ? 'فوق' : 'تحت'} خط الإشارة${m.cross ? `، مع تقاطع ${m.cross === 'up' ? 'إيجابي' : 'سلبي'} حديث` : ''}؛ ${m.line > m.signal ? (m.rising ? 'والزخم الصعودي يتزايد' : 'والزخم الصعودي يتراجع') : (m.rising ? 'والزخم الهبوطي يخفّ' : 'والزخم الهبوطي يتزايد')}.`,
      atr: (v, iv) => `متوسط حركة شمعة الـ${iv} هو ${v.toFixed(2)}%.`,
      bb: { above: 'السعر فوق الحد العلوي لنطاقات بولينجر: ممتد، وغالبًا ما يتبعه توقف.', below: 'السعر تحت الحد السفلي لنطاقات بولينجر: ممتد نزولًا، وغالبًا ما تبدأ الارتدادات من هنا.', nearUp: 'السعر يضغط على الحد العلوي لنطاقات بولينجر.', nearLo: 'السعر ملاصق للحد السفلي لنطاقات بولينجر.', mid: 'السعر في منتصف النطاق.', squeeze: 'النطاقات ضيقة (تقلب منخفض)، وهذا غالبًا يسبق حركة قوية.' },
      volR: (x, adj) => `الحجم الأخير يعادل ${x.toFixed(1)} أضعاف المتوسط ${adj}` + (x > 1.5 ? '، وهو مرتفع بما يكفي ليمنح الحركة مصداقية.' : x < 0.6 ? '، وهو ضعيف، لذا قد لا تستمر الحركة.' : '، وهو طبيعي.'),
      flow: (s) => `${(s * 100).toFixed(0)}% من الحجم تم تداوله في شموع صاعدة: ` + (s > 0.55 ? 'المشترون يسيطرون.' : s < 0.45 ? 'البائعون يسيطرون.' : 'توازن بين المشترين والبائعين.'),
      vwap: (a, adj) => `السعر ${a.last > a.vwap ? 'فوق' : 'تحت'} متوسط السعر المرجّح بالحجم ${adj} (${P(a.vwap)})، أي أن المشترين الجدد ${a.last > a.vwap ? 'رابحون في المتوسط' : 'خاسرون في المتوسط'}.`,
      fund: (f, y) => `معدل التمويل ${f.toFixed(4)}% كل 8 ساعات (${y.toFixed(1)}% سنويًا)` + (f > 0.01 ? '؛ أصحاب الشراء يدفعون لأصحاب البيع، والسوق يميل للشراء، والهبوط الحاد قد يؤدي إلى تصفية مراكز الشراء.' : f < -0.01 ? '؛ أصحاب البيع يدفعون لأصحاب الشراء، والسوق يميل للبيع، والارتفاع قد يسبب ضغطًا على مراكز البيع (short squeeze).' : '، قريب من الحياد.'),
      oi: (v) => `حجم العقود المفتوحة على Hyperliquid هو ${U(v)}.`,
      liq: (l, tf) => `خلال آخر ${tf} تمت تصفية ${U(l.total)}، منها ${(l.share * 100).toFixed(0)}% مراكز شراء` +
        (l.share >= 0.65 ? '؛ أي أن المشترين بالرافعة أُجبروا على البيع، ما زاد ضغط البيع.' : l.share <= 0.35 ? '؛ أي أن البائعين على المكشوف أُجبروا على إعادة الشراء، ما زاد ضغط الشراء.' : '، وهي متوازنة تقريبًا.'),
      liqAvg: (x, n) => `وهذا يعادل ${x.toFixed(1)} أضعاف متوسط اليوم خلال آخر ${n} أيام.`,
      noLiq: (nm, why) => `لا توجد بيانات تصفية لـ${nm} (${why === 'no futures market' ? 'لا يوجد سوق عقود آجلة' : 'لا يوجد مصدر مجاني'}).`,
      sup: (s) => `الدعم: ${s}.`, res: (s) => `المقاومة: ${s}.`,
      noSup: (v) => `لا يوجد دعم واضح تحت السعر في هذه الفترة؛ أدنى سعر ${P(v)} هو أقرب مرجع.`,
      noRes: (v) => `لا توجد مقاومة واضحة فوق السعر في هذه الفترة؛ أعلى سعر ${P(v)} هو أقرب مرجع.`,
      fib: (r, p, up, adj) => `السعر قريب من مستوى فيبوناتشي ${(r * 100).toFixed(1)}% (${P(p)}) ${up ? 'للصعود' : 'للهبوط'} ${adj}.`,
      bull: (s, r1, t, m) => `السيناريو الإيجابي: الثبات فوق ${P(s)} واختراق ${P(r1)} يستهدف ${P(t)}${m ? ' (إسقاط حسب اتساع النطاق، لعدم وجود مستوى أعلى في هذه الفترة)' : ''}.`,
      bear: (s1, t, m) => `السيناريو السلبي: كسر ${P(s1)} يستهدف ${P(t)}${m ? ' (إسقاط حسب اتساع النطاق، لعدم وجود مستوى أدنى في هذه الفترة)' : ''}.`,
      bullHi: (s, h) => `السيناريو الإيجابي: الثبات فوق ${P(s)} واختراق أعلى سعر في الفترة ${P(h)} يضع السعر في منطقة جديدة.`,
      bearLo: (l) => `السيناريو السلبي: كسر أدنى سعر في الفترة ${P(l)} يعني قيعانًا جديدة دون دعم قريب.`,
      noise: (v) => `الحركات الأصغر من نحو ${v.toFixed(2)}% (شمعة متوسطة واحدة) تُعدّ ضجيجًا وليست إشارة.`,
      thin: 'يتم تداول Purple Bitcoin فقط في مجمّعات صغيرة على منصات DEX في شبكة سولانا: صفقة واحدة قد تحرّك السعر، وبعض الشموع مفقودة.',
      none: 'لا توجد بيانات سعرية كافية لهذا الإطار الزمني بعد.',
    },
  };

  const TF_ORDER = ['1h', '4h', '24h', '7d', '30d'];

  // Returns { dir, sections: [{ h, p }] }
  function report(a, ctx, tf, asset, lang) {
    const T = L[lang] || L.en, nm = asset.name, [tfW, tfA] = T.tf[tf];
    if (!a) return { dir: T.dir, sections: [{ h: T.h.verdict, p: T.none }] };
    const S = [], iv = A.TF[tf].iv;
    a = { ...a, n: a.signals.length, biasL: T.bias[a.bias] };

    S.push({ h: T.h.verdict, p: T.verdict(a, nm, tfW, tfA) });

    let tr = T.ema(a);
    if (ctx && ctx.mtf) {
      const parts = TF_ORDER.filter(k => ctx.mtf[k]).map(k => `${A.TF[k].label} ${T.trendW[ctx.mtf[k]]}`);
      const vals = TF_ORDER.map(k => ctx.mtf[k]).filter(Boolean);
      const short = ['1h', '4h'].map(k => ctx.mtf[k]).filter(Boolean), long = ['7d', '30d'].map(k => ctx.mtf[k]).filter(Boolean);
      const all = (arr, v) => arr.length > 0 && arr.every(x => x === v);
      const agree = vals.length >= 3 && vals.every(v => v === vals[0] && v !== 'Mixed') ? 'all'
        : (all(short, 'Bullish') && all(long, 'Bearish')) || (all(short, 'Bearish') && all(long, 'Bullish')) ? 'split' : 'mixed';
      if (parts.length >= 3) tr += ' ' + T.mtf(parts.join(', '), agree);
    }
    S.push({ h: T.h.trend, p: tr });

    const mom = [];
    if (a.rsi !== null) {
      const z = a.rsi < 30 ? 'os' : a.rsi < 45 ? 'weak' : a.rsi <= 55 ? 'neu' : a.rsi <= 70 ? 'firm' : 'ob';
      mom.push(T.rsi(a.rsi, T.rsiZone[z]));
    }
    if (a.rsiDiv) mom.push(T.div[a.rsiDiv]);
    if (a.macd) mom.push(T.macd(a.macd));
    if (mom.length) S.push({ h: T.h.mom, p: mom.join(' ') });

    const vol = [];
    if (a.atr !== null) vol.push(T.atr(a.atr, iv));
    if (a.bb) {
      const b = a.bb.pctB;
      vol.push(T.bb[b > 1 ? 'above' : b < 0 ? 'below' : b > 0.8 ? 'nearUp' : b < 0.2 ? 'nearLo' : 'mid']);
      if (a.bb.squeeze) vol.push(T.bb.squeeze);
    }
    if (vol.length) S.push({ h: T.h.vol, p: vol.join(' ') });

    const fl = [];
    if (a.volRatio !== null) fl.push(T.volR(a.volRatio, tfA));
    if (a.buyShare !== null) fl.push(T.flow(a.buyShare));
    if (a.vwap !== null) fl.push(T.vwap(a, tfA));
    if (fl.length) S.push({ h: T.h.flow, p: fl.join(' ') });

    const pos = [];
    if (ctx && ctx.pos) {
      if (ctx.pos.funding8h !== null) pos.push(T.fund(ctx.pos.funding8h, ctx.pos.fundingYear));
      if (ctx.pos.oiUsd) pos.push(T.oi(ctx.pos.oiUsd));
    }
    if (asset.noLiq) pos.push(T.noLiq(nm, asset.noLiq));
    else if (a.liq && a.liq.total) {
      const share = a.liq.long / ((a.liq.long + a.liq.short) || 1);
      pos.push(T.liq({ total: a.liq.total, share }, tfW));
      if (tf === '24h' && ctx && ctx.liqAvgDay && ctx.liqAvgDay.days >= 3) pos.push(T.liqAvg(a.liq.total / ctx.liqAvgDay.avg, ctx.liqAvgDay.days));
    }
    if (pos.length) S.push({ h: T.h.pos, p: pos.join(' ') });

    const lv = [];
    const iso = t => T.dir === 'rtl' ? '\u2066' + t + '\u2069' : t;
    const fmtL = (arr, tag) => arr.filter(v => v !== null).map((v, i) => iso(`${tag}${i + 1} ${P(v)} (${dist(v, a.last)})`)).join(T.dir === 'rtl' ? '، ' : ', ');
    lv.push(a.support !== null ? T.sup(fmtL([a.support, a.support2], 'S')) : T.noSup(a.low));
    lv.push(a.resistance !== null ? T.res(fmtL([a.resistance, a.resistance2], 'R')) : T.noRes(a.high));
    if (a.fib && a.atr !== null && Math.abs(a.fib.price / a.last - 1) * 100 <= a.atr * 1.5) lv.push(T.fib(a.fib.r, a.fib.price, a.upSwing, tfA));
    S.push({ h: T.h.lv, p: lv.join(' ') });

    const s1 = a.support ?? a.low, s2 = a.support2 ?? (a.support !== null && a.low < a.support ? a.low : null);
    const r1 = a.resistance ?? a.high, r2 = a.resistance2 ?? (a.resistance !== null && a.high > a.resistance ? a.high : null);
    const sc = [];
    sc.push(T.bull(a.trigDn, a.trigUp, a.targetUp, a.upMeasured));
    if (a.targetDown !== null) sc.push(T.bear(a.trigDn, a.targetDown, a.dnMeasured)); else sc.push(T.bearLo(a.low));
    if (a.atr !== null) sc.push(T.noise(a.atr));
    if (sc.length) S.push({ h: T.h.sc, p: sc.join(' ') });

    if (asset.src === 'dex') S.push({ h: T.h.note, p: T.thin });
    if (T.dir === 'rtl') S.forEach(x => { x.p = x.p.replace(/(?:[A-Za-z]+)?[+\-]?\$?\d[\d,]*(?:\.\d+)?(?:[%×]|[A-Za-z]+)?/g, m => '\u2066' + m + '\u2069'); });
    return { dir: T.dir, sections: S };
  }

  A.report = report;
  A.LANGS = Object.fromEntries(Object.entries(L).map(([k, v]) => [k, v.name]));
})();
