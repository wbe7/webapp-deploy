# webapp

## webapp-deploy

Install argocd-webapp
```bash
helm upgrade --install argocd-webapp ./webapp-argocd -f webapp-argocd/values.yaml -n dev-webapp
```