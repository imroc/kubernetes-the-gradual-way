# 准备

## 修改系统配置
开启路由转发（保证 proxy 正常运行，Service 需要）
``` bash
sysctl -w net.ipv4.ip_forward=1
```
- 默认情况下，由于安全原因，linux是关闭了路由转发的，即同台机器不止一个网卡，将数据包从一个网卡传到另一个网卡，让另一个网卡继续路由，即实现两个不同网段的主机通信。service 的 IP 是通过 proxy（即 kube-proxy 或 kube-router ）路由的，并不需要路由器参与，node 收到数据包时，数据包的目的 IP 为本机的内网 IP，proxy 将数据包的目的IP转化成Service IP并路由转发到Serive IP 对应网段的虚拟网卡上，最终路由到正确的Pod
- ip_forward 与路由转发：http://blog.51cto.com/13683137989/1880744

禁用 swap (保证 kubelet 正确运行):
``` bash
swapoff -a
```
关闭SELinux和防火墙
``` bash
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config # 修改配置永久生效，需重启
setenforce 0
#关闭防火墙 
systemctl stop firewalld && systemctl disable firewalld
```

RHEL / CentOS 7上的某些用户报告了由于iptables被绕过而导致流量被错误路由的问题。应该确保net.bridge.bridge-nf-call-iptables的sysctl配置中被设置为1
``` bash
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
```

## 升级内核
运行docker的node节点需要升级到4.x内核支持overlay2驱动

检查内核
``` bash
uname -sr 
```
添加升级内核的第三方库
[www.elrepo.org](http://elrepo.org/tiki/tiki-index.php) 上有方法
``` bash
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
```
列出内核相关包
``` bash
yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
```
安装最新稳定版
``` bash
yum --enablerepo=elrepo-kernel install kernel-ml -y
```
查看内核默认启动顺序
``` bash
awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg
```
结果显示
``` bash
CentOS Linux (4.15.7-1.el7.elrepo.x86_64) 7 (Core)
CentOS Linux (3.10.0-693.17.1.el7.x86_64) 7 (Core)
CentOS Linux (3.10.0-693.2.2.el7.x86_64) 7 (Core)
CentOS Linux (3.10.0-693.el7.x86_64) 7 (Core)
CentOS Linux (0-rescue-f0f31005fb5a436d88e3c6cbf54e25aa) 7 (Core)
```
设置默认启动的内核，顺序index 分别是 0,1,2,3，每个人机器不一样，看清楚选择自己的index， 执行以下代码选择内核
``` bash
grub2-set-default 0
```
重启
``` bash
reboot
```
检查内核
``` bash
uname -a
```

## docker 安装与配置
不建议使用官网的docker-ce版本、支持性不是很好、使用epel源支持的docker即可。

#### 确保epel源已安装
``` bash
yum install -y epel-release
```
#### 安装docker
``` bash
yum install -y docker
```

#### 使用overlay2驱动
docker 存储驱动很多默认用devicemapper，存在很多问题，最好使用overlay2，内核版本小于 3.10.0-693 的不要使用 overlay2 驱动。  

确保 yum-plugin-ovl 安装，解决 ovlerlay2 兼容性问题：
``` bash
yum install -y yum-plugin-ovl
```
- overlay2 兼容性问题详见：[https://docs.docker.com/storage/storagedriver/overlayfs-driver/#limitations-on-overlayfs-compatibility](https://docs.docker.com/storage/storagedriver/overlayfs-driver/#limitations-on-overlayfs-compatibility)  ：  

备份 docker 用到的目录（若需要）
``` bash
cp -au /var/lib/docker /var/lib/docker.bk
```
关闭 docker
``` bash
systemctl stop docker
```
配置 docker 的存储驱动
``` bash
vi /etc/docker/daemon.json
```
``` json
{
  "storage-driver": "overlay2"
}
```
如果使用 Docker EE 并且版本大于 17.06，还需要一个 `storage-opts`，这样配置
``` json
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
```
- docker 设置 overlay2 驱动官方参考文档：[https://docs.docker.com/storage/storagedriver/overlayfs-driver/#configure-docker-with-the-overlay-or-overlay2-storage-driver](https://docs.docker.com/storage/storagedriver/overlayfs-driver/#configure-docker-with-the-overlay-or-overlay2-storage-driver)

启动 docker
``` bash
systemctl start docker
```

## 安装 kubeadm, kubectl, kubelet
配置国内kubernetes源
``` bash
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF
```
如果直接安装最新版可以直接这样做
``` bash
yum install -y kubelet kubeadm kubectl
```
如果要指定版本，可以先看看有那些版本
``` bash
[root@roc ~]# yum list kubeadm --showduplicates
Loaded plugins: fastestmirror, ovl
Loading mirror speeds from cached hostfile
 * elrepo: mirrors.tuna.tsinghua.edu.cn
Installed Packages
kubeadm.x86_64                   1.9.3-0                    @kubernetes
Available Packages
kubeadm.x86_64                   1.6.0-0                    kubernetes
kubeadm.x86_64                   1.6.1-0                    kubernetes
kubeadm.x86_64                   1.6.2-0                    kubernetes
kubeadm.x86_64                   1.6.3-0                    kubernetes
kubeadm.x86_64                   1.6.4-0                    kubernetes
kubeadm.x86_64                   1.6.5-0                    kubernetes
kubeadm.x86_64                   1.6.6-0                    kubernetes
kubeadm.x86_64                   1.6.7-0                    kubernetes
kubeadm.x86_64                   1.6.8-0                    kubernetes
kubeadm.x86_64                   1.6.9-0                    kubernetes
kubeadm.x86_64                   1.6.10-0                   kubernetes
kubeadm.x86_64                   1.6.11-0                   kubernetes
kubeadm.x86_64                   1.6.12-0                   kubernetes
kubeadm.x86_64                   1.6.13-0                   kubernetes
kubeadm.x86_64                   1.7.0-0                    kubernetes
kubeadm.x86_64                   1.7.1-0                    kubernetes
kubeadm.x86_64                   1.7.2-0                    kubernetes
kubeadm.x86_64                   1.7.3-1                    kubernetes
kubeadm.x86_64                   1.7.4-0                    kubernetes
kubeadm.x86_64                   1.7.5-0                    kubernetes
kubeadm.x86_64                   1.7.6-1                    kubernetes
kubeadm.x86_64                   1.7.7-1                    kubernetes
kubeadm.x86_64                   1.7.8-1                    kubernetes
kubeadm.x86_64                   1.7.9-0                    kubernetes
kubeadm.x86_64                   1.7.10-0                   kubernetes
kubeadm.x86_64                   1.7.11-0                   kubernetes
kubeadm.x86_64                   1.8.0-0                    kubernetes
kubeadm.x86_64                   1.8.0-1                    kubernetes
kubeadm.x86_64                   1.8.1-0                    kubernetes
kubeadm.x86_64                   1.8.2-0                    kubernetes
kubeadm.x86_64                   1.8.3-0                    kubernetes
kubeadm.x86_64                   1.8.4-0                    kubernetes
kubeadm.x86_64                   1.8.5-0                    kubernetes
kubeadm.x86_64                   1.8.6-0                    kubernetes
kubeadm.x86_64                   1.8.7-0                    kubernetes
kubeadm.x86_64                   1.8.8-0                    kubernetes
kubeadm.x86_64                   1.9.0-0                    kubernetes
kubeadm.x86_64                   1.9.1-0                    kubernetes
kubeadm.x86_64                   1.9.2-0                    kubernetes
kubeadm.x86_64                   1.9.3-0                    kubernetes
```
如果安装 1.9.3 ，执行下面的命令
``` bash
yum install -y kubelet-1.9.3-0 kubeadm-1.9.3-0 kubectl-1.9.3-0
```
kubelet设置开机自动运行

```bash
systemctl enable kubelet
```

kubelet启动参数增加  `--runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice` 防止kubelet报错

``` bash
vi /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```
将 KUBELET_CGROUP_ARGS 一行改为：
``` bash
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
```
然后reload并启动kubelet

``` bash
systemctl daemon-reload
systemctl start kubelet
```



## 初始化master

国内快速下载镜像（假设docker配了加速器）
``` bash
docker pull docker.io/k8smirror/flannel:v0.9.1-amd64
docker tag docker.io/k8smirror/flannel:v0.9.1-amd64 quay.io/coreos/flannel:v0.9.1-amd64
docker rmi docker.io/k8smirror/flannel:v0.9.1-amd64

docker pull docker.io/gcrio/pause-amd64:3.0
docker tag docker.io/gcrio/pause-amd64:3.0 gcr.io/google_containers/pause-amd64:3.0
docker rmi docker.io/gcrio/pause-amd64:3.0

docker pull docker.io/gcrio/hyperkube:v1.9.3

docker pull docker.io/gcrio/etcd:3.1.11
```
创建 kubeadm 配置文件
``` bash
cat <<EOF >  kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: 0.0.0.0
unifiedControlPlaneImage: docker.io/gcrio/hyperkube:v1.9.3
selfHosted: true
kubernetesVersion: v1.9.3
authorizationModes:
  - RBAC
  - Node
kubeProxy:
  config:
    mode: ipvs # k8s 1.9开始kube-proxy的ipvs进入beta，替代iptables方式路由service
etcd:
  image: docker.io/gcrio/etcd:3.1.11 # k8s 1.9 官方推荐的etcd版本为 3.1.11
imageRepository: gcrio
featureGates:
  CoreDNS: true
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16
EOF
```
执行初始化
``` bash
[root@roc k8s]# kubeadm init --config kubeadm.yaml
[init] Using Kubernetes version: v1.9.3
[init] Using Authorization modes: [RBAC Node]
[preflight] Running pre-flight checks.
	[WARNING Hostname]: hostname "roc" could not be reached
	[WARNING Hostname]: hostname "roc" lookup roc on 100.100.2.138:53: no such host
	[WARNING FileExisting-crictl]: crictl not found in system path
[preflight] Starting the kubelet service
[certificates] Generated ca certificate and key.
[certificates] Generated apiserver certificate and key.
[certificates] apiserver serving cert is signed for DNS names [roc kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 172.17.60.67]
[certificates] Generated apiserver-kubelet-client certificate and key.
[certificates] Generated sa key and public key.
[certificates] Generated front-proxy-ca certificate and key.
[certificates] Generated front-proxy-client certificate and key.
[certificates] Valid certificates and keys now exist in "/etc/kubernetes/pki"
[kubeconfig] Wrote KubeConfig file to disk: "admin.conf"
[kubeconfig] Wrote KubeConfig file to disk: "kubelet.conf"
[kubeconfig] Wrote KubeConfig file to disk: "controller-manager.conf"
[kubeconfig] Wrote KubeConfig file to disk: "scheduler.conf"
[controlplane] Wrote Static Pod manifest for component kube-apiserver to "/etc/kubernetes/manifests/kube-apiserver.yaml"
[controlplane] Wrote Static Pod manifest for component kube-controller-manager to "/etc/kubernetes/manifests/kube-controller-manager.yaml"
[controlplane] Wrote Static Pod manifest for component kube-scheduler to "/etc/kubernetes/manifests/kube-scheduler.yaml"
[etcd] Wrote Static Pod manifest for a local etcd instance to "/etc/kubernetes/manifests/etcd.yaml"
[init] Waiting for the kubelet to boot up the control plane as Static Pods from directory "/etc/kubernetes/manifests".
[init] This might take a minute or longer if the control plane images have to be pulled.
[apiclient] All control plane components are healthy after 29.501817 seconds
[uploadconfig] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[markmaster] Will mark node roc as master by adding a label and a taint
[markmaster] Master roc tainted and labelled with key/value: node-role.kubernetes.io/master=""
[bootstraptoken] Using token: 0e78a0.38a53399a9489d52
[bootstraptoken] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstraptoken] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstraptoken] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstraptoken] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes master has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of machines by running the following on each node
as root:

  kubeadm join --token 0e78a0.38a53399a9489d52 172.17.60.67:6443 --discovery-token-ca-cert-hash sha256:038654a3d0adb79978913e5d2bce191b5d8536feac7d9354ca35b348e9fc4cd5
```
如果初始化失败，可以撤销
``` bash
kubeadm reset
```
如果成功，根据输出提示，master 上如果想通过 kubectl 管理集群，执行下面的命令
``` bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
最重要的是最后一行，保存下来，其它 node 加入集群需要执行那条命令
``` bash
kubeadm join --token 0e78a0.38a53399a9489d52 172.17.60.67:6443 --discovery-token-ca-cert-hash sha256:038654a3d0adb79978913e5d2bce191b5d8536feac7d9354ca35b348e9fc4cd5
```
这个时候，如果你看 kubelet 的日志会发现不断提示没有cni插件，kubeadm 配置文件中的 CoreDNS 也不会生效
``` bash
journalctl -xef -u kubelet -n 20
```
安装 flannel 网络插件就可以搞定了
``` bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
```
看看集群状态
``` bash
[root@roc ~]# kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health": "true"}
```

使用kubeadm初始化的集群，出于安全考虑Pod不会被调度到Master Node上，可使用如下命令使Master节点参与工作负载

``` bash
kubectl taint nodes --all node-role.kubernetes.io/master-
```

输出类似下面（报错可忽略）

``` bash
node "roc" untainted
error: taint "node-role.kubernetes.io/master:" not found
```


## worker 节点加入

下载需要的镜像
``` bash
docker pull docker.io/gcrio/hyperkube:v1.9.3

docker pull docker.io/gcrio/pause-amd64:3.0
docker tag docker.io/gcrio/pause-amd64:3.0 gcr.io/google_containers/pause-amd64:3.0
docker rmi docker.io/gcrio/pause-amd64:3.0
```
将之前保存的 kubeadm join 命令粘贴过来
``` bash
kubeadm join --token 0e78a0.38a53399a9489d52 172.17.60.67:6443 --discovery-token-ca-cert-hash sha256:038654a3d0adb79978913e5d2bce191b5d8536feac7d9354ca35b348e9fc4cd5
```
在master上看看集群节点
``` bash
kubectl get nodes
```

