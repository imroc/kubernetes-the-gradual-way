# Kubernetes 权限控制
Kubernetes 的权限控制这块是理解其搭建过程中比较复杂也是比较重要的部分，这里先简单介绍下相关概念，为后面打下基础。

## Namespace
Kubernetes 集群中可包含多个 namespace，它们在逻辑上相互隔离，比如测试和生产如果在同一个 Kubernetes 集群上，可以用 namaspace 将它们隔离开，互不干扰。当然也可以通过一些方式跨 namespace 访问和操作，前提是分配了足够的权限。

## RBAC——基于角色的访问控制
Kubernetes 的权限控制主要使用基于角色的访问控制（Role-Based Access Control, 即”RBAC”），简单来说，就是不管是集群管理员还是集群中的程序，把它们都看用户，它们要想对集群进行访问或操作，就需要相应的权限，权限通过角色来代表，每个角色可以被赋予一组权限，角色可以绑定到用户上，绑定之后用户就拥有了相应的权限。

## 用户与用户组
Kubernetes 集群中包含两类用户：
- `User` : 限制集群管理员的权限。比如刚开始学习我们可以都用最高管理员权限，可以在集群中任何 namespace 下进行访问和各种操作。到了生产环境，如果集群比较大，操作的人比较多，管理员权限的分配可能就需要更加细化了。
- `Service Account` : 服务账号，限制集群中运行的程序的权限。比如 Kubernetes 自身的组件或一些插件，往往它们都需要对整个集群的一些状态和数据进行读写操作，就需要相应的权限；而一些普通的程序可能不需要很高的权限，我们最好就不需要给那么高的权限，以免发生意外。
> 我们一般要创建的是 Service Account， 定义示例：

``` yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
```
  
用户组：
- `Group` : 用于给一组用户赋予相同的权限。

## 角色
角色用来代表一组权限，在 Kubernetes 中有两类角色：
- `Role` : 代表某个 namaspace 下的一组权限。
> 一个Role对象只能用于授予对某一单一命名空间中资源的访问权限。 以下示例描述了”default”命名空间中的一个Role对象的定义，用于授予对pod的读访问权限：  

``` yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: default
  name: pod-reader
rules:
- apiGroups: [""] # 空字符串""表明使用core API group
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```
- `ClusterRole` : 代表整个集群范围内的一组权限。
> ClusterRole 定义示例：

``` yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  # 鉴于ClusterRole是集群范围对象，所以这里不需要定义"namespace"字段
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
```

## 角色绑定
可以给某个用户或某个用户组分配一组权限，通过角色绑定来实现。分两类：
- `RoleBinding` : 绑定的权限只作用于某个 namespace 下。
> 定义示例：

``` yaml
# 以下角色绑定定义将允许用户"jane"从"default"命名空间中读取pod。
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: read-pods
  namespace: default
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```
- `ClusterRoleBinding` : 绑定的权限作用于整个集群。
> 定义示例：

``` yaml
# 以下`ClusterRoleBinding`对象允许在用户组"manager"中的任何用户都可以读取集群中任何命名空间中的secret。
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: read-secrets-global
subjects:
- kind: Group
  name: manager
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```
**注：** RoleBinding 中的 roleRef 也可以用 ClusterRole，只不过将 ClusterRole 中定义的权限限定在某 namespace 下，通常用于预先定义一些通用的角色，在多个 namespace 下复用。定义示例：

``` yaml
# 以下角色绑定允许用户"dave"读取"development"命名空间中的secret。
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: read-secrets
  namespace: development # 这里表明仅授权读取"development"命名空间中的资源。
subjects:
- kind: User
  name: dave
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```


## TLS
Kubernetes 的权限校验是通过校验证书来实现的，提取证书中的 CN(Common Name) 字段作为用户名，O(Organization) 字段作为用户组。  