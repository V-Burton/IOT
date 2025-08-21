
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
    # Tuer les port-forwards
    if [ -f argocd-info.txt ]; then
        PF_PID=$(grep 'Port-forward PID:' argocd-info.txt | awk '{print $NF}')
        if [ ! -z "$PF_PID" ]; then
            kill $PF_PID 2>/dev/null && echo "✅ Port-forward arrêté (PID $PF_PID)" || echo "ℹ️ Aucun port-forward actif."
        fi
    fi
    echo "🧹 Suppression des namespaces (optionnel)..."
    kubectl delete namespace argocd --ignore-not-found
    kubectl delete namespace dev --ignore-not-found
    echo "✅ Namespaces supprimés."
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

# 1. Installation Docker
echo "📦 Installation de Docker..."
if command_exists docker; then
    echo "✅ Docker est déjà installé"
else
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Ajout de la clé GPG Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Ajout du repository Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Ajouter l'utilisateur au groupe docker
    sudo usermod -aG docker $USER
    echo "✅ Docker installé avec succès"
    echo "⚠️  Vous devrez peut-être vous reconnecter pour utiliser Docker sans sudo"
fi

# 2. Installation k3d
echo "📦 Installation de k3d..."
if command_exists k3d; then
    echo "✅ k3d est déjà installé"
else
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    echo "✅ k3d installé avec succès"
fi

# 3. Installation kubectl
echo "📦 Installation de kubectl..."
if command_exists kubectl; then
    echo "✅ kubectl est déjà installé"
else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo "✅ kubectl installé avec succès"
fi

# 4. Installation ArgoCD CLI
echo "📦 Installation d'ArgoCD CLI..."
if command_exists argocd; then
    echo "✅ ArgoCD CLI est déjà installé"
else
    ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep tag_name | cut -d '"' -f 4)
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
    echo "✅ ArgoCD CLI installé avec succès"
fi

# 5. Création du cluster k3d
echo "🔧 Création du cluster k3d..."
if k3d cluster list | grep -q "argocd"; then
    echo "✅ Le cluster k3d existe déjà"
else
    k3d cluster create argocd
    echo "✅ Cluster k3d créé avec succès"
fi

# Attendre que le cluster soit prêt
wait_for_condition "kubectl get nodes | grep -q Ready" "⏳ Attente que le cluster soit prêt"

# 6. Création des namespaces
echo "📁 Création des namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespaces argocd et dev créés"

# 7. Installation d'ArgoCD
echo "🔧 Installation d'ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que tous les pods ArgoCD soient prêts
wait_for_condition "kubectl get pods -n argocd | grep -v NAME | awk '{print \$3}' | grep -v Running | wc -l | grep -q '^0$'" "⏳ Attente du démarrage d'ArgoCD" 600

echo "✅ ArgoCD installé avec succès"

# 8. Récupération du mot de passe ArgoCD
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "📋 Mot de passe ArgoCD admin: $ARGOCD_PASSWORD"

# 9. Exposition d'ArgoCD via port-forward (en arrière-plan)
echo "🌐 Exposition d'ArgoCD sur http://localhost:8080..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
ARGOCD_PORT_FORWARD_PID=$!

# Attendre que le port-forward soit actif
sleep 5

# 10. Connexion ArgoCD CLI
echo "🔐 Connexion à ArgoCD via CLI..."
# Ignorer les certificats SSL pour localhost
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

# 11. Création de l'application ArgoCD pour le repo hello-iot
echo "🚀 Création de l'application ArgoCD pour hello-iot..."
argocd app create hello-iot \
  --repo https://github.com/V-Burton/helloIOT.git \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Synchronisation initiale
argocd app sync hello-iot

echo "🌐 Exposition d'hello-iot sur http://localhost:5000..."
kubectl port-forward svc/hello-iot-service -n dev 5000:80 > /dev/null 2>&1 &
HELLOIOT_PORT_FORWARD_PID=$!

echo ""
echo "🎉 Installation terminée avec succès !"
echo "======================================="
echo "📊 Informations de connexion ArgoCD:"
echo "   URL: http://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "🔧 Commandes utiles:"
echo "   kubectl get pods -n argocd    # Voir les pods ArgoCD"
echo "   kubectl get pods -n dev       # Voir les pods de votre app"
echo "   argocd app list               # Lister les applications"
echo "   argocd app get hello-iot      # Détails de l'application"
echo ""
echo "⚠️  Pour arrêter le port-forward: kill $PORT_FORWARD_PID"
echo "⚠️  N'oubliez pas de remplacer l'URL du repo par le vôtre dans le script !"

# Sauvegarder les infos dans un fichier
cat > argocd-info.txt << EOF
ArgoCD Connection Info
=====================
URL: http://localhost:8080
Username: admin
Password: $ARGOCD_PASSWORD
Port-forward PID: $PORT_FORWARD_PID

Commands:
- Stop port-forward: kill $PORT_FORWARD_PID
- Restart port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443
EOF

echo "📄 Informations sauvegardées dans argocd-info.txt"