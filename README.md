# agents-skills

我的跨工具 Agent 技能库 —— 对应本机 `~/.agents/` 目录，用于**电脑迁移与多机同步**。

## 这个目录是什么

`~/.agents/skills/` 是 [Agent Skills 生态](https://agentskills.io) 的通用安装路径，
**DSH（DeepSeek Harness）和 Codex 都会自动发现**这里的技能。

- 定义者：[Vercel Labs `skills` CLI](https://github.com/vercel-labs/skills)
- 采用 `~/.agents/skills` 的 agent：Codex、Cline、Dexto、fx、Kimi Code CLI、Loaf、Pi、Sarvam Code、Warp、Zed
- **不支持**该路径的：Claude Code（它只认 `~/.claude/skills`）

## 目录结构

```
.agents/
├── .skill-lock.json          # skills CLI 的安装清单（来源、版本、hash）
└── skills/
    ├── browser-snapshot-timeout/   # 自建：浏览器工具超时与 SPA 取内容的排障流程
    ├── lark-doc/                   # 飞书云文档操作（第三方）
    ├── lark-shared/                # lark-cli 共享底座（lark-doc 依赖）
    └── tmeet-skill/                # 腾讯会议 CLI（第三方）
```

## 新电脑还原

```bash
# 1) 克隆到 ~/.agents
git clone git@github.com:xiaoxiaoshuo/agents-skills.git ~/.agents

# 2) 确认 DSH 能发现
#    启动 DSH 后，技能会出现在可用技能列表里，无需额外配置
```

如果 `~/.agents` 已存在（比如被 `npx skills add` 创建过），先备份再克隆：

```bash
mv ~/.agents ~/.agents.bak
git clone git@github.com:xiaoxiaoshuo/agents-skills.git ~/.agents
```

## 新增/更新技能

两种方式，都建议提交回本仓库：

```bash
# 方式 A：用 skills CLI 安装（注意不要用 --agent '*'，会往 40+ 个 agent 目录复制）
npx -y skills add <source> --skill <name> -a codex -g -y --copy

# 方式 B：手写 SKILL.md（推荐，可控）
mkdir -p ~/.agents/skills/my-skill
$EDITOR ~/.agents/skills/my-skill/SKILL.md

# 提交
cd ~/.agents && git add -A && git commit -m "add: my-skill" && git push
```

## SKILL.md 格式要求

DSH 的解析规则（见 `@deepseek-ai/dsh-skill-filesystem`）：

| 字段 | 要求 |
| --- | --- |
| 文件位置 | `<skill-name>/SKILL.md` |
| `name` | 必填，必须匹配 `^[a-z0-9]+(-[a-z0-9]+)*$` |
| `description` | 必填，模型靠它做路由（写清"什么时候用"） |
| `whenToUse` | 可选 |
| `metadata` | 可选（如 `requires.bins`） |

正文用 Markdown，相对路径资源按 skill 根目录解析。

## 注意

- 本仓库为 **public**，不要往技能里放 token / 密钥。
- 第三方技能（lark-*、tmeet-skill）版权归各自作者，这里仅作个人备份。
- 升级 DSH / Codex 不影响本目录，技能会一直在。
