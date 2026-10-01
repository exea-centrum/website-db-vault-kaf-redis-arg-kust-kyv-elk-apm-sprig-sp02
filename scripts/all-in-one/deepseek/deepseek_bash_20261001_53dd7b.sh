kubectl apply -k manifests/overlays/production
# lub przez ArgoCD:
kubectl apply -f argocd/application.yaml -n argocd