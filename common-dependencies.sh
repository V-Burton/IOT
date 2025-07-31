# Install k3s on both machines (common dependencies for multi-machine tutorial)

apt-get update -y
apt-get install -y curl ca-certificates sudo net-tools openssh-server

# Ajout de la clé SSH de l'utilisateur local
mkdir -p /home/vagrant/.ssh
echo "#{ssh_pub_key}" >> /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/authorized_keys

# Installation de k3s en mode serveur
curl -sfL https://get.k3s.io | sh -

# Préparer le fichier de conf pour transfert
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/k3s.yaml
sed -i 's/127.0.0.1/192.168.56.110/' /home/vagrant/k3s.yaml
chown vagrant:vagrant /home/vagrant/k3s.yaml

# Alias kubectl
echo "alias k='sudo k3s kubectl'" >> /home/vagrant/.bashrc