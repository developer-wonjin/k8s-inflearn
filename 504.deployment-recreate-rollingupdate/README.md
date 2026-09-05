# 504. [컨트롤러] Deployment - Recreate, RollingUpdate

- 원문 : https://cafe.naver.com/kubeops/504
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

새 버전을 배포할 때 **트래픽을 어떻게 넘길 것인가**에 대한 세 가지 답이다.
셋 다 실제로 1초 간격으로 호출하면서 측정했다.

| 전략 | 다운타임 | 두 버전 혼재 | 추가 자원 | 롤백 |
|---|---|---|---|---|
| **Recreate** | **약 2초** | 없음 | 없음 | 새로 띄워야 함 |
| **RollingUpdate** | **없음** | **있음** | 일부 (maxSurge) | 새로 띄워야 함 |
| **Blue/Green** | **없음** | 없음 | **2배** | **즉시** |

```
Recreate      : v1 v1 │ (없음) (없음) │ v2 v2
RollingUpdate : v1 v2 v1 v1 v2 v1 v2 ... v2
Blue/Green    : v1 v1 v1 │ v2 v2 v2
```

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.recreate.md](1.recreate.md) | 1) ReCreate | Deployment `deployment-1`, Service `svc-1` | 없음 |
| [2.rollingupdate.md](2.rollingupdate.md) | 2) RollingUpdate | Deployment `deployment-2`, Service `svc-2` | 없음 |
| [3.blue-green.md](3.blue-green.md) | 3) Blue/Green | ReplicaSet `replica1`·`replica2`, Service `svc-3` | 없음 |

세 문서는 각각 독립적이다. 다만 **한 번에 하나씩** 하는 것이 좋다.
동시에 띄우면 노드 자원이 부족해 결과가 흐려진다.

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

## 다운타임을 측정하는 방법

이 게시글의 핵심은 "정말 끊기는가"를 눈으로 보는 것이다.
**호출을 계속 하면서** 배포를 트리거해야 한다.

```bash
clear                                        # 화면 정리 후 시작

# 백그라운드에서 1초 간격으로 호출하며 로그를 남긴다
( for i in $(seq 1 40); do
    r=$(curl -s --max-time 1 $IP:8080/version 2>/dev/null)
    printf "  [%2ds] %s\n" $i "${r:-*** 응답 없음 ***}"
    timeout 1 tail -f /dev/null              # 1초 대기
  done ) > result.log 2>&1 &

kubectl set image deployment <이름> container=kubetm/app:v2

wait                                         # 루프가 끝날 때까지
uniq -c -f1 result.log                       # 연속된 같은 응답을 묶어서 본다
```

- `timeout 1 tail -f /dev/null` 이 1초 대기 역할을 한다.
- `uniq -c -f1` 은 첫 칸(`[3s]` 같은 시각)을 무시하고 나머지가 같은 줄을 묶어준다.
  40줄을 그대로 보는 것보다 **언제 바뀌었는지**가 한눈에 들어온다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Recreate에 정말 다운타임이 있는가 | **약 2초** 응답 없음 | [1](1.recreate.md#2-v2로-올리면서-1초-간격으로-호출한다) |
| 2 | `--to-revision=1` 롤백이 되는가 | **실패한다.** `revisionHistoryLimit: 1` 이라 리비전 1이 이미 삭제됨 | [1](1.recreate.md#검증---to-revision1-로-롤백이-되는가) |
| 3 | RollingUpdate는 정말 안 끊기는가 | **한 번도 안 끊겼다.** 대신 v1·v2가 번갈아 응답 | [2](2.rollingupdate.md#1-교체하면서-계속-호출한다) |
| 4 | Blue/Green의 전환은 어떤 모습인가 | 한 번에 넘어감. **끊김도 섞임도 없음** | [3](3.blue-green.md#2-selector를-바꿔-한-번에-전환) |

## 공통 구조 — Deployment는 RS를 갈아 끼운다

Recreate든 RollingUpdate든 내부 동작은 같다.

```
Deployment
  ├─ 옛 ReplicaSet  desired=0   (남겨둔다 → 롤백용)
  └─ 새 ReplicaSet  desired=2   (현재)
```

**Deployment는 ReplicaSet을 수정하지 않는다.** 새로 만들고 옛 것을 0으로 내린다.
차이는 *그 과정을 얼마나 급하게 하느냐* 뿐이다.

옛 RS는 `revisionHistoryLimit`(기본 10) 만큼 보관되고, 그 이상은 삭제된다.

## 어느 것을 쓰나

- **RollingUpdate** — 기본값이고 대부분 이걸 쓴다.
  단, 두 버전이 동시에 도는 것을 앱이 견딜 수 있어야 한다.
- **Recreate** — 두 버전 공존이 불가능할 때 (DB 스키마 변경 등). 짧은 다운타임을 감수한다.
- **Blue/Green** — 롤백이 즉시 필요하거나 전환 전 검증이 중요할 때. 자원 여유가 있어야 한다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete deploy \
  deployment-1 \
  deployment-2 \
  --grace-period=1 --ignore-not-found

kubectl delete rs \
  replica1 \
  replica2 \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  svc-1 \
  svc-2 \
  svc-3 \
  --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- Deployments : https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Deployment Strategy : https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy
