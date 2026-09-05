# 삭제가 왜 30초 걸리나 — grace period와 삭제 옵션

- 측정일 : 2026-09-05
- 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21
- 요약 : Pod 삭제는 기본 **32초**, `--grace-period=1`을 붙이면 **1.3초**

## 왜 오래 걸리나

쿠버네티스는 컨테이너를 곧바로 죽이지 않는다. 앱이 정리할 시간을 준다.

```
삭제 요청
  → Pod에 deletionTimestamp 기록, Endpoints에서 제외 (트래픽 차단)
  → 컨테이너에 SIGTERM 전송
  → terminationGracePeriodSeconds 만큼 대기        ← 기본 30초
  → 아직 살아 있으면 SIGKILL
  → kubelet이 종료를 확인하면 API에서 레코드 제거
```

`kubectl delete`는 마지막 단계까지 기다렸다가 프롬프트를 돌려준다. 그래서 30초대가 나온다.

실습 이미지(`kubetm/init`, `kubetm/p8000`)는 **SIGTERM을 처리하지 않는다.**
그래서 30초를 꽉 채우고 SIGKILL로 죽는다. 매번 정확히 32초가 나오는 이유다.

> 실제 운영 앱은 SIGTERM을 받으면 진행 중인 요청을 마치고 스스로 종료하므로
> 30초를 다 쓰지 않는다. 유예 시간은 **최대치**이지 고정 대기 시간이 아니다.

## 측정 결과

Pod 하나(`kubetm/init`)를 지우는 데 걸린 실제 시간이다.

| 방법 | 소요 시간 | 종료 확인 | 안전성 |
|---|---|---|---|
| `kubectl delete pod g1` (기본) | **32.1초** | 함 | 안전 |
| `kubectl delete pod g2 --grace-period=1` | **1.3초** | 함 | 실습에선 안전 |
| `kubectl delete pod g3 --wait=false` | **0.03초** | **안 함** | 안전(뒤에서 30초 진행) |
| `kubectl delete pod g4 --grace-period=0 --force` | **0.03초** | **안 함** | **위험** |

```bash
clear                                        # 화면 정리 후 시작
time kubectl delete pod g1                   # 기본
time kubectl delete pod g2 --grace-period=1  # 유예를 1초로
time kubectl delete pod g3 --wait=false      # 요청만 보내고 반환
```

## 옵션별 의미

### `--grace-period=1` — 권장

유예 시간을 1초로 줄인다. SIGTERM을 보내고 1초 뒤 SIGKILL.
**종료 확인까지 기다리므로**, 명령이 끝났으면 Pod은 실제로 사라진 상태다.
곧바로 같은 이름으로 다시 만들어도 충돌하지 않는다.

이 저장소의 실습 문서는 전부 이 옵션을 쓴다.

### `--wait=false` — 즉시 반환

삭제 요청만 보내고 결과를 기다리지 않는다. 뒤에서는 정상 절차(30초)대로 진행된다.
**명령이 끝나도 Pod은 아직 `Terminating`이다.**
바로 다음에 같은 이름으로 `apply` 하면 충돌한다.

이어서 뭔가 만들 거라면 확인이 필요하다.

```bash
clear                                                   # 화면 정리 후 시작
kubectl delete pod pod-1 --wait=false --grace-period=1  # 요청만 보내고 즉시 반환
kubectl wait --for=delete pod/pod-1 --timeout=90s       # 완전히 사라질 때까지 확인
```

### `--grace-period=0 --force` — 위험, 최후의 수단

```
Warning: Immediate deletion does not wait for confirmation that the running
resource has been terminated. The resource may continue to run on the cluster
indefinitely.
```

경고 그대로다. **API 서버에서 레코드만 지우고 kubelet의 종료 확인을 기다리지 않는다.**
노드가 통신이 끊긴 상태였다면 컨테이너가 계속 돌면서 볼륨과 IP를 잡고 있을 수 있다.

- **StatefulSet Pod에는 절대 쓰지 않는다.** 같은 ID의 Pod이 다른 노드에 새로 뜨는데
  이전 것이 살아 있으면 같은 볼륨에 둘이 붙어 데이터가 깨진다.
- 쓸 때는 `Terminating`에서 몇 분째 멈춘 Pod을 걷어낼 때 정도다.
  그마저도 왜 멈췄는지(finalizer, 노드 NotReady) 먼저 확인하는 게 순서다.

## 리소스 종류별 차이

`--grace-period`는 **Pod에만 의미가 있다.** Deployment·Service·ConfigMap 등은
유예 시간 개념이 없어 원래 즉시 삭제된다.

| 명령 | 소요 시간 | 비고 |
|---|---|---|
| `kubectl delete deploy td --grace-period=1` | 0.04초 | 플래그와 무관하게 원래 즉시 |
| `kubectl delete svc tsvc --grace-period=1` | 0.05초 | 위와 같음 |

### 다만 Deployment를 지우면 Pod이 남는다

```bash
clear                                      # 화면 정리 후 시작
kubectl delete deploy td --grace-period=1  # 0.04초 만에 반환되지만
kubectl get pod                            # 딸린 Pod은 아직 종료 중이다
```

```
deployment.apps "td" deleted

NAME                 READY   STATUS        RESTARTS   AGE
td-d77ff6596-hkxxh   1/1     Terminating   0          2s
td-d77ff6596-qgfpx   1/1     Terminating   0          22s
```

Deployment 삭제는 즉시 끝나지만, 딸린 Pod은 **가비지 컬렉터가 별도로** 지운다.
이때 Pod에 적용되는 유예 시간은 **Pod 자신의 30초**다. Deployment에 준 `--grace-period=1`은
Pod에 전달되지 않는다.

그래서 정리 블록은 Pod을 타입 목록 맨 앞에 명시해 함께 지운다.

```bash
clear  # 화면 정리 후 시작
kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found
```

> **주의 — 이미 종료 중인 Pod에는 소용이 없다.**
> `Terminating` 상태로 이미 30초 유예가 걸린 Pod에 뒤늦게 `--grace-period=1`을 줘도
> 기다리는 시간이 줄지 않는다. 측정 중 실제로 겪었다 — 앞선 테스트의 잔재가 남은 상태에서
> 재보니 28.7초가 나왔고, 완전히 정리한 뒤 다시 재니 1.3초였다.
> **측정할 때는 이전 실습이 완전히 정리됐는지 먼저 확인한다.**

## 관련 옵션

| 옵션 | 뜻 |
|---|---|
| `--grace-period=N` | 유예 시간(초). `0`은 `--force`와 함께 써야 한다 |
| `--wait=false` | 삭제 완료를 기다리지 않고 즉시 반환 |
| `--force` | 종료 확인 없이 API에서 즉시 제거 |
| `--ignore-not-found` | 대상이 없어도 에러로 치지 않음 (exit code 0) |
| `--cascade=orphan` | 하위 리소스는 남기고 상위만 삭제 |
| `--now` | `--grace-period=1` 과 같다 (짧은 표기) |

> `--now`가 정확히 `--grace-period=1`이다. 문서에서는 의미가 분명한 쪽을 택해
> `--grace-period=1`로 통일했다.

## 삭제가 안 끝날 때

`Terminating`에서 몇 분째 멈춰 있다면 강제 삭제 전에 원인을 본다.

```bash
clear                                                        # 화면 정리 후 시작
POD=pod-1                                                    # 멈춰 있는 Pod 이름을 넣는다
kubectl get pod "$POD" -o jsonpath='{.metadata.finalizers}'  # finalizer가 남아 있는지
kubectl describe pod "$POD" | grep -A8 '^Events'             # kubelet이 뭘 못 하고 있는지
kubectl get node                                             # 노드가 NotReady 인지
```

- **finalizer**가 남아 있으면 그것을 처리하는 컨트롤러가 죽었거나 조건을 못 맞춘 것이다.
- **노드가 NotReady**면 kubelet이 종료를 보고할 수 없어 영원히 `Terminating`이다.
  이 경우가 `--force`가 정당한 거의 유일한 상황이다.

## 정리

- 기본 30초는 **버그가 아니라 안전장치**다. 트래픽을 빼고 앱이 정리할 시간을 주는 것.
- 실습에서는 `--grace-period=1`로 충분하다. **1.3초**로 줄면서 종료 확인은 유지된다.
- `--force`는 상태를 망칠 수 있다. 노드가 죽어 `Terminating`이 안 풀릴 때만 쓴다.
- Deployment를 지워도 Pod은 자기 유예 시간을 따로 쓴다. 빨리 없애려면 Pod을 함께 지정한다.

## 참고

- Pod Lifecycle / Termination : https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination
- Force Delete StatefulSet Pods : https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/
- `kubectl delete --help`
