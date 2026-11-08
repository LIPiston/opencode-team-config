# 插件授权边界：为什么仓库里只有引用

这份配置依赖三个第三方插件。它们**都不在本仓库里**（没有源码、没有 dist 产物、没有锁文件），
仓库只保留「怎么引用」和自己的配置。原因逐个写清楚，免得以后有人图省事把目录 copy 进来。

## ryugi（技能 + artifacts 工作台）

- 上游：<https://github.com/Innei/ryugi>，当前用 v1.63.0（commit `e0d082d`）。
- 授权：**Ryugi License 1.0**，文本自己写明「It is not an open source license」。允许使用、
  修改、商用、分发衍生作品，但设了两道墙：
  1. **Section 3.2 No Marketplace Ingestion**——禁止用自动化手段（抓取、爬取、批量下载、
     镜像、索引）收集该软件再在 Marketplace 里重新发布。
  2. **Section 3.1 Restricted Parties**——Schedule A 列了一批主体（含其关联公司与产品）
     完全不给授权。
  3. Section 3.3 要求所有拷贝和实质部分都附上完整 license、版权声明和 Exhibit B。
- 另外 `skills/artifacts/app/` 下的 `ryugi-artifacts` 是**专有**的，明确不在该仓库授权范围内。
- 结论：**不要把 ryugi 目录、它的 skills、或任何拷贝提交进本仓库或任何公开仓库。**
  每个使用者从上游自行 clone。

本配置里它的引用形式是本地目录的绝对路径（V2 要求插件路径是目录、且不展开 `~`）：

```json
"plugins": ["C:\\Users\\<you>\\.config\\opencode\\ryugi"]
```

取得方式（Windows 上 `git+https` 的 npm 安装会退化成 ssh 并失败，直接 clone 更稳）：

```bash
git clone --depth 1 https://github.com/Innei/ryugi.git ~/.config/opencode/ryugi
```

然后把 `plugins` 里的 `__RYUGI_PLUGIN_DIR__` 换成该目录的绝对路径。
`docs/team-design.md` 里的技能白名单（interface-craft、artifacts、test-driven-development、
systematic-debugging、executing-specs、using-git-worktrees、verifying-ui、brainstorming、
using-ryugi）都来自这个插件；**没装 ryugi 时这些 `skill` 权限规则会拦掉一切技能加载**，
按需删掉相应规则或用 `skill: *` allow。

## @tarquinen/opencode-dcp（动态上下文剪枝）

- 引用形式：npm spec `@tarquinen/opencode-dcp@latest`，配置在 `config/dcp.jsonc`。
- 作用：去重重复工具输出、清理旧错误、在上下文将满时压缩工具结果区间。
- 为什么不分发产物：npm 包的分发权归上游；仓库只带自己的 `dcp.jsonc`（策略选择属于配置，
  不是代码）。npm 装在 `~/.cache/opencode/npm/` 下，已被 `.gitignore` 挡住。

## @upstash/context7-opencode（文档检索 MCP）

- 引用形式：npm spec `@upstash/context7-opencode@latest`。
- 它会往 `config.mcp` 里注入一个 MCP server，**需要单独授权**才出现工具：

```bash
opencode mcp auth context7     # 用 PTY/后台跑，它原地等浏览器回调
```

  OAuth 的 `code_challenge` / `state` / 回调端口每次执行都重新生成，旧链接立刻失效——只能把
  当前这次打印的链接原样交给用户。
- 授权凭据存在 OpenCode 自己的凭据库里，不在本仓库；仓库里也没有任何 token 字段。

## 不进仓库的运行时文件

| 文件 | 内容 | 处理 |
|---|---|---|
| 本地裸 key 文件 | 明文 API key | 用环境变量 `LIPISTON_API_KEY` 替代 |
| `service.json` | 远程服务密码 + 标记 | 完全排除（`.gitignore`） |
| `drafts.sqlite` / `opencode-notifier-analytics.db` | 本地会话与通知统计 | 完全排除 |
| `opencode.json.bak-*` / `.bak-<date>/` | 历史备份（含旧密钥） | 完全排除 |
| `ryugi/`、`node_modules/` | 第三方插件源码与依赖 | 完全排除 |

发布前跑 `python scripts/check-secrets.py .` 复查。
