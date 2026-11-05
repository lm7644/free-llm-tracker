# monitor/ · 免费渠道监控管道

借鉴 AIHOT（KKKKhazix/AIHOT）的信源管理与变更检测思路，为「大模型免费渠道全景表」做的轻量监控。

## 它做什么

每天抓取 `sources.json` 里的 13 个官方页面（定价页/活动页/规则页），与 `store/` 里的快照做**行级 diff**；有真实变更（增删行 > 0）时写入 `reports/日期.md` 并更新 `feed.xml`（RSS，保留最近 60 条）；每次运行在 `heartbeat.log` 追加一行结果。空白/动态噪声（推荐位、访问计数等）由规范化处理吸收，不产生假报告。

CI 只在 GitHub Actions 运行 `run-monitor`、Tavily、博查三个引擎；搜狗与极致了为本地/可选。单源抓取失败仅告警，**过半源失败时脚本以非零退出码结束**，工作流会失败并自动开 issue。

## 文件说明

| 文件 | 用途 |
|---|---|
| `sources.json` | 监控清单：slug、名称、URL、模式（text/html）。加监控源就在这里加一行 |
| `run-monitor.ps1` | 主脚本（纯 ASCII，PowerShell 5.1 兼容）。可手动运行 |
| `store/*.txt` | 各源规范化文本快照（diff 的基准，勿手改） |
| `reports/*.md` | 变更报告（按日期，仅在有真实变更时生成） |
| `feed.xml` | 变更 RSS feed（可拖进任何 RSS 阅读器） |
| `heartbeat.log` | 每次运行一行心跳（时间、ok/fail/baseline/changed） |

## 微信公众号检索：三层阶梯（2026-10-31 实测定稿）

| 层 | 方式 | 成本 | 覆盖 | 状态 |
|---|---|---|---|---|
| ① 关键词检索 | 搜狗微信 `type=2`（sogou-search.ps1，每天轮换 2 词） | 免费 | 全网公众号文章（按关键词命中） | ✅ 运行中；实测稳定，注意低频防验证码 |
| ② 指定账号监控 | 极致了 API（dajiala.ps1，AIHOT 同款集成） | post_history ¥0.14/账号/次，article_detail ¥0.03/次 | 指定账号的全部新文章（莫理/狗哥玩ai/牛哥谈ai/阿川同学/赛博禅心/平野先生玩ai/李叔ai/阿枫科技，见 accounts.json） | ⏸ 暂停：最低充值档为 ¥200/次，超出当期预算；key 未配置。恢复时在 `monitor/.env` 写 `DAJIALA_KEY=…`，并给 accounts.json 补各号 ghid（取任意一篇该号文章链接中 `__biz=` 参数值） |
| ③ 自建 RSS | wewe-rss（微信读书凭据） | 免费（有微信读书账号风控风险） | 指定账号 | 备选：若不愿付费可自建，产出的 RSS 可直接加进 sources.json 走现有抓取 |
| ④ 广域发现 | Tavily API（tavily-search.ps1，每天轮换 1 个发现型查询，topic=news 近 7 天） | 免费 1000 credits/月（本管线用量约 30/月） | 公开网页（含英文/聚合来源，官方 X/公告常被它先索引） | ✅ 运行中（CI 用 GitHub Secret，本地可放 .env；首搜即命中 @zcode_ai 每日 3 亿官宣） |
| ⑤ 中文补充 | 博查 API（bocha-search.ps1，**预算节奏制**：1000 次/3 个月，按「剩余额度÷剩余天数」自动计算每日限额（上限 12），每日最多 8 个品牌/产品动态查询，额度用尽自动 SKIP） | 新用户免费 1000 次（一次性，3 个月有效期）；超出后 ¥3.6/千次 | 中文网页泛搜 + 各厂品牌动态监控 | ✅ 运行中（key 生效；预算节奏器实测正常：今日测试后自动收紧）。**实测定位**：泛查询噪声偏多、不支持 site: 语法、不覆盖公众号——定位为中文网页冗余备份层，主力覆盖靠①②④ |

**实测边界**（2026-10-31）：搜狗 `type=1` 账号搜索对未认证账号无效——莫理/狗哥玩ai/阿枫科技/赛博禅心四号实测全部返回「暂无相关官方认证订阅号」，故**指定账号的免费自动化抓取不存在**，正规路径即 Dajiala（AIHOT 生产同款，API 端点 `POST https://www.dajiala.com/fbmain/monitor/v3/post_history`，body `{ghid,key}`，已按其源码 mirror 实现并通过契约级探测）或 wewe-rss。8 个账号每天一轮的成本约 ¥1.12/天。

## 定时运行（四种方式）

1. **GitHub Actions（仓库内、可验证）**：`.github/workflows/daily-update.yml` 每天 00:00 UTC 运行，含构建校验与失败告警。
2. **会话内自动化（本地外部，仓库内不可验证）**：ZCode 自动化「每天早上8点监控官方免费渠道页面变更」，每天 08:00 由 Agent 运行脚本并解读 diff。在 ZCode 的 Automations 页面可暂停/删除（id: automation-df2fc692-31e2-4107-9b06-1c1a58f88fd2）。
3. **Windows 计划任务（手动注册）**：以管理员身份打开终端执行——
   `schtasks /Create /TN "FreeLLM-Monitor" /SC DAILY /ST 08:00 /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<你的仓库路径>\monitor\run-monitor.ps1\""`
   卸载：`schtasks /Delete /TN "FreeLLM-Monitor" /F`
4. **手动**：随时双击或在终端运行 `run-monitor.ps1`。

## 加监控源 / 调频率

在 `sources.json` 加一条 `{"slug":"唯一英文id","name":"中文名","url":"...","mode":"text|html"}`。`text` 用于返回纯文本/markdown 的地址（如 bigmodel 的 .md 文档），`html` 用于普通网页（脚本会去标签、按行规范化）。当前设计为每次运行全量检查 13 源（顺序抓取、25 秒超时，最坏约 3 分钟），如需降频可把 sources.json 拆成多份分日运行。

## 已知边界

- JS 渲染的页面只能抓到服务端返回的静态内容；若某源抓回来的文本明显不完整（如只剩壳），考虑换用该站的 JSON 接口或 .md 文档地址。
- 抓取失败不更新快照、不产生报告，只记 heartbeat；单源失败会告警，过半源失败会让 CI 失败并开 issue，应检查 URL 是否失效。
- 本脚本只做 diff 与留证，不做"变更重要性判断"——那一层由每天 08:00 的 Agent 巡查完成（AIHOT 的两次评分思想的简化版）。
