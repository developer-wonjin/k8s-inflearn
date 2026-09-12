# 526. [기본오브젝트] Dashboard - Kubeconfig, Token

- 원문 : https://cafe.naver.com/kubeops/526
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

## 왜 필요한가

522(인증)와 525(인가)에서 배운 것이 **실제 도구에서 어떻게 쓰이는지** 보는 게시글이다.

Dashboard는 특별한 권한을 갖고 있지 않다.
**로그인할 때 넣은 토큰을 그대로 API 서버에 전달**할 뿐이고,
그 토큰의 권한만큼만 화면에 보인다.

```
브라우저 ──토큰──▶ Dashboard ──같은 토큰──▶ API 서버
                                              ↑ 여기서 인증·인가가 일어난다
```

## 문서 구성

| 파일 | 원문 위치 | 다루는 것 | 실습 여부 |
|---|---|---|---|
| [1.token-login.md](1.token-login.md) | 1) Token 방식으로 Dashboard 로그인 | ServiceAccount 토큰 생성, 권한 확인, 접속 경로 | **서버 쪽 완료** |

원문의 1-4 ~ 1-7(인증서 PC 설치, Chrome 확장 ModHeader 설정)은
**브라우저에서 하는 작업**이라 서버에서 재현할 수 없다. 방법만 정리해 두었다.

## 실습 시작 전 확인

이 게시글은 `default` 네임스페이스를 쓰지 않는다.
클러스터에 이미 설치된 Dashboard를 대상으로 한다.

```bash
clear                                        # 화면 정리 후 시작

kubectl get all -n kubernetes-dashboard      # Dashboard 가 떠 있어야 한다
kubectl get svc -n kubernetes-dashboard kubernetes-dashboard
```

Dashboard가 없다면 이 게시글은 진행할 수 없다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | Dashboard SA의 권한 | ClusterRoleBinding `kubernetes-dashboard2` 로 **`cluster-admin`** 이 묶여 있다 | [1](1.token-login.md#1-dashboard가-어떤-권한을-갖고-있나) |
| 2 | 그 토큰으로 할 수 있는 일 | `delete nodes`, `create clusterrolebinding` **모두 yes** | [1](1.token-login.md#3-이-토큰으로-무엇을-할-수-있나) |
| 3 | NodePort 로 직접 접속 | master·worker 모두 **HTTP 200** (포트 30000) | [1](1.token-login.md#4-접속-경로-두-가지) |
| 4 | API 서버 proxy 경로 | 토큰 있이 **200**, 없이 **403** | [1](1.token-login.md#4-접속-경로-두-가지) |

## 접속 경로 두 가지 — 어느 쪽을 쓸까

| | NodePort 직접 | API 서버 proxy |
|---|---|---|
| 주소 | `https://192.168.56.30:30000` | `https://192.168.56.30:6443/api/v1/.../proxy/` |
| 인증 | Dashboard 로그인 화면에서 | **요청 헤더에 토큰 필요** |
| 브라우저 확장 | 불필요 | **ModHeader 등 필요** |
| PC 인증서 설치 | 불필요 | 필요 |

**실습에서는 NodePort가 훨씬 간단하다.**
원문이 proxy 경로를 안내하는 것은 NodePort를 열지 않은 환경을 전제하기 때문이다.
이 클러스터는 30000번이 이미 열려 있다.

> 참고로 게시글 497·501에서 "실습 포트는 30001을 쓰라"고 한 이유가 이것이다.
> **30000번은 Dashboard가 이미 쓰고 있다.**

## 보안상 짚어둘 것

이 실습에서 만든 토큰은 **클러스터 관리자 자격증명**이다.

```bash
clear                                        # 화면 정리 후 시작

SA=system:serviceaccount:kubernetes-dashboard:kubernetes-dashboard
kubectl auth can-i delete nodes --as=$SA              # yes
kubectl auth can-i create clusterrolebinding --as=$SA # yes
```

- 토큰 문자열을 채팅·문서·스크린샷에 남기지 않는다.
- 만료가 없는 토큰이라(`Secret` 방식) 유출되면 계속 유효하다.
- 실무에서는 Dashboard SA에 `cluster-admin`을 붙이지 않고,
  **사용자별 SA에 필요한 만큼만** 권한을 줘서 각자 로그인하게 한다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

# 이 실습에서 만든 것은 Secret 하나뿐이다
kubectl delete secret kubernetes-dashboard-token -n kubernetes-dashboard --ignore-not-found

# 인증서를 꺼냈다면 함께 삭제한다
rm -f client.crt client.key client.p12 client.cer

kubectl get secret -n kubernetes-dashboard   # 실습 토큰이 없어야 정상
```

> **ServiceAccount 와 ClusterRoleBinding 은 지우지 않는다.**
> 클러스터 설치 때부터 있던 것이라 지우면 Dashboard가 동작하지 않는다.

## Kubernetes Reference

- Web UI (Dashboard) : https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- Access Clusters Using the Kubernetes API : https://kubernetes.io/docs/tasks/administer-cluster/access-cluster-api/
