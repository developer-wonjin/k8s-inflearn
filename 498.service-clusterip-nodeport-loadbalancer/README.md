# 498. [기본오브젝트] Service - ClusterIP, NodePort, LoadBalancer

- 원문 : https://cafe.naver.com/kubeops/498
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21
  - `k8s-master` 192.168.56.30 / `k8s-worker1` 192.168.56.31 / `k8s-worker2` 192.168.56.32

## 왜 필요한가

Pod IP는 재생성마다 바뀐다(497에서 확인). 그 위에 **고정 주소**를 얹는 것이 Service다.
세 타입은 서로를 포함하는 관계다.

```
ClusterIP  →  NodePort  →  LoadBalancer
 내부 전용     + 노드 포트     + 외부 LB IP
```

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.clusterip.md](1.clusterip.md) | 1) ClusterIP | Pod `pod-1`, Service `svc-1` | 없음 |
| [2.nodeport.md](2.nodeport.md) | 2) NodePort | Service `svc-2`·`svc-3`, Pod `pod-2` | **1의 `pod-1` 필요** |
| [3.loadbalancer.md](3.loadbalancer.md) | 3) LoadBalancer | Service `svc-4` | **1·2의 Pod 2개 필요** |

**이 게시글은 세 문서가 이어집니다.** 앞 문서에서 만든 Pod을 뒤 문서가 그대로 씁니다.
1 → 2 → 3 순서로 진행하고, 중간에 [실습 시작 전 정리](#실습-시작-전-정리)를 실행하면 앞 리소스가 사라집니다.

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

> **`-n default`를 반드시 붙인다.** `-A`(전 네임스페이스)로 실행하면 `kube-system`,
> `calico-system` 등 클러스터 구동에 필요한 리소스까지 지워져 **클러스터가 망가진다.**
>
> `service/kubernetes`는 API 서버로 가는 기본 서비스라 `--field-selector`로 제외한다.

## 이 환경에서 원문과 달랐던 점

| # | 원문 | 실제 확인 결과 | 상세 |
|---|---|---|---|
| 1 | `type: LoadBalancer`로 외부 IP 확보 | 베어메탈이라 `EXTERNAL-IP`가 **`<pending>`** 에서 멈춘다. 클라우드 컨트롤러나 MetalLB가 있어야 IP가 붙는다 | [3](3.loadbalancer.md#2-왜-pending-인가) |
| 2 | "내 PC의 CMD에서 호출" | master에서 호출하면 `externalTrafficPolicy: Local`이 **적용되지 않는다.** 노드 자신이 만든 트래픽은 외부 트래픽이 아니기 때문. Pod 안에서 호출해 검증했다 | [2](2.nodeport.md#3-svc-3--externaltrafficpolicy-local) |
| 3 | — | **2026-09-11 MetalLB v0.14.8을 설치**해 `<pending>`을 해소했다. 지금 실습하면 `192.168.56.200`이 붙는다 | [부록) 로드밸런서](../부록%29%20로드밸런서/metallb-설치와-원리.md) |

## 포트 세 개를 구분하기

Service를 처음 보면 포트가 셋이라 헷갈린다.

| 필드 | 누가 쓰나 | 이 실습의 값 |
|---|---|---|
| `port` | 클러스터 내부에서 Service를 부를 때 | 9000 |
| `targetPort` | Service가 Pod으로 넘길 때 (= `containerPort`) | 8080 |
| `nodePort` | 클러스터 밖에서 노드 IP로 들어올 때 | 30001 / 30002 |

```
[외부] ─30001→ [노드] ─9000→ [Service] ─8080→ [Pod]
        nodePort          port            targetPort
```

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod \
  pod-1 \
  pod-2 \
  curlbox \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  svc-1 \
  svc-2 \
  svc-3 \
  svc-4 \
  --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- Service : https://kubernetes.io/docs/concepts/services-networking/service/
- Source IP / externalTrafficPolicy : https://kubernetes.io/docs/tutorials/services/source-ip/
