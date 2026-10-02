#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02"
NAMESPACE="davtro"

echo "=========================================================================="
echo "  DavTro Rentals - Istio + Vault PKI + Kyverno + GitOps (Complete Mesh)   "
echo "=========================================================================="

mkdir -p ${PROJECT_NAME}/manifests/{base,istio-system,kyverno-policies,argocd}

# ==============================================================================
# 1. NAMESPACE & ISTIO INJECTION
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/01-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    istio-injection: enabled
    pod-security.kubernetes.io/enforce: baseline
EOF

# ==============================================================================
# 2. ISTIO CONTROL PLANE & VAULT PKI INTEGRATION (istio-csr)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/istio-system/02-istio-vault-config.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-istio-ca-issuer
spec:
  vault:
    server: http://vault.davtro.svc.cluster.local:8200
    path: pki_istio/sign/istio-ca
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: cert-manager-istio
        secretRef:
          name: cert-manager-vault-token
          key: token
---
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: istio-control-plane
spec:
  profile: default
  values:
    global:
      trustDomain: cluster.local
      caAddress: cert-manager-istio-csr.cert-manager.svc:443
    pilot:
      env:
        ENABLE_CA_SERVER: "false"
EOF

# ==============================================================================
# 3. SECURITY: STRICT mTLS & L7 AUTHORIZATION POLICIES
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/03-security-mesh.yaml << 'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict-mtls
  namespace: davtro
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: postgres-l7-policy
  namespace: davtro
spec:
  selector:
    matchLabels:
      app: postgres
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/davtro/sa/fastapi-sa"
        - "cluster.local/ns/davtro/sa/spring-app-sa"
    to:
    - operation:
        ports: ["5432"]
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: kafka-l7-policy
  namespace: davtro
spec:
  selector:
    matchLabels:
      app: kafka
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/davtro/sa/fastapi-sa"
        - "cluster.local/ns/davtro/sa/message-processor-sa"
        - "cluster.local/ns/davtro/sa/spark-sa"
    to:
    - operation:
        ports: ["9092"]
EOF

# ==============================================================================
# 4. ISTIO INGRESS GATEWAY & EXTERNAL SSL (davtro.local)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/04-ingress-ssl.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: davtro-local-tls-cert
  namespace: istio-system
spec:
  secretName: davtro-local-tls-cert
  issuerRef:
    name: vault-istio-ca-issuer
    kind: ClusterIssuer
  commonName: davtro.local
  dnsNames:
  - davtro.local
  - "*.davtro.local"
---
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: davtro-gateway
  namespace: davtro
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "davtro.local"
    redirect:
      httpsRedirect: true
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: davtro-local-tls-cert
    hosts:
    - "davtro.local"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: davtro-virtualservice
  namespace: davtro
spec:
  hosts:
  - "davtro.local"
  gateways:
  - davtro-gateway
  http:
  - match:
    - uri:
        prefix: /api/v1/messages
    route:
    - destination:
        host: message-processor.davtro.svc.cluster.local
        port:
          number: 8080
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: fastapi-app.davtro.svc.cluster.local
        port:
          number: 8000
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend-service.davtro.svc.cluster.local
        port:
          number: 80
EOF

# ==============================================================================
# 5. POSTGRESQL STATEFULSET (PV Permissions InitContainer Only)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/05-postgres.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: davtro
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      serviceAccountName: postgres-sa
      initContainers:
      - name: init-chmod-data
        image: busybox:1.36
        command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data && chmod 700 /var/lib/postgresql/data"]
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: davtrodb
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: davtro
spec:
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgres
EOF

# ==============================================================================
# 6. KAFKA KRAFT & POST-SYNC TOPIC CREATION JOB
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/06-kafka-kraft.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: davtro
spec:
  serviceName: kafka
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.5
        ports:
        - containerPort: 9092
        env:
        - name: KAFKA_CFG_NODE_ID
          value: "0"
        - name: KAFKA_CFG_PROCESS_ROLES
          value: "controller,broker"
        - name: KAFKA_CFG_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
          value: "0@kafka:9093"
        - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: davtro
spec:
  ports:
  - port: 9092
    name: plaintext
  selector:
    app: kafka
---
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-creator
  namespace: davtro
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: create-topics
        image: bitnami/kafka:3.5
        command:
        - /bin/bash
        - -c
        - |
          /opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic bookings-created --partitions 3 --replication-factor 1
          /opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic marketing-actions --partitions 3 --replication-factor 1
          /opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic email-invoices --partitions 3 --replication-factor 1
      restartPolicy: OnFailure
EOF

# ==============================================================================
# 7. REDIS
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/07-redis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: davtro
spec:
  ports:
  - port: 6379
  selector:
    app: redis
EOF

# ==============================================================================
# 8. HASHICORP VAULT (Dev-Mode & IPC Lock Bypass)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/08-vault.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:1.15
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
        - name: VAULT_DEV_LISTEN_ADDRESS
          value: "0.0.0.0:8200"
        - name: VAULT_DISABLE_MLOCK
          value: "true"
        securityContext:
          capabilities:
            add: ["IPC_LOCK"]
        ports:
        - containerPort: 8200
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtro
spec:
  ports:
  - port: 8200
  selector:
    app: vault
EOF

# ==============================================================================
# 9. BACKEND APPLICATIONS (FastAPI & Message Processor)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/09-apps.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-app
  template:
    metadata:
      labels:
        app: fastapi-app
    spec:
      serviceAccountName: fastapi-sa
      containers:
      - name: fastapi
        image: ghcr.io/exea-centrum/fastapi-app:v1.0.0
        ports:
        - containerPort: 8000
        env:
        - name: DB_HOST
          value: "postgres"
        - name: KAFKA_HOST
          value: "kafka:9092"
        - name: VAULT_ADDR
          value: "http://vault:8200"
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-app
  namespace: davtro
spec:
  ports:
  - port: 8000
  selector:
    app: fastapi-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: message-processor
  template:
    metadata:
      labels:
        app: message-processor
    spec:
      serviceAccountName: message-processor-sa
      containers:
      - name: processor
        image: ghcr.io/exea-centrum/message-processor:v1.0.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: message-processor
  namespace: davtro
spec:
  ports:
  - port: 8080
  selector:
    app: message-processor
EOF

# ==============================================================================
# 10. SPRING BOOT APPLICATION
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/10-spring-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-app
  template:
    metadata:
      labels:
        app: spring-app
    spec:
      serviceAccountName: spring-app-sa
      containers:
      - name: spring
        image: ghcr.io/exea-centrum/spring-app:v1.0.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app
  namespace: davtro
spec:
  ports:
  - port: 8080
  selector:
    app: spring-app
EOF

# ==============================================================================
# 11. APACHE SPARK (Master & Worker)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/11-spark.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spark-master
  template:
    metadata:
      labels:
        app: spark-master
    spec:
      serviceAccountName: spark-sa
      containers:
      - name: spark-master
        image: bitnami/spark:3.4
        env:
        - name: SPARK_MODE
          value: master
        ports:
        - containerPort: 7077
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  namespace: davtro
spec:
  ports:
  - port: 7077
    name: cluster
  - port: 8080
    name: webui
  selector:
    app: spark-master
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spark-worker
  template:
    metadata:
      labels:
        app: spark-worker
    spec:
      containers:
      - name: spark-worker
        image: bitnami/spark:3.4
        env:
        - name: SPARK_MODE
          value: worker
        - name: SPARK_MASTER_URL
          value: spark://spark-master:7077
EOF

# ==============================================================================
# 12. PROMETHEUS & EXPORTERS (Postgres, Redis, JMX)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/12-prometheus-exporters.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        ports:
        - containerPort: 9090
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: davtro
spec:
  ports:
  - port: 9090
  selector:
    app: prometheus
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
    spec:
      containers:
      - name: exporter
        image: prometheuscommunity/postgres-exporter:v0.12.0
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://postgres:postgres@postgres:5432/davtrodb?sslmode=disable"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-exporter
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-exporter
  template:
    metadata:
      labels:
        app: redis-exporter
    spec:
      containers:
      - name: exporter
        image: oliver006/redis_exporter:v1.52.0
        env:
        - name: REDIS_ADDR
          value: "redis:6379"
EOF

# ==============================================================================
# 13. GRAFANA
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/13-grafana.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.0.0
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: davtro
spec:
  ports:
  - port: 3000
  selector:
    app: grafana
EOF

# ==============================================================================
# 14. LOKI & PROMTAIL
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/14-loki-promtail.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: davtro
spec:
  serviceName: loki
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.8.2
        ports:
        - containerPort: 3100
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: davtro
spec:
  ports:
  - port: 3100
  selector:
    app: loki
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: davtro
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      containers:
      - name: promtail
        image: grafana/promtail:2.8.2
EOF

# ==============================================================================
# 15. TEMPO (Distributed Tracing)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/15-tempo.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.1.1
        ports:
        - containerPort: 3200
        - containerPort: 4317 # OTLP gRPC
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: davtro
spec:
  ports:
  - port: 3200
    name: tempo
  - port: 4317
    name: otlp-grpc
  selector:
    app: tempo
EOF

# ==============================================================================
# 16. MANAGEMENT UIs (pgAdmin & Kafka-UI)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/16-admin-uis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:7.4
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: "admin@davtro.local"
        - name: PGADMIN_DEFAULT_PASSWORD
          value: "admin"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: davtro
spec:
  ports:
  - port: 80
  selector:
    app: pgadmin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: davtro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:v0.7.0
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: "davtro-cluster"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: "kafka:9092"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: davtro
spec:
  ports:
  - port: 8080
  selector:
    app: kafka-ui
EOF

# ==============================================================================
# 17. SCALABILITY & AVAILABILITY (HPA & PDB)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/17-hpa-pdb.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
  namespace: davtro
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgres-pdb
  namespace: davtro
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: postgres
EOF

# ==============================================================================
# 18. SERVICE ACCOUNTS
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/18-service-accounts.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-sa
  namespace: davtro
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: davtro
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: message-processor-sa
  namespace: davtro
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spring-app-sa
  namespace: davtro
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark-sa
  namespace: davtro
EOF

# ==============================================================================
# 19. DUMMY SECRETS (Placeholders for External Secrets Operator)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/19-secrets.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: davtro
type: Opaque
stringData:
  username: postgres
  password: postgres-dev-password
EOF

# ==============================================================================
# 20. KYVERNO POLICIES (Enforcing Istio Sidecar Injection & Best Practices)
# ==============================================================================
cat > ${PROJECT_NAME}/kyverno-policies/20-kyverno-istio-policy.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-istio-sidecar-present
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: require-istio-proxy
    match:
      any:
      - resources:
          namespaces:
          - davtro
          kinds:
          - Pod
    validate:
      message: "Pod musi posiadać wstrzyknięty kontener envoy-proxy przez Istio!"
      pattern:
        spec:
          containers:
          - name: "istio-proxy"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Audit
  rules:
  - name: validate-image-tag
    match:
      any:
      - resources:
          namespaces:
          - davtro
          kinds:
          - Pod
    validate:
      message: "Używanie tagu :latest jest niedozwolone na środowisku produkcyjnym."
      pattern:
        spec:
          containers:
          - image: "!*:latest"
EOF

# ==============================================================================
# 21. FRONTEND SERVICE & DEPLOYMENT
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/21-frontend.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
  namespace: davtro
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend-app
  template:
    metadata:
      labels:
        app: frontend-app
    spec:
      containers:
      - name: frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: davtro
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: frontend-app
EOF

# ==============================================================================
# 22. BASE KUSTOMIZATION MANIFEST
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: davtro

resources:
  - 01-namespace.yaml
  - 03-security-mesh.yaml
  - 04-ingress-ssl.yaml
  - 05-postgres.yaml
  - 06-kafka-kraft.yaml
  - 07-redis.yaml
  - 08-vault.yaml
  - 09-apps.yaml
  - 10-spring-app.yaml
  - 11-spark.yaml
  - 12-prometheus-exporters.yaml
  - 13-grafana.yaml
  - 14-loki-promtail.yaml
  - 15-tempo.yaml
  - 16-admin-uis.yaml
  - 17-hpa-pdb.yaml
  - 18-service-accounts.yaml
  - 19-secrets.yaml
  - 21-frontend.yaml
EOF

# ==============================================================================
# 23. PRODUCTION OVERLAY (Kustomize)
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/overlays/production/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: davtro

resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: fastapi-app
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
EOF

# ==============================================================================
# 24. ARGOCD APPLICATION MANIFEST
# ==============================================================================
cat > ${PROJECT_NAME}/manifests/argocd/application.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-rentals-mesh
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git'
    targetRevision: HEAD
    path: manifests/overlays/production
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: davtro
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "=========================================================================="
echo "  SUKCES! Utworzono strukturę 24 zunifikowanych manifestów w Istio Mesh.  "
echo "=========================================================================="