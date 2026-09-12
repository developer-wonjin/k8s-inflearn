# ImagePullBackOff — 노드 시계가 틀어져 인증서 검증에 실패한 사례

- 발생일 : 2026-09-05
- 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대
- 증상 : 새로 생성된 Pod이 `ImagePullBackOff`
- 실제 원인 : 매니페스트가 아니라 **클러스터 전체 시계가 11시간 뒤처짐**
- 관련 실습 : [497 / 1-2 Deployment](../497.pod-container-label-nodeschedule/1-2.deployment.md)

## 실습 중이던 YAML

```bash
clear                          # 화면 정리 후 시작
kubectl apply -f - <<'END'     # deployment-1 — Deployment (replicas 1)
apiVersion: apps/v1            # Deployment는 apps 그룹의 v1
kind: Deployment               # 리소스 종류
metadata:
  name: deployment-1           # Deployment 이름
spec:
  replicas: 1                  # 유지할 Pod 개수
  selector:
    matchLabels:
      app: deploy              # 이 라벨을 가진 Pod을 관리
  template:
    metadata:
      labels:
        app: deploy            # 생성될 Pod에 붙을 라벨
    spec:
      containers:
      - name: container        # 컨테이너 이름
        image: kubetm/init     # ← 이 이미지를 pull 하다 실패했다
END
```

자가 복구를 확인하려고 Pod을 지운 것이 발단이었다.

```bash
clear                                             # 화면 정리 후 시작
kubectl delete pod deployment-1-65bcdc8d77-trl7k  # 자가 복구 확인용으로 Pod 삭제
```

```
pod "deployment-1-65bcdc8d77-trl7k" deleted
```

ReplicaSet이 새 Pod을 만들었는데, 그 Pod이 뜨지 않았다.

---

## 1. 증상 확인

```bash
clear                    # 화면 정리 후 시작
kubectl get pod -o wide  # 어느 노드에서 무슨 상태인지 확인
kubectl get deploy,rs    # Deployment가 왜 0/1 인지 확인
```

```
NAME                            READY   STATUS             RESTARTS   AGE     NODE
deployment-1-65bcdc8d77-m7tr5   0/1     ImagePullBackOff   0          2m10s   k8s-worker2

deployment.apps/deployment-1    0/1     1            0
replicaset.apps/...-65bcdc8d77  1       1        0
```

**이상한 점** — 같은 이미지(`kubetm/init`)로 조금 전까지 잘 돌던 Pod이었다.
매니페스트는 하나도 안 바꿨는데 새로 만든 것만 실패한다.

## 2. 원인 추적 — 이벤트를 본다

`ImagePullBackOff`는 결과일 뿐이고, **진짜 이유는 Events에 있다.**

```bash
clear                                                                     # 화면 정리 후 시작
kubectl describe pod deployment-1-65bcdc8d77-m7tr5 | grep -A12 '^Events'  # 실패 사유 원문 확인
```

```
Warning  Failed  kubelet  Failed to pull image "kubetm/init":
  failed to resolve reference "docker.io/kubetm/init:latest":
  failed to authorize: failed to fetch anonymous token:
  Get "https://auth.docker.io/token?...":
  x509: certificate has expired or is not yet valid:
  current time 2026-09-05T02:14:12+09:00 is before 2026-09-05T00:51:31Z
```

핵심은 마지막 줄이다.

| 값 | 의미 |
|---|---|
| `current time 2026-09-05T02:14:12+09:00` | 노드가 생각하는 현재 시각 (= 2026-09-04 17:14 UTC) |
| `is before 2026-09-05T00:51:31Z` | 인증서가 유효해지기 시작하는 시각 |

**"인증서가 만료됐다"가 아니라 "아직 유효 기간이 시작되지 않았다"** 는 쪽이다.
이건 상대방 인증서 문제가 아니라 **내 시계가 과거에 있다**는 신호다.

> `expired or is not yet valid` 는 두 경우를 한 문장으로 쓴다.
> 뒤의 `current time ... is before ...` 를 봐야 어느 쪽인지 구분된다.
> `is after` 면 진짜 만료, `is before` 면 시계가 느린 것이다.

## 3. 시계 확인

```bash
clear                                              # 화면 정리 후 시작
date -u                                            # 이 노드(master)가 생각하는 UTC
curl -sI http://www.google.com | grep -i '^date:'  # 실제 시각 (HTTP 헤더, TLS 미사용이라 시계와 무관)
timedatectl | grep -E 'Universal|synchronized'     # 동기화 상태
```

```
Fri Sep  4 17:16:57 UTC 2026                   ← 이 머신
Date: Sat, 05 Sep 2026 04:13:25 GMT            ← 실제
System clock synchronized: no
```

**약 11시간 뒤처져 있다.**

> 시각 비교에 `https`를 쓰면 안 된다. 시계가 틀어진 상태에서는 TLS 검증 자체가 실패해서
> 확인하려는 그 문제 때문에 확인이 막힌다. `http`로 받아 **Date 헤더**만 읽는다.

## 4. NTP는 왜 못 고쳤나

`NTP service: active` 인데도 동기화가 안 되고 있었다.

```bash
clear                         # 화면 정리 후 시작
chronyc sources -v | tail -6  # NTP 서버와 통신은 되는지
chronyc tracking              # chrony가 파악한 오차
```

```
^* ec2-3-39-176-65.ap-north>  2  6  377  80  -306us[-387us]     ← Reach 377 = 정상 통신
^- mail.innotab.com           2  6  377  20  +949us[+949us]

Ref time (UTC)  : Sat Sep 05 04:12:26 2026     ← chrony는 정확한 시각을 알고 있다
System time     : 39386.906250000 seconds slow of NTP time
```

- `Reach 377`(8진수, 8회 연속 성공) — 네트워크와 NTP 서버는 멀쩡하다.
- `Ref time`이 정확하다 — chrony는 진짜 시각을 **알고는 있다.**
- 그런데 `System time`이 **39386초(≈10시간 57분) 느리다.**

원인은 chrony의 기본 설정이다.

```
makestep 1.0 3      # 기동 후 3회까지만 시계를 '점프'시키고, 그 뒤로는 미세 조정(slew)만
```

slew는 초당 아주 조금씩만 당기므로 11시간을 따라잡는 데 사실상 무한한 시간이 걸린다.
**chrony는 오차를 알면서도 고치지 못하는 상태**였다.

## 5. 조치

```bash
clear                            # 화면 정리 후 시작
sudo chronyc makestep            # 시계를 즉시 정확한 시각으로 점프
timedatectl | grep synchronized  # synchronized: yes 가 되는지 확인
date -u                          # 실제 시각과 맞는지 대조
```

**세 노드 모두에서 실행해야 한다.** 시계가 서로 어긋난 게 아니라
셋 다 똑같이 11시간 느린 상태였기 때문에, master만 고치면 노드 간 시차가 생겨 더 나빠진다.

## 6. 노드별 시계를 한 번에 확인하는 방법

master에서 worker로 ssh가 안 되는 상황에서도, **kubectl만으로 각 노드의 시계를 볼 수 있다.**

```bash
clear                          # 화면 정리 후 시작
# 노드별 lease 갱신 시각 = 그 노드의 현재 시계 (줄이 길어 주석을 위로 뺌)
kubectl get lease -n kube-node-lease -o custom-columns='NODE:.metadata.name,RENEW:.spec.renewTime'
date -u '+%Y-%m-%dT%H:%M:%SZ'  # 비교 기준이 되는 master의 현재 시각
```

master만 고쳤을 때:

```
NODE          RENEW
k8s-master    2026-09-05T04:15:08Z      ← 맞음
k8s-worker1   2026-09-04T17:18:50Z      ← 11시간 느림
k8s-worker2   2026-09-04T17:18:55Z      ← 11시간 느림
```

세 노드 다 고친 뒤:

```
NODE          RENEW
k8s-master    2026-09-05T04:15:49Z
k8s-worker1   2026-09-05T04:15:44Z
k8s-worker2   2026-09-05T04:15:50Z      ← 초 단위로 일치
```

**왜 lease인가**

| 후보 | 갱신 주기 | 판단 |
|---|---|---|
| `.status.conditions[].lastHeartbeatTime` | 5분 | 너무 느려서 방금 고친 게 반영 안 됨 |
| **`lease.spec.renewTime`** | **10초** | **적합** |

lease는 각 노드의 kubelet이 **자기 시계로** 찍어 보내는 값이라,
노드에 접속하지 않고도 그 노드의 현재 시각을 알 수 있다.

## 7. 복구 확인

Pod을 다시 만들 필요가 없었다.

```bash
clear                      # 화면 정리 후 시작
kubectl get pod -o wide    # 상태가 돌아왔는지
kubectl get deploy,rs,pod  # Deployment까지 정상인지
```

```
NAME                            READY   STATUS    RESTARTS   AGE
deployment-1-65bcdc8d77-m7tr5   1/1     Running   0          11h

deployment.apps/deployment-1    1/1     1            1
```

`ImagePullBackOff` → `Running 1/1`, **`RESTARTS 0`**.
kubelet의 pull 재시도(backoff)가 시계를 고친 뒤 성공한 것이라
Pod을 삭제하거나 롤아웃을 다시 돌릴 필요가 없었다.

> `AGE`가 `11h`로 보이는 건 생성 시각이 틀어진 시계로 기록됐기 때문이다.
> 실제로는 방금 만든 Pod이다. 다음에 새로 만들면 정상 표기된다.

---

## 8. 재발 방지

`chronyc makestep`은 **일회성**이다.
VM을 일시정지했다 재개하거나 스냅샷에서 복원하면 또 뒤처진다.
실습용 VM이라면 chrony가 매번 알아서 점프하도록 바꿔두는 편이 낫다.

```bash
clear                                                           # 화면 정리 후 시작
sudo sed -i 's/^makestep .*/makestep 1.0 -1/' /etc/chrony.conf  # -1 = 횟수 제한 없이 항상 점프
sudo systemctl restart chronyd                                  # 설정 반영
chronyc tracking | grep 'System time'                           # 오차가 0에 가까운지 확인
```

| 설정 | 동작 |
|---|---|
| `makestep 1.0 3` (기본) | 기동 후 3회까지만 점프. 운영 중 벌어진 시차는 못 고침 |
| `makestep 1.0 -1` | 1초 이상 어긋나면 **언제든** 즉시 점프 |

> 운영 환경에서는 시계가 갑자기 뛰면 로그 순서나 인증서 판정이 꼬일 수 있어
> `-1`을 그대로 쓰지 않는다. VM을 자주 정지/재개하는 **실습 환경에 한정**된 설정이다.

---

## 정리

| 항목 | 내용 |
|---|---|
| 겉으로 드러난 증상 | `ImagePullBackOff` (이미지·매니페스트 문제처럼 보임) |
| 실제 원인 | 노드 시계가 11시간 느려 Docker Hub 인증서를 "아직 유효하지 않음"으로 판정 |
| 촉발 시점 | Docker Hub가 인증서를 갱신한 순간 (`notBefore 2026-09-05T00:51:31Z`) |
| worker1은 왜 멀쩡했나 | 이미지가 이미 캐시돼 있어 pull 자체가 필요 없었음 |
| 조치 | 세 노드 모두 `chronyc makestep` |
| 복구 | 자동 (kubelet backoff 재시도, RESTARTS 0) |

## 이번 건에서 얻은 판단 기준

1. **`ImagePullBackOff`는 원인이 아니라 결과다.** 반드시 `describe`의 Events 원문을 본다.
2. **`x509: ... expired or is not yet valid`가 보이면 시계부터 의심한다.**
   `is before`면 내 시계가 느린 것, `is after`면 진짜 만료다.
3. **시각 비교는 `http`로 한다.** `https`는 확인하려는 문제 때문에 막힌다.
4. **`chronyc tracking`의 `System time` 값을 본다.** NTP가 active여도 못 고치고 있을 수 있다.
5. **노드별 시계는 `kube-node-lease`의 `renewTime`으로 본다.** ssh 없이 확인된다.
6. **시계는 전 노드를 함께 맞춘다.** 일부만 고치면 노드 간 시차가 생겨 더 위험하다.

## 참고

- Chrony 문서 : https://chrony-project.org/documentation.html
- `man 5 chrony.conf` (makestep 항목)
- Images / imagePullPolicy : https://kubernetes.io/docs/concepts/containers/images/
- Node heartbeats (Lease) : https://kubernetes.io/docs/concepts/architecture/nodes/#heartbeats
