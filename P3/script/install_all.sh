#!/bin/bash
set -e  # Arrête le script en cas d'erreur

# Fonction pour arrêter et détruire le cluster k3d et les port-forwards
destroy_cluster() {
    echo "🛑 Arrêt et suppression du cluster k3d..."
    if k3d cluster list | grep -q "argocd"; then
        k3d cluster delete argocd
        echo "✅ Cluster k3d supprimé."
    else
        echo "ℹ️ Aucun cluster k3d 'argocd' trouvé."
    fi
    echo "🎉 Destruction terminée !"
}

# Menu principal
if [ "$1" == "destroy" ]; then
    destroy_cluster
    exit 0
fi

echo "🚀 Début de l'installation K3s + ArgoCD"
echo "========================================"

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

# 1. Vérification des prérequis
echo "🔍 Vérification des prérequis..."
if "$(dirname "$0")/install_dependencies.sh"; then
    echo "✅ Tous les prérequis sont installés"
else
    echo "❌ Échec de l'installation des prérequis"
    exit 1
fi

HOST_IP=$(hostname -I | awk '{print $1}')

# 2. Création du cluster k3d
echo "🔧 Création du cluster k3d..."
if k3d cluster list | grep -q "argocd"; then
    echo "✅ Le cluster k3d existe déjà"
else
    k3d cluster create argocd --servers 1 --agents 1 -p "443:443@loadbalancer"
    echo "✅ Cluster k3d créé avec succès"
fi

# Attendre que le cluster soit prêt
wait_for_condition "kubectl get nodes | grep -q Ready" "⏳ Attente que le cluster soit prêt"

# 3. Création des namespaces
echo "📁 Création des namespaces..."
if kubectl get namespace argocd >/dev/null 2>&1 && kubectl get namespace dev >/dev/null 2>&1; then
    echo "✅ Les namespaces argocd et dev existent déjà"
else
    echo "🔧 Création des namespaces argocd et dev..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Namespaces argocd et dev créés"
fi


# 4. Installation d'ArgoCD
echo "🔧 Installation d'ArgoCD..."
if kubectl get pods -n argocd | grep -q argocd-server; then
    echo "✅ ArgoCD est déjà installé"
else
    echo "🔧 Déploiement d'ArgoCD dans le namespace argocd..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "✅ ArgoCD déployé"

    # Attendre que tous les pods ArgoCD soient prêts
    wait_for_condition "kubectl get pods -n argocd | grep -v NAME | awk '{print \$3}' | grep -v Running | wc -l | grep -q '^0$'" "⏳ Attente du démarrage d'ArgoCD" 600

    echo "✅ ArgoCD installé avec succès"
    echo "[INFO] === Désactivation du TLS interne d'ArgoCD ==="
    kubectl patch deployment argocd-server -n argocd --type=json -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["/usr/local/bin/argocd-server"]},
    {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [
        "--staticassets", "/shared/app",
        "--repo-server", "argocd-repo-server:8081",
        "--dex-server", "http://argocd-dex-server:5556",
        "--redis", "argocd-redis:6379",
        "--insecure"
    ]}
    ]'
    kubectl rollout status deployment argocd-server -n argocd

    echo "🌐 Création de l'Ingress pour ArgoCD (argocd.local)..."
    kubectl apply -f "$(dirname "$0")/../confs/ingress-argocd.yaml"
    echo "✅ Ingress créé"
fi

# 5. Récupération du mot de passe ArgoCD
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "📋 Mot de passe ArgoCD admin: $ARGOCD_PASSWORD"

# 6. Connexion ArgoCD CLI
echo "🔐 Connexion à ArgoCD via CLI..."
argocd login argocd.local --username admin --password "$ARGOCD_PASSWORD" --grpc-web --insecure

# 7. Création de l'application ArgoCD pour le repo hello-iot
echo "🚀 Création de l'application ArgoCD pour hello-iot..."
argocd app create hello-iot \
  --repo https://github.com/V-Burton/helloIOT-vburton-ikaismou.git \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal


# Synchronisation initiale
argocd app sync hello-iot

echo ""
echo "🎉 Installation terminée avec succès !"
echo "======================================="
echo "📊 Informations de connexion ArgoCD:"
echo "   URL: https://argocd.local"
echo "   Username: admin"
echo "   ==================> Password: $ARGOCD_PASSWORD"
echo ""
echo "🌐 Informations de l'application Hello-IoT:"
echo "   Namespace: dev"
echo "   Repository: https://github.com/V-Burton/helloIOT-vburton-ikaismou.git"
echo "   URL: http://hello-iot.local"
echo "🔧 Commandes utiles:"
echo "   argocd app list               # Lister les applications"
echo "   argocd app get hello-iot      # Détails de l'application"
echo ""