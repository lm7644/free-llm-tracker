# 大模型免费渠道全景表 | Free LLM Channels Tracker

> 国内外可零成本使用大模型与编程 Agent 的渠道台账：官方 API 免费层、云平台赠金、编程工具、学生福利与限时活动——**每日自动巡查、人工核实后入表，每条带来源链接与核实日期**。

**在线使用**：`https://lm7644.github.io/free-llm-tracker/` （GitHub Pages，手机可"添加到主屏幕"）

## 这是什么

一张持续维护的表格，回答一个问题：**现在有哪些渠道能零成本用上大模型？**

- **130 条记录**（主表 108 条、海外存档 12 条、已停用 10 条；含 AIHOT 自动收录 38 条，标「第三方」待人工复核），分九类：官方 API 免费层 / 云平台赠金 / 编程 Agent·CLI·IDE / 学生教育福利 / 聊天客户端 / 限时活动 / 免费算力 / 公益中转（不推荐）/ 已停用历史区
- 每条含：免费内容、代表模型、**额度性质**（永久 / 每日 / 每月 / 一次性 / 限时 / 学生）、限额、使用方式、到期时间、准入门槛、风险备注、**可信度分级**（官方 / 多方 / 第三方 / 未核实）、**最后核实日期**、来源链接
- 顶部「限时窗口」聚焦有截止日的活额度；「每日十大AI新闻」来自 AIHOT 日报，随每日巡查自动更新；已停用渠道隔离进历史区防踩坑
- 单文件 HTML、零外部依赖、可离线打开；桌面 / 移动自适应；**页面目录**：桌面侧栏 / 移动端抽屉，点击平滑跳转、滚动高亮；提供 manifest 图标，可手动添加到主屏幕（尚未实现 Service Worker，安装式 PWA 的离线缓存未启用）
- 页首只显示「最新单条核实日期」，并注明每条各自核实日期见「核实」列；不再用某一天的日期覆盖全表。最新一条超过 7 天会提示复核，而不是把旧数据当现势值

## 为什么可信

「免费」分三种完全不同的性质，混在一起就是误导：**永久免费**（常限速）、**周期刷新**（每日/每月）、**一次性赠金**（有有效期）。本表逐条区分，并给每行标注：

- **可信度**：官方（定价页直核）＞ 多方（≥2 独立来源一致）＞ 第三方（单一来源）＞ 未核实（仅传闻）
- **最后核实日期**：过期信息不会冒充现势信息——已失效渠道（如 GitHub Models、智谱高校计划）全部移入历史区留痕

## 自动更新机制

仓库内置监控管道（`monitor/`），密钥只放 GitHub Secrets 或本地 `monitor/.env`（模板见 `monitor/.env.example`），仓库与页面不含任何密钥。

每天 00:00 UTC（北京时间 08:00，Actions 队列常有数小时延迟）由 GitHub Actions 运行其中 **4 个引擎**：

1. **页面 diff**：13 个官方定价/活动页的行级对比，变更即记录（`reports/`；`heartbeat.log` 为本地运行产物，不随 Pages 发布）
2. **Tavily 广域发现**：英文/聚合来源的新渠道发现（需 `TAVILY_KEY`，未配置时自动跳过）
3. **博查中文检索**：预算节奏制（需 `BOCHA_KEY`，1000 次/3 个月）
4. **AIHOT 同步**（`monitor/aihot-fetch.js`，匿名接口无需 key）：Token羊毛清单抓取 → 分层去重（URL 规范化 / 产品级品牌+关键词 / 文案相似 / 周期+额度）→ 新条目自动入表（固定「第三方」待复核，带 `ai` 来源标记），AIHOT 下架的自动条目移入已停用区；同时拉取 AIHOT 日报生成「每日十大AI新闻」（不足十条以近 7 天精选补足）。合并与跳过明细写入 `monitor/reports/日期-aihot.md` 供人工审计

搜狗公众号检索依赖本地网络、极致了账号监控为付费可选项（当前暂停），二者均不在 Actions 内。引擎 1–3 发现的变化只写入 `monitor/reports/日期.md` 与 `monitor/changes.xml`（变更日志），**不会自动改写页面数据**；引擎 4 是唯一自动入表的来源，依靠「第三方待复核」标记与每日报告兜底，人工复核后才可升级可信度。

页面数据另有两个由 DATA 生成的派生产物：`feed.xml`（根目录，全量渠道 RSS，每条含各自核实日期与来源）与 `免费渠道种子表.csv`。改 DATA 后必须运行 `node monitor/build-assets.js` 同步，CI 也会在每次巡查后重建，避免主页 / feed / CSV 漂移。

## 本地使用

直接下载 `大模型免费渠道全景表.html` 双击打开——**单文件、零外部依赖、完全离线可用**。

数据以 `app_template.html` 内嵌的 `DATA` 为唯一来源；`免费渠道种子表.csv` 与 `feed.xml` 只是导出副本，**改 CSV 不会更新页面**。改完 DATA 后重建并校验：

```powershell
$t=[IO.File]::ReadAllText('app_template.html');$j=[IO.File]::ReadAllText('logos.json')
$t=$t.Replace('/*__LOGOS__*/{}',$j)
[IO.File]::WriteAllText('大模型免费渠道全景表.html',$t,(New-Object Text.UTF8Encoding($false)))
Copy-Item '大模型免费渠道全景表.html' 'index.html' -Force
node monitor/build-assets.js
node monitor/validate-build.js
```

## 仓库结构

```
├── 大模型免费渠道全景表.html   主应用（单文件，构建产物）
├── index.html                 同上（Pages 根入口副本）
├── 免费渠道种子表.csv          数据表（与页面同源导出）
├── feed.xml                   全量 RSS（逐条含核实日期与来源）
├── 免费大模型渠道调研报告.md    同类项目调研 + 方法论 + 审计记录
├── app_template.html           构建模板（DATA 数据源 + NEWS 占位 + 占位符）
├── logos.json                  品牌 favicon（base64 内嵌用）
├── monitor/                    监控管道（云端 4 引擎 + 本地 2 引擎 + 配置 + 文档）
└── llms.txt                    机器可读说明
```

## 免责声明

免费额度随时可能调整，本表为核实快照而非承诺——**使用前请点开来源链接复核**。灰色/逆向渠道仅作风险记录。数据采用 CC BY 4.0（署名转载，见 NOTICE），代码 MIT（见 LICENSE）。

## 致谢

数据方法论参考 [AIHOT](https://github.com/KKKKhazix/AIHOT) 的信源分级与 [free-for.dev](https://github.com/ripienaar/free-for-dev) 的免费层结构；检索阶梯设计受其启发并做了本地化改造。「Token羊毛」合并数据与「每日十大AI新闻」来自 [aihot.news](https://aihot.news)（匿名只读接口，每日同步；页面已署名标注来源）。
