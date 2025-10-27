#!/bin/bash
set -e

echo "🚀 Création du namespace 'dev-bonus'..."
kubectl create namespace dev-bonus || echo "ℹ️ Le namespace 'dev-bonus' existe déjà."

echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "🌐 Configuration de l'URL du dépôt GitLab..."
GITLAB_HTTP_URL="http://gitlab-webservice-default.gitlab:8181/root/helloIOT-vburton-ikaismou.git"
echo "   URL configurée: $GITLAB_HTTP_URL"

echo "🔐 Connexion à ArgoCD via CLI..."
argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" --grpc-web --insecure

echo "🔑 Récupération du mot de passe root GitLab..."
GITLAB_ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 --decode)

echo "📦 Ajout/mise à jour du dépôt GitLab dans ArgoCD..."
argocd repo add "$GITLAB_HTTP_URL" \
  --username root \
  --password "$GITLAB_ROOT_PASSWORD" \
  --upsert || echo "⚠️ Erreur lors de l'ajout du dépôt"

echo "🚀 Création de l'application ArgoCD pour hello-iot-bonus..."
argocd app create hello-iot-bonus \
  --repo "$GITLAB_HTTP_URL" \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev-bonus \
  --sync-policy automated \
  --auto-prune \
  --self-heal

echo "📝 Application de l'Ingress pour hello-iot-bonus..."
kubectl apply -f $(dirname "$0")/../confs/ingress-hello-iot-bonus.yaml

echo "⏳ Synchronisation de l'application..."
argocd app sync hello-iot-bonus --timeout 120 || echo "ℹ️ Synchronisation déjà en cours ou terminée"

echo ""
echo "✅ Configuration terminée !"
echo "📊 Vérifiez l'état de l'application:"
echo "   argocd app get hello-iot-bonus"
echo ""
echo "🌐 Accès aux applications:"
echo "   App GitHub  : http://hello-iot.local"
echo "   App GitLab  : http://hello-iot-bonus.local"