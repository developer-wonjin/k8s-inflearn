# 507. [컨트롤러] DaemonSet, Job, CronJob

- 원문 : https://cafe.naver.com/kubeops/507
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

## 왜 필요한가

Deployment는 "N개를 계속 띄워라"였다. 이 세 가지는 목적이 다르다.

| 컨트롤러 | 개수를 정하는 기준 | Pod의 정상 상태 |
|---|---|---|
| `DaemonSet` | **노드 수** (replicas 없음) | 계속 떠 있음 |
| `Job` | `completions` | **끝나는 것** |
| `CronJob` | 시각마다 Job을 생성 | (Job에 위임) |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.daemonset.md](1.daemonset.md) | 1) DaemonSet | DaemonSet `daemonset-1`·`daemonset-2` | 없음 |
| [2.job.md](2.job.md) | 2) Job | Job `job-1`·`job-2` | 없음 |
| [3.cronjob.md](3.cronjob.md) | 3) CronJob | CronJob `cron-job` | 없음 |

세 문서는 독립적이라 순서에 상관없이 진행해도 된다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

# default 네임스페이스의 실습 리소스를 전부 삭제 (시스템 네임스페이스는 건드리지 않는다)
kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상

# DaemonSet 실습에서 붙인 노드 라벨도 정리한다
kubectl label nodes k8s-worker1 k8s-worker2 os- --overwrite
```

> **`-n default`를 반드시 붙인다.** `-A`로 실행하면 `calico-node`, `kube-proxy`,
> `csi-node-driver` 같은 **시스템 DaemonSet이 지워져 클러스터가 망가진다.**
> 이 게시글은 DaemonSet을 다루므로 특히 주의한다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | DaemonSet은 몇 개를 만드는가 | 노드 3대 → **Pod 3개.** master 포함 (taint 없음) | [1](1.daemonset.md#1-노드마다-하나씩-생기는가) |
| 2 | `hostPort`는 노드를 넘는가 | **안 넘는다.** 각 노드가 자기 Pod에만 연결 | [1](1.daemonset.md#2-hostport--자기-노드의-pod에만-간다) |
| 3 | 노드 라벨을 바꾸면 | yaml을 안 고쳐도 **DESIRED가 1→2로 자동 증가** | [1](1.daemonset.md#검증-노드-라벨을-바꾸면-즉시-반응하는가) |
| 4 | Job이 끝나면 Pod은 | 삭제되지 않고 **`Completed`로 남는다** | [2](2.job.md#1-작업이-끝나면-어떻게-되는가) |
| 5 | `activeDeadlineSeconds` 초과 시 | 6개 중 **2개만 완료**, 실행 중이던 Pod은 삭제, `DeadlineExceeded` | [2](2.job.md#2-여러-개를-몇-개씩-제한-시간-안에) |
| 6 | `suspend: true` 의 효과 | **새 Job 생성만** 멈춘다. 90초간 개수 변화 없음 | [3](3.cronjob.md#4-suspend--일시-정지) |

## hostPort vs nodePort

이 게시글에서 가장 헷갈리는 지점이다.

| | `hostPort` (Pod) | `nodePort` (Service) |
|---|---|---|
| 연결 대상 | **그 노드의 Pod만** | 클러스터 전체 Endpoints |
| 부하 분산 | 없음 | 있음 |
| 포트 범위 | 제한 없음 | 30000~32767 |
| 노드당 중복 | 불가 (실제 포트 점유) | 불가 (클러스터 전체에서 유일) |

`hostPort`는 "이 노드의 에이전트에 접근"할 때, `nodePort`는 "서비스에 접근"할 때 쓴다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete ds \
  daemonset-1 \
  daemonset-2 \
  --grace-period=1 --ignore-not-found

kubectl delete cronjob cron-job --ignore-not-found

# CronJob을 지워도 이미 만들어진 Job은 남으므로 따로 지운다
kubectl delete job --all -n default --grace-period=1 --ignore-not-found

kubectl label nodes k8s-worker1 k8s-worker2 os- --overwrite

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- DaemonSet : https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
- Jobs : https://kubernetes.io/docs/concepts/workloads/controllers/job/
- CronJob : https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
