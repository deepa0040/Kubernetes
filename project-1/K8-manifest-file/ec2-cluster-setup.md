## Step-by-Step: K8s Cluster on EC2 using kubeadm

---

## PART 1 — Launch EC2 Instances via AWS CLI

### Step 1 — Set variables
```bash
export AWS_REGION="us-east-1"
export KEY_NAME="k8s-key"
export AMI_ID="ami-0c7217cdde317cfec"   # Ubuntu 22.04 LTS us-east-1
export INSTANCE_TYPE="t3.medium"         # minimum for kubeadm
export SG_NAME="k8s-sg"
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)
```

### Step 2 — Create key pair
```bash
aws ec2 create-key-pair \
  --key-name $KEY_NAME \
  --query "KeyMaterial" \
  --output text > ~/.ssh/$KEY_NAME.pem

chmod 400 ~/.ssh/$KEY_NAME.pem
```

### Step 3 — Create security group
```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name $SG_NAME \
  --description "K8s cluster security group" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text)

echo "SG_ID: $SG_ID"
```

### Step 4 — Add security group rules
```bash
# SSH
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# Kubernetes API server
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 6443 --cidr 0.0.0.0/0

# etcd
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 2379-2380 --cidr 0.0.0.0/0

# Kubelet API
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 10250 --cidr 0.0.0.0/0

# NodePort services
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0

# Allow all internal traffic within SG
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol all --port all --source-group $SG_ID

# HTTP/HTTPS for ingress
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
```

### Step 5 — Launch master node
```bash
MASTER_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --count 1 \
  --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=k8s-master},{Key=Role,Value=master}]' \
  --block-device-mappings \
    'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}' \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Master ID: $MASTER_ID"
```

### Step 6 — Launch worker nodes
```bash
WORKER1_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --count 1 \
  --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=k8s-worker-1},{Key=Role,Value=worker}]' \
  --block-device-mappings \
    'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}' \
  --query "Instances[0].InstanceId" \
  --output text)

WORKER2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --count 1 \
  --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=k8s-worker-2},{Key=Role,Value=worker}]' \
  --block-device-mappings \
    'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}' \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Worker1 ID: $WORKER1_ID"
echo "Worker2 ID: $WORKER2_ID"
```

### Step 7 — Wait for instances and get IPs
```bash
aws ec2 wait instance-running \
  --instance-ids $MASTER_ID $WORKER1_ID $WORKER2_ID

# Get public IPs
MASTER_IP=$(aws ec2 describe-instances \
  --instance-ids $MASTER_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

WORKER1_IP=$(aws ec2 describe-instances \
  --instance-ids $WORKER1_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

WORKER2_IP=$(aws ec2 describe-instances \
  --instance-ids $WORKER2_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "Master  : $MASTER_IP"
echo "Worker1 : $WORKER1_IP"
echo "Worker2 : $WORKER2_IP"
```

---

## PART 2 — Install Prerequisites (ALL 3 nodes)

> Run steps 8–13 on **master, worker-1 and worker-2**

```bash
ssh -i ~/.ssh/k8s-key.pem ubuntu@<NODE_IP>
```

### Step 8 — Disable swap
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Step 9 — Load kernel modules
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### Step 10 — Set sysctl params
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Step 11 — Install containerd
```bash
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update -y
sudo apt-get install -y containerd.io
```

### Step 12 — Configure containerd
```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable SystemdCgroup
sudo sed -i \
  's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Step 13 — Install kubeadm, kubelet, kubectl
```bash
sudo apt-get update -y
sudo apt-get install -y apt-transport-https curl

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable kubelet
```

---

## PART 3 — Setup K8s Cluster

### Step 14 — Initialise master node (master only)
```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=<MASTER_PRIVATE_IP>
```

### Step 15 — Configure kubectl (master only)
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Step 16 — Install Calico CNI network plugin (master only)
```bash
kubectl apply -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Wait for calico pods to be ready
kubectl get pods -n kube-system -w
```

### Step 17 — Get join command (master only)
```bash
kubeadm token create --print-join-command
```

Copy the output — looks like:
```
kubeadm join <MASTER_PRIVATE_IP>:6443 \
  --token xxxxx \
  --discovery-token-ca-cert-hash sha256:xxxxx
```

### Step 18 — Join workers (worker-1 and worker-2)
```bash
# Paste the join command from Step 17 with sudo
sudo kubeadm join <MASTER_PRIVATE_IP>:6443 \
  --token xxxxx \
  --discovery-token-ca-cert-hash sha256:xxxxx
```

### Step 19 — Verify cluster (master only)
```bash
kubectl get nodes

# Expected
# NAME           STATUS   ROLES           AGE
# k8s-master     Ready    control-plane   5m
# k8s-worker-1   Ready    <none>          2m
# k8s-worker-2   Ready    <none>          2m
```

---

## PART 4 — Install Nginx Ingress Controller

### Step 20 — Install ingress-nginx (master only)
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml
```

### Step 21 — Wait for ingress controller to be ready
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Step 22 — Get ingress external IP
```bash
kubectl get svc -n ingress-nginx

# NAME                       TYPE           EXTERNAL-IP
# ingress-nginx-controller   LoadBalancer   <PENDING or IP>
```

> On raw EC2 without a cloud LoadBalancer, `EXTERNAL-IP` stays `<PENDING>`. Patch it with the master public IP:

```bash
kubectl patch svc ingress-nginx-controller \
  -n ingress-nginx \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
```

Then access via:
```bash
# Get NodePort
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Access app
curl http://<MASTER_PUBLIC_IP>:<NODE_PORT>/api/health
```

---

## PART 5 — Deploy the App

### Step 23 — Apply all manifests (master only)
```bash
# Clone your repo or copy manifests to master
scp -i ~/.ssh/k8s-key.pem -r ./k8s ubuntu@$MASTER_IP:~/

ssh -i ~/.ssh/k8s-key.pem ubuntu@$MASTER_IP

# Apply in order
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets/
kubectl apply -f k8s/backend/configmap.yaml
kubectl apply -f k8s/database/
kubectl apply -f k8s/backend/
kubectl apply -f k8s/frontend/
kubectl apply -f k8s/ingress/
```

### Step 24 — Verify everything is running
```bash
# All pods
kubectl get pods -A

# All services
kubectl get svc -A

# Ingress
kubectl get ingress -A

# Test
curl http://<MASTER_PUBLIC_IP>/api/health
curl http://<MASTER_PUBLIC_IP>/
```

---

## Quick Reference

| What | Command |
|------|---------|
| Check nodes | `kubectl get nodes` |
| Check all pods | `kubectl get pods -A` |
| Pod logs | `kubectl logs <pod> -n <ns>` |
| Describe pod | `kubectl describe pod <pod> -n <ns>` |
| SSH master | `ssh -i ~/.ssh/k8s-key.pem ubuntu@$MASTER_IP` |
| SSH worker1 | `ssh -i ~/.ssh/k8s-key.pem ubuntu@$WORKER1_IP` |
| Delete cluster | `aws ec2 terminate-instances --instance-ids $MASTER_ID $WORKER1_ID $WORKER2_ID` |