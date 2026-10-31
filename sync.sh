#!/bin/bash
# ============================================================
# ~/.agents/sync.sh —— 把 ~/.agents 同步到 GitHub
#
#   用法:
#     ./sync.sh                     自动生成带时间戳的提交信息
#     ./sync.sh -m "自定义信息"      指定提交信息
#     ./sync.sh --dry-run           只看会提交什么，不真正提交
#     ./sync.sh --no-push           只提交到本地
#     ./sync.sh --no-pull           跳过远程 rebase（强制覆盖风险自负）
#     ./sync.sh --force             跳过敏感信息检查 / 允许空提交
#     ./sync.sh --help              显示帮助
# ============================================================
set -uo pipefail

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="origin"
BRANCH="main"
COMMIT_MSG=""
DRY_RUN=0
DO_PUSH=1
DO_PULL=1
FORCE=0

cd "$AGENTS_DIR" || { echo "无法进入 $AGENTS_DIR"; exit 1; }

# ---------- 输出 ----------
if [ -t 1 ]; then
  C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_C="\033[36m"; C_0="\033[0m"
else
  C_G=""; C_Y=""; C_R=""; C_C=""; C_0=""
fi
info() { printf "${C_C}%s${C_0}\n" "$*"; }
ok()   { printf "${C_G}%s${C_0}\n" "$*"; }
warn() { printf "${C_Y}%s${C_0}\n" "$*" >&2; }
err()  { printf "${C_R}%s${C_0}\n" "$*" >&2; }

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------- 参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message)   COMMIT_MSG="${2:-}"; shift 2 ;;
    -m*)            COMMIT_MSG="${1#-m}"; shift ;;
    --dry-run|-n)   DRY_RUN=1; shift ;;
    --no-push)      DO_PUSH=0; shift ;;
    --no-pull)      DO_PULL=0; shift ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      usage ;;
    *)              err "未知参数: $1"; usage ;;
  esac
done

# ---------- 前置检查 ----------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "❌ $AGENTS_DIR 不是 git 仓库"
  exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  err "❌ 未配置远程仓库 $REMOTE"
  exit 1
fi

# ---------- 1. 暂存 ----------
info "▶ 扫描变更..."
git add -A

if git diff --cached --quiet; then
  if [ "$FORCE" = "1" ]; then
    warn "⚠️  无变更，但 --force 已指定，创建空提交"
  else
    ok "✓ 没有变更，无需同步"
    exit 0
  fi
fi

# ---------- 2. 变更摘要 ----------
CHANGED_FILES=$(git diff --cached --name-only | wc -l | tr -d ' ')
STAT=$(git diff --cached --shortstat | sed 's/^ *//')
SKILLS=$(git diff --cached --name-only \
          | awk -F/ '$1=="skills" && NF>2 {print $2}' \
          | sort -u | tr '\n' ' ' | sed 's/ *$//')

echo "  文件数: $CHANGED_FILES"
[ -n "$STAT" ] && echo "  变更量: $STAT"
[ -n "$SKILLS" ] && echo "  涉及技能: $SKILLS"

# ---------- 3. 敏感信息检查（本仓库是 public，必须拦） ----------
if [ "$FORCE" != "1" ]; then
  SECRET_HITS=$(git grep --cached -nI -E \
    'gho_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|api[_-]?key|secret[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_\-]{12,}' \
    -- . 2>/dev/null | head -20)

  if [ -n "$SECRET_HITS" ]; then
    err "❌ 疑似敏感信息，已中止（仓库是 public）"
    echo "$SECRET_HITS" | sed 's/^/    /'
    err "   确认无风险后可用 --force 跳过此检查"
    # 回滚暂存，避免脏状态
    git reset -q
    exit 1
  fi
  ok "✓ 敏感信息检查通过"
fi

# ---------- 4. 提交 ----------
if [ -z "$COMMIT_MSG" ]; then
  TS=$(date '+%Y-%m-%d %H:%M:%S %z')
  COMMIT_MSG="sync: $TS"
  [ -n "$SKILLS" ] && COMMIT_MSG="$COMMIT_MSG

变更技能: $SKILLS"
  COMMIT_MSG="$COMMIT_MSG
文件: $CHANGED_FILES 个"
fi

if [ "$DRY_RUN" = "1" ]; then
  warn "── DRY RUN，不会真正提交 ──"
  echo "  提交信息:"
  echo "$COMMIT_MSG" | sed 's/^/    /'
  echo "  待提交文件:"
  git diff --cached --name-only | sed 's/^/    /'
  git reset -q
  exit 0
fi

if ! git -c user.name="$(git config user.name || echo lijingang)" \
         -c user.email="$(git config user.email || echo 171232349@qq.com)" \
         commit -q -m "$COMMIT_MSG"; then
  err "❌ 提交失败"
  exit 1
fi
ok "✓ 已提交: $(git log --oneline -1)"

# ---------- 5. 推送 ----------
if [ "$DO_PUSH" != "1" ]; then
  warn "已跳过推送（--no-push），本地提交已保留"
  exit 0
fi

# 先 rebase，避免非快进被拒
if [ "$DO_PULL" = "1" ]; then
  if git fetch -q "$REMOTE" "$BRANCH" 2>/dev/null; then
    if git rev-parse --verify -q "$REMOTE/$BRANCH" >/dev/null 2>&1; then
      BEHIND=$(git rev-list --count "HEAD..$REMOTE/$BRANCH" 2>/dev/null || echo 0)
      if [ "${BEHIND:-0}" -gt 0 ]; then
        warn "远程领先 $BEHIND 个提交，先 rebase..."
        if ! git pull --rebase --autostash -q "$REMOTE" "$BRANCH"; then
          err "❌ rebase 失败，已回滚 rebase（本地提交保留）"
          git rebase --abort 2>/dev/null
          err "   请手动处理冲突后重新执行 ./sync.sh"
          exit 1
        fi
        ok "✓ rebase 完成"
      fi
    fi
  else
    warn "⚠️  无法 fetch 远程（网络问题？），直接尝试推送"
  fi
fi

info "▶ 推送到 $REMOTE/$BRANCH..."
if git push -q "$REMOTE" "$BRANCH" 2>/tmp/agents-sync-push.$$
then
  URL=$(git remote get-url "$REMOTE" | sed -e 's|^git@github.com:|https://github.com/|' -e 's|\.git$||')
  ok "✓ 推送成功 → $URL"
  rm -f /tmp/agents-sync-push.$$
else
  err "❌ 推送失败："
  sed 's/^/    /' /tmp/agents-sync-push.$$ 2>/dev/null | head -10
  rm -f /tmp/agents-sync-push.$$
  err "   本地提交已保留，网络恢复后重试 ./sync.sh"
  exit 1
fi
