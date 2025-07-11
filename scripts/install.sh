#!/usr/bin/env bash
set -e

# 安装部署需要的依赖
# 系统以 Ubuntu 24.04 为目标

## 检查当前用户是否是 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户或使用 sudo 执行此脚本。"
    exit 1
fi

## 0. 更新系统，并关闭无人值守升级，避免系统自动重启
apt-get update -y && apt-get upgrade -y

## 设置 APT::Periodic::Update-Package-Lists 和 APT::Periodic::Unattended-Upgrade 为 0
echo "APT::Periodic::Update-Package-Lists \"0\";" > /etc/apt/apt.conf.d/20auto-upgrades
echo "APT::Periodic::Unattended-Upgrade \"0\";" >> /etc/apt/apt.conf.d/20auto-upgrades

## 1. 安装常用工具
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    unzip \
    zip \
    jq \
    amazon-ecr-credential-helper

## 使用 aws 官方发布的 AWS CLI v2

AWS_CLI_TEMP_DIR=$( mktemp -d )
## 下载 AWS CLI v2 的安装包
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.0.30.zip" -o "${AWS_CLI_TEMP_DIR}/awscliv2.zip"
## 解压安装包
unzip -q "${AWS_CLI_TEMP_DIR}/awscliv2.zip" -d "${AWS_CLI_TEMP_DIR}"
## 安装 AWS CLI v2
"${AWS_CLI_TEMP_DIR}/aws/install" --update

## 2. 找到第一个空白，无分区的磁盘
disk=$(lsblk -d -n -o NAME,TYPE,SIZE | grep disk | awk '{print $1}' | while read -r dev; do
    if [ -z "$(lsblk -n -o PARTTYPE /dev/$dev)" ]; then
        echo "/dev/$dev"
        break
    fi
done)

### 如果没有找到空白磁盘，则跳过磁盘相关初始化
if [ -z "$disk" ]; then
    echo "未找到空白磁盘，跳过磁盘初始化步骤。"
else
    echo "找到空白磁盘: $disk"

    ## 3. 格式化磁盘
    echo "正在格式化磁盘 $disk..."
    parted "$disk" --script "mklabel gpt"
    parted "$disk" --script "mkpart primary ext4 0% 100%"

    # wait for partition to be ready
    sync
    sleep 5

    # 检查分区设备名（兼容 nvme 和普通磁盘）
    partition=""
    if [[ "$disk" =~ nvme ]]; then
        # nvme 设备分区名如 /dev/nvme0n1p1
        partition="${disk}p1"
    else
        # 普通磁盘分区名如 /dev/sda1
        partition="${disk}1"
    fi

    ## 格式化时使用 ext4 文件系统，直接分配日志空间，禁用延迟初始化
    mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0,discard "$partition"

    mkdir -p /data
    mount "$partition" /data

    ## 使用 UUID 挂载分区
    uuid=$(blkid -s UUID -o value "$partition")
    echo "UUID=$uuid /data ext4 defaults,nofail,discard 0 2" >> /etc/fstab
fi

## 5. 安装 docker, docker-compose v2
apt-get install -y \
    docker.io \
    docker-compose-v2

### 创建 docker 容器使用的 systemd slice 配置，限制全部容器使用的最大内存

### 检查 /etc/systemd/system/docker_limit.slice 是否存在，如果存在则跳过
if [ ! -f /etc/systemd/system/docker_limit.slice ]; then

echo "/etc/systemd/system/docker_limit.slice 不存在，创建新的配置文件。"

#### 计算系统内存的 80%
total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
memory_limit=$((total_memory * 80 / 100))

tee /etc/systemd/system/docker_limit.slice <<EOF
[Unit]
Description=Docker global cgroup limit
Before=slices.target

[Slice]
MemoryMax=${memory_limit}k
EOF

else
    echo "/etc/systemd/system/docker_limit.slice 已存在，跳过创建。"
fi

### 检查 daemon.json 是否存在，如果存在则跳过创建

if [ ! -f /etc/docker/daemon.json ]; then

### 创建 docker 的 daemon.json 配置文件
mkdir -p /etc/docker

### 限制日志的最大数量和尺寸
tee /etc/docker/daemon.json << EOF
{
	"cgroup-parent": "docker_limit.slice",
	"log-driver": "json-file",
	"log-opts": {
		"max-size": "10m",
		"max-file": "3",
		"tag": "{{.ImageName}}|{{.Name}}|{{.ID}}"
	}
}
EOF

### 重启 docker 服务
systemctl daemon-reload
systemctl restart docker

else
    echo "/etc/docker/daemon.json 已存在，跳过创建。"
fi

# 检查 fluent-bit 是否安装

if [ ! -f /etc/apt/sources.list.d/fluent-bit.list ]; then

# 安装 fluent-bit,使用官方软件源
curl -s https://packages.fluentbit.io/fluentbit.key | gpg --dearmor -o /usr/share/keyrings/fluentbit.gpg

VERSION_CODENAME=$(lsb_release -cs)

tee /etc/apt/sources.list.d/fluent-bit.list << EOF
deb [signed-by=/usr/share/keyrings/fluentbit.gpg] https://packages.fluentbit.io/ubuntu/${VERSION_CODENAME} ${VERSION_CODENAME} main
EOF

apt-get update -y
apt-get install -y fluent-bit

else
    echo "fluent-bit 已经安装，跳过安装步骤。"
fi

### 通过 AWS EC2 的 meta 接口获取机器标签，其中有 opentofu 在创建机器时配置的标签，包含日志需要写入的 S3 桶和 CloudWatch 日志组
### 需要的 tag 为 Name 和 LogBucket， EC2 默认使用 IMDSv2

# 获取 IMDSv2 session token
imds_token=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# 使用 IMDSv2 token 获取 region 和 instance-id
aws_region=$(curl -s -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/meta-data/instance-id)

### 使用 aws 命令获取 tag 里的 Name 和 LogBucket
tags=$(aws ec2 describe-tags --region "$aws_region" --filters "Name=resource-id,Values=$instance_id" --query "Tags[?Key=='Name' || Key=='LogBucket']" --output json)

aws_log_group=$(echo "$tags" | jq -r '.[] | select(.Key=="Name") | .Value')
aws_s3_bucket=$(echo "$tags" | jq -r '.[] | select(.Key=="LogBucket") | .Value')

if [ -z "$aws_log_group" ] || [ -z "$aws_s3_bucket" ]; then
    echo "无法获取必要的 EC2 标签 Name 或 LogBucket。"
    exit 1
fi

### 创建 fluentbit 的配置文件,将 systemd 的日志和 /var/log/*.log 的日志发送到 CloudWatch 和 S3
aws_log_stream_prefix=$(echo "$aws_log_group" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '-')

mkdir -p /var/lib/fluent-bit
mkdir -p /etc/fluent-bit
mkdir -p /var/lib/fluent-bit/s3

cat << EOF > /etc/fluent-bit/fluent-bit.conf
[SERVICE]
    Flush        1
    Daemon       Off
    Log_Level    error
    Parsers_File /etc/fluent-bit/parsers.conf

[INPUT]
    Name          tail
    Path          /var/log/*.log
    Tag           host.*
    DB            /var/lib/fluent-bit/fluent-bit.db
    Mem_Buf_Limit 5MB

[INPUT]
    Name           systemd
    Tag            host.sshd
    Systemd_Filter _SYSTEMD_UNIT=sshd.service
    DB             /var/lib/fluent-bit/sshd.db
    Mem_Buf_Limit  5MB

[INPUT]
    Name                tail
    Tag                 host.*
    Path                /var/lib/docker/containers/*/*.log
    multiline.parser    docker, cri
    DB                  /var/lib/fluent-bit/flb_container.db
    Mem_Buf_Limit       50MB

[OUTPUT]
    Name              cloudwatch_logs
    Match             host.*
    region            ${aws_region}
    log_group_name    /aws/ec2/${aws_log_group}
    log_stream_prefix ${aws_log_stream_prefix}
    auto_create_group true

[OUTPUT]
    Name            s3
    Match           host.*
    bucket          ${aws_s3_bucket}
    region          ${aws_region}
    total_file_size 100M
    upload_timeout  10m
    use_put_object  true
    s3_key_format   /${aws_log_group}/%Y/%m/%d/%H/%M/%S/\$TAG/\$UUID.gz
    store_dir       /var/lib/fluent-bit/s3
EOF

# 启动 fluent-bit 服务
systemctl enable --now fluent-bit
