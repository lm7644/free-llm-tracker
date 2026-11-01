# brand-spec.md（huashu-design 品牌资产协议）

## 决策

页面为"榜单/对比"体裁，出现 50+ 可识别品牌。按协议"出现几个产品就取几个官方 logo"执行时遇到两个硬约束，做如下降级并留痕：

1. **官方 logo 逐个取不到**：50+ 品牌的官方 logo 需逐站抓取 SVG/PNG 资产，本环境无 Python/Node 处理管线，且实测本机网络对 github.com、google 系、openai.com、x.ai 等域不可达（favicon 第一轮 MISS 名单为证）。
2. **目标读者在中国大陆网络**：任何外链 logo 方案在读者侧同样不可达。

**降级方案**：favicon 级资产（站点 /favicon.ico 或首页 link rel=icon，ICO/PNG/SVG 魔数校验，≤120KB）→ base64 data URI 内嵌单文件；两轮抓取（直连 + 首页 link 标签解析）后仍失败的品牌，用「字母徽标」（品牌名首字，规则线圆框）兜底——诚实占位，不伪造 logo。

## 资产清单

成功内嵌（26 + 第二轮补抓，见 logos.json）：zcode、siliconflow、modelscope、aliyun、tencent、xfyun、minimax、kimi、huawei、aistudio、azure、groq、openrouter、cloudflare、nvidia、cohere、sambanova、chutes、windsurf、cursor、kiro、jetbrains、aws、kaggle、tongyi、comate 等。

字母徽标兜底（网络不可达或无 favicon）：github、googleai（Gemini/Gemini CLI/Colab）、openai（Codex）、xai、deepseek、doubao、qoder、trae、codebuddy、iflow、coze、bigmodel、volcengine、baidu、mistral、together、huggingface、perplexity、notion、warp、cerebras、colab、alibabacloud、stepfun、sensenova、internlm 等。

## 使用规范

- logo 仅作 16-20px 行内标识，旁必须伴随文字品牌名（资产是辅助不是依赖）。
- 不给任何品牌添加其官方未使用的配色/口号/评价；免费额度表述一律以来源链接为准。
- 灰色渠道类（gpt4free 等）不做品牌化展示，仅文字记录。
