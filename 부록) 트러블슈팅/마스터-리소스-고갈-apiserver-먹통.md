# 마스터 리소스 고갈 — Longhorn 설치 중 apiserver 먹통

- 발생일 : 2026-09-06 01:12 ~ 01:29 (KST)
- 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대
- 증상 : `kubectl`이 응답하지 않음 → apiserver `connection refused`
- 실제 원인 : master 노드(4 vCPU / 3.81GiB)의 **리소스 고갈**. Longhorn 설치가 방아쇠
- 조치 : VM 재기동 (다만 **재기동 없이도 자체 복구되던 중**이었다 — 5절)
- 관련 실습 : [518 / 1. Longhorn 구축](../518.dynamic-provisioning/1.longhorn.md)

## 무엇을 하고 있었나

518 게시글 1절 「Longhorn 구축」. 문서에 *"이 절은 실습하지 않았다"*로 남겨뒀던 절을
다시 열어 실제로 진행하던 중이었다.

```bash
clear                                                                       # 화면 정리 후 시작
yum --setopt=tsflags=noscripts install -y iscsi-initiator-utils             # Longhorn 사전 조건
echo "InitiatorName=$(/sbin/iscsi-iname)" > /etc/iscsi/initiatorname.iscsi  # 고유 이니시에이터 이름
systemctl enable iscsid && systemctl start iscsid                           # 지금 시작 + 부팅 시 자동 시작
```

이어서 `longhorn-1.5.0.yaml`을 적용했고, **2분 뒤 클러스터가 멈췄다.**

## 1. 타임라인

| 시각 | 사건 |
|---|---|
| 09-05 22:10 | kubelet housekeeping 지연 첫 등장 (5.4초). **이미 빡빡했다는 신호** |
| 09-06 01:00:37 ~ 01:12:25 | 로그에 에러 **0건** — 정상 |
| 01:10:26 | 커널 `Loading iSCSI transport class v2.0-870` — iscsi 설치 |
| **01:12:26** | 첫 이상 : kubelet lease 갱신 실패, cadvisor partial failure |
| 01:12 ~ 01:14 | `kube-scheduler`·`kube-controller-manager`·`tigera-operator`·`calico-apiserver`×2 재생성 |
| 01:13:24 | Longhorn Pod들이 master에 배치되기 시작 |
| 01:19 | apiserver `TLS handshake timeout`, scheduler `CrashLoopBackOff` (백오프 1m20s) |
| **01:22:01** | apiserver 컨테이너 정지 → `connection refused` 100건. housekeeping **35.9초** |
| 01:23:13 | `kube-apiserver` Attempt:8로 재생성 → **응답 복구** |
| 01:26 | housekeeping **48.9초** (최악점) |
| 01:27 ~ 01:28 | 15.1초 → 13.8초 → 11.7초 → 14.6초 |
| 01:29 | **1.0초** — 정상 범위로 복귀 |
| 01:30 | VM 종료 (재기동은 22시간 뒤인 23:11) |

## 2. 조사 과정

### 2-1) 첫 벽 — 저널이 남아 있지 않다

```bash
clear                    # 화면 정리 후 시작
journalctl --list-boots  # 이전 부팅 로그가 있는지
ls -d /var/log/journal   # 영속 저널 디렉토리 존재 여부
```

```
 0 05bf01650c3149e5a43aea68cb328752 Sun 2026-09-06 23:11:08 KST—Sun 2026-09-06 23:12:35 KST
ls: cannot access '/var/log/journal': No such file or directory
```

**현재 부팅밖에 없다.** `/var/log/journal`이 없으면 저널은 tmpfs에 올라가고 재부팅 때 사라진다.
장애를 겪은 부팅의 `journalctl`은 이미 소실됐다.

→ 대신 rsyslog가 디스크에 남긴 `/var/log/messages`로 조사했다. 이 파일은 9/4 19:37부터
9/6 23:12까지를 담고 있어 장애 구간이 그대로 들어 있었다.

### 2-2) 장애 구간 좁히기

```bash
clear                                                                                                     # 화면 정리 후 시작
last -x | head -6                                                                                         # 종료·부팅 시각 확인
grep 'connection refused' /var/log/messages | grep -oE '^Sep +[0-9]+ [0-9]{2}:[0-9]{2}' | sort | uniq -c  # 분 단위 분포
```

```
shutdown system down  4.18.0-477.10.1. Sun Sep  6 01:30 - 23:11  (21:41)

     55 Sep  6 01:22
     45 Sep  6 01:23
```

apiserver가 실제로 거절한 것은 **01:22 ~ 01:23 두 분간**뿐이다.
그런데 체감 먹통은 더 길었다 — 그 앞뒤는 거절이 아니라 **응답 없음**이었기 때문이다.

### 2-3) 발단 시각 특정

```bash
clear                                                                                              # 화면 정리 후 시작
awk '/^Sep  6 01:00/,/^Sep  6 01:14/' /var/log/messages | grep -iE 'error|fail|timeout' | head -3  # 01시 첫 에러
```

```
Sep  6 01:12:26 ... E0906 cadvisor_stats_provider.go:442] "Partial failure issuing cadvisor.ContainerInfoV2"
Sep  6 01:12:26 ... E0906 controller.go:193] "Failed to update lease" err="Put .../leases/k8s-master?timeout=10s"
```

01:00:37부터 **01:12:25까지 에러가 한 건도 없다.** iscsi 로드(01:10:26) 직후,
Longhorn 적용 시점에 정확히 발단했다.

### 2-4) OOM은 범인이 아니었다

가장 먼저 의심한 것은 메모리였다.

```bash
clear                                                                                      # 화면 정리 후 시작
grep -E 'oom-kill:constraint' /var/log/messages | awk '{print $1,$2,$3}' | sort | uniq -c  # 커널 OOM 시각
grep -cE 'OOMKilled|exit status 137' /var/log/messages                                     # 컨테이너 OOM 종료 건수
```

```
      1 Sep 5 18:14:43
      1 Sep 5 18:14:45
      1 Sep 5 18:15:03
      1 Sep 5 18:15:31
      1 Sep 5 18:16:21
      1 Sep 5 18:17:55
0
```

- 커널 OOM 6건은 **전부 9/5 18시**, 대상은 `pod-oom` Pod(`tail /dev/zero`, memcg 100Mi 제한).
  501 게시글 LimitRange 실습에서 **일부러 만든 테스트**였고 이번 장애와 무관하다.
- 장애 구간인 9/6 01시에는 커널 OOM도, `OOMKilled`도, `exit 137`도 **0건**이다.

**즉 아무것도 kill 당하지 않았다.** 이 사실이 원인 판단을 바꿨다.

### 2-5) 진짜 증거 — housekeeping 36초

```bash
clear                                                                                                                               # 화면 정리 후 시작
grep 'Housekeeping took longer' /var/log/messages | grep -oE '^Sep +[0-9]+ [0-9]{2}:[0-9]{2}|actual="[0-9.]+s"' | paste - - | tail  # 지연 추이
```

```
Sep  6 01:22	actual="35.916s"
Sep  6 01:26	actual="48.895s"
Sep  6 01:27	actual="15.127s"
Sep  6 01:28	actual="14.636s"
Sep  6 01:29	actual="1.038s"
```

kubelet의 housekeeping은 **1초 주기**가 정상이다. 그것이 36초, 49초까지 밀렸다는 것은
kubelet이 CPU를 못 잡았다는 뜻 — **노드 자체가 얼어붙어 있었다.**

### 2-6) 디스크·커널은 멀쩡했다

```bash
clear                                                                                                # 화면 정리 후 시작
grep '^Sep  6' /var/log/messages | grep -iE 'blocked for more than|hung_task|I/O error|soft lockup'  # 커널 레벨 이상
```

hung task, I/O 에러, soft lockup **모두 0건**. 디스크나 커널 문제는 아니다.

### 2-7) 워커는 멀쩡했다 — 고갈은 master에만 있었다

여기까지는 master 로그만 본 것이라, "클러스터 전체 문제"인지 "master 국한"인지 아직 갈리지 않았다.
워커 2대에 SSH로 붙어 같은 항목을 확인했다.

```bash
clear  # 화면 정리 후 시작
for n in 31 32; do
  echo "### 192.168.56.$n"
  ssh root@192.168.56.$n "grep -c 'Housekeeping took longer' /var/log/messages"
done
```

| 항목 | master | worker1 | worker2 |
|---|---|---|---|
| 01:12~01:30 에러 | 다수 | 512건 | 511건 |
| **housekeeping 지연** | **36초·49초** | **0건** | **0건** |
| 커널 OOM (01시) | 0 | 0 | 0 |
| hung task / I/O 에러 / soft lockup | 0 | 0 | 0 |

**워커의 housekeeping 지연이 0건이다.** master가 같은 시각 36초·49초까지 밀린 것과 대비된다.
워커 kubelet은 정상 주기를 유지하고 있었다.

워커 에러 512건은 전부 **master를 향한 클라이언트 측 실패**였다.

```
"Failed to update lease" err="Put https://192.168.56.30:6443/.../leases/k8s-worker1: Client.Timeout"
"Error updating node status, will retry" err="error getting node k8s-worker1: Client.Timeout"
failed to list *v1.Service: net/http: TLS handshake timeout
```

즉 워커는 멀쩡히 돌면서 **apiserver에 못 닿았을 뿐**이다.
`longhorn-manager`가 worker1에서 CrashLoopBackOff 9건을 낸 것도 원인이 아니라 결과다.

이것으로 "클러스터 전체 문제"와 "네트워크 문제" 가설은 배제됐고,
**고갈이 master 한 대에 국한됐다**는 것이 확정됐다.

> 워커의 커널 OOM은 worker1 76건·worker2 10건이 있으나 전부 **9/5 18:34~20:52**이고
> 대상은 `tail` 프로세스 38건(`CONSTRAINT_MEMCG`)이다. 501 LimitRange 실습의
> `pod-oom` 테스트가 워커로도 퍼진 것으로, 이번 장애와 무관하다.

### 2-8) 조사 중 막혔던 것 — 워커에 접근할 수 없었다

장애 당시에는 워커에 SSH가 안 돼 위 확인을 하지 못했다. 원인 판단이 master 로그만으로
이뤄진 이유다. 사후에 접근을 열고서야 교차 검증이 됐다.

| 막힌 지점 | 실제 원인 |
|---|---|
| `Host key verification failed` (worker1) | `known_hosts` 미등록 → `ssh-keyscan`으로 해결 |
| `Permission denied (publickey,...)` | 워커에 공개키 미등록 |
| `ssh-copy-id`가 비밀번호 3회 거부 | 서버는 `PasswordAuthentication yes`. **비대화형 셸이라 프롬프트에 입력이 전달되지 않은 것** |

결국 VirtualBox 콘솔에서 각 워커에 공개키를 직접 심어 해결했다.

```bash
clear                                        # 화면 정리 후 시작
mkdir -p /root/.ssh && chmod 700 /root/.ssh  # 디렉토리 준비
cat >> /root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPMzeocsSGPglSClI612VqIZ6IWhqe2iOKzdwjt6Ucym k8s-master (k8s-inflearn)
EOF
chmod 600 /root/.ssh/authorized_keys         # 권한 조정
```

**교훈 : 노드 접근은 장애가 나기 전에 열어둬야 한다.** 장애 한복판에서 뚫으려 하면
비밀번호 입력조차 안 되는 상황을 만난다.


## 3. 원인 — master가 워커로도 쓰이고 있다

```bash
clear                                                                                                      # 화면 정리 후 시작
kubectl get node k8s-master -o jsonpath='{.spec.taints}'                                                   # taint 확인
kubectl get pods -A -o custom-columns='NODE:.spec.nodeName' --no-headers | sort | uniq -c                  # 노드별 Pod 수
kubectl get pods -n longhorn-system -o custom-columns='NODE:.spec.nodeName' --no-headers | sort | uniq -c  # Longhorn 분포
```

```
(taints: 빈 값)

     25 k8s-master
     12 k8s-worker1
     13 k8s-worker2

      8 k8s-master
      9 k8s-worker1
      9 k8s-worker2
```

master에 `NoSchedule` taint가 없어 **전체 50개 Pod 중 25개가 master에 몰려 있다.**
Longhorn Pod도 8개가 master에 올라갔다.

| master에 올라간 Longhorn Pod |
|---|
| `csi-attacher` / `csi-provisioner` / `csi-resizer` / `csi-snapshotter` |
| `engine-image-ei` / `instance-manager` / `longhorn-csi-plugin`(컨테이너 3개) / `longhorn-manager` |

여기에 제어평면(apiserver·etcd·scheduler·controller-manager) + Calico(5개) +
CoreDNS 2개 + Dashboard 2개 + metrics-server가 이미 얹혀 있었다.

### 워커에 여유가 더 많다

```bash
clear                                                          # 화면 정리 후 시작
free -m | head -2                                              # master
for n in 31 32; do ssh root@192.168.56.$n "free -m | head -2"; done  # worker
```

| 노드 | vCPU | 총 메모리 | **여유** | Pod 수 |
|---|---|---|---|---|
| master | 4 | 3903 MB | **1227 MB** | 25 |
| worker1 | 3 | 2960 MB | **1897 MB** | 12 |
| worker2 | 3 | 2960 MB | **1856 MB** | 13 |

총 메모리는 master가 가장 크지만 Pod을 25개 떠안아 **실제 여유는 가장 적다.**
워커가 각각 600MB 이상 더 남아 있다. 6-2의 근거가 이 표다.

### 요청량이 실제와 어긋나 있다

```bash
clear                                                                        # 화면 정리 후 시작
kubectl describe node k8s-master | sed -n '/Allocated resources/,/Events/p'  # 선언된 요청량
kubectl top node                                                             # 실제 사용량
```

```
  Resource   Requests     Limits
  cpu        1430m (35%)  0 (0%)
  memory     440Mi (11%)  340Mi (8%)

NAME          CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
k8s-master    265m         6%     2702Mi          71%
```

**선언 440Mi(11%) vs 실사용 2702Mi(71%).** 여섯 배 차이다.
스케줄러와 kubelet은 440Mi만 쓰는 노드로 알고 있으니
Longhorn Pod을 계속 배치했고, eviction 임계값도 발동하지 않았다.

## 4. 왜 OOMKilled가 안 찍혔나

제어평면 static Pod과 Calico·Longhorn Pod 대부분에 **memory limit이 없다.**
limit이 없으면 cgroup OOM killer가 걸리지 않는다.
노드 전체 메모리도 완전히 고갈되진 않아(스왑 0, 여유 약 1.2GiB) 커널 OOM도 안 걸렸다.

그래서 **kill 없이 경합만 심해지는** 상태가 됐다.

```
노드 CPU·메모리 경합
  → kubelet housekeeping 36초 지연
  → apiserver 응답 지연 (TLS handshake timeout)
  → scheduler·controller-manager가 apiserver를 잃고 CrashLoopBackOff
  → calico-apiserver liveness 실패 → 재시작 → 부하 가중
  → apiserver 컨테이너 정지 (01:22:01) → connection refused
```

**kill이 아니라 starvation(고갈)이다.** 로그에 OOM이 안 보인다고 메모리 문제가
아니라고 판단하면 안 되는 이유가 여기 있다.

## 5. 재기동은 필요했나

아니었다.

- 01:23:13 apiserver 재생성 → 응답 복구
- 01:29 housekeeping 1.038초 → 정상 범위

**01:29 시점에 이미 자체 복구가 끝나 있었다.** 01:30 종료는 1분 이른 판단이었다.
다만 결과적으로 상태를 깨끗이 정리한 것은 맞다.

## 6. 조치

효과가 큰 순서.

### 6-1) master RAM 증설 (가장 확실)

VirtualBox VM이므로 종료 후 `Vagrantfile`의 master 메모리를 8192으로 올린다.
재기동 직후 워크로드가 하나도 없는 상태에서 이미 71%를 쓰고 있어 **여유가 사실상 없다.**

### 6-2) master를 스케줄링 대상에서 빼기

```bash
clear                                                                            # 화면 정리 후 시작
kubectl taint node k8s-master node-role.kubernetes.io/control-plane=:NoSchedule  # 일반 Pod 배치 차단
```

- DaemonSet(Calico, kube-proxy)은 toleration이 있어 그대로 남는다. 정상이다.
- 이미 master에 떠 있는 Pod은 쫓겨나지 않는다. 재생성돼야 워커로 옮겨간다.
- **Longhorn만 빼려면** taint보다 Longhorn 쪽 설정이 안전하다.
  Longhorn UI → Node → `k8s-master`의 `allowScheduling`을 끈다.

> 주의 : 이 저장소의 실습들은 **master에 taint가 없다는 전제**로 쓰여 있다
> (CLAUDE.md 「클러스터 특이사항」). taint를 걸면 513 Node Scheduling 등
> 일부 실습의 Pod 분포가 문서와 달라진다.

### 6-3) 저널 영속화

이번 조사에서 가장 아쉬웠던 부분이다. 다음 장애 때는 `journalctl -b -1`을 쓸 수 있게 해둔다.

**세 노드 모두 비영속이다.** master뿐 아니라 worker1·worker2도 `/var/log/journal`이 없다.
어느 노드에서 장애가 나든 재부팅하면 증거가 사라진다.

```bash
clear                                                # 화면 정리 후 시작
mkdir -p /var/log/journal                            # 영속 저널 디렉토리 생성
systemd-tmpfiles --create --prefix /var/log/journal  # 권한·소유자 설정
systemctl restart systemd-journald                   # 적용
journalctl --list-boots                              # 이제부터 부팅별로 쌓인다
```

### 6-4) 하지 말 것

- **스왑을 켜지 않는다.** kubelet이 거부하고, 켜더라도 지연만 늘어난다. `Swap: 0`이 정상이다.

## 7. 재발 조건

Longhorn은 지금 볼륨이 0개인 상태로 겨우 떠 있다.

```bash
clear                                               # 화면 정리 후 시작
kubectl get pvc -A                                  # PVC 없음 확인
kubectl -n longhorn-system get volumes.longhorn.io  # 볼륨 없음 확인
free -m | head -2                                   # 여유 메모리
```

```
No resources found
No resources found

              total        used        free      shared  buff/cache   available
Mem:           3903        2404         136        20       1362        1227
```

**PVC를 만들어 볼륨을 attach하면 `instance-manager`가 볼륨별로 메모리를 더 쓴다.**
남은 1.2GiB로는 재발 가능성이 높다. 6-1 또는 6-2를 먼저 적용하고
518 2절(StorageClass)로 넘어가야 한다.

## 이번 건에서 얻은 판단 기준

- **`kubectl`이 안 되면 먼저 노드가 살아 있는지 본다.** apiserver 로그를 파기 전에
  `Housekeeping took longer than expected`를 찾는 편이 빠르다. 1초 주기가 밀렸다면
  그 노드는 얼어붙은 것이고, 그 위의 모든 증상은 결과일 뿐이다.
- **OOM 로그가 없다고 메모리 문제가 아닌 게 아니다.** limit이 없으면 kill이 안 걸린다.
  `kubectl top node`의 실사용과 `describe node`의 requests를 **함께** 봐야 한다.
- **증상 시각이 아니라 "에러가 0건이던 마지막 시각"을 찾는다.** 01:22의 `connection refused`가
  아니라 01:12:25(마지막 정상)와 01:12:26(첫 에러) 사이가 발단이었다.
- **커널 로그의 모듈 로드 한 줄이 타임라인을 확정해준다.** `Loading iSCSI transport class`가
  없었다면 "Longhorn 설치 중"이라는 연결을 증명하기 어려웠다.
- **저널은 기본이 비영속이다.** 장애를 겪고 재부팅하면 증거가 사라진다. 미리 켜둔다.

## 참고

- 원문 : https://cafe.naver.com/kubeops/518 (1. Longhorn 구축)
- Longhorn 하드웨어 요구사항 : https://longhorn.io/docs/1.5.0/best-practices/
- 같은 클러스터의 다른 장애 : [시계 불일치 ImagePullBackOff](시계-불일치-ImagePullBackOff.md)

## 조사 이력

| 시점 | 범위 |
|---|---|
| 2026-09-06 23:1x | master 로그만으로 1차 진단 (1~7절) |
| 2026-09-06 23:3x | 워커 SSH 확보 후 교차 검증 (2-7, 2-8절) — **master 국한 확정** |
