#!/bin/bash
# 네이버 카페(큐브옵스 커뮤니티) 게시글 본문을 텍스트로 받아온다.
#   사용법: ./fetch-article.sh <articleId> [출력디렉토리]
#   예    : ./fetch-article.sh 498
#
# 주의: cafe.naver.com 은 WebFetch로 못 읽는다(차단). SPA라 HTML도 비어 있다.
#       아래처럼 내부 API에 User-Agent / Referer 를 붙여야 응답한다. 로그인은 불필요.
set -euo pipefail

CLUB=30725715                        # 큐브옵스 커뮤니티 cafeId
ID="${1:?articleId를 지정하세요}"
OUT="${2:-.}"
DIR="$(cd "$(dirname "$0")" && pwd)"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

curl -sS --max-time 40 \
  -H "User-Agent: $UA" \
  -H "Referer: https://cafe.naver.com/kubeops/${ID}" \
  "https://apis.naver.com/cafe-web/cafe-articleapi/v3/cafes/${CLUB}/articles/${ID}?query=&useCafeId=true&requestFrom=A" \
  -o "${OUT}/a${ID}.json"

perl "${DIR}/cafe.pl" < "${OUT}/a${ID}.json" > "${OUT}/a${ID}.txt"
echo "${OUT}/a${ID}.txt ($(wc -l < "${OUT}/a${ID}.txt") 줄)"
