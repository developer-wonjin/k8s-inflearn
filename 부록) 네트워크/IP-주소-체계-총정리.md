# 쿠버네티스 IP 주소 체계 총정리

- 확인일 : 2026-09-12
- 환경 : Rocky Linux 8.8 / k8s v1.27.2 / Calico(VXLANCrossSubnet) / kube-proxy **iptables** 모드
- 관련 문서 :
  [부록) 로드밸런서](../부록%29%20로드밸런서/metallb-설치와-원리.md) ·
  [498. Service](../498.service-clusterip-nodeport-loadbalancer/README.md) ·
  [516. Headless·ExternalName](../516.service-headless-endpoint-externalname/README.md)

> 노드IP·Pod IP·ClusterIP·NodePort·EXTERNAL-IP가 각각 무엇이고 어디까지 닿는지를
> **이 클러스터에서 직접 확인한** 기록. 표의 모든 값은 실제 출력에서 가져왔다.

---

## 1. 이 클러스터의 주소 체계

세 종류의 대역이 서로 겹치지 않게 쓰인다.

| 대역 | 값 | 누가 정하는가 | 실체 |
|---|---|---|---|
| **노드망** | `192.168.56.0/24` | VirtualBox 호스트 전용 네트워크 | 물리(가상) NIC에 **실제로 붙어 있다** |
| **Pod 망** | `20.96.0.0/12` | `--cluster-cidr` + Calico IPAM | veth 페어에 실제로 붙어 있다 |
| **Service 망** | `10.96.0.0/12` | `--service-cluster-ip-range` | **어디에도 없다.** iptables 규칙일 뿐 |

```bash
clear                                                                                   # 화면 정리 후 시작
kubectl get nodes -o wide                                                               # 노드망 확인
grep -hE 'cluster-cidr|service-cluster-ip-range' /etc/kubernetes/manifests/kube-*.yaml  # 대역 설정 확인
```

```text
NAME          STATUS   ROLES           INTERNAL-IP     EXTERNAL-IP
k8s-master    Ready    control-plane   192.168.56.30   <none>
k8s-worker1   Ready    <none>          192.168.56.31   <none>
k8s-worker2   Ready    <none>          192.168.56.32   <none>

--service-cluster-ip-range=10.96.0.0/12
--cluster-cidr=20.96.0.0/12
```

> 노드의 `EXTERNAL-IP`가 `<none>`인 건 정상이다. 이 항목은 **클라우드 제공자가 채우는 칸**이라
> 베어메탈·VirtualBox 환경에서는 비어 있다. Service의 `EXTERNAL-IP`와 이름만 같고 다른 개념이다.

### `.spec.podCIDR`과 실제 할당 블록은 다르다

`kubectl get nodes`가 보여주는 `podCIDR`은 kube-controller-manager가 나눠 준 값인데,
**Calico는 자기 IPAM을 쓴다.** 실제로 두 값이 다르다.

```bash
clear                                                                            # 화면 정리 후 시작
kubectl get nodes -o custom-columns='NODE:.metadata.name,PODCIDR:.spec.podCIDR'  # 컨트롤러가 나눠 준 값
kubectl get blockaffinities -o custom-columns='NODE:.spec.node,CIDR:.spec.cidr'  # Calico가 실제로 쓰는 블록
```

```text
NODE          PODCIDR          NODE          CIDR
k8s-master    20.96.0.0/24     k8s-master    20.108.82.192/26
k8s-worker1   20.96.1.0/24     k8s-worker1   20.100.194.64/26
k8s-worker2   20.96.2.0/24     k8s-worker2   20.110.126.0/26
```

**Pod IP를 예측할 때 `podCIDR`을 믿으면 안 된다.** `/12` 안이라는 것만 보장된다.
Calico는 `blockSize: 26` 단위로 필요할 때마다 블록을 떼어 쓴다.

## 2. 한눈에 보는 비교표

이 문서의 핵심이다.

| 이름 | 예시 값 | 어디에 존재하나 | 누가 쓰나 | 수명 | 클러스터 밖에서 접근 |
|---|---|---|---|---|---|
| **노드 IP** | `192.168.56.30` | NIC에 **실재** | 사람, kubelet, etcd | 노드와 같음 | **가능** |
| **Pod IP** | `20.100.194.97` | veth에 **실재** | Pod끼리 | **Pod 재시작마다 바뀜** | 불가 |
| **ClusterIP** | `10.100.202.112` | **없음** (iptables 규칙) | 클러스터 내부 | Service 수명 | 불가 |
| **Headless** | `None` | 없음 (DNS만) | 내부, Pod 직접 지목 | Service 수명 | 불가 |
| **NodePort** | `30808` | 모든 노드의 포트 | 외부 | Service 수명 | **가능** (`노드IP:포트`) |
| **EXTERNAL-IP** | `192.168.56.200` | 한 노드가 ARP로 **가로챔** | 외부 | Service 수명 | **가능** |
| **ExternalName** | `www.google.com` | 없음 (CNAME) | 내부 → 외부 | Service 수명 | 해당 없음 |

### Service 타입별 실제 출력

```bash
clear                               # 화면 정리 후 시작
kubectl get svc -n default -o wide  # 다섯 타입을 한 번에 만든 뒤 조회
```

```text
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)        SELECTOR
web-clusterip   ClusterIP      10.100.202.112   <none>           80/TCP         app=web
web-headless    ClusterIP      None             <none>           80/TCP         app=web
web-nodeport    NodePort       10.100.252.245   <none>           80:30808/TCP   app=web
web-lb          LoadBalancer   10.111.67.87     192.168.56.200   80:32653/TCP   app=web
web-extname     ExternalName   <none>           www.google.com   <none>         app=web-extname
```

**타입은 누적된다.** NodePort는 ClusterIP를 그대로 갖고 포트를 더한 것이고,
LoadBalancer는 NodePort까지 갖고 EXTERNAL-IP를 더한 것이다.
위 출력에서 `web-lb`가 ClusterIP(`10.111.67.87`)와 NodePort(`32653`)를
**둘 다** 갖고 있는 게 그 증거다.

## 3. ClusterIP는 실재하지 않는다

가장 헷갈리는 지점이다. **TCP 연결은 되는데 핑은 안 되고 인터페이스에도 없다.**

```bash
clear                                                           # 화면 정리 후 시작
curl -s -o /dev/null -w "%{http_code}\n" http://10.100.202.112  # HTTP는 응답한다
ping -c 1 -W 2 10.100.202.112                                   # 핑은 안 된다
ip -4 addr show | grep -c "10.100.202.112"                      # 어느 인터페이스에도 없다
```

```text
200                                    ← HTTP 200
1 packets transmitted, 0 received      ← 100% packet loss
0                                      ← 인터페이스에 없음
```

ClusterIP는 **주소가 아니라 규칙**이기 때문이다. 패킷이 나가려는 순간 iptables가
목적지를 Pod IP로 바꿔치기(DNAT)한다. ICMP를 처리하는 규칙은 없으니 핑은 실패한다.

```bash
clear                                                      # 화면 정리 후 시작
iptables -t nat -L KUBE-SERVICES -n | grep 10.100.202.112  # ClusterIP를 받는 규칙
iptables -t nat -L KUBE-SVC-PF753ZCP72PHZRHS -n            # 그 규칙이 분배하는 곳
```

```text
KUBE-SVC-PF753ZCP72PHZRHS  tcp -- 0.0.0.0/0  10.100.202.112  /* default/web-clusterip cluster IP */

KUBE-MARK-MASQ  tcp -- !20.96.0.0/12  10.100.202.112
KUBE-SEP-UHG3TCIEAVAHCYKR  /* -> 20.100.194.97:80 */ statistic mode random probability 0.50000000000
KUBE-SEP-AACJZUUB7QEON4NA  /* -> 20.110.126.19:80 */
```

로드밸런싱의 정체가 `statistic mode random probability 0.5` 한 줄이다.
**정교한 알고리즘이 아니라 확률 기반 무작위 분배**다.

`KUBE-MARK-MASQ`의 조건이 `!20.96.0.0/12`인 것도 중요하다.
**Pod 망에서 온 게 아니면** 출발지를 바꾼다는 뜻이고, 이게 5절의 원인이다.

## 4. DNS는 무엇으로 풀리는가

Pod 안에서 각 Service 이름을 조회한 결과다.

| Service 타입 | DNS 응답 | 비고 |
|---|---|---|
| ClusterIP | `10.100.202.112` | 가상 IP 하나 |
| NodePort | `10.100.252.245` | **ClusterIP를 준다.** 포트는 DNS로 안 온다 |
| LoadBalancer | `10.111.67.87` | **ClusterIP를 준다.** EXTERNAL-IP가 아니다 |
| Headless | `20.100.194.97`, `20.110.126.19` | **Pod IP 전부** |
| ExternalName | `CNAME www.google.com` | 클러스터 밖 이름으로 넘김 |

```bash
clear                                                                        # 화면 정리 후 시작
kubectl exec netcheck -- dig +short web-clusterip.default.svc.cluster.local  # 가상 IP 하나
kubectl exec netcheck -- dig +short web-headless.default.svc.cluster.local   # Pod IP 전부
```

```text
10.100.202.112

20.100.194.97
20.110.126.19
```

**클러스터 안에서 이름으로 부르면 LoadBalancer라도 EXTERNAL-IP로 나가지 않는다.**
내부 트래픽은 ClusterIP를 거쳐 곧바로 Pod으로 간다. 굳이 바깥을 한 바퀴 돌지 않는다.

### Pod의 resolv.conf

```text
search default.svc.cluster.local svc.cluster.local cluster.local Davolink
nameserver 10.96.0.10
options ndots:5
```

`10.96.0.10`은 Service 망에 속한 **CoreDNS의 ClusterIP**다. DNS 서버조차 가상 IP다.
`search` 덕분에 `web-clusterip` 한 마디만 써도 FQDN으로 확장된다.

> **Headless가 NXDOMAIN을 준 적이 있다.** Endpoints가 아직 비어 있을 때 조회하면
> CoreDNS가 그 실패를 캐시한다. Endpoints가 채워진 뒤에도 잠시 NXDOMAIN이 유지된다.
> 만들자마자 조회해서 안 나오면 몇 초 기다렸다 다시 본다.

## 5. 출발지 IP는 경로마다 달라진다

**같은 Pod에서 같은 서버로 보냈는데 서버가 본 출발지가 전부 다르다.**
netcheck Pod(`20.100.194.91`, worker1)에서 nginx에 접속하고 access log를 확인했다.

| 접속 대상 | nginx가 본 출발지 | 보존됐나 |
|---|---|---|
| ClusterIP | `20.100.194.91` | **보존** (원래 Pod IP) |
| NodePort (worker2) | `192.168.56.32` | 바뀜 (worker2의 노드 IP) |
| LoadBalancer VIP | `192.168.56.31` | 바뀜 (worker1의 노드 IP) |

3절의 `KUBE-MARK-MASQ !20.96.0.0/12` 규칙 때문이다. Pod 망에서 온 트래픽은 그대로 두고,
그 밖에서 온 것(= 노드 포트로 들어온 것)은 출발지를 노드 IP로 바꾼다.

바꾸지 않으면 **응답이 돌아갈 길이 없기 때문**이다. 다른 노드로 전달된 패킷의 출발지를
원본 그대로 두면, Pod은 응답을 원본 클라이언트에게 직접 보내려 하고 경로가 어긋난다.

### `externalTrafficPolicy: Local` 로 보존할 수 있다

```bash
clear                                                                     # 화면 정리 후 시작
kubectl patch svc web-lb -p '{"spec":{"externalTrafficPolicy":"Local"}}'  # Local 로 변경
kubectl exec netcheck -- curl -s -o /dev/null http://192.168.56.200       # 같은 경로로 다시 접속
```

바꾼 뒤 같은 VIP로 접속하니 출발지가 `20.100.194.91`로 **보존**됐다.

| | `Cluster` (기본값) | `Local` |
|---|---|---|
| 출발지 IP | 노드 IP로 **바뀜** | **보존** |
| 전달 범위 | 다른 노드의 Pod에도 전달 | **자기 노드의 Pod에만** |
| 부하 분산 | 고르다 | 노드별 Pod 수에 따라 **치우친다** |
| Pod 없는 노드 | 그 노드로도 접속됨 | **응답 안 함** |

접속자 IP를 로그로 남겨야 하면 `Local`, 고른 분산이 중요하면 `Cluster`를 쓴다.

## 6. NodePort는 Pod이 없는 노드에서도 열린다

```bash
clear                                                                # 화면 정리 후 시작
kubectl get pods -l app=web -o wide                                  # Pod은 worker1·worker2에만 있다
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.56.30:30808  # master에는 Pod이 없다
```

```text
web-79c7f75bc-4lfm8   20.100.194.97   k8s-worker1
web-79c7f75bc-5nqzq   20.110.126.19   k8s-worker2

200                                   ← master로 접속해도 200
```

**모든 노드가 모든 NodePort를 연다.** Pod이 없는 노드로 들어와도 kube-proxy가
Pod이 있는 노드로 넘긴다(`Cluster` 정책일 때). 그래서 어느 노드 IP를 써도 접속된다.

기본 포트 범위는 `30000-32767`이다. 직접 지정하지 않으면 이 안에서 임의로 배정된다.

## 7. 바깥으로 나가는 길

지금까지는 들어오는 방향이었다. Pod이 **인터넷으로 나가는** 것은 별개다.

```bash
clear                                                                                        # 화면 정리 후 시작
kubectl exec netcheck -- curl -s -o /dev/null -w "%{http_code}\n" https://pypi.org/simple/   # Pod에서 인터넷 접속
kubectl get installation default -o jsonpath='{.spec.calicoNetwork.ipPools[0].natOutgoing}'  # Calico NAT 설정
```

```text
200
Enabled
```

`natOutgoing: Enabled` 덕분이다. Pod IP(`20.x`)는 클러스터 밖에서 라우팅되지 않으므로,
클러스터를 나갈 때 **노드 IP로 출발지를 바꿔서** 내보낸다. 집 공유기의 NAT와 같은 원리다.

| 방향 | 주소 변환 | 담당 |
|---|---|---|
| 외부 → Pod | 목적지를 Pod IP로 (**DNAT**) | kube-proxy (iptables) |
| Pod → 외부 | 출발지를 노드 IP로 (**SNAT**) | Calico (`natOutgoing`) |

## 8. hostNetwork — 예외

일부 시스템 Pod은 Pod IP를 받지 않고 **노드 IP를 그대로 쓴다.**

```bash
clear                                                                                                                                  # 화면 정리 후 시작
kubectl get pods -A -o custom-columns='POD:.metadata.name,IP:.status.podIP,HOSTNET:.spec.hostNetwork' --no-headers | awk '$3=="true"'  # hostNetwork Pod 목록
```

```text
calico-node-ppt97       192.168.56.30   true
calico-typha-...-8wpsf  192.168.56.30   true
etcd-k8s-master         192.168.56.30   true
```

`hostNetwork: true`면 노드의 네트워크 네임스페이스를 그대로 쓴다.
CNI 자신(`calico-node`)이나 etcd처럼 **CNI가 준비되기 전에 떠야 하는 것들**이 이 방식을 쓴다.
네임스페이스 공유에 대해서는 [네트워크 네임스페이스 공유](네트워크-네임스페이스-공유.md) 참고.

## 9. 그래서 언제 무엇을 쓰나

| 상황 | 선택 |
|---|---|
| 클러스터 안에서만 부른다 | **ClusterIP** (기본값) |
| Pod을 하나씩 직접 지목해야 한다 (StatefulSet 등) | **Headless** |
| 외부에 임시로 열어본다 (실습·디버깅) | **NodePort** |
| 외부에 제대로 서비스한다 | **LoadBalancer** (베어메탈이면 [MetalLB](../부록%29%20로드밸런서/metallb-설치와-원리.md) 필요) |
| HTTP 경로·호스트별로 나눈다 | **Ingress** ([529](../529.ingress/README.md)) |
| 클러스터 밖 주소를 내부 이름으로 부른다 | **ExternalName** |

## 배운 것

- **ClusterIP는 인터페이스에 없다.** 핑도 안 된다. iptables DNAT 규칙일 뿐이다.
- 로드밸런싱의 실체는 `statistic mode random probability 0.5` — **확률 기반 무작위**다.
- Service **타입은 누적**된다. LoadBalancer는 ClusterIP와 NodePort를 모두 갖는다.
- 클러스터 안에서 LoadBalancer를 이름으로 부르면 **ClusterIP로 풀린다.** 밖으로 안 나간다.
- 노드의 `EXTERNAL-IP`와 Service의 `EXTERNAL-IP`는 **이름만 같고 전혀 다른 것**이다.
- **출발지 IP는 경로마다 다르다.** NodePort·LoadBalancer로 들어오면 노드 IP로 바뀐다.
  보존하려면 `externalTrafficPolicy: Local`. 대신 분산이 치우친다.
- **NodePort는 Pod이 없는 노드에서도 열린다.** 모든 노드가 모든 NodePort를 연다.
- `.spec.podCIDR`은 Calico의 실제 할당 블록과 **다르다.** 예측에 쓰면 안 된다.
- Headless는 Endpoints가 빌 때 조회하면 **NXDOMAIN이 캐시**된다. 잠시 뒤 다시 본다.
