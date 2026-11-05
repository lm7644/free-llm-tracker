// 构建产物校验：语法、数据完整性、日期与双文件一致性。CI 在提交前运行。
const fs = require('fs');
const vm = require('vm');

function fail(msg) { console.error('VALIDATE FAIL: ' + msg); process.exit(1); }

const html = fs.readFileSync('index.html', 'utf8');
if (html.includes('/*__LOGOS__*/')) fail('LOGO 占位符未替换');
if (!html.includes('</html>')) fail('HTML 不完整');

const s = html.indexOf('<script>');
const e = html.lastIndexOf('</script>');
if (s < 0 || e < 0) fail('找不到内联脚本');
const code = html.slice(s + 8, e);
try { new Function(code); } catch (err) { fail('脚本语法错误: ' + err.message); }

const a = code.indexOf('const DATA = [');
if (a < 0) fail('找不到 DATA 数组');
const b = code.indexOf('\n];', a);
if (b < 0) fail('DATA 数组未闭合');
const ctx = {};
vm.createContext(ctx);
try { vm.runInContext(code.slice(a, b + 3) + ';globalThis.__D=DATA;', ctx); } catch (err) { fail('DATA 解析失败: ' + err.message); }
const DATA = ctx.__D;
if (!Array.isArray(DATA) || DATA.length < 80) fail('数据条数异常: ' + (DATA && DATA.length));

const REQUIRED = ['n', 'p', 'q', 't', 'u', 'e', 's', 'v', 'd'];
const STATUS = new Set(['active', 'event', 'dead']);
DATA.forEach((d, i) => {
  for (const k of REQUIRED) {
    if (d[k] === undefined || d[k] === null || String(d[k]).trim() === '') fail('第 ' + (i + 1) + ' 条缺少字段 ' + k);
  }
  if (!STATUS.has(d.s)) fail('第 ' + (i + 1) + ' 条状态非法: ' + d.s);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d.d)) fail('第 ' + (i + 1) + ' 条核实日期非法: ' + d.d);
  if (!Array.isArray(d.L) || !d.L.length) fail('第 ' + (i + 1) + ' 条无来源链接');
  for (const l of d.L) {
    if (!Array.isArray(l) || l.length < 2 || !/^https?:\/\//.test(l[1])) fail('第 ' + (i + 1) + ' 条来源链接非法: ' + JSON.stringify(l));
  }
  for (const k of ['n', 'q', 't', 'd']) if (String(d[k]).includes('undefined')) fail('第 ' + (i + 1) + ' 条字段含 undefined');
});

const today = new Date();
today.setMinutes(today.getMinutes() - today.getTimezoneOffset());
const todayISO = today.toISOString().slice(0, 10);
const maxDate = DATA.map(d => d.d).sort().pop();
if (maxDate > todayISO) fail('核实日期晚于今天: ' + maxDate);
const age = Math.floor((Date.parse(todayISO) - Date.parse(maxDate)) / 86400000);
if (age > 14) console.warn('WARN: 最新核实日期已过去 ' + age + ' 天，数据可能过期');

const zh = fs.readFileSync('大模型免费渠道全景表.html', 'utf8');
if (zh !== html) fail('index.html 与中文主文件不一致（请重新构建）');

console.log('VALIDATE OK: ' + DATA.length + ' 条，最新核实 ' + maxDate + '，距今天 ' + age + ' 天');
