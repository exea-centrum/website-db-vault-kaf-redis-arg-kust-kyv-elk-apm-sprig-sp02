Zmiany w skrypcie:

1. **Dynamiczne wykrywanie service'u Dashboardu** — w tej kolejności: `kubernetes-dashboard-kong-proxy` (Twój przypadek, Helm chart) → `kube-system/kubernetes-dashboard` (stary addon) → fallback po labelach. Stara wersja forwardowała `service/kubernetes-dashboard`, którego nie ma, i błąd lądował w `/dev/null`.

2. **Token z `admin-user`** — idempotentne `apply` ServiceAccount + ClusterRoleBinding (już istnieją po `setup-from-scratch.sh`, więc nic się nie zepsuje), token ważny 24h. Koniec z uprawnieniami "default" SA, który przy włączonym RBAC nic nie widzi.

3. **`pkill` starych port-forwardów** przed startem — po restarcie samego skryptu porty 10443/8080 bywają zajęte.

4. **Weryfikacja, że port-forwardy faktycznie wstały** — jeśli service się nie zgadza, zobaczysz komunikat zamiast cichego błędu.

5. `trap` + `wait` na PID-ach — Ctrl+C czyści oba procesy.

Użycie po restarcie VM:

```bash
chmod +x k8s_commands.sh
./k8s_commands.sh
# Dashboard: https://<IP>:10443  (token z wydruku)
# ArgoCD:    https://<IP>:8080   (admin / hasło z wydruku)
```
```bash
#!/bin/bash
# k8s_commands.sh — dashboard + ArgoCD po restarcie VM
#
# POPRAWKI wzgledem poprzedniej wersji:
#  1. Service Dashboardu wykrywany dynamicznie — w tym klastrze jest to
#     kubernetes-dashboard/kubernetes-dashboard-kong-proxy (Helm chart), a NIE
#     service "kubernetes-dashboard". Stara wersja forwardowala nieistniejacy
#     service i "nie dzialal dashboard".
#  2. Token brany z SA admin-user (kube-system) + ClusterRoleBinding — SA
#     "default" w ns kubernetes-dashboard nie ma zadnych uprawnien przy
#     wlaczonym RBAC, wiec dashboard pokazywal puste/odmowy mimo poprawnego tokenu.
#  3. Przed startem ubijane sa stare procesy port-forward (po restarcie VM
#     zwykle nie ma, ale po samym restarcie skryptu porty bywaja zajete).

set -uo pipefail

KC() { microk8s kubectl "$@"; }

if ! microk8s status --wait-ready >/dev/null 2>&1; then
    echo "Blad: MicroK8s nie dziala. Uruchom: microk8s start"
    exit 1
fi
echo "MicroK8s dziala."
echo "--------------------------------------------------"

# ---------- 1. Wykrycie service'u Dashboardu ----------
DASH_NS=""; DASH_SVC=""
if KC get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then
    DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard-kong-proxy"
elif KC get svc -n kube-system kubernetes-dashboard >/dev/null 2>&1; then
    DASH_NS="kube-system"; DASH_SVC="kubernetes-dashboard"
else
    LINE=$(KC get svc -A -l 'app.kubernetes.io/name=kubernetes-dashboard' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$LINE" ] && { DASH_NS="${LINE%% *}"; DASH_SVC="${LINE##* }"; }
fi
if [ -z "$DASH_NS" ]; then
    echo "Blad: nie znaleziono zadnego service'u Kubernetes Dashboard."
    exit 1
fi
echo "Dashboard: $DASH_NS/$DASH_SVC"

# ---------- 2. admin-user (idempotentnie) + token ----------
KC apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
YAML

echo "Generowanie tokenu Dashboardu..."
token=$(KC -n kube-system create token admin-user --duration=24h 2>/dev/null)
if [ -z "$token" ]; then
    echo "Blad: nie udalo sie wygenerowac tokenu."
    exit 1
fi
echo "TOKEN DO DASHBOARDU (ważny 24h, skopiuj):"
echo "--------------------------------------------------"
echo "$token"
echo "--------------------------------------------------"

# ---------- 3. Haslo ArgoCD ----------
argocd_pass=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [ -z "$argocd_pass" ]; then
    echo "Ostrzezenie: brak secretu argocd-initial-admin-secret (usuniety?)."
else
    echo "ArgoCD -> login: admin  haslo: $argocd_pass"
fi
echo "--------------------------------------------------"

# ---------- 4. Port-forward (najpierw sprzatamy stare) ----------
pkill -f 'port-forward.*10443' 2>/dev/null || true
pkill -f 'port-forward.*8080' 2>/dev/null || true
sleep 1

echo "Port-forward Dashboardu na :10443 ..."
KC -n "$DASH_NS" port-forward --address 0.0.0.0 "service/$DASH_SVC" 10443:443 >/dev/null 2>&1 &
DASH_PID=$!

echo "Port-forward ArgoCD na :8080 ..."
KC -n argocd port-forward --address 0.0.0.0 service/argo-cd-argocd-server 8080:443 >/dev/null 2>&1 &
ARGO_PID=$!

sleep 2
if ! kill -0 "$DASH_PID" 2>/dev/null; then
    echo "Blad: port-forward Dashboardu nie wystartowal (sprawdz: KC -n $DASH_NS port-forward service/$DASH_SVC 10443:443)"
fi
if ! kill -0 "$ARGO_PID" 2>/dev/null; then
    echo "Blad: port-forward ArgoCD nie wystartowal."
fi

IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)
echo "--------------------------------------------------"
echo "Gotowe:"
echo "  Dashboard: https://${IP:-IP}:10443"
echo "  ArgoCD:    https://${IP:-IP}:8080"
echo "--------------------------------------------------"
echo "Ctrl+C konczy."

cleanup() {
    kill "$DASH_PID" "$ARGO_PID" 2>/dev/null
    exit 0
}
trap cleanup INT TERM
wait "$DASH_PID" "$ARGO_PID" 2>/dev/null
```
