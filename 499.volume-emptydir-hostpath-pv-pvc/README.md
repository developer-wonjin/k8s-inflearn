# 499. [기본오브젝트] Volume - emptyDir, hostPath, PV/PVC

- 원문 : https://cafe.naver.com/kubeops/499
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

컨테이너는 껍데기가 사라지면 안의 파일도 사라진다. 볼륨은 그 바깥에 파일을 두는 장치다.
세 방식은 **공유 범위와 수명**이 다르다.

| 방식 | 공유 범위 | 수명 | 쓰임 |
|---|---|---|---|
| `emptyDir` | 한 Pod 안의 컨테이너끼리 | **Pod과 함께 소멸** | 컨테이너 간 임시 파일 전달 |
| `hostPath` | **같은 노드**의 Pod끼리 | 노드에 남음 | 테스트, 노드 로그 수집 |
| `PV/PVC` | 정의하기 나름 | **Pod과 무관하게 영구** | 실제 데이터 보관 |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.emptydir.md](1.emptydir.md) | 1) emptyDir | Pod `pod-volume-1` | 없음 |
| [2.hostpath.md](2.hostpath.md) | 2) hostPath | Pod `pod-volume-2`·`3`·`4` | 없음 |
| [3.pv-pvc.md](3.pv-pvc.md) | 3) PVC/PV | PV `pv-01`~`03`, PVC `pvc-01`~`04`, Pod `pod-volume-5` | **2에서 만든 `/node-v` 디렉토리** |

> 3번은 2번이 worker1에 만들어 놓은 `/node-v`를 그대로 쓴다.
> 2번을 건너뛰면 `type: DirectoryOrCreate`가 아니라 PV의 `local.path`라서 디렉토리가 없으면 문제가 된다.
> **1 → 2 → 3 순서로 진행한다.**

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

> **`-n default`를 반드시 붙인다.** `-A`로 실행하면 `kube-system`, `calico-system`이
> 지워져 클러스터가 망가진다.
>
> PV는 네임스페이스에 속하지 않아 위 명령으로 지워지지 않는다.
> 3번 실습을 다시 하려면 `kubectl get pv`로 확인하고 따로 지운다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Pod을 지우면 `emptyDir`이 사라지는가 | 재생성 후 디렉토리가 **비어 있음** | [1](1.emptydir.md#검증-pod을-지우면-정말-사라지는가) |
| 2 | 다른 노드의 Pod이 같은 `hostPath`를 보는가 | worker1엔 파일, **worker2엔 없음** | [2](2.hostpath.md#검증-다른-노드의-pod은-어떻게-되는가) |
| 3 | PVC가 요청보다 큰 PV를 받으면 | 1G 요청이 **2G PV를 통째로 차지**, 나머지는 놀게 됨 | [3](3.pv-pvc.md#2-pvc-4개로-어떻게-짝지어지는지-본다) |
| 4 | `local` PV를 쓰는 Pod의 스케줄링 | `nodeSelector` 없이도 **PV의 `nodeAffinity` 노드로 끌려감** | [3](3.pv-pvc.md#3-pod에-붙인다) |
| 5 | PV의 `capacity`가 실제 디스크로 강제되는가 | **아니다.** 29G 디스크에 500Gi PV가 Bound되고, 10Mi PV에 50MB가 써진다 | [3](3.pv-pvc.md#이-값을-pv-만들기-전에-참고해야-하나--아니다) |
| 6 | `local` PV의 `nodeAffinity`가 스케줄링을 지배하는가 | **그렇다.** 볼륨만 뺀 대조군은 worker2에 뜨고, PVC를 붙이면 `Pending` | [3](3.pv-pvc.md#검증-정말-nodeaffinity-때문인가--대조군) |
| 7 | `Released` PV를 새 PVC가 재사용하는가 | **못 한다.** 조건이 같은 PVC도 `Pending`에 머문다 | [3](3.pv-pvc.md#검증-정말-재사용이-안-되나) |
| 8 | 쓰는 중인 PVC를 지우면 | `kubectl`은 `deleted`라 출력하지만 finalizer에 막혀 실제로는 안 지워진다 | [3](3.pv-pvc.md#검증-순서를-어기면-어떻게-되나) |

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

# ① Pod 먼저
kubectl delete pod \
  pod-volume-1 \
  pod-volume-2 \
  pod-volume-3 \
  pod-volume-4 \
  pod-volume-5 \
  --grace-period=1 --ignore-not-found

# ② 그다음 PVC
kubectl delete pvc \
  pvc-01 \
  pvc-02 \
  pvc-03 \
  pvc-04 \
  --ignore-not-found

# ③ 마지막으로 PV
kubectl delete pv \
  pv-01 \
  pv-02 \
  pv-03 \
  --ignore-not-found

kubectl get pv,pvc,pod -n default            # 아무것도 안 남아야 정상
```

> 노드의 `/node-v` 디렉토리와 그 안의 파일은 남는다. 쿠버네티스가 청소해주지 않는다.
> 지우려면 해당 노드에 접속해 직접 삭제한다.

## Kubernetes Reference

- Volumes : https://kubernetes.io/docs/concepts/storage/volumes/
- Persistent Volumes : https://kubernetes.io/docs/concepts/storage/persistent-volumes/
