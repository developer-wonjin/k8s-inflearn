#!/bin/bash
# 게시판 목록을 가져온다.  사용법: ./list-articles.sh [page] [perPage]
#   웹 화면 기준은 perPage=15. 오래된 글일수록 뒷 페이지.
set -euo pipefail
CLUB=30725715; MENU=43
PAGE="${1:-1}"; PER="${2:-15}"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
curl -sS --max-time 30 -H "User-Agent: $UA" -H 'Referer: https://cafe.naver.com/kubeops' \
  "https://apis.naver.com/cafe-web/cafe2/ArticleListV2dot1.json?search.clubid=${CLUB}&search.menuid=${MENU}&search.page=${PAGE}&search.perPage=${PER}" \
  | tr ',' '\n' | grep -E '"articleId":|"subject":' \
  | sed 's/.*"articleId":/ID /; s/.*"subject":"/   /; s/"$//'
