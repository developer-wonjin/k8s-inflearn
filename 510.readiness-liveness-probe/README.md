# 510. [Pod] ReadinessProbe, LivenessProbe

- 원문 : https://cafe.naver.com/kubeops/510
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

쿠버네티스는 기본적으로 **프로세스가 살아 있는지**만 본다.
프로세스는 멀쩡한데 앱이 응답을 못 하는 상황은 알아채지 못한다.

Probe는 그 간극을 메운다. 두 종류가 있고 **하는 일이 정반대**다.

| | ReadinessProbe | LivenessProbe |
|---|---|---|
| 실패하면 | **Endpoints에서 뺀다** (트래픽 차단) | **컨테이너를 재시작한다** |
| Pod은 | 그대로 살아 있다 | 재시작된다 |
| 언제 쓰나 | 아직 준비 안 된 앱 | 고장나서 회복 못 하는 앱 |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.readinessprobe.md](1.readinessprobe.md) | 1) ReadinessProbe | Service `svc-readiness`, Pod `pod1`·`pod-readiness-exec1` | 없음 |
| [2.livenessprobe.md](2.livenessprobe.md) | 2) LivenessProbe | Service `svc-liveness`, Pod `pod-liveness-httpget1` | 없음 |

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

## 공통 설정값

두 Probe가 같은 필드를 쓴다.

| 필드 | 뜻 | 기본값 |
|---|---|---|
| `initialDelaySeconds` | Pod 생성 후 검사를 시작하기까지 대기 | 0 |
| `periodSeconds` | 검사 간격 | 10 |
| `timeoutSeconds` | 응답을 기다리는 시간 | 1 |
| `successThreshold` | 성공으로 인정하기까지 연속 성공 횟수 | 1 (Liveness는 1 고정) |
| `failureThreshold` | 실패로 판정하기까지 연속 실패 횟수 | 3 |

검사 방식도 공통이다.

| 방식 | 성공 기준 |
|---|---|
| `exec` | 명령의 종료코드가 0 |
| `httpGet` | HTTP 상태코드 **200~399** |
| `tcpSocket` | 포트 연결 성공 |

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Readiness 실패 시 Pod 상태 | `Running` 인데 **`0/1`**, `Ready=False` | [1](1.readinessprobe.md#1-probe가-실패하면-endpoints에서-빠진다) |
| 2 | Readiness 실패 Pod이 트래픽을 받는가 | **안 받는다.** Endpoints에 IP가 없다 | [1](1.readinessprobe.md#1-probe가-실패하면-endpoints에서-빠진다) |
| 3 | 조건 충족 후 합류까지 걸린 시간 | **약 35초** (`successThreshold: 3` × 10초) | [1](1.readinessprobe.md#2-조건을-만족시키면-합류한다) |
| 4 | Liveness 실패 시 재시작까지 | **약 30초** (`failureThreshold: 3` × 10초) | [2](2.livenessprobe.md#3-재시작되는-것을-지켜본다) |
| 5 | 재시작되는 것은 Pod인가 컨테이너인가 | **컨테이너.** Pod IP가 그대로 유지됨 | [2](2.livenessprobe.md#4-재시작-뒤-상태) |

## 워커 노드에 접속할 수 없을 때

원문의 ReadinessProbe 실습은 "Pod이 배치된 노드에 접속해서 `/tmp/readiness/ready.txt`를 만들라"고 한다.
워커 노드에 ssh가 안 되는 환경이라면 **컨테이너 안에서 만들면 된다.**

```bash
clear                                        # 화면 정리 후 시작
kubectl exec pod-readiness-exec1 -c readiness -- touch /readiness/ready.txt
```

hostPath로 노드의 디렉토리를 그대로 붙여놓았으므로 결과가 같다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod \
  pod1 \
  pod-readiness-exec1 \
  pod-liveness-httpget1 \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  svc-readiness \
  svc-liveness \
  --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

> 노드의 `/tmp/readiness` 디렉토리는 남는다. hostPath라 쿠버네티스가 청소하지 않는다.

## Kubernetes Reference

- Configure Liveness, Readiness and Startup Probes : https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Pod Lifecycle : https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
