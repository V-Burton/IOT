#!/bin/bash
set -e

# Creation d'un nouveau namespace dans ArgoCD
echo "🚀 Création du namespace 'dev-bonus' dans ArgoCD..."
kubectl create namespace dev-bonus || echo "ℹ️ Le namespace 'dev-bonus' existe déjà."

# Recuperation du mot de passe admin ArgoCD depuis le secret kubernetes
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Utilisation de l'URL interne Kubernetes du service GitLab au lieu de l'Ingress
# Format court : service.namespace (le DNS k8s ajoute automatiquement .svc.cluster.local)
echo "🌐 Configuration de l'URL du dépôt GitLab (service interne)..."
GITLAB_HTTP_URL="http://gitlab-webservice-default.gitlab:8181/root/helloIOT-vburton-ikaismou.git"

echo "   URL configurée: $GITLAB_HTTP_URL"

# Connexion a argocd via CLI...
echo "🔐 Connexion à ArgoCD via CLI..."
argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" --grpc-web --insecure

# Récupération du token GitLab root depuis le secret
echo "🔑 Récupération du mot de passe root GitLab..."
GITLAB_ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 --decode)

# Ajout du repository GitLab dans ArgoCD avec credentials
echo "📦 Ajout du dépôt GitLab dans ArgoCD..."
argocd repo add "$GITLAB_HTTP_URL" \
  --username root \
  --password "$GITLAB_ROOT_PASSWORD" \
  --insecure-skip-server-verification || echo "ℹ️ Le dépôt existe peut-être déjà."

echo "🚀 Création de l'application ArgoCD pour hello-iot-bonus..."
argocd app create hello-iot-bonus \
  --repo "$GITLAB_HTTP_URL" \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev-bonus \
  --sync-policy automated \
  --auto-prune \
  --self-heal