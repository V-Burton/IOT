#!/bin/bash
set -e  # Arrête le script en cas d'erreur

command_exists() {
    command -v "$1" >/dev/null 2>&1
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