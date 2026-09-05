# 513. [Pod] Node Scheduling - Node Affinity, Pod Affinity/Anti-Affinity, Toleration/Taint

- 원문 : https://cafe.naver.com/kubeops/513
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

Pod을 어느 노드에 올릴지 정하는 방법 세 가지. **기준이 각각 다르다.**

| 방식 | 무엇을 보나 | 누가 주도하나 |
|---|---|---|
| **Node Affinity** | 노드의 라벨 | Pod이 노드를 고른다 |
| **Pod Affinity** | 다른 Pod의 라벨 | Pod이 Pod을 따라간다 |
| **Taint / Toleration** | 노드의 거부 표시 | **노드가 Pod을 밀어낸다** |

497에서 본 `nodeSelector`는 Node Affinity의 가장 단순한 형태다.

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.node-affinity.md](1.node-affinity.md) | 1) Node Affinity | Pod `pod-match-expressions1`·`pod-required`·`pod-preferred` | 없음 |
| [2.pod-affinity.md](2.pod-affinity.md) | 2) Pod Affinity / Anti-Affinity | Pod `web1`·`server1`·`web2`·`server2`·`master`·`slave` | 없음 |
| [3.taint-toleration.md](3.taint-toleration.md) | 3) Taint / Toleration | Pod `pod-no-toleration`·`pod-with-toleration` | 없음 |

세 문서 모두 **노드에 라벨을 붙였다 떼는** 작업을 한다.
한 문서를 끝내면 반드시 정리하고 다음으로 넘어간다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod --all -n default --grace-period=1 --ignore-not-found

# 이전 실습에서 붙인 노드 라벨을 모두 제거한다
kubectl label nodes k8s-worker1 k8s-worker2 \
  kr- \
  us- \
  a-team- \
  gpu- \
  os- \
  --overwrite

# taint 도 제거한다 (남아 있으면 그 노드에 아무것도 못 뜬다)
kubectl taint nodes k8s-worker1 hw- hw2-

kubectl get nodes --show-labels               # 실습용 라벨이 없어야 정상
kubectl describe node k8s-worker1 | grep -A1 '^Taints'
```

> 라벨·taint 제거 명령은 대상이 없으면 에러를 내지만 무시해도 된다.
> `label ... key-` 와 `taint ... key-` 의 **뒤에 붙은 `-` 가 삭제**를 뜻한다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | `required` 조건에 맞는 노드가 없으면 | **`Pending`** 으로 무한 대기 | [1](1.node-affinity.md#2-세-가지-pod을-동시에-만들어-비교한다) |
| 2 | `preferred` 조건에 맞는 노드가 없으면 | **그냥 배치된다.** 선호일 뿐 | [1](1.node-affinity.md#2-세-가지-pod을-동시에-만들어-비교한다) |
| 3 | 따라갈 Pod이 없는 podAffinity | `Pending` → **대상이 생기면 자동 배치** | [2](2.pod-affinity.md#3-대상이-생기면-따라간다) |
| 4 | `podAntiAffinity` | `nodeSelector` 없이 **반대편 노드로** 배치됨 | [2](2.pod-affinity.md#4-anti-affinity--떨어뜨리기) |
| 5 | taint가 있는 노드에 toleration 없는 Pod | `Pending`. `untolerated taint {hw: gpu}` | [3](3.taint-toleration.md#2-toleration-유무로-비교한다) |
| 6 | `NoExecute` taint를 나중에 걸면 | **이미 떠 있던 Pod이 삭제된다** | [3](3.taint-toleration.md#검증-noexecute는-이미-떠-있는-pod도-쫓아내는가) |

## 이 클러스터의 특이점

master에 `NoSchedule` taint가 **없다.**

```bash
clear                                        # 화면 정리 후 시작
kubectl get node k8s-master -o jsonpath='{.spec.taints}'   # 빈 값
```

보통 kubeadm 클러스터의 control-plane에는
`node-role.kubernetes.io/control-plane:NoSchedule` 이 붙어 일반 Pod이 배치되지 않는다.
여기서는 그것이 제거돼 있어 **master도 스케줄링 후보가 된다.**

강의 화면과 노드 분포가 달라 보이는 원인이고,
동시에 이 게시글의 Taint 개념이 실제로 어디에 쓰이는지 보여주는 예이기도 하다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod --all -n default --grace-period=1 --ignore-not-found

kubectl label nodes k8s-worker1 k8s-worker2 \
  kr- \
  us- \
  a-team- \
  gpu- \
  --overwrite

kubectl taint nodes k8s-worker1 hw- hw2-

kubectl get all -n default                    # service/kubernetes 만 남으면 정상
kubectl describe node k8s-worker1 | grep -A1 '^Taints'
```

## Kubernetes Reference

- Assigning Pods to Nodes : https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- Taints and Tolerations : https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
