# 503. [컨트롤러] ReplicaSet - Template, Replicas, Selector

- 원문 : https://cafe.naver.com/kubeops/503
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

## 왜 필요한가

Pod을 직접 만들면 죽었을 때 그걸로 끝이다. **개수를 지켜주는 것**이 컨트롤러이고,
그중 가장 기본이 ReplicaSet이다.

```
ReplicaSet  ──selector로 찾고──▶  Pod 들
            ──모자라면 template으로 만든다──▶
```

> **실무에서 ReplicaSet을 직접 쓰지는 않는다.** Deployment가 대신 만들어 관리한다(게시글 504).
> 여기서는 그 아래에서 실제로 무슨 일이 일어나는지 보기 위해 직접 다룬다.

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.template-replicas.md](1.template-replicas.md) | 1) Template, 2) Replicas | Pod `pod1`, ReplicaSet `replica1` | 없음 |
| [2.selector.md](2.selector.md) | 3) Selector | ReplicaSet `replica2` | 없음 |

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

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | 이미 있는 Pod을 ReplicaSet이 가져가는가 | **가져간다.** 새로 만들지 않고 `ownerReferences`만 붙음 | [1](1.template-replicas.md#1-이미-있는-pod을-replicaset이-인수한다) |
| 2 | Pod을 지우면 같은 이름으로 복구되는가 | **아니다.** `<RS이름>-<랜덤>` 으로 새로 생긴다 | [1](1.template-replicas.md#3-pod을-지우면-이름이-돌아오지-않는다) |
| 3 | 컨트롤러만 지우고 Pod을 남길 수 있는가 | `--cascade=orphan` 으로 가능. 소유 관계만 끊긴다 | [1](1.template-replicas.md#4-컨트롤러만-지우고-pod은-남기기) |
| 4 | selector와 template.labels가 다르면 | **생성이 거부된다.** 허용하면 Pod이 무한 생성됨 | [2](2.selector.md#검증-selector와-templatelabels가-안-맞으면) |

## `terminationGracePeriodSeconds: 0` 에 대해

원문 yaml에 이 설정이 들어 있다. 삭제할 때 유예 없이 즉시 죽이라는 뜻이라
실습에서 Pod이 빨리 사라져 편하다.

다만 **운영에서는 쓰지 않는다.** 진행 중인 요청을 정리할 틈 없이 SIGKILL로 죽는다.
자세한 내용은 [부록) 삭제](../부록%29%20삭제/삭제-grace-period-와-옵션.md) 참고.

> 이 문서의 정리 명령에서 `--grace-period=1`을 쓰는 것과 같은 취지다.
> yaml에 박아두는 것과 삭제할 때 옵션으로 주는 것의 차이일 뿐이다.

## ReplicaSet vs Deployment

| | ReplicaSet | Deployment |
|---|---|---|
| 개수 유지 | O | O (ReplicaSet에 위임) |
| 이미지 변경 시 | 새 Pod으로 교체 안 됨 | **새 RS를 만들어 무중단 교체** |
| 롤백 | X | O |
| 실무 사용 | 거의 없음 | 표준 |

ReplicaSet은 **개수만** 본다. 템플릿을 바꿔도 이미 떠 있는 Pod을 갈아치우지 않는다.
그 일을 해주는 것이 Deployment다 → 게시글 504

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete rs \
  replica1 \
  replica2 \
  --grace-period=1 --ignore-not-found

# --cascade=orphan 으로 남겨둔 Pod이 있으면 함께 정리한다
kubectl delete pod --all -n default --grace-period=1 --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- ReplicaSet : https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/
- Labels and Selectors : https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
