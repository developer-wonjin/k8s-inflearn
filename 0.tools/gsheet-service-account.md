# 구글 스프레드시트 연동 기록 (서비스 계정)

- 설정일: 2026-09-12
- 대상 시트: `inflearn - 쿠버네티스 k8s` (탭 17개)
- 설치 위치: `/root/.gsheet/` — **저장소 바깥** (키가 git에 딸려 들어가는 사고 방지)
- 목적: Claude가 실습 정리용 스프레드시트를 직접 읽고 쓰게 한다

실습 내용을 정리해 둔 구글 시트를 Claude가 읽기만 하는 게 아니라 **셀까지 고칠 수 있게** 만든
과정이다. 시트 탭이 이 저장소의 실습 주제와 그대로 대응된다 (`Pod`, `Service`, `Volume`,
`Ingress`, `인증인가` 등).

---

## 1. Claude의 Google Drive 커넥터로는 왜 안 되는가

먼저 기본 제공되는 `claude.ai Google Drive` 커넥터를 인증해서 시도했다. **읽기는 되지만
셀 편집은 안 된다.** 인증 후 열린 도구는 이렇다.

| 도구 | 가능 여부 |
|---|---|
| `read_file_content` / `get_file_metadata` / `search_files` | 읽기 **가능** |
| `create_file` (내용 포함 새 파일 생성) | **가능** |
| `copy_file` / `trash_file` / `share_file` | **가능** |
| `update_file` | **제목·폴더 이동만** |
| 기존 시트의 셀 수정 | **불가능** |

`update_file`의 스펙에 그대로 적혀 있다.

```text
Request to update a file (currently only title and parent_id are supported).
```

즉 Drive 커넥터는 **파일 단위** 도구이지 **셀 단위** 도구가 아니다.
셀을 고치려면 Google Sheets API를 직접 써야 한다.

## 2. 사전 확인

```bash
clear                                                                            # 화면 정리 후 시작
which python3                                                                    # 없음 — Rocky 8.8 기본 상태
curl -sS -o /dev/null -w "pypi: %{http_code}\n" https://pypi.org/simple/         # 200
curl -sS -o /dev/null -w "sheets: %{http_code}\n" https://sheets.googleapis.com  # 400
```

`sheets.googleapis.com`의 `400`은 정상이다. API 루트라 GET으로는 400을 주지만,
**TLS까지 도달했다**는 뜻이라 연결 확인으로는 충분하다.

## 3. Python 3.9 설치

기본 `python3`(3.6)으로는 안 된다. `google-auth`가 **3.7 이상**을 요구한다.

```bash
clear                     # 화면 정리 후 시작
dnf module list python3*  # 3.6 / 3.8 / 3.9 선택 가능
dnf install -y python39   # 3.9 설치
python3.9 --version       # Python 3.9.25
```

## 4. 가상환경과 라이브러리

시스템 파이썬을 더럽히지 않도록 venv를 쓴다.

```bash
clear                                                             # 화면 정리 후 시작
mkdir -p /root/.gsheet                                            # 키·스크립트 보관 (저장소 바깥)
chmod 700 /root/.gsheet                                           # 소유자만 접근
python3.9 -m venv /root/.gsheet/venv                              # 가상환경 생성
/root/.gsheet/venv/bin/pip install --quiet gspread google-auth    # 라이브러리 설치
/root/.gsheet/venv/bin/pip list | grep -iE 'gspread|google-auth'  # 설치 확인
```

```text
google-auth          2.50.0
google-auth-oauthlib 1.3.1
gspread              6.2.1
```

## 5. 구글 콘솔 설정 (브라우저에서 직접)

| 단계 | 위치 | 주의 |
|---|---|---|
| ① Sheets API 사용 설정 | API 라이브러리 → Google Sheets API → **사용** | **빠뜨리기 쉽다.** 아래 6절 참고 |
| ② 서비스 계정 생성 | IAM 및 관리자 → 서비스 계정 → 만들기 | **역할(Role)은 지정하지 않아도 된다** |
| ③ JSON 키 발급 | 해당 계정 → 키 → 키 추가 → **JSON** | 이 파일이 곧 자격증명이다 |
| ④ 시트 공유 | 스프레드시트 공유 → 서비스 계정 이메일을 **편집자** | 여기서 실제 권한이 정해진다 |

②의 역할과 ④의 공유를 헷갈리기 쉽다. ②에서 주는 역할은 **GCP 리소스** 권한이고,
시트 접근 권한은 전적으로 ④의 공유로 결정된다. 역할을 안 줘도 ④만 하면 동작한다.

④에 넣을 주소는 발급받은 JSON의 `client_email` 값이다.

## 6. 키 파일 배치

**JSON 내용을 채팅에 붙여넣지 않는다.** 대화 기록에 비밀키가 남는다.
파일로 직접 두고, 서버에서는 식별자만 확인한다.

```bash
clear                                                                                            # 화면 정리 후 시작
ls -l /root/.gsheet/key.json                                                                     # 2KB 안팎이면 정상 (0이면 붙여넣기 실패)
chmod 600 /root/.gsheet/key.json                                                                 # 소유자만 읽기
python3.9 -c "import json;d=json.load(open('/root/.gsheet/key.json'));print(d['client_email'])"  # 비밀키는 출력하지 않는다
```

> 터미널에 `cat > key.json` 으로 붙여넣을 때 **0바이트로 끝나는 일이 실제로 있었다.**
> 붙여넣기가 전달되기 전에 Ctrl+D가 눌린 경우다. 크기를 꼭 확인한다.
> VS Code Remote로 파일을 열어 붙여넣거나 `scp`로 보내는 편이 확실하다.

## 7. 연결 확인

5절 ①(API 사용 설정)을 빠뜨리면 여기서 막힌다. 실제로 겪은 오류다.

```text
APIError: [403]: Google Sheets API has not been used in project 1059871942319
before or it is disabled.
```

**인증은 통과했는데 API가 꺼져 있는 상태**라 메시지를 잘 읽어야 한다.
"권한 없음"이 아니라 "API가 꺼짐"이다. 콘솔에서 켜고 1~2분 기다리면 된다.

켠 뒤 다시 실행한 결과다.

```bash
clear                                            # 화면 정리 후 시작
ID=1imudCD71gMjtlWunqkRLDjSjDihlVIw0F2JqJ32Slg8  # 스프레드시트 ID (URL의 /d/ 다음 부분)
/root/.gsheet/gs.py --id $ID info                # 워크시트 목록
```

```text
제목: inflearn - 쿠버네티스 k8s
  - 개요  (1000행 x 26열, gid=0)
  - 네트워크  (1005행 x 27열, gid=1627099849)
  - ArgoCD  (1000행 x 26열, gid=1409852137)
  ... (총 17개)
```

## 8. 쓰기 확인

빈 셀에 썼다가 지우는 방식으로 검증했다. 원래 상태로 되돌아간다.

```bash
clear                                                                               # 화면 정리 후 시작
ID=1imudCD71gMjtlWunqkRLDjSjDihlVIw0F2JqJ32Slg8                                     # 스프레드시트 ID
/root/.gsheet/gs.py --id $ID read --sheet 개요 --range Z1000                          # 먼저 비어 있는지 확인
/root/.gsheet/gs.py --id $ID write --sheet 개요 --range Z1000 --values '[["쓰기테스트"]]'  # 쓰기
/root/.gsheet/gs.py --id $ID read --sheet 개요 --range Z1000                          # 반영됐는지 확인
/root/.gsheet/gs.py --id $ID write --sheet 개요 --range Z1000 --values '[[""]]'       # 원상 복구
```

```text
[[]]                          ← 시험 전 (비어 있음)
갱신됨: '개요'!Z1000 (1개 셀)
[["쓰기테스트"]]               ← 반영됨
갱신됨: '개요'!Z1000 (1개 셀)
[[]]                          ← 복구됨
```

## 사용법

```bash
clear                                                                                 # 화면 정리 후 시작
ID=1imudCD71gMjtlWunqkRLDjSjDihlVIw0F2JqJ32Slg8                                       # 스프레드시트 ID
/root/.gsheet/gs.py --id $ID info                                                     # 워크시트 목록·크기·gid
/root/.gsheet/gs.py --id $ID read --sheet Service --range A1:D20                      # 범위 읽기
/root/.gsheet/gs.py --id $ID read --sheet Service                                     # 시트 전체 읽기
/root/.gsheet/gs.py --id $ID write --sheet Service --range A1 --values '[["a","b"]]'  # 범위에 쓰기
/root/.gsheet/gs.py --id $ID append --sheet Service --values '[["새 행"]]'              # 맨 아래 행 추가
```

`--sheet`를 생략하면 첫 번째 워크시트를 쓴다.
`--values`는 **2차원 배열 JSON**이다. 한 행이어도 `[["a","b"]]` 처럼 두 번 감싼다.

## 스크립트

`/root/.gsheet/gs.py` — `gspread`로 감싼 얇은 CLI다.

```python
KEY = "/root/.gsheet/key.json"
SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]


def client():
    return gspread.authorize(Credentials.from_service_account_file(KEY, scopes=SCOPES))
```

오류는 스택 트레이스 대신 한 줄로 나오게 했다.

| 상황 | 메시지 |
|---|---|
| 키 파일 없음 | `키 파일이 없습니다: /root/.gsheet/key.json` |
| 공유 안 됨 | `시트를 찾을 수 없습니다. 서비스 계정에 '편집자'로 공유했는지 확인하세요.` |
| API 꺼짐·권한 부족 | `접근 거부. Sheets API 사용 설정과 시트 공유 권한을 확인하세요.` |
| 탭 이름 오타 | `워크시트 이름이 없습니다. 'info' 로 목록을 먼저 확인하세요.` |

## 배운 것

- Claude의 Drive 커넥터는 **파일 단위** 도구다. 셀 편집은 Sheets API를 직접 써야 한다.
- 서비스 계정은 **역할(Role)이 아니라 문서 공유**로 권한이 정해진다. ②와 ④를 헷갈리지 않는다.
- `403 has not been used in project` 는 권한 문제가 아니라 **API 미사용 설정** 문제다.
- 비밀키는 채팅·저장소에 넣지 않는다. 경로만 기록하고 권한은 `600`으로 잠근다.
- 터미널 붙여넣기는 **조용히 실패**할 수 있다. 파일 크기로 확인한다.
