# 522. [기본오브젝트] Authentication - X509 Certs, Kubectl, ServiceAccount

- 원문 : https://cafe.naver.com/kubeops/522
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21

## 왜 필요한가

API 서버에 요청이 들어오면 세 관문을 거친다.

```
요청 ─▶ ① Authentication ─▶ ② Authorization ─▶ ③ Admission Control ─▶ 처리
        "너 누구야?"          "그거 해도 돼?"      "형식은 맞아?"
        ← 이 게시글            ← 게시글 525
```

이 게시글은 **①번, 신원을 증명하는 방법**만 다룬다.

| 방법 | 대상 | 수단 |
|---|---|---|
| **X509 Client Certs** | 사람, 외부 시스템 | 클라이언트 인증서 |
| **ServiceAccount** | Pod 안의 프로그램 | Bearer 토큰 |

## 문서 구성

| 파일 | 원문 위치 | 다루는 것 | 실습 여부 |
|---|---|---|---|
| [1.x509-client-certs.md](1.x509-client-certs.md) | 1) X509 Client Certs | kubeconfig 인증서, `kubectl proxy` | **완료** |
| [2.kubectl-multi-cluster.md](2.kubectl-multi-cluster.md) | 2) kubectl | 여러 클러스터 컨텍스트 전환 | **미실습** (클러스터 2개 필요) |
| [3.serviceaccount.md](3.serviceaccount.md) | 3) Service Account | SA 토큰으로 API 호출 | **완료** |

## 실습 시작 전 정리

이 게시글은 `default` 네임스페이스를 쓰지 않는다. 특별히 지울 것이 없다.

```bash
clear                                        # 화면 정리 후 시작

kubectl get ns nm-01                         # 이전 실습 잔재가 있으면 지운다
kubectl delete ns nm-01 --ignore-not-found

# kubectl proxy 가 떠 있으면 종료한다
PROXY_PID=$(pgrep -f 'kubectl proxy --port=8001' | head -1)
[ -n "$PROXY_PID" ] && kill "$PROXY_PID"
```

> **`pkill -f 'kubectl proxy'` 는 쓰지 않는다.** `-f` 패턴이 명령줄 전체를 훑기 때문에
> 그 문자열을 포함한 **현재 셸까지 죽인다.** 실습 중 실제로 겪었다.
> 위처럼 PID를 찾아 `kill` 한다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | kubeconfig 인증서는 누구를 증명하나 | `O=system:masters, CN=kubernetes-admin` — **O가 그룹, CN이 사용자** | [1](1.x509-client-certs.md#1-인증서를-꺼내본다) |
| 2 | 인증서 없이 API 호출 | **403.** 인증서를 붙이면 200 | [1](1.x509-client-certs.md#2-인증서-유무로-비교한다) |
| 3 | `kubectl proxy` 를 띄우면 | **http에 인증서 없이도 200.** proxy가 대신 인증한다 | [1](1.x509-client-certs.md#3-kubectl-proxy--인증을-대신-처리하게-하기) |
| 4 | v1.24+ 에서 SA 토큰 | **자동 생성되지 않는다.** Secret을 직접 만들어야 함 | [3](3.serviceaccount.md#2-v124부터는-토큰이-자동-생성되지-않는다) |
| 5 | SA 토큰으로 Pod 목록 조회 | **인증은 200, 조회는 403.** 인가가 없어서 | [3](3.serviceaccount.md#검증-인증은-됐는데-왜-pod-목록은-못-보는가) |

## 핵심 — 인증과 인가는 다르다

이 게시글에서 가장 중요한 대목이다.

```
curl .../api/v1                    -H "Bearer $TOKEN"  → HTTP 200   ← 인증 성공
curl .../api/v1/namespaces/nm-01/pods/ -H "Bearer $TOKEN"  → HTTP 403   ← 인가 실패
```

403 응답의 메시지를 보면 구분된다.

```
"pods is forbidden: User \"system:serviceaccount:nm-01:default\"
 cannot list resource \"pods\" ..."
```

**"누군지 모르겠다"가 아니라 "너는 아는데 권한이 없다"** 이다.
사용자 이름까지 정확히 찍힌다.

여기에 권한을 붙이는 것이 **RBAC**이고, 다음 게시글 525의 주제다.

## 쿠버네티스에 User 오브젝트는 없다

```bash
clear                                        # 화면 정리 후 시작
kubectl get serviceaccounts -A               # ServiceAccount 는 조회된다
kubectl api-resources | grep -i user         # User 는 없다
```

- **ServiceAccount** — 오브젝트로 존재한다. 만들고 지울 수 있다.
- **User** — 오브젝트가 아니다. **인증서 안의 CN/O로만 존재**한다.
  사용자를 추가한다는 것은 곧 CA로 인증서를 하나 더 발급한다는 뜻이다.

## 보안상 주의

이 실습은 **관리자 인증서를 파일로 꺼내고**, **인증 없는 proxy를 여는** 작업을 한다.

```bash
clear                                        # 화면 정리 후 시작
rm -f client.crt client.key                  # 꺼낸 인증서는 반드시 삭제

PROXY_PID=$(pgrep -f 'kubectl proxy --port=8001' | head -1)
[ -n "$PROXY_PID" ] && kill "$PROXY_PID"     # proxy 도 반드시 종료
```

- `client.key` 는 **관리자 권한 그 자체**다. 이 파일만 있으면 클러스터를 마음대로 할 수 있다.
- `kubectl proxy --accept-hosts='^*$'` 는 그 포트에 닿는 누구에게나 관리자 권한을 준다.

## 실습 후 정리

**하지 않는다.** 원문 주석대로 다음 실습(525 RBAC)에서 그대로 쓴다.

```bash
clear                                        # 화면 정리 후 시작
kubectl get ns nm-01                         # 남겨둔다
kubectl get sa,secret,pod -n nm-01           # 남겨둔다
```

인증서 파일과 proxy만 정리한다 (위 [보안상 주의](#보안상-주의) 참고).

## Kubernetes Reference

- Authenticating : https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- ServiceAccount : https://kubernetes.io/docs/concepts/security/service-accounts/
- Organizing Cluster Access Using kubeconfig : https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
