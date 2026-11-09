#!/usr/bin/env bash
# fix-argocd-sync.sh — odblokowuje nieudany sync Application/davtro-website:
#   blad: "failed calling webhook webhook.cert-manager.io ... cert-manager-webhook.svc:443 connection refused" (5 prob)
# Co robi:
#   1) dodaje ignoreDifferences dla ClusterIssuer /spec/vault/caBundle (caBundle wstrzykniete na zywo przez unblock-sync.sh
#      nie istnieje w gicie => ClusterIssuery sa stale OutOfSync => KAZDY sync probuje je patchowac => wymaga webhooka cert-managera)
#   2) czeka az cert-manager-webhook ma endpoint (restartuje go tylko gdy nie ma)
#   3) twardy refresh + nowy sync (ArgoCD nie ponawia synca tej samej rewizji po 5 nieudanych probach)
#   4) przez kilka minut pokazuje wynik i zasoby, ktore nadal nie sa Synced/Healthy
# Uzycie: ./scripts/fix-argocd-sync.sh   (zmienne: ARGO_APP=davtro-website, WAIT_MIN=6)
set -uo pipefail
if command -v kubectl >/dev/null 2>&1; then KC="kubectl"; else KC="microk8s kubectl"; fi
APP="${ARGO_APP:-davtro-website}"; WAIT_MIN="${WAIT_MIN:-6}"
log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
kr(){ local i; for i in 1 2 3 4; do out=$($KC "$@" 2>&1) && { printf '%s' "$out"; return 0; }; sleep 6; done; printf '%s' "$out" >&2; return 1; }

kr -n argocd get application "$APP" >/dev/null || { echo "Brak Application/$APP w ns argocd (albo API nie odpowiada)."; exit 1; }

log "=== 1/4: ignoreDifferences dla ClusterIssuer (caBundle) ==="
CUR=$(kr -n argocd get application "$APP" -o jsonpath='{.spec.ignoreDifferences}' 2>/dev/null || true)
if echo "$CUR" | grep -q 'ClusterIssuer'; then
  echo "  juz jest wpis dla ClusterIssuer:"; echo "  $CUR" | cut -c1-300
else
  ENTRY='{"group":"cert-manager.io","kind":"ClusterIssuer","jsonPointers":["/spec/vault/caBundle"]}'
  if [ -z "$CUR" ]; then P="[{\"op\":\"add\",\"path\":\"/spec/ignoreDifferences\",\"value\":[$ENTRY]}]"
  else P="[{\"op\":\"add\",\"path\":\"/spec/ignoreDifferences/-\",\"value\":$ENTRY}]"; fi
  kr -n argocd patch application "$APP" --type json -p "$P" >/dev/null && echo "  [OK] dodano ignoreDifferences (ClusterIssuer /spec/vault/caBundle)" || echo "  [WARN] nie udalo sie dodac"
  echo "  >>> Dodaj to samo w gicie (argocd/application*.yaml, spec.ignoreDifferences), inaczej kolejny 'kubectl apply' Application je skasuje:"
  echo "      - group: cert-manager.io"
  echo "        kind: ClusterIssuer"
  echo "        jsonPointers: [/spec/vault/caBundle]"
fi
SO=$(kr -n argocd get application "$APP" -o jsonpath='{.spec.syncPolicy.syncOptions}' 2>/dev/null || true)
echo "$SO" | grep -q RespectIgnoreDifferences || echo "  [WARN] brak syncOptions RespectIgnoreDifferences=true — bez niego ignoreDifferences dziala tylko w diffie, nie przy syncu."

log "=== 2/4: cert-manager-webhook (endpoint) ==="
ep() { $KC -n cert-manager get endpoints cert-manager-webhook -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null; }
EP=$(ep)
if [ -z "$EP" ]; then
  echo "  brak endpointu — restartuje deploy/cert-manager-webhook"
  kr -n cert-manager rollout restart deploy/cert-manager-webhook >/dev/null
  kr -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s || true
  EP=$(ep)
fi
if [ -n "$EP" ]; then echo "  [OK] webhook ma endpoint: $EP"; else echo "  [WARN] webhook dalej bez endpointu — sync ClusterIssuerow moze znowu padac (sprawdz: kubectl -n cert-manager logs deploy/cert-manager-webhook --tail=30)"; fi
echo "  restarty: $($KC -n cert-manager get pods -o custom-columns=POD:.metadata.name,RST:.status.containerStatuses[0].restartCount --no-headers 2>/dev/null | tr '\n' ';')"

log "=== 3/4: hard refresh + nowy sync ==="
kr -n argocd annotate application "$APP" argocd.argoproj.io/refresh=hard --overwrite >/dev/null && echo "  hard refresh zlecony"
sleep 10
OP=$(kr -n argocd get application "$APP" -o jsonpath='{.operation}' 2>/dev/null || true)
if [ -n "$OP" ]; then
  echo "  trwa juz operacja synca — czekam, nie zaczynam nowej: $OP" | cut -c1-200
else
  kr -n argocd patch application "$APP" --type merge \
    -p '{"operation":{"initiatedBy":{"username":"fix-argocd-sync"},"sync":{"revision":"HEAD","prune":false}}}' >/dev/null \
    && echo "  [OK] uruchomiono nowy sync" || echo "  [WARN] nie udalo sie uruchomic synca"
fi

log "=== 4/4: wynik (maks. $WAIT_MIN min) ==="
END=$(( $(date +%s) + WAIT_MIN*60 )); PH=""
while [ "$(date +%s)" -lt "$END" ]; do
  PH=$($KC -n argocd get application "$APP" -o jsonpath='{.status.operationState.phase}' 2>/dev/null)
  SY=$($KC -n argocd get application "$APP" -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HE=$($KC -n argocd get application "$APP" -o jsonpath='{.status.health.status}' 2>/dev/null)
  echo "  [$(date +%H:%M:%S)] operation=${PH:-?} sync=${SY:-?} health=${HE:-?}"
  case "$PH" in Succeeded|Failed|Error) break;; esac
  sleep 20
done
if [ "$PH" = "Failed" ] || [ "$PH" = "Error" ]; then
  echo "  --- powod ---"
  $KC -n argocd get application "$APP" -o jsonpath='{.status.operationState.message}' 2>/dev/null | cut -c1-600; echo
fi
echo "  --- zasoby nie-Synced albo nie-Healthy ---"
$KC -n argocd get application "$APP" -o jsonpath='{range .status.resources[*]}{.kind}{"/"}{.name}{" sync="}{.status}{" health="}{.health.status}{"\n"}{end}' 2>/dev/null \
  | grep -vE 'sync=Synced health=(Healthy|)$' | grep -vE '^(ReplicaSet|Pod|ControllerRevision|PersistentVolumeClaim)/' | head -25
echo
echo "Jesli na liscie zostaly tylko ClusterPolicy (Missing) i HPA (Degraded): pierwsza czeka na Kyverno (admission controller nie dziala), druga na metrics-server."