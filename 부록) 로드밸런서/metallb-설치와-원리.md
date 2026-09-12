# MetalLB — 베어메탈에서 LoadBalancer를 쓰는 법

- 설치일 : 2026-09-11
- 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / Calico VXLAN
- 버전 : MetalLB **v0.14.8** (L2 모드)
- 관련 실습 : [498. Service - LoadBalancer](../498.service-clusterip-nodeport-loadbalancer/3.loadbalancer.md)

> [3.loadbalancer.md](../498.service-clusterip-nodeport-loadbalancer/3.loadbalancer.md)에서
> `EXTERNAL-IP`가 `<pending>`으로 멈췄던 이유를 해결한 기록.
> **왜 필요한가 → 어떤 원리인가 → 어떻게 설치하는가** 순서로 정리했다.

---

## 1. 배경 — 왜 pending에서 멈추나

### 1-1) `type: LoadBalancer`는 "요청서"다

쿠버네티스는 로드밸런서를 **직접 만들지 않는다.** Service에 `type: LoadBalancer`를 적으면
"누가 이 서비스 앞에 IP 하나 붙여 달라"는 **요청을 API에 걸어두는 것**뿐이다.

그 요청을 실제로 처리하는 주체는 클러스터 밖에 있다.

| 환경 | 요청을 처리하는 주체 | 결과 |
|---|---|---|
| GCP / AWS / Azure | 클라우드 컨트롤러 매니저 | 클라우드 LB가 생기고 공인 IP가 붙는다 |
| 베어메탈 / VM 직접 구축 | **없음** | 아무도 안 받아서 `<pending>` 영구 대기 |

이 클러스터는 VirtualBox VM 3대를 직접 묶은 것이라 그 주체가 없었다.
**에러가 아니라 처리할 사람이 없는 상태**였다.

### 1-2) MetalLB가 그 빈자리를 채운다

MetalLB는 **베어메탈 클러스터용 LoadBalancer 구현체**다. 하는 일은 딱 두 가지다.

```
1) 주소 할당   대기 중인 Service를 보고, 미리 정해둔 IP 풀에서 하나를 골라 EXTERNAL-IP에 박는다
2) 주소 광고   "그 IP는 여기 있다"고 네트워크에 알려, 트래픽이 클러스터로 들어오게 한다
```

두 가지를 **두 개의 컴포넌트**가 나눠 맡는다.

| 컴포넌트 | 형태 | 역할 |
|---|---|---|
| `controller` | Deployment (1개) | IP 풀 관리와 **할당**. Service를 보고 EXTERNAL-IP를 정한다 |
| `speaker` | DaemonSet (노드마다 1개) | 할당된 IP를 **광고**. 실제 트래픽을 끌어온다 |

### 1-3) 광고 방식이 두 가지 — L2 와 BGP

| 모드 | 광고 방법 | 필요 조건 | 이 문서 |
|---|---|---|---|
| **L2 (ARP/NDP)** | "이 IP의 MAC은 나다"라고 ARP 응답 | **같은 L2 네트워크**면 끝. 장비 설정 불필요 | **이걸 쓴다** |
| BGP | 라우터와 BGP 피어링해 경로를 광고 | BGP를 말하는 라우터 필요 | 가정/실습 환경엔 과하다 |

VirtualBox 호스트 전용 네트워크(`192.168.56.0/24`)에 노드 3대가 같이 물려 있으므로

### 1-4) EXTERNAL-IP는 "공인 IP"라는 뜻이 아니다

`EXTERNAL-IP`에 사설 IP(`192.168.56.200`)가 붙는 것을 보고 **설정이 덜 된 건 아닌지**
의심하기 쉽다. 아니다. 여기서 `EXTERNAL`은 **인터넷**이 아니라
**클러스터 바깥**을 가리킨다. 기준선은 Pod 네트워크·ClusterIP 대역이다.

| 이름 | 닿는 범위 | 이 클러스터의 값 |
|---|---|---|
| Pod IP | 클러스터 안 | `20.96.0.0/12` |
| ClusterIP | 클러스터 안 (실재하지 않는 규칙) | `10.96.0.0/12` |
| **EXTERNAL-IP** | **클러스터 밖 = 노드가 물린 네트워크** | `192.168.56.200` |

클라우드에서 공인 IP가 붙는 건 **클라우드 LB가 원래 인터넷 대면용 장비**라서지,
`type: LoadBalancer`의 규격이 공인 IP를 요구해서가 아니다. 같은 클라우드에서도
내부용 LB(`service.beta.kubernetes.io/aws-load-balancer-internal` 등)를 요청하면
VPC 사설 IP가 붙는다. **어느 쪽이든 Service 입장에서는 똑같은 EXTERNAL-IP다.**

오히려 L2 모드에서는 **사설 IP가 아니면 동작하지 않는다.** 광고 수단이 ARP라
풀의 IP가 노드와 같은 서브넷에 있어야 하기 때문이다 ([3-1](#3-1-ip-풀로-쓸-대역-고르기)).
공인 IP 대역을 풀에 적어 넣으면 할당은 되지만 ARP가 닿지 않아 아무도 찾아오지 못한다.

실제로 IP가 붙고 통신까지 되는지는 이렇게 확인한다.

```bash
clear                                                       # 화면 정리 후 시작
kubectl get svc svc-4 -o wide                               # EXTERNAL-IP 가 붙었는지
kubectl get endpoints svc-4                                 # 뒤에 Pod 이 실제로 물려 있는지
kubectl describe svc svc-4 | tail -5                        # MetalLB 가 할당·광고한 이벤트
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.56.200:9000/  # 통신 확인
```

```
NAME    TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
svc-4   LoadBalancer   10.106.176.66   192.168.56.200   9000:30359/TCP   36m

NAME    ENDPOINTS                               AGE
svc-4   20.100.194.93:8080,20.110.126.37:8080   36m

Events:
  Type    Reason        Age                From                Message
  Normal  IPAllocated   36m                metallb-controller  Assigned IP ["192.168.56.200"]
  Normal  nodeAssigned  31m (x2 over 34m)  metallb-speaker     announcing from node "k8s-worker2" with protocol "layer2"

HTTP 200
```

`IPAllocated` + `nodeAssigned` 이벤트가 둘 다 있고 `curl`이 응답하면 **정상이다.**
`<pending>`에서 멈추거나, IP는 붙었는데 `nodeAssigned`가 없는 경우만 문제다.

#### 그래도 한계는 있다 — 어디까지 닿느냐

사설 IP라는 사실 자체는 문제가 아니지만, **닿는 범위는 그 네트워크까지**다.

| 출발지 | `192.168.56.200:9000` 접근 | 이유 |
|---|---|---|
| 클러스터 노드 3대 | 된다 (위에서 확인) | 같은 L2 |
| 호스트 PC (`192.168.56.1`) | 된다 (여기서는 미검증) | 호스트 전용 네트워크에 함께 물려 있어 ARP가 닿는다 |
| 같은 사무실 다른 PC | **안 된다** | 호스트 전용 네트워크는 호스트 PC 밖으로 나가지 않는다 |
| 인터넷 | **안 된다** | 사설 대역이라 라우팅되지 않는다 |

진짜로 바깥에 공개해야 한다면 MetalLB가 할 일이 아니다.
**공인 IP를 가진 앞단 장비**(공유기 포트포워딩, 클라우드 NAT, 리버스 프록시)가
`192.168.56.200`으로 넘겨주도록 따로 구성해야 한다.
**L2 모드의 전제가 이미 충족**돼 있다.

---

## 2. 원리 — L2 모드는 어떻게 동작하나

### 2-1) 핵심은 ARP 한 줄

IP 통신을 하려면 상대의 MAC 주소를 알아야 하고, 그걸 묻는 게 ARP다.

```
[클라이언트] "192.168.56.200 쓰는 사람 누구야?"   (ARP 요청, 브로드캐스트)
       ↓
[speaker]   "나야. 내 MAC은 08:00:27:59:25:3e"   (ARP 응답)
       ↓
[클라이언트] → worker2의 NIC로 프레임 전송
       ↓
[kube-proxy] → iptables 규칙으로 pod-1 / pod-2 에 분배
```

`192.168.56.200`이라는 IP는 **어느 NIC에도 설정돼 있지 않다.** speaker가 ARP에 거짓말로
응답해서 트래픽을 자기 노드로 끌어오는 것이다. 그래서 L2 모드를 **ARP 스푸핑을 정당하게 쓰는 것**
이라고 설명하기도 한다.

### 2-2) 반드시 알아야 할 한계 — 로드밸런싱이 아니라 페일오버다

이름이 로드밸런서지만, **L2 모드에서 노드 분산은 일어나지 않는다.**

- 하나의 EXTERNAL-IP는 **항상 한 노드**만 광고한다 (ARP 응답자가 둘이면 충돌하니까)
- 그 노드로 들어온 트래픽을 **kube-proxy가 Pod 단위로 분산**한다
- 광고 노드가 죽으면 **다른 speaker가 이어받는다** → 이게 L2 모드가 주는 가용성

```
        [ 모든 트래픽 ]
              ↓
        worker2 (광고 중)          ← 대역폭이 이 노드 하나에 몰린다
              ↓
   kube-proxy가 여기서 분산
        ↓           ↓
      pod-1       pod-2
```

즉 **입구는 1노드, 분산은 Pod 단위**다. 노드 대역폭을 합치고 싶으면 BGP 모드를 써야 한다.

### 2-3) Service 타입 포함 관계에서의 위치

MetalLB는 NodePort를 **대체하지 않는다.** 그 위에 얹힌다.

```
ClusterIP    ─ 클러스터 내부 전용
   ↑ 포함
NodePort     ─ ClusterIP + 모든 노드의 30000~32767 포트
   ↑ 포함
LoadBalancer ─ NodePort + 외부 IP 하나          ← MetalLB가 이 IP를 만들어 준다
```

설치 후에도 `9000:31216/TCP`처럼 NodePort는 그대로 남아 있다.

---

## 3. 설치 전 준비

### 3-1) IP 풀로 쓸 대역 고르기

가장 중요한 결정이다. 규칙은 두 가지다.

- **노드와 같은 L2 네트워크(같은 서브넷)여야 한다.** 다른 대역을 적으면 ARP가 닿지 않는다
- **아무도 안 쓰는 IP여야 한다.** 노드 IP·게이트웨이·DHCP 대역과 겹치면 충돌한다

이 환경의 `192.168.56.0/24` 사용 현황을 먼저 확인했다.

```bash
clear                   # 화면 정리 후 시작
ip -4 addr show eth1    # 노드가 물린 대역 확인 (192.168.56.30/24)
ip neigh show dev eth1  # 이미 쓰이는 IP 목록
for i in $(seq 200 210); do ping -c1 -W1 192.168.56.$i >/dev/null 2>&1 && echo "$i 사용중" || echo "$i 비었음"; done
```

```
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.56.30/24 brd 192.168.56.255 scope global noprefixroute eth1

192.168.56.1  lladdr 0a:00:27:00:00:08 REACHABLE   ← 호스트 PC
192.168.56.31 lladdr 08:00:27:77:9e:1a REACHABLE   ← worker1
192.168.56.32 lladdr 08:00:27:59:25:3e REACHABLE   ← worker2

200 비었음 ~ 210 비었음
```

| 항목 | 값 |
|---|---|
| 노드 대역 | `192.168.56.0/24` (VirtualBox 호스트 전용 네트워크) |
| 이미 쓰는 IP | `.1` 호스트 PC / `.30` master / `.31` worker1 / `.32` worker2 |
| **고른 풀** | **`192.168.56.200 ~ 192.168.56.210`** (11개) |

### 3-2) kube-proxy 모드 확인 — IPVS면 추가 설정이 필요하다

kube-proxy가 **IPVS 모드**면 `strictARP: true`로 바꿔야 한다.
안 그러면 모든 노드가 ARP에 응답해 버려 MetalLB가 동작하지 않는다.

```bash
clear  # 화면 정리 후 시작
kubectl get cm kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep -E '^mode|strictARP'
```

```
  strictARP: false
mode: ""
```

`mode: ""` 는 **기본값인 iptables 모드**다. iptables 모드는 `strictARP`가 필요 없으므로
**이 클러스터는 추가 설정 없이 진행**했다.

> IPVS 모드였다면 아래를 실행해야 한다.
>
> ```bash
> clear
> kubectl get cm kube-proxy -n kube-system -o yaml | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
> ```

---

## 4. 설치

### 4-1) 매니페스트 적용

Helm 없이 공식 단일 매니페스트를 쓴다.

```bash
clear                                                  # 화면 정리 후 시작
curl -sfLO https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
grep -c '' metallb-native.yaml                         # 1985줄
grep -E '^kind:' metallb-native.yaml | sort | uniq -c  # 무엇이 들어있는지 먼저 본다
kubectl apply -f metallb-native.yaml                   # 적용
```

```
      7 kind: CustomResourceDefinition      ← IPAddressPool, L2Advertisement 등
      2 kind: ClusterRole
      1 kind: DaemonSet                     ← speaker
      1 kind: Deployment                    ← controller
      1 kind: ValidatingWebhookConfiguration
      ...

namespace/metallb-system created
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created
```

### 4-2) 파드가 뜨는지 확인

```bash
clear                                      # 화면 정리 후 시작
kubectl get pod -n metallb-system -o wide  # controller 1개 + speaker 노드수만큼
```

```
NAME                         READY   STATUS    RESTARTS   AGE    IP              NODE
controller-5d98f447f-kvnmx   1/1     Running   0          2m7s   20.110.126.28   k8s-worker2
speaker-b7cqp                1/1     Running   0          2m7s   192.168.56.32   k8s-worker2
speaker-m8gvg                1/1     Running   0          2m7s   192.168.56.30   k8s-master
speaker-tr5rd                1/1     Running   0          2m7s   192.168.56.31   k8s-worker1
```

**speaker의 IP가 Pod IP가 아니라 노드 IP다.** `hostNetwork: true`로 뜨기 때문이고,
노드의 NIC에서 직접 ARP를 주고받아야 하니 당연한 설정이다.

> **speaker가 잠깐 0/1 로 보이는 건 정상이다.**
> speaker는 `memberlist`라는 Secret을 마운트하는데, 이 Secret은 **매니페스트에 없다.**
> controller가 뜬 뒤에 자동으로 만들어 주므로, 그 전까지 speaker는 기다린다.
>
> ```bash
> clear
> kubectl get secret -n metallb-system
> ```
>
> ```
> NAME                   TYPE     DATA   AGE
> memberlist             Opaque   1      101s   ← controller가 자동 생성
> metallb-webhook-cert   Opaque   4      5m4s
> ```

### 4-3) IP 풀과 광고 설정 — 이걸 안 하면 아무 일도 안 일어난다

설치만으로는 IP가 붙지 않는다. **어떤 대역을, 어떤 방식으로 쓸지**를 CR로 알려줘야 한다.

```bash
clear                                        # 화면 정리 후 시작
kubectl apply -f - <<'END'                   # lab-pool — IPAddressPool
apiVersion: metallb.io/v1beta1
kind: IPAddressPool                          # 1) 쓸 IP 대역
metadata:
  name: lab-pool
  namespace: metallb-system                  # 반드시 metallb-system 에 만든다
spec:
  addresses:
  - 192.168.56.200-192.168.56.210            # 범위 표기. 192.168.56.200/30 같은 CIDR도 된다
END
```

```bash
clear                                        # 화면 정리 후 시작
kubectl apply -f - <<'END'                   # lab-l2 — L2Advertisement
apiVersion: metallb.io/v1beta1
kind: L2Advertisement                        # 2) 그 대역을 L2(ARP)로 광고하라
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool                                 # 위 풀을 지목. 생략하면 모든 풀이 대상
END
```

```bash
clear                                                        # 화면 정리 후 시작
kubectl apply -f - <<'END'                                   # 위 YAML 두 개를 한 번에 적용
# ... IPAddressPool + L2Advertisement YAML ...
END

kubectl get ipaddresspool,l2advertisement -n metallb-system  # 등록 확인
```

```
NAME                                AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/lab-pool   true          false             ["192.168.56.200-192.168.56.210"]

NAME                                IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/lab-l2   ["lab-pool"]
```

- `AUTO ASSIGN true` : 풀을 지정하지 않은 Service에도 이 풀에서 자동으로 준다
- `L2Advertisement`를 빠뜨리면 **IP는 할당되지만 통신은 안 된다.** 할당과 광고가 별개라서다

---

## 5. 검증

### 5-1) pending 이던 Service에 IP가 붙는다

`3.loadbalancer.md`에서 만든 `svc-4`를 **그대로 둔 채로** 위 설정을 적용했다.

```bash
clear                  # 화면 정리 후 시작
kubectl get svc svc-4  # EXTERNAL-IP 확인
```

```
NAME    TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)          AGE
svc-4   LoadBalancer   10.108.121.230   192.168.56.200   9000:31216/TCP   28m
```

`<pending>` → `192.168.56.200`. **Service를 다시 만들 필요가 없었다.**
MetalLB controller가 대기 중이던 요청을 뒤늦게 집어간 것이다.

### 5-2) 실제로 통신되고, Pod 단위로 분산된다

```bash
clear  # 화면 정리 후 시작
for i in 1 2 3 4; do curl -s 192.168.56.200:9000/hostname; echo; done
```

```
Hostname : pod-1
Hostname : pod-2
Hostname : pod-1
Hostname : pod-2
```

노드 IP도 NodePort도 아닌 **전용 IP 하나**로 접근된다. 분산은 kube-proxy가 한다.

### 5-3) 검증: ARP 응답이 진짜 그 노드에서 오는가

원리가 맞는지 확인하는 가장 확실한 방법이다. **MetalLB가 지목한 노드의 MAC과
ARP 테이블의 MAC이 같아야 한다.**

```bash
clear                                                                  # 화면 정리 후 시작
kubectl describe svc svc-4 | tail -4                                   # 어느 노드가 광고 중인지
ip neigh show 192.168.56.200 dev eth1                                  # 그 IP가 어느 MAC으로 해석되는지
ip link show eth1 | awk '/ether/{print $2}'                            # master의 MAC
ssh root@192.168.56.32 "ip link show eth1 | awk '/ether/{print \$2}'"  # worker2의 MAC
```

```
Events:
  Normal  IPAllocated   15s   metallb-controller  Assigned IP ["192.168.56.200"]
  Normal  nodeAssigned  15s   metallb-speaker     announcing from node "k8s-worker2" with protocol "layer2"

192.168.56.200 lladdr 08:00:27:59:25:3e STALE

master  : 08:00:27:cf:d5:cb
worker2 : 08:00:27:59:25:3e          ← 일치
```

`192.168.56.200`은 **어느 노드에도 설정되지 않은 IP인데** worker2의 MAC으로 해석된다.
speaker가 ARP에 응답하고 있다는 직접 증거다.

### 5-4) 검증: 광고 노드가 죽으면 넘어가는가 (페일오버)

L2 모드가 주는 유일한 가용성이므로 반드시 확인할 값어치가 있다.
worker2의 speaker를 지우고 무중단으로 넘어가는지 봤다.

```bash
clear                                                                # 화면 정리 후 시작
kubectl delete pod -n metallb-system speaker-b7cqp --grace-period=1  # 광고 중인 노드의 speaker 제거
for i in 1 2 3; do curl -s --max-time 3 192.168.56.200:9000/hostname; echo; sleep 8; done
ip neigh show 192.168.56.200 dev eth1                                # MAC이 바뀌었는지
```

```
23:07:50  announcing from node "k8s-worker1" with protocol "layer2"   | Hostname : pod-1
23:08:13  announcing from node "k8s-worker1" with protocol "layer2"   | Hostname : pod-2
23:08:27  announcing from node "k8s-worker1" with protocol "layer2"   | Hostname : pod-1

192.168.56.200 lladdr 08:00:27:77:9e:1a STALE      ← worker1의 MAC으로 교체
```

**worker2 → worker1로 넘어갔고 curl은 한 번도 실패하지 않았다.**
새 speaker가 Gratuitous ARP를 보내 "이제 내 MAC이다"라고 갱신시키기 때문이다.

### 5-5) 검증: 여러 Service는 어떻게 나뉘나

LoadBalancer Service를 2개 더 만들어 봤다.

```bash
clear            # 화면 정리 후 시작
kubectl get svc  # 풀에서 순서대로 배정된다
kubectl get events -A --field-selector reason=nodeAssigned -o custom-columns=SVC:.involvedObject.name,MSG:.message --no-headers | tail -3
```

```
NAME    TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)
svc-4   LoadBalancer   10.108.121.230   192.168.56.200   9000:31216/TCP
svc-5   LoadBalancer   10.107.210.36    192.168.56.201   9000:30127/TCP
svc-6   LoadBalancer   10.107.186.213   192.168.56.210   9000:32103/TCP

svc-4   announcing from node "k8s-worker2" with protocol "layer2"
svc-5   announcing from node "k8s-worker1" with protocol "layer2"
svc-6   announcing from node "k8s-worker2" with protocol "layer2"
```

- IP는 풀의 **앞에서부터 순서대로** 배정된다 (`.200` → `.201`)
- **Service마다 광고 노드가 다르다.** 서비스 단위로는 노드가 분산된다
  (5-2의 한계는 "**하나의** Service가 한 노드에 묶인다"는 뜻이다)

### 5-6) 특정 IP를 지정하려면 — 도메인을 틀리면 조용히 무시된다

`svc-6`에 `.210`을 고정으로 요청했다. **여기서 한 번 헛짚었다.**

```bash
clear                  # 화면 정리 후 시작
# 공식 문서에서 흔히 보이는 metallb.io 도메인 — v0.14.8에서는 먹히지 않았다
kubectl get svc svc-6  # .210 을 요청했으나 .202 가 배정됨
```

```
NAME    TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
svc-6   LoadBalancer   10.109.142.84   192.168.56.202   9000:31809/TCP
```

`metallb.io/loadBalancerIPs` 어노테이션은 **에러도 경고도 없이 무시**되고 자동 배정이 됐다.
이 버전이 읽는 도메인은 `metallb.universe.tf` 다.

```bash
clear                                                     # 화면 정리 후 시작
kubectl apply -f - <<'END'                                # svc-6 — Service (LoadBalancer)
apiVersion: v1
kind: Service
metadata:
  name: svc-6
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.56.210   # v0.14.8은 이 도메인을 읽는다
spec:                                                     # metallb.io/... 는 무시된다
  selector:
    app: pod
  ports:
  - port: 9000
    targetPort: 8080
  type: LoadBalancer
END
```

```bash
clear                  # 화면 정리 후 시작
kubectl get svc svc-6  # 다시 확인
```

```
NAME    TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)
svc-6   LoadBalancer   10.107.186.213   192.168.56.210   9000:32103/TCP
```

> `spec.loadBalancerIP` 필드는 쿠버네티스에서 **deprecated**라 어노테이션을 쓴다.
> 도메인이 헷갈리면 `kubectl get svc <이름> -o jsonpath='{.metadata.annotations}'`로
> `metallb.universe.tf/ip-allocated-from-pool`이 붙었는지 보면 된다.
> **MetalLB가 실제로 쓰는 도메인이 그쪽임을 알려주는 단서**다.

---

## 6. 설치 중 만난 장애 — 파드가 아예 안 만들어졌다

매니페스트를 적용했는데 **Deployment와 DaemonSet만 생기고 Pod이 0개**였다.

```bash
clear                                    # 화면 정리 후 시작
kubectl get deploy,ds -n metallb-system  # DESIRED가 0이다
kubectl get pod -n metallb-system        # 아무것도 없다
```

```
deployment.apps/controller   0/1   0   0   81s
daemonset.apps/speaker       0     0   0   0   0   61s

No resources found in metallb-system namespace.
```

ReplicaSet과 DaemonSet Pod을 만드는 건 **kube-controller-manager**다. 거기를 봤다.

```bash
clear  # 화면 정리 후 시작
kubectl get pod -n kube-system | grep controller-manager
kubectl logs -n kube-system kube-controller-manager-k8s-master --previous | tail -3
```

```
kube-controller-manager-k8s-master   0/1   CrashLoopBackOff   28 (2m20s ago)   48d

E leaderelection.go:364] Failed to update lock: Put ".../leases/kube-controller-manager?timeout=5s": context deadline exceeded
I leaderelection.go:280] failed to renew lease kube-system/kube-controller-manager: timed out waiting for the condition
E controllermanager.go:300] "leaderelection lost"
```

**MetalLB 때문이 아니었다.** [부록) 트러블슈팅 - 마스터 리소스 고갈](../부록%29%20트러블슈팅/마스터-리소스-고갈-apiserver-먹통.md)에
기록된 문제가 계속되고 있었던 것이다. master 여유 메모리가 부족해 apiserver 응답이 밀리고,
controller-manager가 5초 안에 리더 리스를 갱신하지 못해 스스로 종료하는 악순환이었다.

### 조치 — Longhorn을 잠시 내렸다

master에 무엇이 메모리를 쓰는지 실측했다 (metrics-server도 죽어 있어 `crictl`을 썼다).

```bash
clear                # 화면 정리 후 시작
crictl stats         # 컨테이너별 메모리
free -m | sed -n 2p  # 노드 여유
```

| 컨테이너 | 메모리 | 비고 |
|---|---|---|
| kube-apiserver | 695.7MB | 줄일 수 없다 |
| calico-node | 146.6MB | CNI, 필수 |
| **longhorn-manager** | **125.8MB** | master의 Longhorn 8개 파드 합계 **약 253MB** |
| MetalLB speaker | 31.2MB | **가볍다** |

Longhorn은 **볼륨 0개**로 떠 있기만 한 상태였다(518 실습이 중단된 채였다). 이걸 내렸다.

```bash
clear                                               # 화면 정리 후 시작
kubectl get pvc -A                                  # 볼륨이 정말 없는지 먼저 확인 — 데이터 손실 방지
kubectl -n longhorn-system get volumes.longhorn.io  # 둘 다 No resources found 여야 한다

# DaemonSet은 삭제하지 않고, 존재하지 않는 라벨로 묶어 비운다 (되돌리기 쉽다)
for ds in longhorn-manager longhorn-csi-plugin engine-image-ei-d911131c; do
  kubectl -n longhorn-system patch ds $ds \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"longhorn-scaled-down":"true"}}}}}'
done

kubectl -n longhorn-system scale deploy \
  longhorn-driver-deployer \
  longhorn-ui \
  csi-attacher \
  csi-provisioner \
  csi-resizer \
  csi-snapshotter \
  --replicas=0

# controller-manager가 죽어 있으면 스케일 다운이 진행되지 않는다. 파드를 직접 지운다
kubectl delete pod -n longhorn-system --all --grace-period=10
```

> **`kubectl scale`은 controller-manager가 살아 있어야 반영된다.**
> 그게 죽어서 생긴 문제를 그걸로 고치려니 순환이 생긴다.
> `kubectl delete pod`은 kubelet이 직접 처리하므로 controller-manager 없이도 동작한다.
> DaemonSet의 `nodeSelector`를 먼저 바꿔둔 덕에 파드가 되살아나지도 않았다.

```
              total        used        free      shared  buff/cache   available
Mem:           3903        2648         147           3        1107         998    ← 650 → 998Mi
```

여유가 **650Mi → 998Mi**로 늘자 controller-manager가 살아났고, MetalLB 파드도 정상 생성됐다.

```
23:17:23  cm=false/31   ep(svc-5)=[]
23:17:43  cm=true/31    ep(svc-5)=[]                                      ← Ready 회복
23:18:03  cm=true/31    ep(svc-5)=[20.100.194.76:8080,20.110.126.24:8080] ← Endpoints 채워짐
```

> **Endpoints가 비어 있으면 MetalLB를 의심하기 전에 controller-manager를 본다.**
> EXTERNAL-IP는 붙는데(MetalLB controller의 일) 통신만 안 되면(Endpoints는 kube-controller-manager의 일),
> 두 컨트롤러 중 어느 쪽이 죽었는지가 바로 갈린다.

---

## 7. 되돌리기

### 7-1) Longhorn 복구 (518 실습을 재개할 때)

```bash
clear                               # 화면 정리 후 시작
for ds in longhorn-manager longhorn-csi-plugin engine-image-ei-d911131c; do
  kubectl -n longhorn-system patch ds $ds \
    -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
done

kubectl -n longhorn-system scale deploy longhorn-driver-deployer longhorn-ui --replicas=1
kubectl -n longhorn-system scale deploy csi-attacher csi-provisioner csi-resizer csi-snapshotter --replicas=3

kubectl get pod -n longhorn-system  # 전부 Running 될 때까지 기다린다
```

> 되돌리면 master 여유가 다시 650Mi대로 떨어져 **controller-manager가 또 불안정해질 수 있다.**
> 518을 재개하려면 트러블슈팅 문서의 6-1(RAM 증설) 또는 6-2(master 스케줄링 차단)를 먼저 적용하는 편이 낫다.

### 7-2) MetalLB 제거

```bash
clear            # 화면 정리 후 시작
kubectl delete l2advertisement lab-l2 -n metallb-system --ignore-not-found
kubectl delete ipaddresspool lab-pool -n metallb-system --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

kubectl get svc  # LoadBalancer가 다시 <pending>으로 돌아간다
```

- **CR(IPAddressPool·L2Advertisement)을 먼저 지운다.** 네임스페이스를 통째로 지우면
  ValidatingWebhook이 남아 삭제가 멈출 수 있다.
- 기존 LoadBalancer Service는 지워지지 않고 `EXTERNAL-IP`만 `<pending>`으로 되돌아간다.

---

## 8. 한 줄 정리

| 질문 | 답 |
|---|---|
| EXTERNAL-IP가 사설 IP인데 | **정상이다.** `EXTERNAL`은 인터넷이 아니라 **클러스터 밖**이라는 뜻. L2 모드는 오히려 사설이어야 동작 |
| 왜 `<pending>`이었나 | `type: LoadBalancer`는 요청서일 뿐, 처리할 주체가 베어메탈엔 없어서 |
| MetalLB가 하는 일 | `controller`가 IP를 **할당**하고, `speaker`가 ARP로 **광고**한다 |
| 왜 두 컴포넌트인가 | 할당은 클러스터 전체에 하나면 되고, 광고는 노드마다 필요해서 |
| 설치만 하면 되나 | 아니다. **IPAddressPool + L2Advertisement**를 만들어야 IP가 붙는다 |
| IP 풀 조건 | 노드와 **같은 서브넷**, 아무도 안 쓰는 대역 |
| L2 모드가 로드밸런싱인가 | **아니다.** 한 노드가 다 받고 kube-proxy가 Pod 단위로 분산. 노드 분산은 BGP 모드 |
| 노드가 죽으면 | 다른 speaker가 Gratuitous ARP로 이어받는다 (무중단 확인) |
| 특정 IP 고정 | `metallb.universe.tf/loadBalancerIPs` 어노테이션. `metallb.io/...`는 **조용히 무시된다** |
| NodePort는 사라지나 | 아니다. LoadBalancer가 NodePort를 포함하므로 그대로 남는다 |
| IPVS 모드라면 | `strictARP: true`가 필요하다 (이 클러스터는 iptables 모드라 불필요) |
| 인터넷에 공개되나 | **안 된다.** 호스트 전용 네트워크 밖으로 안 나간다. 앞단에 포트포워딩·NAT가 따로 필요하다 |
| 자원 부담 | speaker 약 31MB/노드 + controller 1개. **가볍다** |

## 참고

- MetalLB : https://metallb.universe.tf/
- Installation : https://metallb.universe.tf/installation/
- L2 Configuration : https://metallb.universe.tf/configuration/_advanced_l2_configuration/
- Service Type=LoadBalancer : https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer
