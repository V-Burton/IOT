#!/bin/bash
set -e  # Arrête le script en cas d'erreur

# Fonction d'attente avec spinner
wait_for_condition() {
    local condition="$1"
    local message="$2"
    local timeout="${3:-300}"
    local count=0
    
    echo -n "$message"
    while ! eval "$condition" && [ $count -lt $timeout ]; do
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
    
    if [ $count -ge $timeout ]; then
        echo " ❌ Timeout atteint"
        return 1
    else
        echo " ✅"
        return 0
    fi
}

# Delete namespace gitlab if it exists
destroy_namespace() {
    if kubectl get namespace gitlab >/dev/null 2>&1; then
        echo "🗑️ Suppression du namespace gitlab existant..."
        kubectl delete namespace gitlab
        echo "✅ Namespace gitlab supprimé"
    fi
}

# Call Delete namespace si option destroy is passed
if [ "$1" == "destroy" ]; then
    destroy_namespace
    exit 0
else
    echo "✅ Option 'destroy' non détectée. Le script continue"
fi

# Installation Helm si nécessaire
if ! command -v helm &> /dev/null; then
    echo "📦 Installation de Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ Helm installé avec succès"
else
    echo "✅ Helm est déjà installé"
fi
# Ajout du repository GitLab Helm
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Création du namespace gitlab
if ! kubectl get namespace gitlab >/dev/null 2>&1; then
    echo "🔧 Création du namespace gitlab..."
    kubectl create namespace gitlab
    echo "✅ Namespace gitlab créé"
else
    echo "✅ Le namespace gitlab existe déjà"
fi

# Deploiement de gitlab avec Traefik et fichier de valeurs personnalisé
echo "🔧 Déploiement de GitLab avec Traefik..."
helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.edition=ce \
  -f $(dirname "$0")/../confs/gitlab-minimal.yaml

# Attente que GitLab soit prêt
echo "⏳ Attente que GitLab soit prêt..."
if wait_for_condition "kubectl get pods -n gitlab | grep -E 'gitlab-webservice-default|gitlab-sidekiq-default|gitlab-gitaly-default' | grep -q Running" "⏳ Attente que les pods GitLab soient en état 'Running'" 900; then
    echo "✅ GitLab est prêt"
else
    echo "❌ Échec du démarrage de GitLab"
    exit 1
fi
kubectl apply -f $(dirname "$0")/../confs/ingress.yaml -n gitlab
echo "✅ Déploiement de GitLab terminé"
# Récupère le mot de passe initial root depuis le secret généré par le chart
PASSWORD="$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)"

if [[ -z "$PASSWORD" ]]; then
  echo "⚠️ Impossible de lire gitlab-gitlab-initial-root-password dans le namespace gitlab."
  echo "   Vérifie que le chart a bien créé le secret ou récupère manuellement le mot de passe."
else
  # Crée ou met à jour un secret dédié contenant le mot de passe root (clef: password)
  kubectl create secret generic gitlab-root-password \
    -n gitlab \
    --from-literal=password="$PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "🔒 Mot de passe root stocké dans le secret 'gitlab-root-password' (namespace: gitlab)."
fi

# Expose le mot de passe en variable d'environnement pour usage immédiat dans le shell courant
export PASSWORD
echo "🌐 Accédez à GitLab via https://gitlab.local (utilisateur: root, mot de passe: $PASSWORD)"
