# 500. [기본오브젝트] ConfigMap, Secret - Env(Literal, File), Mount(File)

- 원문 : https://cafe.naver.com/kubeops/500
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

## 왜 필요한가

같은 이미지를 개발/운영에 함께 쓰려면 **설정을 이미지 밖으로 빼야** 한다.
그 설정을 담는 것이 `ConfigMap`(평범한 값)과 `Secret`(감출 값)이다.

주입 방법은 크게 두 가지이고, **갱신 여부가 다르다.**

| 방법 | 형태 | ConfigMap을 고치면 |
|---|---|---|
| `env` / `envFrom` | 환경변수 | **안 바뀐다.** Pod을 다시 만들어야 한다 |
| `volumeMounts` | 파일 | 바뀐다 (실측 약 75초 뒤) |

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.env-literal.md](1.env-literal.md) | 1) Env (Literal) | ConfigMap `cm-dev`, Secret `sec-dev`, Pod `pod-1` | 없음 |
| [2.env-file.md](2.env-file.md) | 2) Env (File) | ConfigMap `cm-file`, Secret `sec-file`, Pod `pod-file` | 없음 |
| [3.volume-mount.md](3.volume-mount.md) | 3) Volume Mount | Pod `pod-mount` | **2의 `cm-file` 필요** |

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

# default 네임스페이스의 실습 리소스를 전부 삭제 (시스템 네임스페이스는 건드리지 않는다)
kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

# 이 실습에서 만드는 ConfigMap·Secret 도 정리 (기본 제공되는 것은 남긴다)
kubectl delete cm \
  cm-dev \
  cm-file \
  --ignore-not-found

kubectl delete secret \
  sec-dev \
  sec-file \
  --ignore-not-found

kubectl get all -n default                   # service/kubernetes 만 남으면 정상
```

> `kubectl delete cm --all`은 쓰지 않는다. `kube-root-ca.crt`처럼
> 쿠버네티스가 자동으로 만드는 ConfigMap까지 지워지기 때문이다 (다시 생기긴 한다).

## 이 실습에서 원문과 달랐던 점

| # | 원문 | 실제 확인 결과 | 상세 |
|---|---|---|---|
| 1 | "환경변수로 들어갈 때 `.txt`는 허용되지 않아 **제거됨**" | 제거되지 않고 `file-c.txt=Content` 로 그대로 들어갔다. 다만 셸에서 `$file-c.txt`로는 못 꺼낸다 | [2](2.env-file.md#검증-envfrom-으로-넣으면-txt-가-제거되는가) |
| 2 | "마운팅은 수정 시 **즉시** 변경됨" | 즉시가 아니라 **약 75초** 걸렸다. kubelet 동기화 주기 때문 | [3](3.volume-mount.md#검증-마운트는-정말-즉시-반영되는가) |

## Secret에 대해 알아둘 것

`Secret`의 값은 **base64로 인코딩**될 뿐 암호화되지 않는다.

```bash
clear                                        # 화면 정리 후 시작
echo 'MTIzNA==' | base64 -d                  # 누구나 되돌릴 수 있다 → 1234
```

그럼에도 ConfigMap 대신 쓰는 이유는 취급 방식이 다르기 때문이다.

- 노드에 파일로 쓰이지 않고 **메모리(tmpfs)** 에 올라간다
- 로그나 조회 결과에 값이 그대로 노출되지 않는다
- RBAC으로 Secret만 따로 권한을 막을 수 있다 (게시글 525)

진짜 기밀이 필요하면 etcd 암호화나 외부 Vault를 붙인다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod \
  pod-1 \
  pod-file \
  pod-mount \
  --grace-period=1 --ignore-not-found

kubectl delete cm \
  cm-dev \
  cm-file \
  --ignore-not-found

kubectl delete secret \
  sec-dev \
  sec-file \
  --ignore-not-found

kubectl get all,cm,secret -n default         # 실습 리소스가 없어야 정상
```

## Kubernetes Reference

- ConfigMaps : https://kubernetes.io/docs/concepts/configuration/configmap/
- Secrets : https://kubernetes.io/docs/concepts/configuration/secret/
