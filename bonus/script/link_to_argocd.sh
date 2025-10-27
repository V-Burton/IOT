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

# Ajout ou mise à jour du repository GitLab dans ArgoCD avec credentials
echo "📦 Ajout/mise à jour du dépôt GitLab dans ArgoCD..."
argocd repo add "$GITLAB_HTTP_URL" \
  --username root \
  --password "$GITLAB_ROOT_PASSWORD" \
  --insecure-skip-server-verification \
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

echo "Upgrade ingress hello-iot to hello-iot-bonus..."
kubectl apply -f $(dirname "$0")/../confs/ingress-hello-iot-bonus.yaml

# Synchronisation initiale (si pas déjà en cours)
echo "⏳ Synchronisation de l'application..."
argocd app sync hello-iot-bonus --timeout 120 || echo "ℹ️ Synchronisation déjà en cours ou terminée"

# Attente que l'ingress soit créé par ArgoCD
echo "⏳ Attente de la création de l'Ingress..."
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' ingress/hello-iot-bonus-ingress -n dev-bonus --timeout=60s 2>/dev/null || echo "ℹ️ Ingress en cours de création..."

# Correction de l'Ingress : suppression de l'annotation Traefik problématique
echo "🔧 Correction de l'annotation Traefik sur l'Ingress..."
kubectl annotate ingress hello-iot-bonus-ingress -n dev-bonus traefik.ingress.kubernetes.io/router.entrypoints- --overwrite 2>/dev/null || echo "ℹ️ Annotation déjà absente"

# Correction du port du service : 8888 -> 80
echo "🔧 Correction du port du service dans l'Ingress (8888 -> 80)..."
kubectl patch ingress hello-iot-bonus-ingress -n dev-bonus --type=json -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/port/number", "value": 80}]' 2>/dev/null || echo "ℹ️ Port déjà configuré à 80"

echo ""
echo "✅ Configuration terminée !"
echo "📊 Vérifiez l'état de l'application:"
echo "   argocd app get hello-iot-bonus"
echo ""
echo "🌐 Accès aux applications:"
echo "   App GitHub  : http://hello-iot.local"
echo "   App GitLab  : http://hello-iot-bonus.local"