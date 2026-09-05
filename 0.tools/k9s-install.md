# k9s 설치 기록

- 설치일: 2026-09-04
- 설치 버전: **v0.51.0** (2026-06-06 릴리즈)
- 대상: Rocky Linux 8.8 / x86_64 / k8s-master
- 설치 위치: `/usr/local/bin/k9s`
- 설치 방식: GitHub 릴리즈 바이너리 (tarball)

k9s는 kubectl 명령을 일일이 치지 않고 터미널 UI로 클러스터를 탐색하는 도구다.
Pod 목록, 로그, exec, 삭제를 키 몇 번으로 처리한다.

---

## 1. 환경 확인

```bash
clear                        # 화면 정리 후 시작
cat /etc/os-release          # Rocky Linux 8.8 (Green Obsidian)
uname -m                     # x86_64
which k9s                    # 없음 (신규 설치)
which dnf yum curl tar       # dnf, yum, curl, tar 있음 / wget 없음
```

> wget이 없으므로 이 문서는 전부 `curl` 기준으로 작성했다.

## 2. 네트워크 확인

```bash
clear  # 화면 정리 후 시작
curl -sS --max-time 15 -o /dev/null -w 'HTTP %{http_code}\n' \
  https://api.github.com/repos/derailed/k9s/releases/latest
# → HTTP 200
```

GitHub에 직접 나갈 수 있어야 이 방식이 가능하다.
폐쇄망이면 아래 [부록: 오프라인 설치] 참고.

## 3. 최신 버전 조회

```bash
clear  # 화면 정리 후 시작
VER=$(curl -sS https://api.github.com/repos/derailed/k9s/releases/latest \
      | grep -m1 '"tag_name"' | cut -d'"' -f4)
echo $VER
# → v0.51.0
```

## 4. 다운로드

```bash
clear  # 화면 정리 후 시작
cd /tmp
curl -sSL -o k9s_Linux_amd64.tar.gz \
  "https://github.com/derailed/k9s/releases/download/${VER}/k9s_Linux_amd64.tar.gz"
```

- `-L` 필수: GitHub 릴리즈는 CDN으로 302 리다이렉트된다. 빼면 빈 파일을 받는다.
- 받은 크기: 약 40M

> 파일명을 `k9s.tar.gz` 같은 임의 이름으로 바꿔 받으면 다음 단계 체크섬 검증이 실패한다.
> `checksums.sha256`이 **원본 파일명 기준**으로 기록돼 있기 때문. (실제로 한 번 겪음)

## 5. 체크섬 검증

```bash
clear  # 화면 정리 후 시작
curl -sSL -o checksums.sha256 \
  "https://github.com/derailed/k9s/releases/download/${VER}/checksums.sha256"

grep -E '\sk9s_Linux_amd64\.tar\.gz$' checksums.sha256 | sha256sum -c -
# → k9s_Linux_amd64.tar.gz: OK
```

- `grep`에 `-E '\s...$'`를 쓴 이유: 단순히 `grep k9s_Linux_amd64.tar.gz`로 하면
  `k9s_Linux_amd64.tar.gz.sbom.json` 줄까지 걸려서 없는 파일을 검증하려다 FAILED가 난다.
- 인터넷에서 받은 바이너리를 root 권한으로 설치하는 것이므로 이 단계를 생략하지 말 것.

## 6. 압축 해제 및 설치

```bash
clear                                      # 화면 정리 후 시작
tar -xzf k9s_Linux_amd64.tar.gz k9s        # 아카이브에서 k9s 바이너리만 꺼냄
install -m 755 k9s /usr/local/bin/k9s      # 실행권한 755로 복사
```

- `install`을 쓰면 `cp` + `chmod`를 한 번에 처리한다.
- `/usr/local/bin`은 기본 PATH에 있어서 별도 PATH 설정이 필요 없다.

## 7. 설치 확인

```bash
clear            # 화면 정리 후 시작
which k9s        # /usr/local/bin/k9s
k9s version      # Version: v0.51.0
k9s info         # 설정 파일 경로 목록
```

`k9s info` 출력 중 아래 에러는 **정상**이다.

```
ERROR Unable to reads k9s config file
error="open /root/.config/k9s/config.yaml: no such file or directory"
```

설정 파일은 k9s를 처음 TUI로 실행할 때 생성된다. 아직 실행 전이라 없는 것뿐이다.

## 8. 실행

```bash
clear                                       # 화면 정리 후 시작
k9s                      # 현재 컨텍스트로 실행
k9s -n default           # 특정 네임스페이스로 시작
k9s --context kubernetes-admin@kubernetes   # 특정 컨텍스트로 시작 (이름은 kubectl config current-context)
k9s -A                   # 전체 네임스페이스
```

k9s는 kubectl과 **같은 kubeconfig**(`~/.kube/config`)를 쓴다. 별도 인증 설정이 없다.

```bash
clear  # 화면 정리 후 시작
kubectl config current-context
# → kubernetes-admin@kubernetes
```

> k9s는 터미널 UI라 실제 터미널(TTY)에서 직접 실행해야 한다.
> 스크립트나 파이프로는 정상 동작하지 않는다.

---

## 주요 단축키

| 키 | 동작 |
|---|---|
| `:pod` `:svc` `:deploy` `:ns` | 리소스 종류 전환 (`:` 누르고 별칭 입력) |
| `/문자열` | 목록 내 필터 |
| `0` | 전체 네임스페이스 |
| `Enter` | 선택 리소스 상세 |
| `d` | describe |
| `y` | YAML 보기 |
| `l` | 로그 보기 |
| `s` | 컨테이너 shell 접속 |
| `Ctrl+d` | 리소스 삭제 |
| `Esc` | 뒤로 |
| `?` | 단축키 도움말 |
| `:q` / `Ctrl+c` | 종료 |

컨테이너가 2개인 Pod(예: `1.pod/pod-1.yaml`)에서 `l`이나 `s`를 누르면
어느 컨테이너를 볼지 선택하는 목록이 먼저 뜬다.

---

## 업그레이드

같은 절차를 새 버전 태그로 반복하면 된다. `install` 명령이 기존 파일을 덮어쓴다.

## 제거

```bash
clear  # 화면 정리 후 시작
rm -f /usr/local/bin/k9s
rm -rf ~/.config/k9s ~/.local/share/k9s ~/.local/state/k9s
```

---

## 부록: 다른 설치 방법

**dnf/yum은 안 된다.** Rocky 8 기본 저장소나 EPEL에 k9s 패키지가 없다.
그래서 위와 같이 바이너리를 직접 받았다.

```bash
clear                  # 화면 정리 후 시작
# 참고: 아래는 이 서버에서 쓸 수 없거나 부적합한 방법
dnf install k9s        # 패키지 없음
snap install k9s       # snapd 미설치
brew install k9s       # macOS/Linuxbrew 필요
```

### 오프라인(폐쇄망) 설치

인터넷 되는 PC에서 tarball과 checksums 파일을 받아 옮긴 뒤, 위 5~7단계만 수행한다.

```bash
clear  # 화면 정리 후 시작
# 외부 PC에서
curl -sSLO https://github.com/derailed/k9s/releases/download/v0.51.0/k9s_Linux_amd64.tar.gz
curl -sSLO https://github.com/derailed/k9s/releases/download/v0.51.0/checksums.sha256
# → 두 파일을 서버로 복사 후 검증/설치
```

---

## 한 번에 실행하는 스크립트

```bash
#!/bin/bash
set -euo pipefail

VER=$(curl -sS https://api.github.com/repos/derailed/k9s/releases/latest \
      | grep -m1 '"tag_name"' | cut -d'"' -f4)
echo "installing k9s ${VER}"

TMP=$(mktemp -d)
cd "$TMP"
curl -sSL -O "https://github.com/derailed/k9s/releases/download/${VER}/k9s_Linux_amd64.tar.gz"
curl -sSL -O "https://github.com/derailed/k9s/releases/download/${VER}/checksums.sha256"
grep -E '\sk9s_Linux_amd64\.tar\.gz$' checksums.sha256 | sha256sum -c -

tar -xzf k9s_Linux_amd64.tar.gz k9s
install -m 755 k9s /usr/local/bin/k9s
cd / && rm -rf "$TMP"

k9s version
```

## 참고 링크

- GitHub : https://github.com/derailed/k9s
- 릴리즈 : https://github.com/derailed/k9s/releases
- 공식 문서 : https://k9scli.io/
