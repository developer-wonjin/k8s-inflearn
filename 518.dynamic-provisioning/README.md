# 518. [기본오브젝트] Volume - Dynamic Provisioning, StorageClass, Status, ReclaimPolicy

- 원문 : https://cafe.naver.com/kubeops/518
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

게시글 499에서는 **PV를 사람이 미리 만들었다**(정적 프로비저닝).
그 방식의 한계를 스토리지 솔루션으로 푸는 것이 이 게시글이다.

```
[정적]  사람이 PV 생성  →  PVC 가 조건에 맞는 것을 찾음  →  없으면 Pending
[동적]  PVC 생성        →  프로비저너가 PV 를 그 크기로 만들어 줌
```

## 문서 구성

| 파일 | 원문 위치 | 다루는 것 | 실습 여부 |
|---|---|---|---|
| [1.longhorn.md](1.longhorn.md) | 1) Longhorn 구축 | iscsi 설치, Longhorn, `fast` StorageClass | **미실습** |
| [2.storageclass.md](2.storageclass.md) | 2) Dynamic Provisioning | `storageClassName` 세 가지 사용법 | **부분 실습** |
| [3.pv-status-reclaim.md](3.pv-status-reclaim.md) | 3) PV Status, ReclaimPolicy | PV 상태 전이, `Released` | **완료** |

## Longhorn을 설치하지 못한 이유

```
master  : iscsi-initiator-utils is not installed
worker1 : iscsid.service 없음, initiatorname.iscsi 없음
```

Longhorn은 **모든 노드에 iscsi 패키지**를 요구한다.
이 환경에서는 워커 노드에 접속할 수 없어 설치할 수 없었다.

설치하려면 **세 노드 각각에서** 아래를 실행한다.

```bash
clear                                        # 화면 정리 후 시작

yum --setopt=tsflags=noscripts install -y iscsi-initiator-utils
echo "InitiatorName=$(/sbin/iscsi-iname)" > /etc/iscsi/initiatorname.iscsi
systemctl enable iscsid
systemctl start iscsid
systemctl is-active iscsid                   # active 여야 한다
```

그다음 [1번 문서](1.longhorn.md#1-2-longhorn-설치)의 설치 절차를 따른다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

# PVC 와 PV 는 위 명령으로 지워지지 않는다
kubectl delete pvc --all -n default --ignore-not-found
kubectl get pv                               # 남아 있으면 이름을 지정해 지운다

kubectl get sc                               # 어떤 StorageClass 가 있는지 확인
```

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | 이 클러스터의 StorageClass | **하나도 없다.** `No resources found` | [2](2.storageclass.md#2-1-비교용-pv-두-개) |
| 2 | `storageClassName` 생략 시 | **정적 바인딩됐다.** default SC가 없기 때문 | [2](2.storageclass.md#검증-생략하면-어떻게-되는가) |
| 3 | PVC 삭제 후 PV 상태 | `Bound` → **`Released`**, CLAIM 이름이 남아 있음 | [3](3.pv-status-reclaim.md#2-pvc를-지우면-released가-된다) |
| 4 | `Released` PV 재사용 | **불가.** 조건이 같은 새 PVC도 `Pending` | [3](3.pv-status-reclaim.md#검증-released-pv를-새-pvc가-쓸-수-있는가) |

## 원문과 달랐던 점

| 원문 | 이 환경의 결과 | 이유 |
|---|---|---|
| "storageClassName을 생략하면 **default StorageClass가 추가**된다" | 추가되지 않고 **정적 PV에 바인딩**됐다 | 이 클러스터에 default StorageClass가 없다 |

원문은 Longhorn 설치 후 `longhorn (default)` 가 등록된 상태를 전제한다.

> 실무에서 자주 겪는 함정이다.
> 클러스터에 default StorageClass가 없으면 `storageClassName` 을 생략한 PVC가
> **영원히 `Pending`** 이 된다(붙을 정적 PV도 없을 때).
>
> ```bash
> kubectl get sc     # (default) 표시를 먼저 확인한다
> ```

## Longhorn 없이 대체한 사례

이 저장소의 [게시글 528(StatefulSet)](../528.statefulset/README.md) 은
`storageClassName: "fast"` 를 쓴다. 거기서는 이렇게 대체했다.

```bash
clear                                        # 화면 정리 후 시작

# 프로비저너 없는 StorageClass 를 이름만 맞춰 만든다
kubectl apply -f - <<'END'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
END

# PVC 가 붙을 PV 를 미리 만들어 둔다
```

빠지는 것은 **PV 자동 생성**뿐이고, PVC 바인딩·볼륨 분리·재사용 동작은 동일하게 관찰된다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod pod-hostpath1 --grace-period=1 --ignore-not-found

kubectl delete pvc \
  pvc-hostpath1 \
  pvc-default1 \
  pvc-retry \
  --ignore-not-found

kubectl delete pv \
  pv-hostpath1 \
  pv-hostpath2 \
  --ignore-not-found

kubectl get pv,pvc -n default                # 아무것도 안 남아야 정상
```

> 노드의 `/mnt/hostpath` 디렉토리는 남는다. `Retain` 정책이라 직접 지워야 한다.

## Kubernetes Reference

- Storage Classes : https://kubernetes.io/docs/concepts/storage/storage-classes/
- Dynamic Volume Provisioning : https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/
- Persistent Volumes : https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- Longhorn : https://longhorn.io/docs/
