# 501. [기본오브젝트] Namespace, ResourceQuota, LimitRange

- 원문 : https://cafe.naver.com/kubeops/501
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

여러 팀이 한 클러스터를 나눠 쓸 때 필요한 세 가지.

| 리소스 | 하는 일 | 단위 |
|---|---|---|
| `Namespace` | 이름과 권한을 갈라놓는다 | 그룹 |
| `ResourceQuota` | **네임스페이스 전체**가 쓸 총량을 제한 | 합계 |
| `LimitRange` | **컨테이너 하나**가 지킬 범위를 정하고 기본값을 채움 | 개별 |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.namespace.md](1.namespace.md) | 1) Namespace | Namespace `nm-1`·`nm-2`, Pod·Service | 없음 |
| [2.resourcequota.md](2.resourcequota.md) | 2) ResourceQuota | Namespace `nm-3`, ResourceQuota `rq-1`·`rq-2` | 없음 |
| [3.limitrange.md](3.limitrange.md) | 3) LimitRange | Namespace `nm-5`, LimitRange `lr-1` | 없음 |

세 문서는 각자 별도의 네임스페이스를 쓰므로 **순서에 상관없이 진행해도 된다.**

## 실습 시작 전 정리

이 게시글은 `default`가 아니라 전용 네임스페이스를 만들어 쓴다.
정리도 네임스페이스째 지우면 된다.

```bash
clear                                        # 화면 정리 후 시작

kubectl delete ns \
  nm-1 \
  nm-2 \
  nm-3 \
  nm-4 \
  nm-5 \
  --ignore-not-found

kubectl get ns                               # 실습용 nm-* 가 없어야 정상
```

> **네임스페이스를 지우면 안에 있던 모든 오브젝트가 함께 사라진다.**
> Pod, Service, ConfigMap, ResourceQuota, LimitRange 전부 포함이다.
> `default`, `kube-system`, `calico-*` 같은 기존 네임스페이스는 절대 지우지 않는다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | 네임스페이스가 다르면 이름이 겹쳐도 되는가 | **된다.** `pod-1`·`svc-1`이 두 ns에 공존 | [1](1.namespace.md#1-이름-중복이-되는가) |
| 2 | Service selector가 다른 ns의 Pod을 잡는가 | **안 잡는다.** 각자 자기 ns의 Pod만 | [1](1.namespace.md#2-service-selector는-네임스페이스를-넘는가) |
| 3 | 네임스페이스가 다르면 통신이 막히는가 | **안 막힌다.** Pod IP·Service IP·DNS 전부 통한다 | [1](1.namespace.md#3-그런데-네트워크-통신은-넘어간다) |
| 4 | 같은 NodePort를 두 ns에 쓸 수 있는가 | **못 쓴다.** `provided port is already allocated` | [1](1.namespace.md#4-네임스페이스로-갈리지-않는-것--nodeport) |
| 5 | hostPath가 ns를 넘어 공유되는가 | **공유된다.** 노드의 물리 자원이라서 | [1](1.namespace.md#5-네임스페이스로-갈리지-않는-것--hostpath) |
| 6 | 쿼터를 걸면 resources가 필수가 되는가 | **된다.** 안 적으면 생성 거부 | [2](2.resourcequota.md#1-쿼터를-걸면-resources가-필수가-된다) |
| 7 | LimitRange가 기본값을 채워주는가 | **채워준다.** yaml에 없어도 Pod에는 값이 들어감 | [3](3.limitrange.md#3-resources를-안-쓰면-기본값이-채워진다) |

## 핵심 — 네임스페이스는 격리가 아니다

가장 오해하기 쉬운 부분이다.

| 갈리는 것 | 갈리지 않는 것 |
|---|---|
| 오브젝트 이름 | 네트워크 (Pod IP·Service IP·DNS) |
| Service selector 범위 | NodePort (클러스터 전체에서 유일) |
| RBAC 권한 (게시글 525) | 노드 자원 (hostPath 등) |
| ResourceQuota·LimitRange 적용 범위 | PersistentVolume (클러스터 자원) |

네트워크까지 막으려면 **NetworkPolicy**를 따로 걸어야 한다.

## ResourceQuota와 LimitRange는 짝으로

- ResourceQuota만 걸면 → 모든 Pod에 resources를 일일이 적어야 한다 (번거로움)
- LimitRange를 함께 걸면 → 안 적어도 기본값이 채워져 쿼터 계산이 정상 동작한다

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete ns \
  nm-1 \
  nm-2 \
  nm-3 \
  nm-4 \
  nm-5 \
  --ignore-not-found

kubectl get ns                               # 실습용 nm-* 가 없어야 정상
```

## Kubernetes Reference

- Namespaces : https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- Resource Quotas : https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Limit Ranges : https://kubernetes.io/docs/concepts/policy/limit-range/
