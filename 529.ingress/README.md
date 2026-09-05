# 529. [컨트롤러] Ingress - Service Loadbalancing, Canary Upgrade

- 원문 : https://cafe.naver.com/kubeops/529
- 실습일 : 2026-09-05
- 실습 환경 : Rocky Linux 8.8 / k8s v1.27.2 / containerd 1.6.21 / 노드 3대

Service(498)는 앱 하나에 입구 하나였다. 앱이 셋이면 포트도 셋이다.
Ingress는 **입구 하나**를 두고 URL로 갈라 보낸다. 게다가 **비율 조절과 HTTPS**까지 얹을 수 있다.

```
                         ┌─ 경로별 라우팅   (/order → 주문 서비스)
30431 ──▶ Nginx ─────────┼─ 가중치/헤더 분배 (10% 만 v2 로)
30798 ──▶ Controller     └─ TLS 종료        (https 를 여기서 풀어준다)
```

**Ingress는 규칙일 뿐이고, 실제로 일하는 것은 Ingress Controller다.**
이것을 설치하지 않으면 Ingress를 만들어도 아무 일도 일어나지 않는다.

## 문서 구성

| 파일 | 원문 위치 | 다루는 리소스 | 선행 조건 |
|---|---|---|---|
| [1.nginx-controller.md](1.nginx-controller.md) | 1) Nginx Controller | `ingress-nginx` 네임스페이스 전체 | 없음 |
| [2.service-loadbalancing.md](2.service-loadbalancing.md) | 2) Service Loadbalancing | Pod·Service 3벌, Ingress `service-loadbalancing` | **1번 필수** |
| [3.canary.md](3.canary.md) | 3) Canary Upgrade | Pod·Service `v1`·`v2`, Ingress `app`·`canary-v2`·`canary-kr` | **1번 필수** |
| [4.https.md](4.https.md) | 4) Https | Pod·Service `https`, Secret `secret-https`, Ingress `https` | **1번 필수** |

**1번을 먼저 해야 나머지가 동작한다.** 2·3·4는 서로 독립적이다.

## 실습 시작 전 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete pod,deploy,rs,statefulset,daemonset,job,cronjob \
  --all -n default --grace-period=1 --ignore-not-found

kubectl delete svc -n default \
  --field-selector 'metadata.name!=kubernetes' --ignore-not-found

# Ingress 는 위 명령으로 지워지지 않는다
kubectl delete ingress --all -n default --ignore-not-found

kubectl get all,ingress -n default            # service/kubernetes 만 남으면 정상
```

> **`-n default` 를 반드시 붙인다.** `-A` 로 실행하면 `ingress-nginx` 네임스페이스의
> 컨트롤러까지 지워진다.

## 이 실습에서 확인한 것

| # | 확인 내용 | 결과 | 상세 |
|---|---|---|---|
| 1 | 컨트롤러 설치 결과 | Pod 1개 Running, NodePort **30431/30798**, IngressClass `nginx` | [1](1.nginx-controller.md#설치-확인) |
| 2 | 경로별 라우팅 | 포트 하나로 `/`·`/customer`·`/order` 가 **각기 다른 Pod** 에 도달 | [2](2.service-loadbalancing.md#실습-과정) |
| 3 | `canary-weight: "10"` | 100회 호출에 **v1 92 / v2 8** — 약 10% | [3](3.canary.md#3-4-가중치로-나누기) |
| 4 | `canary-by-header` | `Accept-Language: kr` 만 v2, `en` 과 헤더 없음은 **모두 v1** | [3](3.canary.md#3-5-헤더로-나누기) |
| 5 | Ingress에 TLS 적용 | https 200, 인증서 subject가 **직접 만든 것과 일치** | [4](4.https.md#어떤-인증서가-쓰였는지-확인) |
| 6 | https 설정 후 http 접속 | **308 리다이렉트.** 자동으로 https 로 보낸다 | [4](4.https.md#http로-접속하면) |

## Ingress vs Service — 언제 무엇을

| | Service (NodePort/LB) | Ingress |
|---|---|---|
| 계층 | L4 (TCP/포트) | **L7 (HTTP/경로·헤더)** |
| 앱이 3개면 | 포트 3개 | **포트 1개** |
| 경로별 분기 | 불가 | 가능 |
| 트래픽 비율 조절 | 불가 | **가능 (canary)** |
| HTTPS 처리 | 앱이 직접 | **컨트롤러가 대신** |
| 별도 설치 | 불필요 | **Controller 필요** |

## host 를 쓰면 hosts 파일 등록이 필요하다

3·4번은 `host: www.app.com` 처럼 도메인을 지정한다.
DNS에 없는 이름이므로 호출하는 쪽에 등록해야 한다.

```bash
clear                                        # 화면 정리 후 시작

grep -q 'www.app.com' /etc/hosts || echo '192.168.56.30 www.app.com' >> /etc/hosts
grep -q 'www.https.com' /etc/hosts || echo '192.168.56.30 www.https.com' >> /etc/hosts

# 실습이 끝나면 지운다
sed -i '/www.app.com/d;/www.https.com/d' /etc/hosts
```

원문은 **PC의 hosts 파일**(`C:\Windows\System32\drivers\etc\hosts`)에 등록하라고 안내한다.
master에서 curl로 확인할 거라면 master의 `/etc/hosts` 에 넣으면 된다.

## 실습 후 정리

```bash
clear                                        # 화면 정리 후 시작

kubectl delete ingress \
  service-loadbalancing \
  app \
  canary-v2 \
  canary-kr \
  https \
  --ignore-not-found

kubectl delete pod \
  pod-shopping \
  pod-customer \
  pod-order \
  pod-v1 \
  pod-v2 \
  pod-https \
  --grace-period=1 --ignore-not-found

kubectl delete svc \
  svc-shopping \
  svc-customer \
  svc-order \
  svc-v1 \
  svc-v2 \
  svc-https \
  --ignore-not-found

kubectl delete secret secret-https --ignore-not-found
rm -f tls.key tls.crt
sed -i '/www.app.com/d;/www.https.com/d' /etc/hosts

# Nginx Controller 를 더 안 쓸 거라면 함께 지운다
kubectl delete -f https://raw.githubusercontent.com/k8s-1pro/install/refs/heads/main/ground/k8s-1.27/nginx-1.8.2/nginx-controller.yaml

kubectl get all,ingress -n default            # service/kubernetes 만 남으면 정상
```

## Kubernetes Reference

- Ingress : https://kubernetes.io/docs/concepts/services-networking/ingress/
- Ingress Controllers : https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/
- NGINX Ingress Annotations : https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
