if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo."
    echo "RUN WITH sudo"
    exit 1
fi

echo "Script executed successfully with sudo privileges."

# stopping swap tmp
swapoff -a
# stopping swap permanent, after reboot also it will be off 
sed -i '/\sswap\s/s/^/#/' /etc/fstab


# Adding docker key 
apt-get update -y
apt-get install ca-certificates curl gnupg -y
apt-get install open-iscsi nfs-common -y

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installing docker 
apt-get update -y
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Add kubeadm, kubelet, kubectl keys 
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl
mkdir -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key |  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list


# installing kubeadm, kubelet, kubectl keys 

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Adding cri-o service 

wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.4/cri-dockerd_0.3.4.3-0.ubuntu-focal_amd64.deb	
dpkg -i cri-dockerd_0.3.4.3-0.ubuntu-focal_amd64.deb
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket

## Installing helm 

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh


cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

systemctl daemon-reload
systemctl enable --now containerd
containerd config default > /etc/containerd/config.toml
sed -i  's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
service containerd restart
systemctl daemon-reload
crictl config runtime-endpoint unix:///run/containerd/containerd.sock

# install yq and jq
snap install yq jq

# install crio
# curl https://raw.githubusercontent.com/cri-o/packaging/main/get | bash
# systemctl daemon-reload
# systemctl enable --now crio
# service crio restart


# install nerdctl
wget https://github.com/containerd/nerdctl/releases/download/v1.7.5/nerdctl-1.7.5-linux-amd64.tar.gz
tar -xvf nerdctl-1.7.5-linux-amd64.tar.gz
mv nerdctl /bin/nerdctl

(crontab -l 2>/dev/null; echo "@reboot systemctl stop kubelet && rm -f /var/lib/kubelet/cpu_manager_state && systemctl start kubelet " ) | crontab -


if [[ $1 == "gpu" ]]; then

################ this was used when docker is been used 
# offical Link https://github.com/NVIDIA/k8s-device-plugin
#     distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
#     curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add -
#     curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | tee /etc/apt/sources.list.d/libnvidia-container.list
#     apt-get update && apt-get install -y nvidia-container-toolkit

#     rm -rf /etc/docker/daemon.json

# cat <<EOF > /etc/docker/daemon.json
# {
#   "default-runtime": "nvidia",
#   "runtimes": {
#     "nvidia": {
#       "path": "/usr/bin/nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   }
# }
# EOF

#     sudo systemctl restart docker

# https://github.com/NVIDIA/k8s-device-plugin 
# offical docs https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html
# ctr https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html


curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit


sudo nvidia-ctk runtime configure --runtime=containerd --set-as-default
sudo systemctl restart containerd

sysctl -w fs.inotify.max_user_watches=10000000
sysctl -w fs.inotify.max_user_instances=10000000

fi 

