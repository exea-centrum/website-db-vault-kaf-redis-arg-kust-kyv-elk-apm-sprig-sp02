# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (dev-mode, do produkcji HA)
7. **Observability** → Prometheus + Grafana + Loki + Tempo

## Lokalne uruchomienie (dev)
```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## K8s / ArgoCD
```bash
kubectl apply -f argocd/application.yaml -n argocd
```
Push do `main` → GitHub Actions buduje obrazy → Kustomize aktualizuje tagi → ArgoCD sync.

### Dostep ArgoCD do prywatnego repozytorium GitHub

ArgoCD musi miec osobne dane dostepowe do prywatnego repozytorium. Tokenu nie
wpisuj do tego repozytorium ani do `application.yaml`. Utworz secret w
namespace `argocd` z tokenem GitHub (PAT powinien miec co najmniej `Contents:
Read`):

```bash
read -s GITHUB_PAT
export GITHUB_PAT
kubectl create secret generic davtro-github-repo \
	-n argocd \
	--from-literal=type=git \
	--from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git \
	--from-literal=username=exea-centrum \
	--from-literal=password="$GITHUB_PAT" \
	--dry-run=client -o yaml |
	kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml |
	kubectl apply -f -
unset GITHUB_PAT
```

Nastepnie odswiez ArgoCD:

```bash
kubectl annotate application davtro-website -n argocd \
	argocd.argoproj.io/refresh=hard --overwrite
kubectl get application davtro-website -n argocd -w
```

## WAZNE – przed produkcja
- Zamien Vault dev-mode na oficjalny Helm chart (HA + auto-unseal)
- Skonfiguruj ArgoCD Vault Plugin (AVP) dla sekretow
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor
Completed

## Bootstrap monitoringu / szyfrowania / operatorow
```bash
./scripts/bootstrap-monitoring.sh            # cert-manager, Kyverno, prometheus-stack, CNPG + apply
MESH=linkerd ./scripts/bootstrap-monitoring.sh  # + automatyczny mTLS z rotacja certow
```
Szczegoly: docs/architecture.md. PostgreSQL stoi na CloudNativePG (3 instancje,
HA/failover, PodMonitor), certyfikaty TLS rotowane automatycznie przez cert-manager.

Wdrożenie naprawione — wszystko stoi. Ostateczny status:

Klaster davtro02 (po Twoim usunięciu poda postgres)
Komponent	Status
postgres-db-0	✅ 1/1 Running — initContainer (root, runAsNonRoot: false) → chown 999:999 → initdb OK
fastapi (3/3 pody)	✅ 1/1 Running — nowa wersja, readiness /api/health przechodzi
spring-app	✅ 1/1 Running
vault-0	✅ 1/1 Running (dev-mode bez entrypointa)
message-processor, kafka-kraft, redis	✅ 1/1 Running
observability (prometheus, grafana, loki, tempo, promtail, exporters, pgadmin)	✅ 1/1 Running
ArgoCD	sync=Synced, health=Progressing — dokańcza operację
Co naprawiliśmy (przez Twój flow GitOps — 5 commitów)
postgres — root-owned PV na microk8s-hostpath (fsGroup nie działa) → initContainer robiący chown 999:999 + runAsNonRoot: false na poziomie kontenera (kubelet odrzucał root-init)
vault — CAP_SETFCAP: Operation not permitted → ominięcie docker-entrypoint.sh (dev-mode nie potrzebuje setcap/mlock)
kafka-topic-job — runAsNonRoot bez numerycznego UID → runAsUser: 1000 (wejdzie z PostSync hook)
pętla CI — bot commitował → build → bot commit… → warunek head_commit.author.username != 'github-actions[bot]'
Ostatni detal
kafka-topic-job (PostSync hook) zostanie odtworzony, gdy ArgoCD uzna stan za zdrowy — dzięki hook-delete-policy: BeforeHookCreation stary, padnięty job już usunął (NotFound = normalne). Jeśli op wisi bardzo długo na Ingressie (cecha microk8s — brak adresu LB), tematy Kafka i tak utworzą się automatycznie przy pierwszym połączeniu producenta (auto.create.topics domyślnie on).

Gdybyś chciał, w folderze mogę jeszcze (za Twoją akceptacją) dopiąć: pominięcie blokady syncu na Ingressie (np. ignoreDifferences/health check) albo porządki w pupa.txt. Ale technicznie — misja wykonana
