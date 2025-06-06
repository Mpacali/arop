# 使用一个轻量的 Python 镜像作为基础
FROM python:3.9-slim

# 设置工作目录
WORKDIR /app

# 安装必要的工具：curl 用于下载，tar 用于解压
# ca-certificates 用于 https 连接
RUN apt-get update && apt-get install -y curl tar ca-certificates && rm -rf /var/lib/apt/lists/*

# 复制你的 Python 脚本到容器中
COPY arop.py .
# 复制启动脚本到容器中
COPY entrypoint.sh .

# 赋予脚本执行权限
RUN chmod +x entrypoint.sh

# --- 下载并准备二进制文件 ---
# 注意：这里的 URL 和版本是根据 arop.py 脚本逻辑提取的。
# 脚本会动态检测架构，这里我们为 amd64/x86_64 硬编码。
# 如果你需要在 ARM64 架构上构建，请修改下面的 URL。

# 下载 cloudflared
# 适用于 amd64 架构
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /app/cloudflared && \
    chmod +x /app/cloudflared

# 下载 sing-box (以脚本中的 v1.6.0 为例，你也可以改为最新版)
# 适用于 amd64 架构
RUN curl -L https://github.com/SagerNet/sing-box/releases/download/v1.6.0/sing-box-1.6.0-linux-amd64.tar.gz -o sing-box.tar.gz && \
    tar -xzf sing-box.tar.gz && \
    mv sing-box-1.6.0-linux-amd64/sing-box /app/sing-box && \
    rm -r sing-box-1.6.0-linux-amd64 sing-box.tar.gz && \
    chmod +x /app/sing-box

# 设置容器的入口点
ENTRYPOINT ["./entrypoint.sh"]
