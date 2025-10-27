#!/bin/bash
set -e

GITHUB_REPO_URL="https://github.com/V-Burton/helloIOT-vburton-ikaismou.git"
GITLAB_TOKEN="-"
GITLAB_USER="root"
GITLAB_URL="https://gitlab.local"
KUBE_NAMESPACE="gitlab"

if [[ -z "$GITHUB_REPO_URL" || -z "$GITLAB_USER" ]]; then
  echo "Usage: $0 <github_repo_url> [<gitlab_private_token>|-] <GITLAB_USER>"
  exit 1
fi

REPO_NAME=$(basename -s .git "$GITHUB_REPO_URL")

# 1. Cloner le repo GitHub
if [[ -d "$REPO_NAME.git" ]]; then
  echo "Le répertoire $REPO_NAME.git existe déjà. Supprimez-le avant de continuer."
else
  echo "🔄 Clonage du dépôt GitHub $GITHUB_REPO_URL..."
  git clone --mirror "$GITHUB_REPO_URL"
fi
cd "$REPO_NAME.git"


# If token not provided or set to "-", attempt to generate OAuth token for root
if [[ -z "$GITLAB_TOKEN" || "$GITLAB_TOKEN" == "-" ]]; then
  echo "🔐 Génération d'un token OAuth root via le secret Kubernetes..."

  # Récupère le mot de passe initial root depuis le secret helm/gitlab
  ROOT_PASS="$(kubectl get secret gitlab-gitlab-initial-root-password -n "$KUBE_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
  if [[ -z "$ROOT_PASS" ]]; then
    echo "❌ Impossible de récupérer le mot de passe root depuis le secret kubernetes $KUBE_NAMESPACE/gitlab-gitlab-initial-root-password"
    exit 1
  fi
  echo "ROOT_PASS=$ROOT_PASS"

  # Appel OAuth password grant (ignore TLS si certificat auto-signé)
  TOKEN_JSON=$(curl -sk --request POST "${GITLAB_URL}/oauth/token" \
    --form "grant_type=password" \
    --form "username=root" \
    --form "password=${ROOT_PASS}" \
    --form "scope=api" 2>/dev/null || true)
  echo "TOKEN_JSON=$TOKEN_JSON"

  TOKEN=$(echo "$TOKEN_JSON" | jq -r '.access_token' 2>/dev/null || true)

  if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "❌ Échec génération du token OAuth. Réponse:"
    echo "$TOKEN_JSON"
    exit 1
  fi

  echo "✔ Token OAuth récupéré"
  GITLAB_TOKEN="$TOKEN"
fi

NAMESPACE_ID=$(curl -ks --header "Authorization: Bearer $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/namespaces?search=$GITLAB_USER" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [ -z "$NAMESPACE_ID" ]; then
    echo "❌ Namespace GitLab introuvable."
    cd ..
    rm -rf "$REPO_NAME.git"
    exit 1
fi

EXISTING_PROJECT_JSON=$(curl -ks --header "Authorization: Bearer $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/projects?search=$REPO_NAME")

EXISTING_PROJECT_URL=$(echo "$EXISTING_PROJECT_JSON" | grep -o '"http_url_to_repo":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$EXISTING_PROJECT_URL" ]; then
    echo "ℹ️ Le projet existe déjà. Utilisation de l'URL existante."
    GITLAB_HTTP_URL="$EXISTING_PROJECT_URL"
else
    curl -k --header "Authorization: Bearer $GITLAB_TOKEN" \
         --data "name=$REPO_NAME&namespace_id=$NAMESPACE_ID&visibility=public" \
         "$GITLAB_URL/api/v4/projects" > /tmp/gitlab_repo.json

    GITLAB_HTTP_URL=$(grep -o '"http_url_to_repo":"[^"]*' /tmp/gitlab_repo.json | cut -d'"' -f4)
fi

echo "✅ Dépôt GitLab créé: $GITLAB_HTTP_URL"
echo "🔐 Configuration des identifiants Git..."

cat <<EOF > ~/.git-credentials
https://root:${GITLAB_TOKEN}@gitlab.local
EOF

git config --global credential.helper store
git config --global http.sslVerify false

if ! git ls-remote "$GITLAB_HTTP_URL" >/dev/null 2>&1; then
    echo "❌ Échec de l'authentification auprès de GitLab."
    exit 1
else
    echo "✅ Authentification réussie auprès de GitLab."
fi

git push --mirror "$GITLAB_HTTP_URL"

cd ..
rm -rf "$REPO_NAME.git"
