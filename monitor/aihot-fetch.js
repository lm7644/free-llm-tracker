// AIHOT 同步引擎：抓取 aihot.news 的 Token羊毛清单与每日日报，合并进 DATA / NEWS。
// 匿名只读接口，无需 key；UA 按官方要求用 aihot-api/2.0.0，单 IP ≤60 次/分钟（本脚本每次运行 3 个请求）。
// 用法：node monitor/aihot-fetch.js [--dry-run]
// 约定：自动收录条目带 ai:<dealId> 标记、可信度固定「第三方」（待人工复核后才可升级）；
//       命中去重的跳过并写入报告，不自动改写人工维护的条目。
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const root = path.resolve(__dirname, '..');
const TPL = path.join(root, 'app_template.html');
const UA = 'aihot-api/2.0.0';
const DRY = process.argv.includes('--dry-run');
const todayISO = (() => { const x = new Date(); x.setMinutes(x.getMinutes() - x.getTimezoneOffset()); return x.toISOString().slice(0, 10); })();

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function getJSON(url) {
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'application/json' }, signal: AbortSignal.timeout(25000) });
    } catch (e) {
      if (attempt === 0) { await sleep(3000); continue; }
      throw new Error(url + ' 网络失败: ' + e.message);
    }
    if (res.status === 429 && attempt === 0) {
      const wait = Math.min(Number(res.headers.get('retry-after')) || 30, 60);
      console.warn('429 限流，等待 ' + wait + 's 重试'); await sleep(wait * 1000); continue;
    }
    if (res.status >= 500 && attempt === 0) { await sleep(3000); continue; }
    if (!res.ok) throw new Error(url + ' HTTP ' + res.status);
    return res.json();
  }
}

// React Router single-fetch 的 turbo-stream v2 扁平数组解码（常量与标签对齐 turbo-stream@2.4.1）
function decodeTurboStream(flat) {
  const cache = new Array(flat.length), done = new Array(flat.length).fill(false);
  function hydrate(i) {
    switch (i) {
      case -1: case -7: return undefined;
      case -2: return NaN;
      case -3: return -Infinity;
      case -4: return -0;
      case -5: return null;
      case -6: return Infinity;
    }
    if (done[i]) return cache[i];
    const v = flat[i];
    if (v === null || typeof v !== 'object') { done[i] = true; return cache[i] = v; }
    if (Array.isArray(v)) {
      if (typeof v[0] === 'string') {
        const [t, b, c] = v;
        let out;
        switch (t) {
          case 'D': out = new Date(b); break;
          case 'U': out = String(new URL(b)); break;
          case 'B': out = BigInt(b); break;
          case 'R': out = new RegExp(b, c); break;
          case 'S': out = new Set(v.slice(1).map(hydrate)); break;
          case 'M': { const m = new Map(); for (let k = 1; k < v.length; k += 2) m.set(hydrate(v[k]), hydrate(v[k + 1])); out = m; break; }
          case 'N': { const o = Object.create(null); for (const key of Object.keys(b)) o[hydrate(Number(key.slice(1)))] = hydrate(b[key]); out = o; break; }
          case 'E': out = new Error(b); break;
          default: throw new Error('未知 turbo-stream 标签: ' + t);
        }
        done[i] = true; return cache[i] = out;
      }
      const arr = []; done[i] = true; cache[i] = arr;
      for (let k = 0; k < v.length; k++) if (v[k] !== -1) arr[k] = hydrate(v[k]);
      return arr;
    }
    const obj = {}; done[i] = true; cache[i] = obj;
    for (const key of Object.keys(v)) obj[hydrate(Number(key.slice(1)))] = hydrate(v[key]);
    return obj;
  }
  return hydrate(0);
}

async function fetchDeals() {
  // 首选 React Router .data 接口；失败时回退到页面 HTML 里 streamController.enqueue 的流式载荷
  try {
    const flat = await getJSON('https://aihot.news/free-tokens.data');
    const data = decodeTurboStream(flat)['free-tokens'].data;
    if (!Array.isArray(data.deals)) throw new Error('deals 不是数组');
    return data;
  } catch (e) {
    console.warn('.data 接口失败（' + e.message + '），回退解析页面内嵌数据');
    const res = await fetch('https://aihot.news/free-tokens', { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(25000) });
    if (!res.ok) throw new Error('free-tokens 页面 HTTP ' + res.status);
    const html = await res.text();
    const chunks = [...html.matchAll(/streamController\.enqueue\(("(?:[^"\\]|\\.)*")\)/g)].map(m => JSON.parse(m[1]));
    if (!chunks.length) throw new Error('页面中找不到内嵌数据');
    const data = decodeTurboStream(JSON.parse(chunks.join('')))['free-tokens'].data;
    if (!Array.isArray(data.deals)) throw new Error('deals 不是数组');
    return data;
  }
}

// ---------- 从模板提取 DATA（与 build-assets.js 同一口径） ----------
function extractDATA(tpl) {
  const a = tpl.indexOf('const DATA = [');
  const b = tpl.indexOf('\n];', a);
  if (a < 0 || b < 0) throw new Error('找不到 DATA 数组');
  const ctx = {};
  vm.createContext(ctx);
  vm.runInContext(tpl.slice(a, b + 3) + ';globalThis.__D=DATA;', ctx);
  return { DATA: ctx.__D, start: a, end: b + 3 };
}

// ---------- 去重 ----------
const TRACKING = new Set(['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'from', 'wxfrom', 'wx_lazy', 'tp', 'spm', 'ref', 'source']);
function normURL(u) {
  try {
    const x = new URL(u);
    x.hostname = x.hostname.toLowerCase().replace(/^www\./, '');
    x.hash = '';
    x.protocol = 'https:';
    [...x.searchParams.keys()].forEach(k => { if (TRACKING.has(k.toLowerCase())) x.searchParams.delete(k); });
    x.searchParams.sort();
    let s = x.toString();
    if (!x.search && s.endsWith('/')) s = s.slice(0, -1);
    return s;
  } catch (e) { return String(u || ''); }
}
const normText = s => String(s || '').toLowerCase().replace(/[^a-z0-9一-鿿]+/g, '');
const GENERIC_LATIN = new Set(['api', 'token', 'tokens', 'pro', 'free', 'ai', 'app', 'credits', 'credit', 'pu', 'ocr', 'pdf', 'http', 'https', 'www', 'com', 'cn', 'the', 'and', 'for', 'max', 'lite', 'flash', 'code', 'plan', 'daily', 'new', 'vip', 'gpu', 'cpu', 'llm', 'agent', 'ide', 'cli', 'sdk', 'web', 'win', 'mac', 'linux']);
const CJK_BRANDS = ['豆包', '小浣熊', '硅基流动', '魔搭', '百炼', '千帆', '火山方舟', '混元', '智谱', '阶跃', '书生', '蚂蚁百灵', '文心', '讯飞', '星火', '千问', '通义', '元宝', '码道', '超算互联网', '日日新', '云工开物', '搭子', '库库', '腾讯', '阿里', '百度', '华为', '商汤'];
// 厂商级品牌：同厂不同产品会共享厂商名，仅凭厂商重合不足以判定同一活动，启发式规则要求产品级品牌命中
const VENDOR_BRANDS = new Set(['腾讯', '阿里', '百度', '华为', '商汤']);
function brandsOf(text) {
  const t = String(text || '');
  const set = new Set();
  for (const m of t.toLowerCase().matchAll(/[a-z][a-z0-9]{2,}/g)) if (!GENERIC_LATIN.has(m[0])) set.add(m[0]);
  for (const b of CJK_BRANDS) if (t.includes(b)) set.add(b);
  return set;
}
const KEYWORDS = ['签到', '学生', '新用户', '新人', '新客', '注册', '实名', '限免', '限时免费', '月卡', '周活动', '邀请', '受邀', '体验', '赠金', '代金券', '抵扣金', '公测', 'globalbuild', 'qoduck', '双十一', '程序员节'];
// 强关键词本身足够独特，品牌命中即可去重；弱关键词还须周期词命中，避免同品牌不同活动误判
const STRONG_KEYWORDS = new Set(['globalbuild', 'qoduck', '双十一', '程序员节', '月卡', '周活动']);
function bigrams(s) {
  const set = new Set();
  for (let i = 0; i < s.length - 1; i++) set.add(s.slice(i, i + 2));
  return set;
}
function sim(a, b) {
  const A = bigrams(a), B = bigrams(b);
  if (!A.size || !B.size) return 0;
  let hit = 0;
  for (const x of A) if (B.has(x)) hit++;
  return hit / (A.size + B.size - hit);
}
const CADENCE = { daily: ['每天', '每日'], weekly: ['每周'], monthly: ['每月', '每个月'], once: ['新用户', '新人', '新客', '注册', '首次', '登录'], limited: ['限时', '限免'], free: ['长期', '永久'] };
// 去掉品牌词后再比相似度，避免同品牌不同活动被误判
function stripBrands(s, brands) {
  let out = String(s);
  for (const b of brands) out = out.split(b).join('');
  return normText(out);
}
function dedup(deal, DATA) {
  const url = normURL(deal.url);
  for (const d of DATA) {
    if (d.ai && d.ai === deal.id) return { action: 'update', entry: d };
  }
  for (const d of DATA) {
    if ((d.L || []).some(l => normURL(l[1]) === url)) return { action: 'skip', rule: 'URL 相同', entry: d };
  }
  const dealText = deal.title + ' ' + (deal.label || '') + ' ' + (deal.tags || []).join(' ');
  const dealNorm = normText(dealText);
  const dealBrands = brandsOf(deal.provider + ' ' + deal.title);
  const dealKeys = new Set(KEYWORDS.filter(k => dealNorm.includes(normText(k))));
  const dealNum = ((deal.label || deal.title).match(/\d[\d,.]*/) || [])[0];
  for (const d of DATA) {
    if (d.s === 'dead') continue;
    const existText = d.n + ' ' + d.q + ' ' + (d.l || '');
    const existNorm = normText(existText);
    const existBrands = brandsOf(d.n + ' ' + d.p + ' ' + existText);
    let productHit = false;
    for (const b of dealBrands) if (existBrands.has(b) && !VENDOR_BRANDS.has(b)) { productHit = true; break; }
    if (!productHit) continue;
    const cad = CADENCE[deal.kind] || [];
    const cadHit = cad.some(w => existNorm.includes(normText(w)));
    for (const k of dealKeys) {
      if (existNorm.includes(normText(k)) && (STRONG_KEYWORDS.has(k) || cadHit)) return { action: 'skip', rule: '同品牌同关键词「' + k + '」', entry: d };
    }
    if (sim(stripBrands(dealNorm, dealBrands), stripBrands(existNorm, existBrands)) >= 0.35) return { action: 'skip', rule: '同品牌文案相似', entry: d };
    if (dealNum && cadHit && new RegExp('(?<!\\d)' + dealNum.replace(/[.,]/g, '') + '(?!\\d)').test(existNorm.replace(/[.,]/g, ''))) {
      return { action: 'skip', rule: '同品牌同周期同额度', entry: d };
    }
  }
  return { action: 'add' };
}

// ---------- 字段映射：AIHOT deal → 本站 DATA ----------
const INTL = new Set(['cloudflare', 'elevenlabs', 'zed', 'fal', 'nace', 'opencode', 'huggingface', 'mistral', 'groq', 'cerebras']);
function mapDeal(deal) {
  const kind = deal.kind;
  const student = !!deal.studentOnly;
  const c = student ? 'student' : (kind === 'daily' || kind === 'monthly' || kind === 'weekly') ? 'signin' : kind === 'limited' ? 'event' : kind === 'free' ? 'api' : 'event';
  const t = student ? '学生' : { daily: '每日', weekly: '每周', monthly: '每月', once: '一次性', limited: '限时', free: '永久' }[kind] || '信息';
  const s = kind === 'limited' ? 'event' : 'active';
  const brands = brandsOf(deal.provider + ' ' + deal.title);
  let r = 'c';
  for (const b of brands) if (INTL.has(b)) r = 'i';
  const ends = deal.endsAt ? String(deal.endsAt).slice(0, 10) : null;
  const e = ends ? '至 ' + ends + '（以厂商页面为准）' : (deal.validity || (kind === 'free' ? '长期有效' : '以厂商页面为准'));
  const tags = (deal.tags || []).length ? '限制：' + deal.tags.join('、') + '。' : '';
  const access = [deal.realName ? '需实名' : '', deal.clientOnly ? '仅限客户端' : '', student ? '学生认证' : ''].filter(Boolean).join(' + ') || '注册登录';
  return {
    n: deal.title, p: deal.provider, g: '', r, c,
    m: (deal.models || []).map(m => typeof m === 'string' ? m : (m && m.name) || '').filter(Boolean).join(' / '),
    q: deal.detail, t,
    l: (deal.label || '以厂商页面为准') + (deal.validity ? '；' + deal.validity : ''),
    u: (deal.appliesTo ? deal.appliesTo + '。' : '') + '入口：' + deal.url,
    e, a: access,
    k: tags + 'AIHOT 自动收录（证据标注：' + (deal.evidence === 'official' ? '官方页面' : '客户端实测') + '），待本站人工复核' + (deal.note ? '；' + deal.note : ''),
    s, v: '第三方',
    d: String(deal.verifiedAt || todayISO).slice(0, 10),
    L: [['AIHOT Token羊毛', 'https://aihot.news/free-tokens'], [deal.evidence === 'official' ? '厂商页面（经 AIHOT 核实）' : '来源页', deal.url]],
    ai: deal.id
  };
}

// ---------- 每日十大 AI 新闻 ----------
async function buildNews() {
  const daily = await getJSON('https://aihot.news/api/v1/dailies/latest');
  const r = daily.report;
  if (!r || !r.date) throw new Error('日报结构异常');
  const items = [], seen = new Set();
  const push = it => {
    if (!it || !it.title) return;
    const key = (it.links && it.links.aihot) || it.title;
    if (seen.has(key)) return;
    seen.add(key);
    items.push({
      title: it.title, summary: it.summary || '',
      source: (it.source && it.source.name) || '',
      url: (it.links && it.links.aihot) || r.links.aihot,
      original: (it.links && it.links.original) || '',
      publishedAt: it.publishedAt || ''
    });
  };
  if (r.lead) push({ title: r.lead.title, summary: r.lead.leadParagraph, links: r.links });
  (r.highlights || []).forEach(push);
  (r.sections || []).forEach(s => (s.items || []).forEach(push));
  (r.flashes || []).forEach(push);
  let supplemented = 0;
  if (items.length < 10) {
    // 日报要闻不足十条时，用最近 7 天精选按发布时间补足（优先落在日报窗口内的）
    const extra = await getJSON('https://aihot.news/api/v1/items?limit=30&window=7d&by=published');
    const inWindow = [], older = [];
    for (const it of extra.items || []) {
      const t = Date.parse(it.publishedAt || 0);
      (t >= Date.parse(r.windowStart) && t < Date.parse(r.windowEnd) + 86400000 ? inWindow : older).push(it);
    }
    for (const it of [...inWindow, ...older]) {
      if (items.length >= 10) break;
      const before = items.length;
      push(it);
      if (items.length > before) supplemented++;
    }
  }
  return { news: { date: r.date, link: r.links.aihot, items: items.slice(0, 10) }, supplemented };
}

// ---------- 主流程 ----------
(async () => {
  const tpl = fs.readFileSync(TPL, 'utf8');
  const { DATA, start, end } = extractDATA(tpl);
  const report = ['# AIHOT 同步 ' + todayISO, '', '来源：https://aihot.news/free-tokens （匿名接口，UA ' + UA + '）', ''];
  const warns = [];
  let dealsData = null, newsResult = null;

  try { dealsData = await fetchDeals(); } catch (e) { warns.push('Token羊毛抓取失败：' + e.message); }
  try { newsResult = await buildNews(); } catch (e) { warns.push('每日日报抓取失败：' + e.message); }

  const added = [], updated = [], skipped = [], ended = [];
  let block = tpl.slice(start, end);
  if (dealsData) {
    const lines = block.split('\n');
    for (const deal of dealsData.deals) {
      if (!deal || !deal.id || !deal.title || !deal.url) continue;
      const verdict = dedup(deal, DATA);
      if (verdict.action === 'update') {
        const mapped = mapDeal(deal);
        const idx = lines.findIndex(l => l.includes('"ai":' + JSON.stringify(deal.id)));
        if (idx >= 0) {
          lines[idx] = JSON.stringify(mapped) + ',';
          updated.push(deal.title);
        }
        continue;
      }
      if (verdict.action === 'skip') {
        skipped.push('- 「' + deal.title + '」→ 命中已有「' + verdict.entry.n + '」（' + verdict.rule + '）');
        continue;
      }
      added.push(deal);
    }
    // AIHOT 已下架的自动条目 → 移入已停用历史区
    const endedIds = new Set((dealsData.ended || []).map(d => d && d.id).filter(Boolean));
    for (const d of DATA) {
      if (!d.ai || !endedIds.has(d.ai)) continue;
      const idx = lines.findIndex(l => l.includes('"ai":' + JSON.stringify(d.ai)));
      if (idx < 0) continue;
      const dead = Object.assign({}, d, { s: 'dead', c: 'dead', t: '已停', e: '已结束（AIHOT 下架）', d: todayISO, k: (d.k || '') + '；' + todayISO + ' AIHOT 下架，移入历史区' });
      lines[idx] = JSON.stringify(dead) + ',';
      ended.push(d.n);
    }
    if (added.length) {
      const insertAt = lines.length - 1; // 闭合 "];" 前
      // 手维护的末条可能不带行尾逗号，补上，否则与插入的首条连成非法语法
      const prev = lines[insertAt - 1].replace(/\s+$/, '');
      if (!prev.endsWith(',') && !prev.endsWith('[')) lines[insertAt - 1] = prev + ',';
      lines.splice(insertAt, 0, '/* ===== AIHOT 自动收录（第三方待复核，ai 字段为来源 dealId） ===== */', ...added.map(d => JSON.stringify(mapDeal(d)) + ','));
    }
    block = lines.join('\n');
    report.push('## Token羊毛合并', '', '- 抓取 ' + dealsData.deals.length + ' 条；新增 ' + added.length + '，刷新 ' + updated.length + '，去重跳过 ' + skipped.length + '，下架 ' + ended.length, '');
    if (added.length) report.push('### 新增（可信度=第三方，待人工复核）', '', ...added.map(d => '- [' + d.provider + '] ' + d.title + ' — ' + d.url), '');
    if (updated.length) report.push('### 刷新（此前自动收录）', '', ...updated.map(t => '- ' + t), '');
    if (skipped.length) report.push('### 去重跳过（如属误判请人工入表）', '', ...skipped, '');
    if (ended.length) report.push('### 下架移入历史区', '', ...ended.map(t => '- ' + t), '');
  }

  let out = tpl.slice(0, start) + block + tpl.slice(end);
  if (newsResult) {
    const newsJSON = JSON.stringify(newsResult.news);
    out = out.replace(/\/\*__NEWS_START__\*\/[\s\S]*?\/\*__NEWS_END__\*\//, '/*__NEWS_START__*/' + newsJSON + '/*__NEWS_END__*/');
    report.push('## 每日十大AI新闻', '', '- 日报日期：' + newsResult.news.date + '；展示 ' + newsResult.news.items.length + ' 条（精选补足 ' + newsResult.supplemented + ' 条）', '- 日报页：' + newsResult.news.link, '');
  }
  if (warns.length) report.push('## 警告', '', ...warns.map(w => '- ' + w), '');

  const reportPath = path.join(root, 'monitor', 'reports', todayISO + '-aihot.md');
  if (DRY) {
    console.log(report.join('\n'));
    console.log('DRY RUN：未写入任何文件');
  } else {
    fs.writeFileSync(TPL, out, 'utf8');
    fs.writeFileSync(reportPath, report.join('\n'), 'utf8');
    console.log(report.join('\n'));
    console.log('SYNC OK：模板已更新，报告 ' + path.relative(root, reportPath));
  }
  if (warns.length && !dealsData && !newsResult) process.exit(1); // 两路全挂才让 CI 失败开告警
})().catch(e => { console.error('SYNC FAIL: ' + e.message); process.exit(1); });