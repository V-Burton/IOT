# Génération du certificat et création des secrets/configmap nécessaires pour GitLab et ArgoCD
echo "🔐 Génération du certificat pour gitlab.local..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout gitlab.local.key \
  -out gitlab.local.crt \
  -subj "/CN=gitlab.local/O=MyOrg"

echo "🔐 Création du secret TLS pour gitlab.local dans le namespace gitlab..."
kubectl create secret tls gitlab-tls-secret \
  --cert=gitlab.local.crt \
  --key=gitlab.local.key \
  -n gitlab --dry-run=client -o yaml | kubectl apply -f -

echo "🔐 Création du ConfigMap CA pour gitlab.local dans kube-system..."
kubectl create configmap gitlab-ca-cert \
  --from-file=ca.crt=gitlab.local.crt \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Patch pour monter le certificat CA de GitLab dans argocd-repo-server
echo "[INFO] === Ajout du certificat CA GitLab dans argocd-repo-server ==="
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "gitlab-ca", "configMap": {"name": "gitlab-ca-cert"}}},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "gitlab-ca", "mountPath": "/etc/ssl/certs/gitlab.local.crt", "subPath": "ca.crt"}}
]'
kubectl rollout status deployment argocd-repo-server -n argocd
#!/bin/bash
set -e

# Creation d'un nouveau namespace dans ArgoCD
echo "🚀 Création du namespace 'dev-bonus' dans ArgoCD..."
kubectl create namespace dev-bonus || echo "ℹ️ Le namespace 'dev-bonus' existe déjà."

# Recuperation du mot de passe admin ArgoCD depuis le secret kubernetes
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Recuperation de l'URL du repo GitLab depuis le configmap kubernetes
echo "🌐 Récupération de l'URL du dépôt GitLab..."
GITLAB_HTTP_URL=$(kubectl get configmap gitlab-repo-url -n gitlab -o jsonpath='{.data.url}')

if [ -z "$GITLAB_HTTP_URL" ]; then
  echo "❌ L'URL du dépôt GitLab est vide !"
  exit 1
fi

# Connexion a argocd via CLI...
echo "🔐 Connexion à ArgoCD via CLI..."
argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" --grpc-web --insecure

argocd repo add "$GITLAB_HTTP_URL" --insecure-skip-server-verification

echo "🚀 Création de l'application ArgoCD pour hello-iot-bonus..."
argocd app create hello-iot-bonus \
  --repo "$GITLAB_HTTP_URL" \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev-bonus \
  --sync-policy automated \
  --auto-prune \
  --self-heal