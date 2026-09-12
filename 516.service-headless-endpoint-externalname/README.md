# 516. [기본오브젝트] Service - Headless, Endpoint, ExternalName

- 원문 : https://cafe.naver.com/kubeops/516
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

## 왜 필요한가

498에서 Service의 **타입**(ClusterIP/NodePort/LoadBalancer)을 봤다면,
여기서는 Service의 **이름과 연결 구조**를 파고든다.

| 주제 | 한 줄 요약 |
|---|---|
| **DNS** | Service 이름이 곧 도메인이다 |
| **Headless** | Service IP를 없애고 **Pod 하나하나를 이름으로** 부른다 |
| **Endpoint** | Service와 Pod을 잇는 실제 목록. **직접 만들 수도** 있다 |
| **ExternalName** | 외부 도메인에 클러스터 안의 별명을 붙인다 |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.dns-clusterip.md](1.dns-clusterip.md) | 1) ClusterIP | Service `clusterip1`, Pod `pod1`·`request-pod` | 없음 |
| [2.headless.md](2.headless.md) | 2) Headless Service | Service `headless1`, Pod `pod4`·`pod5` | **1의 `request-pod`** |
| [3.endpoint.md](3.endpoint.md) | 3~5) Endpoint | Service `endpoint1`~`endpoint3`, Pod `pod7`·`pod9` | **1의 `request-pod`** |
| [4.externalname.md](4.externalname.md) | 6) ExternalName | Service `externalname1` | **1의 `request-pod`** |

**`request-pod`가 전 문서에서 호출자 역할을 한다.** 1번을 먼저 하고 순서대로 진행한다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

# default 네임스페이스의 실습 리소스를 전부 삭제 (시스템 네임스페이스는 건드리지 않는다)
kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

# Service는 kubernetes(클러스터 기본 서비스)만 남기고 삭제
kubectl delete svc -n default \
  --field-selector 'metadata.name!=kubernetes' --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## 왜 `request-pod` 안에서 호출하는가

**클러스터 DNS는 Pod 안에서만 통한다.** master에서 `curl clusterip1` 을 하면 실패한다.
노드의 `/etc/resolv.conf`는 CoreDNS(`10.96.0.10`)를 가리키지 않기 때문이다.

그래서 이 게시글의 모든 호출은 이 형태다.

```bash
clear                                                # 화면 정리 후 시작
SVC=clusterip1                                       # 조회할 Service 이름을 넣는다
kubectl exec request-pod -- nslookup "$SVC"          # 이름이 어떤 IP로 풀리는지
kubectl exec request-pod -- curl -s "$SVC/hostname"  # 그 이름으로 호출
```

원문은 `kubectl exec request-pod -it -- /bin/bash` 로 들어가서 작업하지만,
문서에 결과를 남기려면 위처럼 **한 줄씩 실행**하는 편이 낫다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | 짧은 이름으로 DNS가 되는가 | **된다.** `search` 도메인이 자동으로 붙는다 | [1](1.dns-clusterip.md#1-dns-질의) |
| 2 | Headless의 DNS 응답 | Service IP가 아니라 **Pod IP 두 개**가 반환됨 | [2](2.headless.md#2-dns가-pod-ip들을-돌려준다) |
| 3 | Pod 개별 도메인 | `pod-a.headless1` 로 **특정 Pod만** 호출됨 | [2](2.headless.md#3-pod마다-개별-도메인) |
| 4 | selector 없는 Service | Endpoints가 자동 생성되지 않음. **직접 만들면 연결됨** | [3](3.endpoint.md#3-2-직접-만드는-경우--selector-없는-service) |
| 5 | Endpoints에 외부 IP | **된다.** 클러스터 이름으로 GitHub 호출 성공 (HTTP 200) | [3](3.endpoint.md#3-3-클러스터-밖의-ip를-붙이기) |
| 6 | ExternalName 으로 그냥 호출하면 | **404.** Host 헤더가 Service 이름으로 나가기 때문 | [4](4.externalname.md#검증-그냥-호출하면-404가-난다) |

## 이름 규칙 정리

| 대상 | FQDN |
|---|---|
| Service | `<서비스명>.<네임스페이스>.svc.cluster.local` |
| Headless의 Pod | `<hostname>.<서비스명>.<네임스페이스>.svc.cluster.local` |
| Pod (기본) | `<IP를 -로 바꾼 값>.<네임스페이스>.pod.cluster.local` |

마지막 것은 IP가 바뀌면 이름도 바뀌므로 **실제로 쓸 수 없다.**
Pod을 이름으로 부르려면 Headless Service가 필요하다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod \
  pod1 \
  request-pod \
  pod4 \
  pod5 \
  pod7 \
  pod9 \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  clusterip1 \
  headless1 \
  endpoint1 \
  endpoint2 \
  endpoint3 \
  externalname1 \
  --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- DNS for Services and Pods : https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Service without selectors : https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors
