git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek  " && git pull --rebase origin main && git push origin main
git checkout --ours . && git add -A && GIT_EDITOR=true git rebase --continue && git push origin main

git rebase --abort || true && git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek" && git fetch origin && git rebase -X ours origin/main && git push origin main