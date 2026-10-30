#!/usr/bin/env bash
# relief.sh — awaryjne odciazenie wezla (7,8 GiB RAM): wylacza niekrytyczne komponenty i zapamietuje, co bylo wlaczone.
#   ./scripts/relief.sh down          # wyl.: spark, kafka-ui, pgadmin, kyverno (raporty/cleanup/postgresql), dashboard-scraper
#   ./scripts/relief.sh down --obs    # dodatkowo observability: prometheus, grafana, loki, tempo, alertmanager, eksportery
#   ./scripts/relief.sh status        # biezace repliki celow
#   ./scripts/relief.sh up            # przywraca repliki zapamietane przez 'down'
# Dlaczego nie samo 'kubectl scale': selfHeal ArgoCD cofa reczne zmiany w davtro02 — 'down' najpierw go wstrzymuje
# (automated sync z gita dalej dziala; selfHeal wlaczysz z powrotem przez './scripts/relief.sh up').
# Trwala zmiana liczby replik = overlays/production/kustomization.yaml (git).
set -uo pipefail
if command -v kubectl >/dev/null 2>&1; then KC="kubectl"; else KC="microk8s kubectl"; fi
STATE="${RELIEF_STATE:-$HOME/.relief-state}"
APP="${ARGO_APP:-davtro-website}"

# ns|kind|nazwa
TIER_A="davtro02|deploy|spark-worker davtro02|deploy|spark-master davtro02|deploy|kafka-ui davtro02|deploy|pgadmin
kyverno|deploy|kyverno-cleanup-controller kyverno|deploy|kyverno-reports-controller kyverno|deploy|kyverno-reports-server
kyverno|sts|kyverno-postgresql kubernetes-dashboard|deploy|kubernetes-dashboard-metrics-scraper"
TIER_B="davtro02|deploy|prometheus davtro02|deploy|grafana davtro02|deploy|loki davtro02|deploy|tempo
davtro02|deploy|alertmanager davtro02|deploy|cert-expiry-exporter davtro02|deploy|kafka-exporter davtro02|deploy|postgres-exporter"

# kubectl z ponawianiem (API wezla bywa przeciazone: TLS handshake timeout)
kr(){ local i; for i in 1 2 3 4; do out=$($KC "$@" 2>&1) && { printf '%s' "$out"; return 0; }; sleep 6; done; printf '%s' "$out" >&2; return 1; }

cmd="${1:-status}"; shift || true
OBS=0; [ "${1:-}" = "--obs" ] && OBS=1
targets="$TIER_A"; [ "$OBS" = 1 ] && targets="$TIER_A $TIER_B"
[ "$cmd" = status ] && targets="$TIER_A $TIER_B"

case "$cmd" in
  down)
    echo "[*] wstrzymuje selfHeal Application/$APP (zmiany z gita nadal sie synchronizuja)"
    kr -n argocd patch application "$APP" --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}' >/dev/null \
      && touch "$STATE.selfheal" || echo "    (nie udalo sie / brak Application — kontynuuje)"
    touch "$STATE"
    for t in $targets; do
      IFS='|' read -r ns kind name <<<"$t"
      cur=$(kr -n "$ns" get "$kind" "$name" -o jsonpath='{.spec.replicas}' 2>/dev/null) || { echo "  - $ns/$name: brak (pomijam)"; continue; }
      [ -z "$cur" ] && cur=1
      if [ "$cur" -gt 0 ] 2>/dev/null; then
        grep -qx "$ns $kind $name .*" "$STATE" 2>/dev/null || echo "$ns $kind $name $cur" >> "$STATE"
        kr -n "$ns" scale "$kind" "$name" --replicas=0 >/dev/null && echo "  - $ns/$name: $cur -> 0" || echo "  ! $ns/$name: scale nieudany"
      else
        echo "  - $ns/$name: juz 0"
      fi
    done
    echo "[OK] Stan zapisany w $STATE. Przywrocenie: ./scripts/relief.sh up"
    ;;
  up)
    [ -f "$STATE" ] || { echo "Brak $STATE — nic do przywrocenia."; exit 0; }
    while read -r ns kind name n; do
      [ -z "${name:-}" ] && continue
      kr -n "$ns" scale "$kind" "$name" --replicas="$n" >/dev/null && echo "  - $ns/$name: 0 -> $n" || echo "  ! $ns/$name: scale nieudany"
    done < "$STATE"
    rm -f "$STATE"
    if [ -f "$STATE.selfheal" ]; then
      kr -n argocd patch application "$APP" --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}' >/dev/null && echo "[OK] selfHeal wlaczony." && rm -f "$STATE.selfheal"
    fi
    ;;
  status)
    for t in $targets; do
      IFS='|' read -r ns kind name <<<"$t"
      cur=$(kr -n "$ns" get "$kind" "$name" -o jsonpath='{.spec.replicas}' 2>/dev/null) || cur="brak"
      printf '  %-22s %-6s %-36s replicas=%s\n' "$ns" "$kind" "$name" "${cur:-?}"
    done
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac