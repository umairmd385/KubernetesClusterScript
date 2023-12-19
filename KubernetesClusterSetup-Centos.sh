#!/bin/bash
#echo "This script file will install kubernetes on your Centos based machine"

echo "Installing Kubernetes"
echo "Step-1: Installing Docker"
which docker > /dev/null 2>&1
if [ $? -eq 0 ]

then
    echo "Docker is already Installed"
else       
    echo ""
    echo "Installing Docker"
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    sudo yum-config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin wget curl
    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable --now docker
fi

echo "STEP-2:- Adding kubernetes repos"

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

echo "STEP-3:- Downloading packages"

sudo yum update -y
sudo yum install -y kubelet-1.28.1 kubeadm-1.28.1 kubectl-1.28.1 --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

echo "STEP-4:- Setting hostname of nodes"

read -p "To set hostname for master node then use 'M or m' and To set hostname for worker node then use 'W or w': " hostname
echo ""
echo "Your option: $hostname"
        
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

echo "STEP-5:- Disabling Selinux"

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo "Step-6: Adding firewall rules"
            
sudo firewall-cmd --state >/dev/null 2>&1
if [ $? -eq 0 ]; then
read -p "Do you want to add ports and enable firewalld service.Use y or Y for yes and n or N for No: " firewall
    if [[ "$firewall" == "Y" || "$firewall" == "y" ]]
    then
        if [[ "$hostname" == "M" || "$hostname" == "m" ]];
        then 
            sudo firewall-cmd --permanent --add-port=6443/tcp
            sudo firewall-cmd --permanent --add-port=2379-2380/tcp
            sudo firewall-cmd --permanent --add-port=10250/tcp
            sudo firewall-cmd --permanent --add-port=10257/tcp
            sudo firewall-cmd --permanent --add-port=10259/tcp
            sudo firewall-cmd --permanent --add-port=30000-32767/tcp
            sudo firewall-cmd --reload
        elif [[ "$hostname" == "W" || "$hostname" == "w" ]];
        then 
            sudo firewall-cmd --permanent --add-port=10250/tcp
            sudo firewall-cmd --permanent --add-port=30000-32767/tcp
            sudo firewall-cmd  --reload
            
        fi
    elif [[ "$firewall" == "n" || "$firewall" == "N" ]]
    then
        echo "You choose to disable firewalld-service"
        sudo systemctl stop firewalld
        sudo systemctl disable firewalld
    fi
else
    echo "Firewalld service is not running."
    sleep 10
fi

echo "Step-7: Configuring sysctl"

sudo modprobe overlay
sudo modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

echo "Step-9: Disable swap"
sudo sed -i 's|/dev/mapper/centos-swap|# /dev/mapper/centos-swap|' /etc/fstab
sudo swapoff -a

echo "Step-9: Configuring Docker for container runtime engine"4

sudo mkdir -p /etc/systemd/system/docker.service.d

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

VER=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest|grep tag_name | cut -d '"' -f 4|sed 's/v//g')
echo $VER

wget https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.amd64.tgz
tar xvf cri-dockerd-${VER}.amd64.tgz

rm -rf cri-dockerd-${VER}.amd64.tgz
sudo mv cri-dockerd/cri-dockerd /usr/bin/
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
sudo mv cri-docker.socket cri-docker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cri-docker.service
sudo systemctl enable --now cri-docker.socket
sudo systemctl start cri-docker.service

#enabling kubelet service


echo "Step-10: Removing the containerd config file"
sudo chmod u+w /etc/containerd/config.toml
sudo containerd config default > /etc/containerd/config.toml
#sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd

echo "Step-11: Intializing kubernetes kubeadm"

#echo -n "Initializing kubernetes for Nodes,use 'M or m' for master-node and 'W or w' for worker-node: "
#read node
read -p "Enter your machine ipv4 ip adress: " mip
if [[ "$hostname" == "M" || "$hostname" == "m" ]]
then

cat >> /etc/hosts <<EOF
$mip    $mset_hostname
EOF
else
cat >> /etc/hosts <<EOF
$mip   $wset_hostname
EOF
fi

sudo kubeadm config images pull --cri-socket unix:///var/run/cri-dockerd.sock

if [[ "$hostname" == "M" || "$hostname" == "m" ]]; 
then
  echo ""
  echo ""
  echo "Note:- In next step it will ask to enter ip address. If you are installing cluster on local machine then please enter both public and private address same as machine ip. Else if you are using to setup cluster on clouds then please enter both private ip and public ip of the machine"
  sleep 15
  read -p "Enter your public ipv4 ip adress: " pip
  read -p "Enter your private ipv4 ip adress: " prip
  sudo kubeadm init --ignore-preflight-errors=all --cri-socket unix:///var/run/cri-dockerd.sock --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=0.0.0.0  --apiserver-cert-extra-sans=$pip,$prip
  #it will generate a node join token list 
  
  read -p "Enter your cluster deployment type.Cloud or cloud for cloud and On-Premises or on-premises for on-premises:  " type

  if [[ "$type" == "cloud" || "$type" == "Cloud" ]]
  then
    rm -rf /etc/kubernetes/pki/apiserver*
    kubeadm init phase certs all --apiserver-advertise-address=0.0.0.0 --apiserver-cert-extra-sans=$pip
    sudo sed -i "s#https://.*:6443#https://$pip:6443#g"  /etc/kubernetes/admin.conf
    sudo sed -i "s#https://.*:6443#https://$pip:6443#g"  /etc/kubernetes/controller-manager.conf
    sudo sed -i "s#https://.*:6443#https://$pip:6443#g"  /etc/kubernetes/kubelet.conf
    sudo sed -i "s#https://.*:6443#https://$pip:6443#g"  /etc/kubernetes/scheduler.conf
    sudo systemctl restart kubelet
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
  
  elif [[ "$type" == "On-Premises" || "$type" == "on-premises" ]]
  then
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
  fi 
  #Adding CNI (Container Network Interface)
  #Adding calico as a CNI
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  wget  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
  sed -i  's/10.244.0.0\/16/192.168.0.0\/16/g' kube-flannel.yml
  kubectl apply -f kube-flannel.yml
  echo "Use this token to join other nodes to cluster with --cri-socket unix:///var/run/cri-dockerd.sock"
  echo ""
  kubeadm token create --print-join-command
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
rm -rf cri-dockerd kube-flannel.yml
