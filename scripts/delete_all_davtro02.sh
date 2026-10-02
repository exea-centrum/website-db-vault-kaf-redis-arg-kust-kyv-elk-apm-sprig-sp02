# 1. Argo CD Application
kubectl patch application davtro-website -n argocd \
  -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete application davtro-website -n argocd --ignore-not-found

# 2. Namespace
kubectl delete namespace davtro02 --ignore-not-found

# 3. Cluster-scoped
kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found

# 4. PV
kubectl get pv -o json | jq -r '
  .items[] | select(.spec.claimRef.namespace == "davtro02") | .metadata.name
' | while read pv; do
  kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge
  kubectl delete "$pv" --ignore-not-found
done

# 5. Weryfikacja
kubectl get ns,clusterissuer,application -n argocd 2>/dev/null | grep -i davtro || echo "CZYSTO"