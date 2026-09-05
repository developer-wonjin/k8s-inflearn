# 497. [기본오브젝트] Pod - Container, Label, NodeSchedule

- 원문 : https://cafe.naver.com/kubeops/497
- 실습일 : 2026-09-04
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21
  - `k8s-master` 192.168.56.30 / `k8s-worker1` 192.168.56.31 / `k8s-worker2` 192.168.56.32

| 노드 | allocatable memory | CPU | taint |
|---|---|---|---|
| k8s-master  | 3894424Ki (약 3.71Gi) | 4 | 없음 (Pod 스케줄링 가능) |
| k8s-worker1 | 2928800Ki (약 2.79Gi) | 3 | 없음 |
| k8s-worker2 | 2928804Ki (약 2.79Gi) | 3 | 없음 |

> master에 `node-role.kubernetes.io/control-plane:NoSchedule` taint가 **없다.**
> 그래서 이 실습에서 일반 Pod이 master에도 스케줄링된다. 강의 화면과 노드 분포가 달라 보이는 원인.

## 실습 시작 전 정리

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

> **`-n default`를 반드시 붙인다.** `-A`(전 네임스페이스)로 실행하면 `kube-system`,
> `calico-system` 등 클러스터 구동에 필요한 리소스까지 지워져 **클러스터가 망가진다.**
>
> `service/kubernetes`는 API 서버로 가는 기본 서비스라 `--field-selector`로 제외한다.
> 지워도 자동 재생성되지만 그 사이 통신이 끊긴다.

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1-1.pod-container.md](1-1.pod-container.md) | 1-1) Pod | Pod `pod-1` (컨테이너 2개) | 없음 |
| [1-2.deployment.md](1-2.deployment.md) | 1-2) Deployment | Deployment `deployment-1` | 없음 |
| [2-1.pod-label.md](2-1.pod-label.md) | 2-1) Pod | Pod `pod-1` ~ `pod-6` (라벨) | 없음 |
| [2-2.service-label.md](2-2.service-label.md) | 2-2) Service | Service `svc-for-web`, `svc-for-production` | **2-1의 Pod 6개 필요** |
| [3.pod-nodeschedule.md](3.pod-nodeschedule.md) | 3-1~3-3) Pod | Pod `pod-3`, `pod-4`, `pod-5` (nodeSelector, resources) | 없음 |

**선행 조건이 "없음"인 문서는 어디서 시작해도 된다.** 각 문서 맨 앞의 [실습 시작 전 정리](#실습-시작-전-정리)를
실행하면 이전 실습 잔재가 사라진 깨끗한 상태에서 시작한다.

**2-2만 예외다.** 2-1이 만든 Pod 6개를 Service가 라벨로 잡아가는지 보는 실습이라,
2-1을 건너뛰거나 그 사이에 정리를 실행하면 Endpoints가 비어 실습이 성립하지 않는다.
2-2 문서 맨 앞에도 같은 주의를 적어 두었다.

## 실습 순서

섹션끼리 Pod 이름이 겹친다(`pod-1`, `pod-3`, `pod-4`, `pod-5`).
**한 섹션을 끝내면 반드시 정리하고 다음 섹션으로 넘어가야 한다.**

```
1. Container    → 정리 → 2. Label    → 정리 → 3. NodeSchedule → 정리
```

## 원문과 달랐던 점

| # | 원문 서술 | 실제 확인 결과 | 상세 |
|---|---|---|---|
| 1 | "Container 간에 같은 Port를 노출시키면 **Pod 생성시 충돌 에러** 발생" | 생성은 **성공**한다. 런타임에 두 번째 컨테이너가 `EADDRINUSE`로 죽어 `CrashLoopBackOff`가 된다 | [1-1](1-1.pod-container.md#검증-같은-port를-쓰면-정말-생성-에러가-나는가) |
| 2 | `template.metadata.name: pod-1` | 원문에는 있으나 **이 문서에서는 뺐다.** Pod 이름은 `generateName` + 랜덤 5자로 지어져 이 값이 쓰이지 않는데, `pod-template-hash`에는 포함되어 넣고 빼는 것만으로 새 RS가 생기고 롤아웃이 발생한다 | [1-2](1-2.deployment.md#yaml) |
| 3 | `memory: 2.7Gi` | 동작은 하지만 API 서버가 `fractional byte value ... is invalid` 경고를 낸다 | [3](3.pod-nodeschedule.md#주의-27gi-소수점-표기-경고) |

## 실습 후 정리

```bash
clear                       # 화면 정리 후 시작

# 섹션 1·2·3에서 만든 Pod 전부
kubectl delete pod \
  pod-1 \
  pod-2 \
  pod-3 \
  pod-4 \
  pod-5 \
  pod-6 \
  --grace-period=1 --ignore-not-found

# 섹션 1-2의 Deployment
kubectl delete deploy deployment-1 --ignore-not-found

# 섹션 2-2의 Service 2개
kubectl delete svc \
  svc-for-web \
  svc-for-production \
  --ignore-not-found

kubectl get all -n default  # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- Pods : https://kubernetes.io/docs/concepts/workloads/pods/
- Labels and Selectors : https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
- Assigning Pods to Nodes : https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
