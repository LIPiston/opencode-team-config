# 把本仓库的配置装到 %USERPROFILE%\.config\opencode
# 用法：
#   pwsh -File scripts/install.ps1 -GatewayBaseUrl "https://ai.example.com/v1"
#   pwsh -File scripts/install.ps1 -GatewayBaseUrl "..." -RyugiDir "C:\path\to\ryugi"
# 只复制配置与 agent 定义；不写密钥、不装插件、不动数据库。

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$GatewayBaseUrl,
  [string]$RyugiDir = "",
  [string]$ProviderName = "lipiston",
  [string]$EnvVarName = "LIPISTON_API_KEY",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $env:USERPROFILE ".config\opencode"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "仓库: $repo"
Write-Host "目标: $dest"

if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

# 1) 备份现有配置（备份里可能有旧密钥，只留在本机，不要提交）
foreach ($f in @("opencode.json", "dcp.jsonc")) {
  $p = Join-Path $dest $f
  if (Test-Path $p) {
    $bak = "$p.bak-install-$stamp"
    Copy-Item $p $bak
    Write-Host "备份: $bak"
  }
}

# 2) 渲染配置：替换网关地址与插件占位符
$cfgText = Get-Content (Join-Path $repo "config\opencode.json") -Raw -Encoding UTF8
$cfgText = $cfgText.Replace("https://your-gateway.example.com/v1", $GatewayBaseUrl.TrimEnd("/"))

if ($RyugiDir) {
  if (-not (Test-Path (Join-Path $RyugiDir "index.js"))) {
    throw "RyugiDir 下没有 index.js，拒绝写入：$RyugiDir"
  }
  $escaped = $RyugiDir -replace '\\', '\\\\'
  $cfgText = $cfgText.Replace("__RYUGI_PLUGIN_DIR__", $escaped)
  Write-Host "ryugi: $RyugiDir"
}
else {
  # 没给 ryugi 就整条移除，避免 OpenCode 加载一个不存在的路径
  $cfg = $cfgText | ConvertFrom-Json
  $cfg.plugins = @($cfg.plugins | Where-Object { $_ -ne "__RYUGI_PLUGIN_DIR__" })
  $cfgText = $cfg | ConvertTo-Json -Depth 32
  Write-Warning "未提供 -RyugiDir：已从 plugins 移除 ryugi。依赖它的 skill 白名单规则会拦掉技能加载，按需调整 agents/*.md。"
}

if ($cfgText -match "__RYUGI_PLUGIN_DIR__") { throw "占位符未被替换，中止。" }

$cfgPath = Join-Path $dest "opencode.json"
if ((Test-Path $cfgPath) -and (-not $Force)) {
  $answer = Read-Host "opencode.json 已存在，覆盖？(y/N)"
  if ($answer -ne "y") { throw "已取消。" }
}
# 用无 BOM UTF8 写入
[System.IO.File]::WriteAllText($cfgPath, $cfgText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "写入: $cfgPath"

# 3) 其余配置文件
Copy-Item (Join-Path $repo "config\dcp.jsonc") (Join-Path $dest "dcp.jsonc") -Force
Copy-Item (Join-Path $repo "config\models-archive.json") (Join-Path $dest "opencode.json.models-archive") -Force -ErrorAction SilentlyContinue

# 4) agent 定义
$agentsDest = Join-Path $dest "agents"
if (-not (Test-Path $agentsDest)) { New-Item -ItemType Directory -Path $agentsDest -Force | Out-Null }
Copy-Item (Join-Path $repo "agents\*.md") $agentsDest -Force
$count = (Get-ChildItem (Join-Path $repo "agents\*.md")).Count
Write-Host "agent: $count 个已复制到 $agentsDest"

# 5) 密钥与验证提示
Write-Host ""
Write-Host "下一步：" -ForegroundColor Cyan
Write-Host "  1) 设置密钥（只写进环境变量，不进 JSON）："
Write-Host "     [Environment]::SetEnvironmentVariable('$EnvVarName','<你的 key>','User')"
Write-Host "  2) 完全退出 OpenCode（含所有进程）再重新启动，桌面版才读到新环境变量。"
Write-Host "  3) 读回验证："
Write-Host "     CLI=`"`$env:LOCALAPPDATA\Programs\ai.opencode.desktop\resources\opencode-cli.exe`""
Write-Host "     & `$CLI debug agents"
Write-Host "     & `$CLI api GET /api/plugin"
Write-Host ""
if (-not [Environment]::GetEnvironmentVariable($EnvVarName, "User")) {
  Write-Warning "$EnvVarName 尚未设置，模型请求会认证失败。"
}
