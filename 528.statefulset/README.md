# 528. [컨트롤러] StatefulSet - Pod, PersistentVolume, Headless Service

- 원문 : https://cafe.naver.com/kubeops/528
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

## 왜 필요한가

지금까지의 컨트롤러(ReplicaSet, Deployment)는 **Pod들이 서로 구분되지 않는** 것을 전제했다.
아무거나 죽여도 되고 아무거나 요청을 받아도 된다. 웹 서버가 그렇다.

DB는 다르다. **어느 Pod이 primary인지, 어느 데이터가 누구 것인지**가 중요하다.
StatefulSet은 그런 앱을 위한 컨트롤러다.

| | ReplicaSet / Deployment | StatefulSet |
|---|---|---|
| Pod 이름 | `<이름>-<랜덤5자>` | **`<이름>-<순번>`** |
| 생성·삭제 | 동시에 | **순서대로 하나씩** |
| 볼륨 | 사람이 만든 것을 공유 | **Pod마다 자동 생성** |
| 재생성 시 | 이름·볼륨 모두 바뀜 | **이름·볼륨·데이터 유지** |
| 개별 Pod 호출 | 불가 | **Headless Service로 가능** |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.pod-naming-order.md](1.pod-naming-order.md) | 1) StatefulSet Controller | ReplicaSet `replica-web`, StatefulSet `stateful-db` | 없음 |
| [2.persistentvolume.md](2.persistentvolume.md) | 2) PersistentVolumeClaim | PVC `replica-pvc1`, ReplicaSet `replica-pvc`, StatefulSet `stateful-pvc` | 없음 |
| [3.headless-service.md](3.headless-service.md) | 3) Headless Service | Service `stateful-headless`, Pod `request-pod` | **2의 `stateful-pvc`** |

## Longhorn 없이 진행한 부분

원문의 2·3절은 `storageClassName: "fast"` 를 쓴다.
[게시글 518](https://cafe.naver.com/kubeops/518)에서 Longhorn을 설치해 만드는 StorageClass다.

> **이 실습에서는 Longhorn을 설치하지 않았다.**
> 모든 노드에 iscsi 패키지가 필요한데 워커 노드에 접근할 수 없었다.
>
> 대신 **`fast` StorageClass와 PV 4개를 수동으로 만들어** 정적으로 바인딩했다.
> 빠지는 것은 **동적 프로비저닝(PV 자동 생성)** 뿐이고,
> `volumeClaimTemplates`가 Pod마다 PVC를 만드는 동작, 볼륨이 공유되지 않는 것,
> Pod 재생성 시 같은 볼륨에 다시 붙는 것은 **모두 그대로 관찰된다.**
>
> 준비 명령은 [2번 문서](2.persistentvolume.md#이-환경에서의-대체-구성)에 있다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

kubectl delete svc -n default \
  --field-selector 'metadata.name!=kubernetes' --ignore-not-found

# PVC 와 PV 는 위 명령으로 지워지지 않는다
kubectl delete pvc --all -n default --ignore-not-found
kubectl get pv                               # 이전 실습 잔재가 있으면 따로 지운다

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Pod 이름 규칙 | RS는 `replica-web-5dh55`, STS는 **`stateful-db-0`** | [1](1.pod-naming-order.md#1-이름이-다르다) |
| 2 | 생성 순서 | RS는 3개 동시, STS는 **0 → 1 → 2 순차** | [1](1.pod-naming-order.md#2-생성-순서가-다르다) |
| 3 | 삭제 순서 | RS는 동시, STS는 **2 → 1 → 0 역순** | [1](1.pod-naming-order.md#3-삭제-순서는-반대다) |
| 4 | PVC 생성 | `volumeClaimTemplates` 가 **Pod마다 자동 생성** (`volume-stateful-pvc-0`) | [2](2.persistentvolume.md#2-3-statefulset--pod마다-자기-볼륨) |
| 5 | 볼륨 공유 여부 | RS는 3개가 같은 파일을 보고, STS는 **각자 따로** | [2](2.persistentvolume.md#2-3-statefulset--pod마다-자기-볼륨) |
| 6 | Pod 삭제 후 재생성 | **이름·PVC·데이터가 모두 그대로** 복원됨 | [2](2.persistentvolume.md#검증-pod을-지우면-볼륨은-어떻게-되는가) |
| 7 | 개별 Pod 호출 | `stateful-pvc-0.stateful-headless` 로 **정확히 지목** | [3](3.headless-service.md#2-pod마다-고유한-도메인) |

## 핵심 — 세 조각이 함께 동작한다

```
순번 이름        →  누가 누구인지 구분된다
   +
개별 볼륨        →  각자 자기 데이터를 갖는다
   +
Headless Service →  밖에서 특정 Pod을 부를 수 있다
   =
    mysql-0.mysql-headless 를 primary 로 고정할 수 있다
```

하나라도 빠지면 상태 있는 앱을 감당할 수 없다.

## PVC는 자동으로 지워지지 않는다

```bash
clear                                        # 화면 정리 후 시작
kubectl delete sts stateful-pvc              # StatefulSet 만 지운다
kubectl get pvc                              # PVC 는 그대로 남아 있다
```

**실수로 지웠을 때 데이터를 잃지 않게** 하려는 설계다.
정말 없앨 생각이면 PVC를 직접 지워야 한다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod request-pod --grace-period=1 --ignore-not-found

kubectl delete sts \
  stateful-db \
  stateful-pvc \
  --grace-period=1 --ignore-not-found

kubectl delete rs \
  replica-web \
  replica-pvc \
  --grace-period=1 --ignore-not-found

kubectl delete svc stateful-headless --ignore-not-found

kubectl delete pvc \
  replica-pvc1 \
  volume-stateful-pvc-0 \
  volume-stateful-pvc-1 \
  --ignore-not-found

kubectl delete pv \
  manual-pv-1 \
  manual-pv-2 \
  manual-pv-3 \
  manual-pv-4 \
  --ignore-not-found

kubectl delete sc fast --ignore-not-found

kubectl get all,pvc,pv -n default            # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- StatefulSets : https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Headless Services : https://kubernetes.io/docs/concepts/services-networking/service/#headless-services
