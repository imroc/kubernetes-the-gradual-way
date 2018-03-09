# 利用Katacoda免费同步Docker镜像到Docker Hub
> 无需买服务器，脚本批量同步

## 为什么要同步
安装kubernetes的时候，我们需要用到 gcr.io/google_containers 下面的一些镜像，在国内是不能直接下载的。如果用 Self Host 方式安装，master 上的组件除开kubelet之外都用容器运行，甚至 CNI 插件也是容器运行，比如 flannel，在 quay.io/coreos 下面，在国内下载非常慢。但是我们可以把这些镜像同步到我们的docker hub仓库里，再配个docker hub加速器，这样下载镜像就很快了。

## 原理
Katacoda 是一个在线学习平台，在web上提供学习需要的服务器终端，里面包含学习所需的环境，我们可以利用docker的课程的终端来同步，因为里面有docker环境，可以执行 `docker login`，`docker pull`，`docker tag`，`docker push` 等命令来实现同步镜像。

但是手工去执行命令很麻烦，如果要同步的镜像和tag比较多，手工操作那就是浪费生命，我们可以利用程序代替手工操作，不过 Katacoda 为了安全起见，不允许执行外来的二进制程序，但是可以shell脚本，我写好了脚本，大家只需要粘贴进去根据自己需要稍稍修改下，然后运行就可以了。

## Let's Do It

点击 [这里](https://www.katacoda.com/courses/docker/deploying-first-container) 进入docker课程  

<img src="https://res.cloudinary.com/imroc/image/upload/v1520565820/blog/k8s/katacoda-docker.png">

点击 `START SCENARIO` 或 终端右上角全屏按钮将终端放大

<img src="https://res.cloudinary.com/imroc/image/upload/v1520565820/blog/k8s/katacoda-terminal.png">



安装脚本依赖的 `jq` 命令

``` bash
apt install jq
```

登录docker hub

``` bash
docker login
```

创建脚本并赋予执行权限

``` bash
touch sync
chmod +x sync
```

<img src="https://res.cloudinary.com/imroc/image/upload/v1520565825/blog/k8s/katacoda-terminal2.png">

编辑脚本，可以使用自带的vim编辑器

``` bash
vim sync
```

将脚本粘贴进去

``` bash
#! /bin/bash

docker_repo="k8smirror" # your docker hub username or organization name
registry="gcr.io" # the registry of original image, e.g. gcr.io, quay.io
repo="google_containers" # the repository name of original image


sync_one(){
  docker pull ${registry}/${repo}/${1}:${2}
  docker tag ${registry}/${repo}/${1}:${2} docker.io/${docker_repo}/${1}:${2}
  docker push docker.io/${docker_repo}/${1}:${2}
  docker rmi -f ${registry}/${repo}/${1}:${2} docker.io/${docker_repo}/${1}:${2}
}

sync_all_tags() {
  for image in $*; do
    tags_str=`curl https://${registry}/v2/${repo}/$image/tags/list | jq '.tags' -c | sed 's/\[/\(/g' | sed 's/\]/\)/g' | sed 's/,/ /g'`
    echo "$image $tags_str"
    src="
sync_one(){
  docker pull ${registry}/${repo}/\${1}:\${2}
  docker tag ${registry}/${repo}/\${1}:\${2} docker.io/${docker_repo}/\${1}:\${2}
  docker push docker.io/${docker_repo}/\${1}:\${2}
  docker rmi -f ${registry}/${repo}/\${1}:\${2} docker.io/${docker_repo}/\${1}:\${2}
}
tags=${tags_str}
echo \"$image ${tags_str}\"
for tag in \${tags[@]}
do
  sync_one $image \${tag}
done;"
    bash -c "$src"
  done 
}

sync_with_tags(){
  image=$1
  skip=1
  for tag in $*; do
    if [ $skip -eq 1 ]; then
	  skip=0
    else
      sync_one $image $tag
	fi
  done 
}

sync_after_tag(){
  image=$1
  start_tag=$2
  tags_str=`curl https://${registry}/v2/${repo}/$image/tags/list | jq '.tags' -c | sed 's/\[/\(/g' | sed 's/\]/\)/g' | sed 's/,/ /g'`
  echo "$image $tags_str"
  src="
sync_one(){
  docker pull ${registry}/${repo}/\${1}:\${2}
  docker tag ${registry}/${repo}/\${1}:\${2} docker.io/${docker_repo}/\${1}:\${2}
  docker push docker.io/${docker_repo}/\${1}:\${2}
  docker rmi -f ${registry}/${repo}/\${1}:\${2} docker.io/${docker_repo}/\${1}:\${2}
}
tags=${tags_str}
start=0
for tag in \${tags[@]}; do
  if [ \$start -eq 1 ]; then
    sync_one $image \$tag
  elif [ \$tag == '$start_tag' ]; then
    start=1
  fi
done"
  bash -c "$src"
}

get_tags(){
  image=$1
  curl https://${registry}/v2/${repo}/$image/tags/list | jq '.tags' -c
}

#sync_with_tags etcd 2.0.12 2.0.13 # sync etcd:2.0.12 and etcd:2.0.13
#sync_after_tag etcd 2.0.8 # sync tag after etcd:2.0.8
#sync_all_tags etcd hyperkube # sync all tags of etcd and hyperkube
```

脚本中有一些参数需要根据你自己情况修改，可以使用它自带的vim在线修改，也可以在你本地改好在粘贴上去

- `docker_repo` 改为你的Docker Hub账号组织名
- `registry` 改为被同步镜像所在仓库的域名
- `repo` 改为被同步镜像所在仓库的账号或组织名

在脚本最后，可以调用写好的函数来实现镜像同步，举例：

- 同步一个镜像中指定的一个或多个tag

  ``` bash
  sync_with_tags etcd 2.0.12 2.0.13 
  ```

- 从某个tag后面的tag开始一直同步到最后（tag顺序按照字母数字来的，不是上传日期；Katacoda 终端用久了会断连，可能处于安全原因考虑，断开之后可以看tag同步到哪一个了，然后执行类似下面的命令从断连的tag开始同步）

  ``` bash
  sync_after_tag etcd 2.0.8
  ```

- 同步一个或多个镜像的所有tag

  ``` bash
  sync_all_tags etcd hyperkube
  ```

最后执行脚本

``` bash
./sync
```

这就开始同步了，Katacoda 服务器在国外，下载 gcr.io 或 quay.io 上那些镜像都很快，上传 Docker Hub 也很快，如果断连了，可以在 Docker Hub 上查最新上传的 tag 是哪个（如：https://hub.docker.com/r/k8smirror/hyperkube/tags/  把`k8smirror`改为你的docker用户名或组织名，`hyperkube`改为镜像名），然后改脚本，用 `sync_after_tag` 这个函数继续上传。

