#!/usr/bin/env bash
# 扫描项目中的 Swift 文件，按行数阈值列出路径
# 用法: ./scan_swift_loc.sh [项目根目录]
# 默认扫描当前目录

set -euo pipefail

ROOT="${1:-.}"

if [[ ! -d "$ROOT" ]]; then
  echo "目录不存在: $ROOT" >&2
  exit 1
fi

# 排除常见无关目录
EXCLUDE_DIRS=(
  -path "*/.git/*"
  -o -path "*/DerivedData/*"
  -o -path "*/build/*"
  -o -path "*/.build/*"
  -o -path "*/Pods/*"
  -o -path "*/Carthage/*"
  -o -path "*/Thirdparty/*"
  -o -path "*/Third_tools/*"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

find "$ROOT" \( "${EXCLUDE_DIRS[@]}" \) -prune -o -type f -name "*.swift" -print0 \
  | while IFS= read -r -d '' f; do
      lines=$(wc -l < "$f" | tr -d ' ')
      printf '%s\t%s\n' "$lines" "$f"
    done \
  | sort -nr > "$tmp"

echo "扫描目录: $(cd "$ROOT" && pwd)"
echo "Swift 文件总数: $(wc -l < "$tmp" | tr -d ' ')"

echo ""
echo "=== 超过 2000 行 ==="
found=0
while IFS=$'\t' read -r lines path; do
  if (( lines > 2000 )); then
    printf '%6d  %s\n' "$lines" "$path"
    found=1
  fi
done < "$tmp"
(( found )) || echo "(无)"

echo ""
echo "=== 超过 1000 行（不含已列入 >2000）==="
found=0
while IFS=$'\t' read -r lines path; do
  if (( lines > 1000 && lines <= 2000 )); then
    printf '%6d  %s\n' "$lines" "$path"
    found=1
  fi
done < "$tmp"
(( found )) || echo "(无)"

echo ""
echo "=== 超过 500 行（不含已列入 >1000）==="
found=0
while IFS=$'\t' read -r lines path; do
  if (( lines > 500 && lines <= 1000 )); then
    printf '%6d  %s\n' "$lines" "$path"
    found=1
  fi
done < "$tmp"
(( found )) || echo "(无)"
