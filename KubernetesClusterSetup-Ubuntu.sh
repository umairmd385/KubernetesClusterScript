#!/bin/bash

#echo "This script file will install kubernetes on your machine"

echo "############################################## Installing Kubernetes in Ubuntu ###############################################"
echo "Step-1: Installing Docker"
which docker > /dev/null 2>&1
if [ $? -eq 0 ]
then
    echo "Docker is already Installed"
else
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "STEP-2:- Adding kubernetes repos"

sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg git wget
sudo mkdir -p /etc/apt/keyrings
sudo chmod -R 755 /etc/apt/keyrings
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/kubernetes.gpg] http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list
sudo apt update -y
sudo apt -y install kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "STEP-3:- Setting hostname of nodes"

read -p "To set hostname for master node then use 'M or m' and To set hostname for worker node then use 'W or w': " hostname
echo ""echo "Your option: $hostname"
if [[ "$hostname" == "M" || "$hostname" == "m" ]]
then
    echo ""
    echo "Setting Hostname for Master-Node"
    read -p "Enter your hostname for master node: " mset_hostname
    sudo hostnamectl set-hostname $mset_hostname
elif [[ "$hostname" == "W" || "$hostname" == "w" ]]
then
    echo ""
    echo "Setting Hostname for Worker-node"
    read -p "Enter your hostname for worker node: " wset_hostname
    sudo hostnamectl set-hostname $wset_hostname
else
    echo "You have used wrong option to edit"
fi

echo "Step-4: Configuring sysctl"

sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

echo "Step-5: Disable swap"
sudo sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab
sudo swapoff -a

echo "Step-6: Configuring Docker for container runtime engine"4sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
    "max-size": "100m"
    },
    "storage-driver": "overlay2",
    "storage-opts": [],
    "live-restore": true
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

#enabling kubelet service
echo "Step-7: Removing the containerd config file"

sudo chmod u+w /etc/containerd/config.toml
sudo containerd config default > /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl restart containerd

echo "Step-8: Intializing kubernetes kubeadm"
#echo -n "Initializing kubernetes for Nodes,use 'M or m' for master-node and 'W or w' for worker-node: "

sudo kubeadm config images pull --cri-socket=unix:///var/run/containerd/containerd.sock
if [[ "$hostname" == "M" || "$hostname" == "m" ]];
then
    echo ""
    echo ""
    sudo kubeadm init --ignore-preflight-errors=all --cri-socket=unix:///var/run/containerd/containerd.sock --pod-network-cidr=192.168.0.0/16

    #it will generate a node join token list
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    #Adding CNI (Container Network Interface)
    #Adding Kube-flannel as CNI
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    wget https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    sed -i 's/10.244.0.0\/16/192.168.0.0\/16/g' kube-flannel.yml
    kubectl apply -f kube-flannel.yml
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "Use this token to join other nodes to cluster with --cri-socket=unix:///var/run/containerd/containerd.sock"
    echo ""
    echo ""
    echo ""
    echo "Please add other worker nodes ip-address and hostname inside /etc/hosts file"
elif [[ "$hostname" == "W" || "$hostname" == "w" ]];
then
    echo "Please use the token generated during master node initialization"
    echo "If Forget to copy the token then please use below command to regenerate the tokens"
    echo "# kubeadm token create --print-join-command"
    echo ""
    echo ""
    echo "Please add master node and other worker nodes ip-address and hostname inside /etc/hosts file"
else
    echo "Installation complete and now follow the README.md file for few remaining setups"
fi
