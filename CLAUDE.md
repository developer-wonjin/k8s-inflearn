# k8s-inflearn — 쿠버네티스 실습 기록

큐브옵스 커뮤니티(인프런 강의 부속 카페) 게시글을 하나씩 실습하고 그 과정을 문서로 남기는 저장소.

- 원문 게시판 : https://cafe.naver.com/f-e/cafes/30725715/menus/43 (cafeId `30725715`, menuId `43`)
- 진행 순서 : **작성일 오래된 순** (articleId 오름차순)
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대(master, worker1, worker2)

## 클러스터 특이사항

- **master에 `NoSchedule` taint가 없다.** 일반 Pod이 master에도 스케줄링되므로 강의 화면과 노드 분포가 다르다.
- 노드 allocatable memory : master 약 3.71Gi / worker 각 약 2.79Gi
- **master에 Pod 절반이 몰려 있어 여유가 거의 없다.** 무거운 애드온을 올리면 노드가 멈춘다
  → [부록) 트러블슈팅](부록%29%20트러블슈팅/마스터-리소스-고갈-apiserver-먹통.md)
- 노드별 여유 메모리 : master 약 1.2GiB / worker1 약 1.85GiB / worker2 약 1.81GiB
  (총량은 master가 크지만 Pod 25개를 떠안아 **실제 여유는 가장 적다**)

### 노드 접근

master에서 워커 2대로 **키 인증 SSH가 열려 있다.** 비밀번호는 필요 없다.

```bash
clear                                    # 화면 정리 후 시작
ssh root@192.168.56.31 hostname          # k8s-worker1
ssh root@192.168.56.32 hostname          # k8s-worker2
```

- 키 : `/root/.ssh/id_ed25519` (master에서 생성, 워커 `authorized_keys`에 등록)
  - `id_ed25519_github`는 **GitHub 전용**이라 노드 접속과 무관하다. `~/.ssh/config`의
    `IdentitiesOnly yes`로 github.com에만 쓰이므로 워커 접속에 간섭하지 않는다.
- `ssh-copy-id`는 이 환경에서 실패한다. 비대화형 셸이라 비밀번호 프롬프트에 입력이 전달되지 않는다.
  키를 새로 심어야 하면 VirtualBox 콘솔에서 직접 `authorized_keys`에 붙여넣는다.
- 세 노드에 명령을 한 번에 돌릴 때 쓰는 형태 :

  ```bash
  clear                                  # 화면 정리 후 시작
  for n in 31 32; do
    echo "### 192.168.56.$n"
    ssh root@192.168.56.$n "systemctl is-active iscsid"
  done
  ```
- VM을 정지·재개하면 시계가 뒤처져 이미지 pull이 깨진다 → [부록) 트러블슈팅](부록%29%20트러블슈팅/시계-불일치-ImagePullBackOff.md)
- **저널이 영속화돼 있다.** 재부팅 후에도 `journalctl -b -1`로 직전 부팅 로그를 볼 수 있다

---

## 부록

특정 게시글에 매이지 않는 개념·장애·운영 기록.

| 문서 | 내용 |
|---|---|
| [부록) 네트워크](부록%29%20네트워크/네트워크-네임스페이스-공유.md) | Pod 안 컨테이너가 net/uts/ipc를 공유하고 mnt/pid는 따로 쓰는 구조 |
| [부록) 네트워크](부록%29%20네트워크/IP-주소-체계-총정리.md) | 노드IP·Pod IP·ClusterIP·NodePort·EXTERNAL-IP의 차이와 출발지 IP가 바뀌는 지점 |
| [부록) 삭제](부록%29%20삭제/삭제-grace-period-와-옵션.md) | 삭제가 30초 걸리는 이유, `--grace-period` / `--wait` / `--force` 비교 |
| [부록) 트러블슈팅](부록%29%20트러블슈팅/시계-불일치-ImagePullBackOff.md) | 노드 시계가 틀어져 `ImagePullBackOff`가 났던 사례 |
| [부록) 트러블슈팅](부록%29%20트러블슈팅/마스터-리소스-고갈-apiserver-먹통.md) | Longhorn 설치 중 master가 고갈돼 apiserver가 먹통이 된 사례 |
| [부록) 로드밸런서](부록%29%20로드밸런서/metallb-설치와-원리.md) | 베어메탈에서 `<pending>`이 나는 이유, MetalLB L2 모드의 원리와 설치 |

# 문서 작성 규칙

새 게시글을 실습할 때 아래 규칙을 그대로 따른다.

## 1. 디렉토리 구조

```
k8s-inflearn/
├── CLAUDE.md                      이 파일
├── 0.tools/                       도구 설치 기록
│   ├── k9s-install.md
│   ├── gsheet-service-account.md
│   └── doc/                       문서 작성용 스크립트 (아래 4절)
├── <articleId>.<슬러그>/           게시글 하나 = 디렉토리 하나
│   ├── README.md                  개요·문서 구성·실습 순서·원문과 다른 점
│   └── <절번호>.<리소스>.md        자원별로 파일을 나눈다
└── 부록) <주제>/                   특정 게시글에 매이지 않는 개념·장애 기록
```

- 게시글 디렉토리 이름은 `497.pod-container-label-nodeschedule` 형태.
  articleId를 앞에 두면 작성일 순으로 정렬된다.
- 파일은 **원문의 절 번호를 따른다** (`1-1.pod-container.md`, `2-2.service-label.md`).

## 2. 문서 구성 순서

각 문서는 반드시 이 순서로 쓴다.

1. **제목 + 메타** — 원문 링크, 실습일, 관련 문서 링크
2. **`## 왜 필요한가`** — 학습 목표. 아래 2-1절 참고
3. **`## 실습 시작 전 정리`** — 아래 3절의 정리 블록 (선행 조건이 있으면 경고를 먼저)
4. **`## YAML`** — 매니페스트 전문, **라인마다 주석을 열 맞춰** 단다
5. **`## 실습 과정`** — 명령어 블록과 **실제 출력**을 번갈아
6. **`### 검증: ...`** — 원문 서술을 실제로 확인한 결과 (다르면 그 사실을 남긴다)
7. **`### 정리`** — 이 문서에서 만든 리소스 삭제
8. **`## 배운 것`** — 한 줄 요약 목록

### 2-1) `## 왜 필요한가` — 맨 앞에 학습 목표를 둔다

**문법보다 존재 이유가 먼저다.** 이 오브젝트가 왜 있는지 모르고 YAML부터 보면
외우기만 하고 남지 않는다. 세 부분으로 쓴다.

| 소절 | 내용 |
|---|---|
| `### 없으면 이렇게 된다` | 이 개념이 없을 때 부딪히는 **구체적인 문제**. 앞 문서에서 확인한 한계를 링크로 잇는다 |
| `### ○○가 나눈 것` / `해결하는 것` | 그 문제를 **어떤 방식으로** 푸는지. 역할 분리·구조를 표나 그림으로 |
| `### 이 문서에서 확인할 것` | 실습으로 답할 질문 목록. **몇 절에서 다루는지** 함께 적는다 |

- 개념 설명을 여기에 몰아넣지 않는다. **문제 → 해결 방식 → 확인할 질문**까지만이다.
- 앞 문서가 있으면 그 한계를 출발점으로 삼는다. 문서끼리 이어져야 흐름이 생긴다.
  (예: `3.pv-pvc.md`는 emptyDir·hostPath의 한계에서 시작한다)
- 이미 쓴 문서에도 **요청이 있으면 소급해서 넣는다.**

### 지켜야 할 원칙

- **출력은 실제로 실행해서 얻은 것만 적는다.** 지어내지 않는다.
- **원문과 다르면 그대로 기록한다.** 원문이 틀린 경우가 실제로 여러 번 있었다.
  (예: "같은 포트 쓰면 Pod 생성 에러" → 실제로는 생성은 되고 런타임에 `CrashLoopBackOff`)
- **실패한 시도도 남긴다.** 왜 안 됐는지가 다음 사람에게 가장 쓸모 있다.
  (예: `/dev/shm`은 기본 64Mi 제한이라 OOM 테스트가 안 됐던 건)

## 3. 코드 블록 규칙

### 3-1) 명령어 라인마다 주석, 열 맞춰서

```bash
clear                                                       # 화면 정리 후 시작
kubectl apply -f - <<'END'                                  # 파일 없이 표준입력으로 생성
# ... YAML ...
END

kubectl wait --for=condition=Ready pod/pod-1 --timeout=90s  # Ready 될 때까지 대기
kubectl get pod pod-1 -o wide                               # IP·NODE까지 확인
```

- `#` 위치는 **블록 안에서만** 맞춘다. 문서 전체를 한 열로 통일하면 짧은 블록에서 주석이 밀려난다.
- 손으로 맞추지 말고 `0.tools/doc/align-blocks.pl`을 쓴다 (4절).

### 3-2) `clear`를 블록 맨 앞에 넣는다

화면을 정리하고 시작해야 문서에 적힌 출력과 실제 화면이 일치한다.
단, `#!`로 시작하는 블록(저장해서 실행할 스크립트)은 예외.

### 3-3) heredoc 종료 구분자 뒤에는 아무것도 붙이지 않는다

```text
잘못된 예 ─ 이렇게 쓰면 heredoc이 닫히지 않는다

    END                                      # heredoc 종료
    END␣␣                                    (주석 없이 후행 공백만 있어도 안 된다)

올바른 예

    END
```

`END`는 그 줄에 **단독으로** 있어야 한다. 주석은 물론 **후행 공백도 안 된다.**
안 그러면 문서를 복사해 붙여넣은 사람의 셸이 입력을 계속 기다리며 멈춘다.
설명이 필요하면 여는 줄(`kubectl apply -f - <<'END'  # ...`)에 붙인다.

### 3-4) 긴 명령어와 여러 리소스 나열

- **리소스 이름을 2개 이상 나열할 때는 한 줄에 하나씩 쓴다.** 무엇을 대상으로 하는지
  한눈에 세어지고, 나중에 하나만 추가·삭제하기도 쉽다.

  ```bash
  # 셀렉터가 실제로 잡은 Pod의 IP 목록
  kubectl get endpoints \
    svc-for-web \
    svc-for-production
  ```

- **끊어 쓸 수 있으면 백슬래시로 개행한다.** 단 `\` 뒤에는 주석을 못 다니 주석은 윗줄에 둔다.
  플래그(`--ignore-not-found`, `--timeout` 등)는 이름 목록 뒤에 붙인다.

  ```bash
  # Pod 6개가 전부 Ready 될 때까지 대기 (최대 120초)
  kubectl wait --for=condition=Ready \
    pod/pod-1 \
    pod/pod-2 \
    pod/pod-3 \
    pod/pod-4 \
    pod/pod-5 \
    pod/pod-6 \
    --timeout=120s
  ```

- **이름이 하나뿐이면 나누지 않는다.** `kubectl delete deploy deployment-1` 처럼 짧으면 한 줄에 둔다.

- **`jsonpath`처럼 한 덩어리인 건 나누지 않는다.** 주석만 윗줄로 뺀다.

### 3-5) 셸 특수문자를 자리표시자로 쓰지 않는다

`k9s --context <이름>` 같은 표기는 `<`가 리다이렉션으로 해석돼 복붙하면 에러가 난다.
실제 값을 쓰거나 (`kubernetes-admin@kubernetes`) 따옴표로 감싼다.

## 4. 작성용 스크립트 (`0.tools/doc/`)

| 스크립트 | 용도 |
|---|---|
| `list-articles.sh [page] [perPage]` | 게시판 목록 조회 (웹 화면 기준 `perPage=15`) |
| `fetch-article.sh <articleId> [출력dir]` | 게시글 본문을 텍스트로 변환 |
| `align-blocks.pl` | ```` ```bash ```` 블록 안 `명령어¦주석` 을 열 맞춰 정렬 |
| `repl.pl <파일> <시작줄> <끝줄> <새내용파일>` | 줄 범위 교체 |
| `insert.pl <절파일> <대상파일>` | 첫 `## ` 앞에 절 삽입 |
| `anchors.pl <md...>` | 내부 링크 앵커가 실제 헤딩과 맞는지 검사 |
| `validate.sh [md...]` | 위 규칙 일괄 검사 (인자 없으면 전체) |

### 표준 작성 절차

```bash
clear                                           # 화면 정리 후 시작
cd /root/k8s-inflearn/0.tools/doc

./list-articles.sh 2                            # 실습할 게시글 번호 확인
./fetch-article.sh 498 /tmp                     # 본문 받아오기

# ... 실습을 실제로 수행하고, 초안을 '명령어¦주석' 형태로 작성한 뒤 ...

perl align-blocks.pl < draft.md > ../../498.service-clusterip/2-1.svc.md
./validate.sh ../../498.service-clusterip/*.md  # 규칙 위반 검사
```

> **네이버 카페는 WebFetch로 못 읽는다** (도메인 차단, SPA라 HTML도 비어 있음).
> 내부 API에 `User-Agent`와 `Referer` 헤더를 붙여야 응답한다. 로그인은 필요 없다.
> 이 처리는 `fetch-article.sh`에 들어 있다.

## 5. 실습 시작 전 정리 블록

각 실습 문서 맨 앞에 이 블록을 넣는다.

```bash
clear                       # 화면 정리 후 시작

# default 네임스페이스의 실습 리소스를 전부 삭제 (시스템 네임스페이스는 건드리지 않는다)
kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

# Service는 kubernetes(클러스터 기본 서비스)만 남기고 삭제
kubectl delete svc -n default \
  --field-selector 'metadata.name!=kubernetes' --ignore-not-found

kubectl get all -n default  # service/kubernetes 만 남으면 정상
```

- **`-n default`를 반드시 붙인다.** `-A`로 실행하면 `kube-system`, `calico-system`이
  지워져 클러스터가 망가진다.
- `service/kubernetes`는 제외한다. 지워도 자동 재생성되지만 그 사이 통신이 끊긴다.
- `--all`과 `--field-selector`는 함께 못 쓴다. 그래서 Service만 따로 분리했다.
- **Pod을 지울 때는 `--grace-period=1`을 붙인다.** 기본값 30초를 기다리면 삭제 한 번에
  32초가 걸린다. 1초로 줄이면 **1.3초**로 끝나면서 종료 확인은 그대로 유지된다.
  근거와 다른 옵션들은 [부록) 삭제](../부록%29%20삭제/삭제-grace-period-와-옵션.md) 참고.
  - `--force`는 쓰지 않는다. 종료 확인을 건너뛰어 컨테이너가 계속 돌 수 있다.
  - Deployment·Service에는 유예 시간 개념이 없어 붙여도 의미가 없다.
    단 Deployment를 지우면 딸린 Pod은 자기 30초를 쓰므로, 정리 블록처럼
    **타입 목록 맨 앞에 `pod`을 함께 적어** 같이 지워야 빨리 끝난다.

### 선행 조건이 있는 문서

앞 문서의 리소스를 이어받는 문서에는 **정리 블록을 두지 않는다.** 정리를 돌리면 전제가 되는
리소스까지 지워져 실습 자체가 성립하지 않기 때문이다.
(예: `2-2.service-label.md`는 2-1이 만든 Pod 6개가 있어야 Endpoints가 채워진다)

`## 실습 시작 전 정리` 대신 `## 시작 전 확인`을 두고, 경고와 전제 확인 명령만 적는다.

| 상황 | 할 일 |
|---|---|
| 앞 문서를 막 끝내고 이어서 온 경우 | 그대로 진행한다 |
| 처음부터 다시 하는 경우 | 앞 문서를 먼저 실습하고 복귀한다 |

README의 문서 구성 표에도 **선행 조건** 열로 표시한다.

## 6. 작업 중 지킬 것

- **실행한 명령어를 항상 보여준다.** 결과만 보고하지 않는다. 학습이 목적이라 어떤 명령으로
  그 결과에 도달했는지가 본체다. 확인·검증용 조회 명령도 포함한다.
- **리소스를 지우기 전에 무엇이 있는지 먼저 본다** (`kubectl get all -n default`).
- **`mv`와 `cp`는 대화형 별칭(`-i`)이 걸려 있다.** 스크립트에서 덮어쓸 때는
  `cat tmp > 파일` 형태를 쓴다. 안 그러면 확인 프롬프트에서 멈춘다.
- **`perl -pe 's|...|...|'`에서 구분자를 조심한다.** 마크다운 표를 다룰 때 `|`를 구분자로
  쓰면 표의 `|`와 충돌해 파일이 깨진다. 리터럴 비교(`index($l, '...') == 0`)를 쓰는 편이 안전하다.
- **문서를 고친 뒤에는 `validate.sh`를 돌린다.**

## 7. 진행 현황

| articleId | 제목 | 상태 | 디렉토리 |
|---|---|---|---|
| 492 | [기초다지기] Getting-Started Kubernetes! | 미실습 (개념·Docker 위주) | — |
| 495 | [설치] Kubernetes Cluster 설치 - Windows | 해당 없음 (설치 완료) | — |
| 496 | [설치] Kubernetes Cluster 설치 - Mac | 해당 없음 | — |
| 497 | [기본오브젝트] Pod - Container, Label, NodeSchedule | **완료** | `497.pod-container-label-nodeschedule/` |
| 498 | [기본오브젝트] Service - ClusterIP, NodePort, LoadBalancer | **완료** | `498.service-clusterip-nodeport-loadbalancer/` |
| 499 | [기본오브젝트] Volume - emptyDir, hostPath, PV/PVC | **완료** | `499.volume-emptydir-hostpath-pv-pvc/` |
| 500 | [기본오브젝트] ConfigMap, Secret | **완료** | `500.configmap-secret/` |
| 501 | [기본오브젝트] Namespace, ResourceQuota, LimitRange | **완료** | `501.namespace-resourcequota-limitrange/` |
| 503 | [컨트롤러] ReplicaSet | **완료** | `503.replicaset/` |
| 504 | [컨트롤러] Deployment - Recreate, RollingUpdate | **완료** | `504.deployment-recreate-rollingupdate/` |
| 507 | [컨트롤러] DaemonSet, Job, CronJob | **완료** | `507.daemonset-job-cronjob/` |
| 510 | [Pod] ReadinessProbe, LivenessProbe | **완료** | `510.readiness-liveness-probe/` |
| 513 | [Pod] Node Scheduling - Affinity, Taint | **완료** | `513.node-scheduling/` |
| 516 | [기본오브젝트] Service - Headless, Endpoint, ExternalName | **완료** | `516.service-headless-endpoint-externalname/` |
| 518 | [기본오브젝트] Volume - Dynamic Provisioning | **부분** (1절 Longhorn 설치 완료, 2절 이후 미실습) | `518.dynamic-provisioning/` |
| 522 | [기본오브젝트] Authentication - X509, ServiceAccount | **부분** (멀티 클러스터 절 제외) | `522.authentication/` |
| 525 | [기본오브젝트] Authorization - RBAC | **완료** | `525.authorization-rbac/` |
| 526 | [기본오브젝트] Dashboard - Token | **완료** (브라우저 절차 제외) | `526.dashboard-token/` |
| 528 | [컨트롤러] StatefulSet | **완료** (PV 수동 대체) | `528.statefulset/` |
| 529 | [컨트롤러] Ingress - Loadbalancing, Canary | **완료** | `529.ingress/` |
| 530 | [컨트롤러] AutoScaler - HPA | **완료** | `530.hpa/` |

전체 목록은 `0.tools/doc/list-articles.sh` 로 확인한다.

### 미실습으로 남은 것

| 대상 | 이유 | 필요한 조건 |
|---|---|---|
| 518 StorageClass·PV 실습 | Longhorn 설치·iscsi 사전조건은 완료. master 리소스 고갈로 중단. **2026-09-11 스케일 다운** | 복구 후 master RAM 증설 또는 master 스케줄링 차단 |
| 522 멀티 클러스터 | 두 번째 클러스터 필요 | `vagrant up` 으로 cluster-B 구축 |
| 526 브라우저 절차 | PC 인증서 설치·Chrome 확장 | 브라우저에서 직접 |

### 실습 환경에 남긴 변경

실습 과정에서 설치했다가 **되돌린** 것들이다. 다시 필요하면 각 문서를 참고한다.

| 대상 | 상태 | 재설치 |
|---|---|---|
| k9s | **설치됨** (`/usr/local/bin/k9s`) | [0.tools/k9s-install.md](0.tools/k9s-install.md) |
| Longhorn v1.5.0 | **설치돼 있으나 스케일 다운됨** (2026-09-11, 파드 0개, 볼륨 0개) | [부록) 로드밸런서 7-1](부록%29%20로드밸런서/metallb-설치와-원리.md) 로 복구 |
| MetalLB v0.14.8 | **설치됨** (`metallb-system`, L2 모드, 풀 `192.168.56.200-210`) | [부록) 로드밸런서](부록%29%20로드밸런서/metallb-설치와-원리.md) |
| iscsi-initiator-utils | **설치됨** (세 노드 모두, `iscsid` active/enabled) | [518/1.longhorn.md](518.dynamic-provisioning/1.longhorn.md) |
| 워커 SSH 키 인증 | **설정됨** (master → worker1·worker2, root) | 아래 「노드 접근」 |
| 저널 영속화 | **적용됨** (세 노드, `Storage=persistent` / `SystemMaxUse=200M`) | [부록) 트러블슈팅 6-3](부록%29%20트러블슈팅/마스터-리소스-고갈-apiserver-먹통.md) |
| Nginx Ingress Controller | 제거됨 | [529/1.nginx-controller.md](529.ingress/1.nginx-controller.md) |
| `fast` StorageClass, 수동 PV | 제거됨 | [528/2.persistentvolume.md](528.statefulset/2.persistentvolume.md) |
| 노드 라벨·taint | 모두 제거됨 | — |
| Python 3.9 | **설치됨** (master만, `dnf install python39`) | [0.tools/gsheet-service-account.md](0.tools/gsheet-service-account.md) |
| 구글 시트 연동 | **설정됨** (`/root/.gsheet/`, 서비스 계정 + gspread) | [0.tools/gsheet-service-account.md](0.tools/gsheet-service-account.md) |
| GitHub SSH 키 인증 | **설정됨** (`~/.ssh/id_ed25519_github`, origin이 SSH 리모트) | 아래 「노드 접근」 |
