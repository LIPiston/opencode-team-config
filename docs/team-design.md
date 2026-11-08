# OpenCode 编排小队（2026-11-07 配置）

配置位置：`~\.config\opencode\agents\*.md`（V2 只认 markdown agent 目录）
入口：`opencode.json` 里 `"default_agent": "orchestrator"`

## 分工

| agent | mode | 模型 | 权限要点 | 用途 |
|---|---|---|---|---|
| `orchestrator` | primary | **gpt-6.1-sol** | edit 全 deny（只许写 ~/.opencode/plan/）；subagent 全 allow；skill 开 brainstorming/artifacts/using-ryugi | 唯一对话入口，拆解任务、派活、读回验证、汇报 |
| `planner` | subagent | **deepseek-v4.1-flash** | edit 只许写 plan 文件；skill 开 brainstorming/artifacts/executing-specs | 把模糊需求变成带验收标准的有序步骤 |
| `executor` | subagent | **deepseek-v4.1-flash** | edit allow；shell 禁 push / reset --hard / clean / rm -r(f)；skill 开 TDD/debugging/executing-specs/worktrees/verifying-ui | 真正动手改代码、跑构建、本地 commit |
| `designer` | subagent | **kimi-3.1-pro** | edit 仅产物目录；skill 只开 interface-craft/artifacts/brainstorming/verifying-ui | **一切用户看得见的东西**：mockup、artboard、落地页、视觉方向、设计文档、界面评审 |
| `scout` | subagent | **deepseek-v4.1-flash** | 只读；shell 仅 git status/diff/log/rg/ls；skill 只开 systematic-debugging | 代码侦察：找文件、找调用点、答"这块怎么工作" |
| `verifier` | subagent | **deepseek-v4.1-flash** | 只读代码，可跑构建/测试；skill 开 systematic-debugging/verifying-ui | 独立验收，给原始输出 + exit code |
| `reviewer` | subagent | **glm-5.3** | 只读，shell 仅 git 只读；skill + todowrite 全 deny | 复审 diff 找 bug/边界/安全问题（**异构模型，与 executor 不同源**） |
| `researcher` | subagent | **deepseek-v4.1-flash** | 无 shell、无 edit；webfetch/websearch allow；skill 全 deny | 查官方文档 / RFC / 上游源码，带 URL 引用 |

模型只用四个：

- **gpt-6.1-sol** —— 只给 orchestrator（总指挥，唯一需要最强判断力的角色）
- **deepseek-v4.1-flash** —— 规划、执行、侦察、验收、查资料
- **kimi-3.1-pro** —— UI 设计（designer）
- **glm-5.3** —— 只给 reviewer

关键约束：**executor 用 deepseek，reviewer 必须用别的族**（现在是 glm-5.3），
否则复审退化成同源复读。改 executor 的模型时，顺手检查 reviewer 是否还异构。

provider 里只保留这三个模型，其余（glm-5.3、glm-5.3-flash、gpt-6-luna、LIP-grok、
LIP-deepseek-v4-flash、FIM:deepseek-v4.1-flash）已从配置移除，避免误用死模型。

## 技能归属：一个技能只有一个主人

**技能内容不会从父会话传给子会话**（实测：orchestrator 加载 brainstorming 后，
scout 上下文里只有它自己白名单里的 systematic-debugging，且 scout 自己也加载不了
brainstorming → `Permission denied: skill`）。所以"总指挥装技能然后派活时加载"
不成立——技能必须装在真正干活的角色身上。

按这个原则分配：

| 技能 | 主人 | 为什么是它 |
|---|---|---|
| `interface-craft` | designer | 设计判断 + 4 个 reference（tokens 109 行 / signs 112 行 / evaluation 52 行 / direction 37 行）必须在绘制者手里 |
| `artifacts` | designer（+ orchestrator/planner 只看不画） | 产物落在 `<project>/.ryugi/artifacts/<type>/<id>/` |
| `test-driven-development` | executor | 写实现代码前用 |
| `systematic-debugging` | executor / verifier / scout | 复现与定位 |
| `executing-specs` | executor / planner | 按批准的设计实现 |
| `using-git-worktrees` | executor | 实现前隔离工作区 |
| `verifying-ui` | designer / verifier / executor | 构建物需人验收时 |
| `brainstorming` | orchestrator / planner / designer | 需求塑形，任一环都可能需要 |
| `using-ryugi` | orchestrator | 技能发现入口 |

新增技能时的坑：白名单是静态的，插件升级新长出来的技能默认被 `*` deny 拦掉，
**报错只说 `Permission denied: skill`，不会告诉你"该加白名单了"**。
ryugi 升到 v1.63.0 时新增 `interface-craft` 就是这样被拦的。

## 思考强度（variant）——档位由 `opencode.json` 的 `providers` 决定，不是全局三档

**默认三档的来源**：`@opencode/ai/providers/openai-compatible` 的 effort 映射在
`a.values` 为空时回退到内置常量 `["low","medium","high"]`。所以只要模型卡片没有显式的
`capabilities.reasoning.effort` 数组，所有模型都会被套上同一组 low/medium/high——这就是
“所有模型只有三档”的原因，和你配了几个模型无关。

**要按模型定档，必须写在 V2 encoded 的 `providers.<id>.models.<model>` 里**：

```json
"providers": {
  "lipiston": {
    "name": "LIPiston",
    "package": "@opencode/ai/providers/openai-compatible",
    "settings": { "baseURL": "https://your-gateway.example.com/v1", "apiKey": "..." },
    "models": {
      "gpt-6.1-sol": {
        "name": "GPT-6.1 Sol",
        "limit": { "context": 275000, "output": 32000 },
        "capabilities": { "reasoning": { "supported": true,
                          "effort": ["none","low","medium","high","xhigh"] } }
      }
    }
  }
}
```

实测的生效规则（2026-11-07 在 v2.2.6 上逐条比对 `/api/model`）：

- `capabilities.reasoning.effort` **只有写在 encoded `providers` 里才生效**。写进 legacy
  `provider.<id>.models.<m>.capabilities` 完全不产生变体（实测变体列表为空）。
- legacy `provider.<id>.models.<m>.variants`（对象形态）**只能加变体，不能改档位**：
  `{"low": {}}` 得到的就是 `low`，`{"myown": {}}` 得到变体 id `myown` 但 settings 为空。
  想禁用某档写 `{"low": {"disabled": true}}`——结果是**只留 low 一个变体**（语义是“变体表
  只保留登记过的项”，很容易写反，别指望它删档）。
- legacy 块继续留着是安全的：`provider.lipiston` 提供 npm/baseURL/apiKey/models/limit，
  `providers.lipiston` 只补 `capabilities`，两边合并后 `/api/model` 里 apiKey、limit、
  variants 同时正确。**不要**把 legacy 的 `models` 删掉只靠 encoded——那样 limit 会掉回默认
  200000/32000，且 encoded `settings.apiKey` 若漏写会直接 Authentication failed。
- encoded 的 settings 与 legacy 的 options **不互相继承**：encoded 里要么写全
  `settings.baseURL` + `settings.apiKey`，要么整块不写（只写 `capabilities`）。写了
  `package` 但漏 `settings` 时 `/api/model` 显示 `settings: None`、key=NO。

**各模型实际可用的档位（网关侧实测，2026-11-07）**：

| 模型 | 可用 effort | 证据 |
|---|---|---|
| `deepseek-v4.1-flash` | none / low / medium / high / max | 8 档 × 4 次全部 200，reasoning_tokens 19–63 |
| `gpt-6.1-sol` | none / low / medium / high / xhigh | 只这些档 200；`minimal` 稳定 400 `Invalid request parameters` |
| `kimi-3.1-pro` | low / medium / high / max | 8 档全 200；`max` 的 rt 最高（75–82） |
| `glm-5.3` | none / low / medium / high / max | 8 档全 200；`max` 明显更深（rt 31–56 vs 其他 6–13） |

注意 `gpt-6.1-sol` 在这个上游**极不稳定**：同一请求连打 15 次，`#high` 得 4×200 + 1×400 +
5×502，`#low` 全线 502。所以 orchestrator 挂 gpt 时出现 502/400 是**上游问题**，不是配置错。

当前分配：

| agent | model#variant | 理由 |
|---|---|---|
| `orchestrator` | gpt-6.1-sol#high | 拆解、判证据、决定派谁 |
| `planner` | deepseek-v4.1-flash#high | 规划需要深度 |
| `executor` | deepseek-v4.1-flash#high | 写代码，正确性优先 |
| `designer` | kimi-3.1-pro#high | 设计判断 |
| `reviewer` | glm-5.3#high | 找 bug 要深 |
| `verifier` | deepseek-v4.1-flash#medium | 跑测试读输出，不需要深度推理 |
| `scout` | deepseek-v4.1-flash#low | 大范围扫文件，快而省 |
| `researcher` | deepseek-v4.1-flash#low | 查文档摘录 |

想要更省的档位就改 frontmatter：scout/researcher 可用 `#none`（deepseek 有），
verifier 想更深可用 `#max`。

写法：`model: lipiston/<model>#<variant>`。也可拆成 `model:` + `variant:` 两行，等价。

**variant 是真的生效的（实测）**：同一道速度追击题，scout 用
`deepseek-v4.1-flash#low` 产生 **1465** 个 reasoning token、`#high` 产生 **3790** 个
（2.6 倍），输出长度 376 vs 854。查证据：

```sql
select agent, model, tokens_reasoning, tokens_output, title
from session_v2 order by time_created desc limit 10;
```

（`opencode.db` 是 SQLite，位于 `~/.local/share/opencode/opencode.db`，只读连接即可）

写错档位会硬失败：`Error: Variant unavailable for <provider>/<model>: <v>`，
不是静默忽略。改完 `capabilities.reasoning.effort` 后，**该模型没列出的档位立刻变成硬失败**
（实测 deepseek 删掉 `minimal` 后 `#minimal` 报 Variant unavailable）。

改档位后要重启桌面版（`reload` 只影响后台服务）。验证链：
`api GET /api/model` 看 variants → `run --model <m>#<v>` 看是否 200。

## 改模型 / 改 steps / 改技能权限（实测过的写法）

agent 的 model 写在 markdown frontmatter，语法只有两种：

```yaml
model: lipiston/gpt-6.1-sol            # 普通
model: lipiston/gpt-6.1-sol#high       # 带变体（可选值见「思考强度」一节的表）
```

也可以拆成两行，效果同 `#high`：

```yaml
model: lipiston/gpt-6.1-sol
variant: high
```

实测的语义（2026-11-07 逐条验过）：

- **档位不是只有三档**：档位来自 `opencode.json` 的 `providers.<id>.models.<m>.capabilities.reasoning.effort`
  数组；没写就回退到内置 `low`/`medium`/`high`。当前各模型档位见上面「思考强度」一节，
  不在该模型列表里的档位会 `Error: Variant unavailable for lipiston/<model>: <v>`。
- **markdown 里的 model 优先于 `opencode.json` 的 `agents.<id>.model`**。同名 agent 两处都写，
  md 赢（实测：md=glm-5.3 + json=deepseek-flash → 生效 glm-5.3）。
- **markdown 不写 model，则 `opencode.json` 的 `agents.<id>.model` 会补上**（实测生效）。
- **两处都没有 → 子智能体继承父会话模型，primary agent 继承全局 `model`**。
- **运行时覆盖**：`opencode run --agent scout --model lipiston/glm-5.3 "..."` 会压掉 agent 自己
  的配置（日志里显示 `> scout · glm-5.3`）。
- **`model:` 写错成网关不存在的 id** → 配置能解析，但 `run` 时 `Error: model not found`。
  改之前先 `curl $baseURL/models` 对齐。
- **改完必须 `opencode reload` 再 `debug agents` 读回**，frontmatter 语法错会让整个 agent 静默消失。

查询当前生效值：

```bash
CLI="$LOCALAPPDATA/Programs/ai.opencode.desktop/resources/opencode-cli.exe"
"$CLI" debug agents              # 解析后的 model（含 variant）/steps/permissions
"$CLI" api GET /api/model        # 每个模型支持的 variants、context、output、是否支持图片
```


## 为什么不给子智能体再派子智能体

嵌套深度默认 1。所以每个 brief 必须自包含：

1. GOAL（一句话可观测结果）
2. INPUT（绝对路径、当前状态、前序发现）
3. CONSTRAINTS（不许碰什么、禁哪些命令）
4. ACCEPTANCE（可检查的完成判据）
5. EVIDENCE（要读回并引用什么原始输出）
6. OUTPUT（回复的确切形状）

## 全局权限底线（opencode.json 的 `permissions`）

对所有 agent 生效、排在 agent 自己规则之前：
`git push`、`git reset --hard`、`git clean`、`rm -rf` 一律 deny。

## 实测结论（2026-11-07）

- 端到端跑通：orchestrator 自己调了 scout → executor → verifier 三层，改文件、跑测试、
  引用 `python check.py` 的真实输出，orchestrator 自身零编辑。
- 权限边界有效：命令 orchestrator "你自己直接编辑，不要委派" → 它拒绝执行并说明原因。
- `reviewer` 用 glm-5.3 独立复审，抓到了 CRLF 换行churn 并主动声明"我没能执行测试"。
- ryugi 插件注册的技能会自动触发（原为 systematic-debugging / TDD / worktrees），
  会把子智能体带跑偏，因此除 executor 外全部 `skill: deny`。
  代价：orchestrator 日志里会留一条 `Skill "ryugi:systematic-debugging" failed`，无害。

## 网关模型可用性（实测 `/v1/models` 只有 10 个 id）

可用：deepseek-v4.1-flash、gpt-6.1-sol、gpt-6-luna、glm-5.3、glm-5.3-flash、
kimi-3.1-pro、LIP-deepseek-v4-flash、FIM:deepseek-v4.1-flash
不可用（已从配置删除）：qwen-flashnext、step-5-preview、openrouter/free（`model not found`）、
LIP-grok（超时 98s 失败）

## 日常用法

- 桌面版：重启后默认就是 orchestrator（Tab 可切到 build/plan）。
- CLI 一次性：`opencode run "..."` → 走 orchestrator。
- 手动指定：`opencode run --agent reviewer "review 当前 diff"`
- 会话里 `@scout` / `@verifier` 可手动点名子智能体。
- 子会话导航：`<Leader>+Down` 进子会话，`←` `→` 切换，`↑` 回父会话。
