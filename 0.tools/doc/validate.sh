#!/bin/bash
# 문서 규칙을 지켰는지 일괄 검사한다.
#   사용법: ./validate.sh <md파일...>      (인자 없으면 프로젝트 전체)
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ $# -gt 0 ]; then FILES=("$@")
else mapfile -t FILES < <(find "$ROOT" -name '.git' -prune -o -name '*.md' -print | sort); fi

fail=0; tot=0
for f in "${FILES[@]}"; do
  # 1) 코드펜스 짝
  n=$(grep -c '^```' "$f"); [ $((n%2)) -ne 0 ] && { echo "  [펜스 홀수] $f"; fail=1; }

  # 2) heredoc 종료 구분자 오염 — END 뒤에 주석/공백이 있으면 복붙이 멈춘다
  grep -q '^END.\+' "$f" && { echo "  [END 오염] $f"; fail=1; }

  # 3) 블록별 검사 (clear 유무 / bash 구문)
  for s in $(grep -n '^```bash' "$f" | cut -d: -f1); do
    e=$(awk -v s="$s" 'NR>s && /^```$/{print NR; exit}' "$f"); tot=$((tot+1))
    first=$(sed -n "$((s+1))p" "$f")
    sed -n "$((s+1)),$((e-1))p" "$f" > "$TMP/blk.sh"
    bash -n "$TMP/blk.sh" 2>/dev/null || { echo "  [구문 오류] $f 줄 $s"; fail=1; }
    # shebang으로 시작하는 블록은 '저장해서 실행할 스크립트'라 clear 대상이 아니다
    case "$first" in \#!*) continue;; esac
    grep -q '^\s*clear\b' "$TMP/blk.sh" || { echo "  [clear 누락] $f 줄 $s"; fail=1; }
  done
done

# 4) 내부 링크 앵커
perl "$DIR/anchors.pl" "${FILES[@]}" || fail=1

[ $fail -eq 0 ] && echo "  => 전부 통과 (파일 ${#FILES[@]}개 / bash 블록 ${tot}개)"
exit $fail
