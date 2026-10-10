```bash
git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek  " && git pull --rebase origin main && git push origin main
git checkout --ours . && git add -A && GIT_EDITOR=true git rebase --continue && git push origin main

git rebase --abort || true && git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek" && git fetch origin && git rebase -X ours origin/main && git push origin main

cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02 && git add manifests/base/vault-bootstrap.yaml && git commit -m "fix: caBundle w formacie byte (base64) w kroku 25a bootstrapu" && git pull --rebase origin main && git push origin main && git log --oneline -2


cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02 && git add -A && git commit -m "GitSecOps MLOps Marietta Julia Zosia Helena compared AI agent for vscode " && git pull --rebase origin main && git push origin main && git log --oneline -2


 9104  [2026-10-02 16:25:09 CEST] kubectl delete namespace davtro02
 9105  [2026-10-02 16:26:39 CEST] kubectl get all -n davtro02
 9106  [2026-10-02 16:26:55 CEST] argocd app get davtro-website
 9107  [2026-10-02 16:27:02 CEST] kubectl get application davtro-website -n argocd -o jsonpath='{.metadata.deletionTimestamp}'
 9108  [2026-10-02 16:30:04 CEST] # ClusterIssuery (cert-manager)
 9109  [2026-10-02 16:30:04 CEST] kubectl get clusterissuer
 9110  [2026-10-02 16:30:07 CEST] # ClusterRoleBinding (RBAC)
 9111  [2026-10-02 16:30:07 CEST] kubectl get clusterrolebinding | grep -i davtro
 9112  [2026-10-02 16:30:07 CEST] # ClusterRole
 9113  [2026-10-02 16:30:07 CEST] kubectl get clusterrole | grep -i davtro
 9114  [2026-10-02 16:30:47 CEST] kubectl delete clusterissuer vault-issuer vault-issuer-internal
 9115  [2026-10-02 16:30:48 CEST] kubectl delete clusterrolebinding davtro02-vault-tokenreview
 9116  [2026-10-02 16:30:56 CEST] kubectl get clusterissuer
 9117  [2026-10-02 16:30:57 CEST] # Powinno być: No resources found
 9118  [2026-10-02 16:30:57 CEST] kubectl get clusterrolebinding | grep -i davtro
 9119  [2026-10-02 16:30:57 CEST] # Powinno być: puste
 9120  [2026-10-02 16:35:09 CEST] kubectl patch application davtro-website -n argocd   -p '{"metadata": {"finalizers": null}}' --type=merge
 9121  [2026-10-02 16:35:10 CEST] kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
 9122  [2026-10-02 16:35:10 CEST] kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found
 9123  [2026-10-02 16:35:10 CEST] kubectl get pv -o name | grep -iE 'davtro|vault|pgdata|kafka-data' | while read pv; do   kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge;   kubectl delete "$pv"; done




kubectl -n davtro02 describe pod frontend-5f95c949d8-5wp4s | sed -n '/Events:/,$p'


kubectl -n davtro02 get pods
kubectl -n davtro02 logs deploy/vault-bootstrap -c vault-bootstrap --tail=40
kubectl -n davtro02 describe pod vault-0 | sed -n '/Events:/,$p'
kubectl -n davtro02 get secretstore,externalsecret
```