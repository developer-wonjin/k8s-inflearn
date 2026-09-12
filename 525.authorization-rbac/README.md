# 525. [기본오브젝트] Authorization - RBAC, Role, RoleBinding

- 원문 : https://cafe.naver.com/kubeops/525
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21
- **선행 조건 : [게시글 522](../522.authentication/README.md) 의 `nm-01` 리소스**

## 왜 필요한가

522에서 토큰은 통했는데 403이 났다. 그 이유가 여기 있다.

```
① Authentication  "너 누구야?"     → 522. 토큰으로 통과
② Authorization   "그거 해도 돼?"  → 525. ← 이 게시글
```

RBAC(Role-Based Access Control)은 **역할에 권한을 담고, 그 역할을 사용자에게 붙이는** 방식이다.

```
Subject ──── Binding ────▶ Role
(누가)       (연결)         (무엇을)
```

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.role-rolebinding.md](1.role-rolebinding.md) | 1) Role, RoleBinding | Role `r-01`, RoleBinding `rb-01`, Service `svc-1` | **522의 `nm-01`** |
| [2.clusterrole.md](2.clusterrole.md) | 2) ClusterRole, ClusterRoleBinding | Namespace `nm-02`, SA `sa-02`, ClusterRole `cr-02` | 1번을 먼저 |

## 실습 시작 전 확인

이 게시글은 **522에서 만든 리소스를 이어받는다.** 지우면 안 된다.

```bash
clear                                        # 화면 정리 후 시작

kubectl get ns nm-01                         # 있어야 한다
kubectl get sa,secret,pod -n nm-01           # default SA, nm-01 Secret, pod-1

# 없다면 522 의 3번 문서를 먼저 실습한다
```

## 네 가지 조합

RBAC의 오브젝트는 네 개인데, 조합이 헷갈린다.

| Role 종류 | Binding 종류 | 유효 범위 |
|---|---|---|
| `Role` | `RoleBinding` | 그 네임스페이스 안 |
| `ClusterRole` | `ClusterRoleBinding` | **클러스터 전체** |
| `ClusterRole` | `RoleBinding` | **그 네임스페이스 안에서만** (내장 Role 재사용에 유용) |
| `Role` | `ClusterRoleBinding` | **불가능** |

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Role 적용 전 | pods·services **모두 403** | [1](1.role-rolebinding.md#1-적용-전-상태) |
| 2 | `resources: ["pods"]` Role 적용 후 | pods **200**, services **403** | [1](1.role-rolebinding.md#2-role과-rolebinding을-붙인다) |
| 3 | `verbs: ["get","list"]` 로 DELETE 시도 | **403.** 동작 단위로도 갈린다 | [1](1.role-rolebinding.md#3-verb-단위로도-갈린다) |
| 4 | ClusterRole `*` 토큰 | 다른 ns·`nodes` 까지 **전부 200** | [2](2.clusterrole.md#1-두-토큰을-나란히-비교한다) |
| 5 | Role 토큰으로 다른 ns 조회 | **403.** Role은 자기 ns 안에서만 | [2](2.clusterrole.md#1-두-토큰을-나란히-비교한다) |

## 권한을 확인하는 가장 빠른 방법

curl로 하나씩 찔러볼 필요 없다.

```bash
clear                                        # 화면 정리 후 시작

kubectl auth can-i get pods -n nm-01 \
  --as=system:serviceaccount:nm-01:default   # yes

kubectl auth can-i delete pods -n nm-01 \
  --as=system:serviceaccount:nm-01:default   # no

kubectl auth can-i --list -n nm-01 \
  --as=system:serviceaccount:nm-01:default   # 가진 권한 전부 나열
```

`--as` 는 **다른 사용자인 척** 물어보는 기능(impersonation)이다.
권한 설계를 검증할 때 이것부터 쓴다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

# ClusterRole / ClusterRoleBinding 은 네임스페이스에 속하지 않아 따로 지운다
kubectl delete clusterrolebinding rb-02 --ignore-not-found
kubectl delete clusterrole cr-02 --ignore-not-found

kubectl delete ns \
  nm-01 \
  nm-02 \
  --ignore-not-found

kubectl get clusterrole,clusterrolebinding | grep -E 'cr-02|rb-02'   # 없어야 정상
```

> **네임스페이스를 지워도 ClusterRole·ClusterRoleBinding은 남는다.**
> 클러스터 자원이라 소속이 없기 때문이다. 반드시 따로 지운다.
>
> 게시글 526(Dashboard)을 이어서 할 계획이면 `nm-01`·`nm-02`는 지워도 되지만,
> 526은 별도의 ServiceAccount와 ClusterRoleBinding을 다시 만든다.

## Kubernetes Reference

- Using RBAC Authorization : https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Authorization Overview : https://kubernetes.io/docs/reference/access-authn-authz/authorization/
