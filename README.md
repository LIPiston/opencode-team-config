# opencode-team-config

一套可以直接复用的 **OpenCode V2（桌面版 2.2.x）多智能体编排配置**：一个 `orchestrator`
入口 + 8 个专职 subagent（scout / planner / executor / verifier / reviewer / designer /
researcher）+ 2 个隐藏的兼容入口（build / plan）。

配置本身经过脱敏，可以直接 clone 下来按自己的网关改。**不含任何第三方插件的源码或产物。**

```
config/opencode.json          # 主配置：provider / models / plugins / default_agent / 全局权限
config/dcp.jsonc              # 动态上下文剪枝（DCP）插件的配置
config/models-archive.json    # 从配置里移除的死模型 id，仅存档备查
agents/*.md                   # 10 个 agent，frontmatter = 配置，正文 = system prompt
docs/team-design.md           # 设计说明与实测结论（模型分配、技能归属、V2 配置踩坑）
docs/plugins.md               # 每个插件的授权边界，以及为什么仓库里不放插件文件
scripts/install.ps1           # Windows 一键安装到 %USERPROFILE%\.config\opencode
scripts/check-secrets.py      # 发布前的密钥/本机路径扫描
```

---

## 1. 队伍形态

| agent | mode | 模型 | 权限要点 | 职责 |
|---|---|---|---|---|
| `orchestrator` | primary | `gpt-6.1-sol#high` | `edit: *` deny（只许写 `~/.opencode/plan/`）；`subagent: *` allow；skill 只开 brainstorming / artifacts / using-ryugi | 唯一对话入口，拆解、派活、读回验证、汇报 |
| `planner` | subagent | `deepseek-v4.1-flash#high` | edit 只许写 plan 文件；subagent deny | 把模糊需求变成带验收标准的有序步骤 |
| `executor` | subagent | `deepseek-v4.1-flash#high` | edit allow；shell 禁 push / reset --hard / clean / rm -r(f) | 真正改代码、跑构建、本地 commit |
| `designer` | subagent | `kimi-3.1-pro#high` | edit 限定产物目录；skill 只开 interface-craft / artifacts / brainstorming / verifying-ui | 一切用户看得见的东西：mockup、落地页、设计文档、界面评审 |
| `scout` | subagent | `deepseek-v4.1-flash#low` | 只读；shell 仅 git status/diff/log、rg、ls | 代码侦察，回答"这块怎么工作"，带 path:line |
| `verifier` | subagent | `deepseek-v4.1-flash#medium` | 源码只读，可跑构建/测试；禁 push / rm -rf | 独立验收，给原始输出 + exit code |
| `reviewer` | subagent | `glm-5.3#high` | 只读，shell 仅 git 只读命令；skill + todowrite deny | 异构复审：正确性、边界、安全、scope creep |
| `researcher` | subagent | `deepseek-v4.1-flash#low` | 无 shell、无 edit；webfetch / websearch allow | 查官方文档、RFC、上游源码，带 URL 引用 |
| `build` / `plan` | primary | 继承全局 | `hidden: true`，edit deny，subagent allow | 只为内置名字还能解析，UI 里不出现 |

三条设计原则，改配置时别破坏：

1. **贵模型只给需要判断的角色。** `gpt-6.1-sol` 只给 orchestrator；扫描和查资料用便宜档位。
2. **reviewer 必须与 executor 异构**（现在 `deepseek-v4.1-flash` 写、`glm-5.3` 复审），
   否则复审退化成同源复读。改 executor 的模型时顺手检查 reviewer。
3. **orchestrator 不给 edit**，用权限从机制上强制委派，而不是靠 prompt 自觉。

细节（技能归属表、variant 档位来源、`/goal` 状态机、桌面版忽略 `default_agent` 的根因）
见 [`docs/team-design.md`](docs/team-design.md)。

## 2. 安装

前置：OpenCode 桌面版 2.2.x，PowerShell。

```powershell
git clone https://github.com/LIPiston/opencode-team-config.git
cd opencode-team-config
pwsh -File scripts/install.ps1 -GatewayBaseUrl "https://<你的网关>/v1"
```

脚本会：备份现有 `opencode.json` → 复制 `agents/*.md` 与 `config/*` 到
`%USERPROFILE%\.config\opencode\` → 把 `{env:LIPISTON_API_KEY}` 保持为占位符（不写死密钥）→
提示你设置环境变量与 ryugi 插件目录。

手写等价步骤：

```bash
# 1) 复制配置
cp config/opencode.json        ~/.config/opencode/opencode.json
cp config/dcp.jsonc            ~/.config/opencode/dcp.jsonc
cp config/models-archive.json  ~/.config/opencode/opencode.json.models-archive
cp agents/*.md                 ~/.config/opencode/agents/

# 2) 密钥只走环境变量，别写进 JSON
export LIPISTON_API_KEY="<你自己的 key>"       # Windows: setx LIPISTON_API_KEY "..." （新进程生效）
```

然后改 `opencode.json` 三处：

- `provider.lipiston.options.baseURL` 和 `providers.lipiston.settings.baseURL` → 你的网关地址
  （仓库里是占位符 `https://your-gateway.example.com/v1`，**两处都要改**，encoded 块不继承
  legacy 的 options）。`scripts/install.ps1` 的 `-GatewayBaseUrl` 参数会自动同时替换这两处。
- `provider.lipiston.models` / `providers.lipiston.models` 的模型 id → 必须和
  `curl $BASEURL/models` 返回的 id 一字不差。仓库里的 id 是示例，换成你自己网关有的。
- `plugins` 里的 `__RYUGI_PLUGIN_DIR__` → 你本地 ryugi 的绝对路径（见下节）。

> `{env:VAR}` 占位符只在**启动进程继承了该变量**时解析。从开始菜单启动的桌面版拿不到
> shell 里的 export；要么用 `setx` 写持久用户变量后重启桌面版，要么把 key 写字面量并按敏感文件对待。

## 3. 插件：只引用，不分发

`plugins` 里三条都是**引用**，仓库里没有它们的任何源码、产物或锁文件。授权边界和原因写在
[`docs/plugins.md`](docs/plugins.md)，要点：

| 插件 | 引用形式 | 为什么不放进仓库 |
|---|---|---|
| `ryugi`（技能 + artifacts 工作台） | 本地 clone 的**目录绝对路径** | Ryugi License 1.0 是**非开源授权**：禁止大范围收录/镜像再发布，且对受限主体零授权。只能各自从上游取得 |
| `@tarquinen/opencode-dcp` | npm spec + `config/dcp.jsonc` | 分发权归上游，仓库只带自己的配置 |
| `@upstash/context7-opencode` | npm spec | 需要单独 `opencode mcp auth context7` 授权，凭据不入库 |

`.gitignore` 已拦截 `ryugi/`、`node_modules/`、`*.key`、`*.db`、`opencode.json.bak*`、
`service.json` 等，避免插件目录或运行时产物被顺手提交。

## 4. 脱敏说明

发布前做了这些替换（原文件还在本机，未改动）：

| 项 | 原值 | 仓库里的值 |
|---|---|---|
| provider API key（legacy `options.apiKey` 与 encoded `settings.apiKey` 各一处） | `sk-...` 字面量 | `{env:LIPISTON_API_KEY}` |
| 网关地址（legacy `options.baseURL` 与 encoded `settings.baseURL` 各一处，文档里还有一处示例） | 真实自建网关 URL | `https://your-gateway.example.com/v1` |
| ryugi 插件路径 | `C:\Users\<user>\.config\opencode\ryugi` | `__RYUGI_PLUGIN_DIR__` |
| 文档中的本机绝对路径 | `C:\Users\<user>\...` | `~/.config/opencode/...` |

**没有**进仓库的文件：本地裸 key 文件（59 字节明文）、`service.json`（远程服务密码）、
`drafts.sqlite`、`opencode-notifier-analytics.db`、`*.bak-*` 备份、`ryugi/` 插件目录。
`scripts/check-secrets.py` 会把 `sk-` 形态、`Bearer`、GitHub/AWS token、私钥块、本机用户路径
一起拦下来，也会拒绝 secret 字段里出现的非占位符字面量。

自查：

```bash
python scripts/check-secrets.py .
```

## 5. 验证链

配置写对了不代表生效，按这个顺序读回：

```bash
CLI="$LOCALAPPDATA/Programs/ai.opencode.desktop/resources/opencode-cli.exe"
"$CLI" debug agents          # 解析后的 mode/model(含 variant)/steps/permissions
"$CLI" api GET /api/model    # variants、context、output 是否与配置一致
"$CLI" api GET /api/plugin   # state.status 必须逐条 active
"$CLI" reload                # 只重载后台服务，桌面版仍需整体重启
```

行为证据（只看列表不算）：新建会话时 `session_v2.agent` 应为 `orchestrator`；给它一个
「别自己动手，派下去」的任务，库里应出现 `parent_id` 指向它的子会话，而不是 agent 自己念总结。

## 6. 注意

- 模型 id、`baseURL`、`capabilities.reasoning.effort` 数组**都跟具体网关绑定**。换网关先
  `curl $BASEURL/models` 对齐 id，再逐个 effort 打探针，别照搬这里的档位表。
- `enabled_providers: ["lipiston"]` 是白名单语义：只启用列表内的供应商，内置免费模型也会一并关掉。
- 别把 provider 里网关不存在的模型留着：配置能解析，`run` 时报 `Error: model not found`。

## License

本仓库自己的配置、agent prompt 和文档用 [MIT](LICENSE)。第三方插件不属于本仓库，
各自授权见上游；ryugi 的 Ryugi License 1.0 与本仓库的 MIT 无关，也未在此分发。
