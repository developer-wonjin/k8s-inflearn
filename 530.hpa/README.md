# 530. [컨트롤러] AutoScaler - HPA

- 원문 : https://cafe.naver.com/kubeops/530
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

## 왜 필요한가

지금까지 `replicas` 는 사람이 정했다. HPA(Horizontal Pod Autoscaler)는
**부하를 보고 스스로 Pod 수를 조절한다.**

```
Metrics Server ──현재 사용량──▶ HPA ──replicas 변경──▶ Deployment ──▶ ReplicaSet ──▶ Pod
```

**Metrics Server가 없으면 HPA는 동작하지 않는다.**
Ingress에 Controller가 필요했던 것과 같은 구조다.

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.metrics-server.md](1.metrics-server.md) | 1) Metrics Server | (확인만) | 없음 |
| [2.hpa-cpu.md](2.hpa-cpu.md) | 2-1, 2-2 | Deployment `stateless-cpu1`, HPA `hpa-resource-cpu` | **1번 확인** |
| [3.hpa-memory.md](3.hpa-memory.md) | 2-3, 2-4 | Deployment `stateless-memory1`, HPA `hpa-resource-memory` | **2번을 먼저 정리** |

> 2번을 끝내면 **HPA를 먼저 지우고** 3번으로 간다.
> 두 HPA가 동시에 돌면 노드 자원이 부족해 결과가 흐려진다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

# HPA 는 아래 명령으로 지워지지 않으므로 따로 지운다
kubectl delete hpa --all -n default --ignore-not-found

kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

kubectl delete svc -n default \
  --field-selector 'metadata.name!=kubernetes' --ignore-not-found

kubectl get all,hpa -n default               # service/kubernetes 만 남으면 정상
```

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Metrics Server 상태 | `v1beta1.metrics.k8s.io` **True**, `kubectl top` 동작 | [1](1.metrics-server.md#설치-확인) |
| 2 | CPU 부하 시 스케일 아웃 | **2 → 4 → 7 → 10** 단계적으로 증가 | [2](2.hpa-cpu.md#2-부하를-넣고-지켜본다) |
| 3 | 부하 중단 후 스케일 인 | **약 4분 뒤** 10 → 2 로 한 번에 감소 | [2](2.hpa-cpu.md#3-줄어드는-데는-시간이-걸린다) |
| 4 | 메모리 HPA (`AverageValue: 5Mi`) | 부하 없이도 **max(10)까지 올라가 멈춤** | [3](3.hpa-memory.md#2-계속-늘어난다) |
| 5 | 왜 안 줄어드나 | Pod을 늘려도 **Pod당 메모리는 그대로**라 평균이 안 내려감 | [3](3.hpa-memory.md#검증-왜-줄어들지-않는가) |

## 반드시 짚어야 할 두 가지

### 1) `resources.requests` 가 없으면 HPA는 동작하지 않는다

`Utilization` 은 **"requests 대비 몇 %"** 다. 기준값이 없으면 계산 자체가 불가능하다.

```yaml
resources:
  requests:
    cpu: 10m          # ← 이것이 100% 의 기준이 된다
```

HPA를 붙였는데 `TARGETS` 가 `<unknown>` 으로 나온다면 이것부터 확인한다.

### 2) 늘릴 때와 줄일 때의 속도가 다르다

| | 늘릴 때 | 줄일 때 |
|---|---|---|
| 반응 | 빠름 (15초 주기) | **느림 (기본 5분 안정화 창)** |
| 실측 | 부하 후 ~15초 만에 시작 | 부하 중단 후 **약 4분** |
| 이유 | 늦으면 서비스가 죽는다 | 성급히 줄이면 다시 늘려야 한다 |

이 비대칭은 **의도된 설계**다. Pod 수가 요동치는 것(flapping)을 막는다.
바꾸려면 `behavior.scaleDown.stabilizationWindowSeconds` 를 조정한다.

## CPU vs 메모리 — 왜 CPU가 기본인가

이 실습의 가장 중요한 발견이다.

```
[CPU]     Pod 을 늘리면 → 요청이 나뉘어 → Pod 당 사용률이 내려간다 → 목표에 수렴
[메모리]  Pod 을 늘려도 → 각 Pod 이 여전히 같은 양을 쓴다 → 평균 그대로 → max 까지 직행
```

메모리는 **부하에 비례해 늘었다 줄었다 하지 않는다.** 한 번 잡으면 잘 안 놓는다.
그래서 목표값을 실사용보다 낮게 잡으면 `maxReplicas` 까지 올라가 멈춘다.

- **CPU 기반이 기본**이다.
- 메모리 기반은 "메모리를 쓸수록 처리량이 느는" 구조일 때만, **실측 후** 목표를 정한다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete hpa \
  hpa-resource-cpu \
  hpa-resource-memory \
  --ignore-not-found

kubectl delete deploy \
  stateless-cpu1 \
  stateless-memory1 \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  stateless-svc1 \
  stateless-svc2 \
  --ignore-not-found

kubectl get all,hpa -n default               # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- Horizontal Pod Autoscaling : https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- HPA Walkthrough : https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- Resource Metrics Pipeline : https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
