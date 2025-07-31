# Service Configuration reference
SERVICES = {
    'vburtonS' => {
        ip: '192.168.56.110',
        hostname: 'vburtonS',
    },
    'vburtonSW' => {
        ip: '192.168.56.111',
        hostname: 'vburtonSW',
    }
}

Vagrant.configure("2") do |config|

    config.vm.box = "debian/bookworm64"
    config.ssh.insert_key=false

    ssh_pub_key = File.read(File.expand_path("~/.ssh/vagrantConfig.pub"))

    config.vm.define "vburtonS" do |control|
        control.vm.hostname = SERVICES['vburtonS'][:hostname]
        control.vm.network "private_network", ip: SERVICES['vburtonS'][:ip]
        
        control.vm.provider "virtualbox" do |vb|
            vb.name = "vburtonS"
            vb.memory = 512
            vb.cpus = 1
        end

        control.vm.provision "shell", inline: <<-SHELL
            apt-get update -y
            apt-get install -y curl ca-certificates sudo net-tools openssh-server

            mkdir -p /home/vagrant/.ssh
            echo "#{ssh_pub_key}" >> /home/vagrant/.ssh/authorized_keys
            chmod 600 /home/vagrant/.ssh/authorized_keys

            curl -sfL https://get.k3s.io | sh -

            cp /etc/rancher/k3s/k3s.yaml /home/vagrant/k3s.yaml
            sed -i 's/127.0.0.1/192.168.56.110/' /home/vagrant/k3s.yaml
            chown vagrant:vagrant /home/vagrant/k3s.yaml

            echo "alias k='sudo k3s kubectl'" >> /home/vagrant/.bashrc
        
            echo "alias k='sudo k3s kubectl'" >> /home/vagrant/.bashrc
        SHELL
    end

    config.vm.define "vburtonSW" do |control|
        control.vm.hostname = SERVICES['vburtonSW'][:hostname]
        control.vm.network "private_network", ip: SERVICES['vburtonSW'][:ip]
        
        control.vm.provider "virtualbox" do |vb|
            vb.name = "vburtonSW"
            vb.memory = 512
            vb.cpus = 1
        end
        
        control.vm.provision "shell", inline: <<-SHELL
            apt-get update -y
            apt-get install -y curl ca-certificates sudo net-tools openssh-client

            mkdir -p /home/vagrant/.ssh
            echo "#{ssh_pub_key}" >> /home/vagrant/.ssh/authorized_keys
            chown -R vagrant:vagrant /home/vagrant/.ssh
            chmod 600 /home/vagrant/.ssh/authorized_keys

            curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no vagrant@192.168.56.110 "sudo cat /var/lib/rancher/k3s/server/node-token") sh -

            scp -o StrictHostKeyChecking=no vagrant@192.168.56.110:/home/vagrant/k3s.yaml /home/vagrant/k3s.yaml

            echo "alias k='sudo k3s kubectl'" >> /home/vagrant/.bashrc
            export KUBECONFIG=/home/vagrant/k3s.yaml
        SHELL
    end
end