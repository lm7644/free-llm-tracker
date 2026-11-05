// 从 app_template.html 的 DATA 生成派生产物：CSV 导出 + 全量 feed.xml（根目录与 monitor 各一份）
// 单一数据源：DATA。任何改动必须重跑本脚本，避免主页 / feed / CSV 漂移。
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const root = path.resolve(__dirname, '..');
const tpl = fs.readFileSync(path.join(root, 'app_template.html'), 'utf8');

const a = tpl.indexOf('const DATA = [');
const b = tpl.indexOf('\n];', a);
if (a < 0 || b < 0) throw new Error('找不到 DATA 数组');
const code = tpl.slice(a, b + 3);
const ctx = {};
vm.createContext(ctx);
vm.runInContext(code + ';globalThis.__D=DATA;', ctx);
const DATA = ctx.__D;

const catsBlock = tpl.slice(tpl.indexOf('const CATS = ['), tpl.indexOf('\n];', tpl.indexOf('const CATS = [')) + 3);
vm.runInContext(catsBlock + ';globalThis.__C=CATS;', ctx);
const CATS = ctx.__C;

const EXTRA = { dead: '已停用历史区', overseas: '海外难以直连（存档）' };
const CATNAME = {};
for (const c of CATS) CATNAME[c.k] = c.t;

function catName(d) {
  return EXTRA[d.c] || CATNAME[d.c] || d.c;
}

// ---------- CSV ----------
function q(v) {
  v = v === undefined || v === null ? '' : String(v);
  return '"' + v.replace(/"/g, '""') + '"';
}
const header = ['分类', '渠道', '提供方', '地区', '额度性质', '代表模型', '免费内容', '限额', '使用方式', '到期时间', '准入门槛', '风险备注', '可信度', '核实日期', '来源链接'];
const rows = DATA.map(d => [
  catName(d), d.n, d.p, d.r === 'c' ? '国内' : '海外', d.t, d.m || '—', d.q, d.l, d.u, d.e, d.a || '—', d.k || '', d.v, d.d,
  (d.L || []).map(x => x[0] + '：' + x[1]).join(' ； ')
].map(q).join(','));
const csv = '\uFEFF' + [header.map(q).join(','), ...rows].join('\r\n') + '\r\n';
fs.writeFileSync(path.join(root, '免费渠道种子表.csv'), csv, 'utf8');

// ---------- RSS ----------
const BASE = 'https://lm7644.github.io/free-llm-tracker/';
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const cdata = s => '<![CDATA[' + String(s).replace(/]]>/g, ']]]]><![CDATA[>') + ']]>';
const rfc = d => new Date(d + 'T08:00:00+08:00').toUTCString();

const maxD = DATA.map(d => d.d).sort().pop();
const items = DATA.map(d => {
  const src = (d.L || []).map(x => x[0] + '：' + x[1]).join('\n');
  const desc = [
    '免费内容：' + d.q,
    '限额：' + d.l,
    '使用方式：' + d.u,
    '到期：' + d.e,
    '门槛：' + (d.a || '—'),
    '分类：' + catName(d) + ' / 地区：' + (d.r === 'c' ? '国内' : '海外'),
    '核实日期：' + d.d + '（可信度：' + d.v + '）',
    '来源：',
    src
  ].join('\n');
  return '    <item>\n' +
    '      <title>' + esc(d.n) + '</title>\n' +
    '      <link>' + esc(BASE) + '</link>\n' +
    '      <guid isPermaLink="false">free-llm-tracker/' + esc(d.n) + '</guid>\n' +
    '      <pubDate>' + rfc(d.d) + '</pubDate>\n' +
    '      <category>' + esc(catName(d)) + '</category>\n' +
    '      <description>' + cdata(desc) + '</description>\n' +
    '    </item>';
}).join('\n');

const feed = '<?xml version="1.0" encoding="UTF-8"?>\n' +
  '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n' +
  '  <channel>\n' +
  '    <title>大模型免费渠道全景表（全量 ' + DATA.length + ' 条，逐条核实日期）</title>\n' +
  '    <link>' + BASE + '</link>\n' +
  '    <atom:link href="' + BASE + 'feed.xml" rel="self" type="application/rss+xml"/>\n' +
  '    <description>每条渠道含免费内容、限额、到期、来源链接与各自核实日期；口径为「单条核实日期」，不用单日覆盖全表。</description>\n' +
  '    <language>zh-CN</language>\n' +
  '    <lastBuildDate>' + rfc(maxD) + '</lastBuildDate>\n' +
  items + '\n' +
  '  </channel>\n' +
  '</rss>\n';

for (const p of [path.join(root, 'feed.xml'), path.join(root, 'monitor', 'feed.xml')]) {
  fs.writeFileSync(p, feed, 'utf8');
}

console.log('BUILD OK: CSV ' + DATA.length + ' 行；feed.xml ' + DATA.length + ' 条；最新单条核实 ' + maxD);
