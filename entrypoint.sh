#!/bin/bash

# --- 1. 生成随机配置 ---
# 从 arop.py 的逻辑中获取，用于生成 sing-box 配置文件和 cloudflared URL
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=$((RANDOM % 55536 + 10000))
WS_PATH="/${UUID}-vm"

echo "Generated UUID: ${UUID}"
echo "Generated Port: ${PORT}"
echo "Generated WebSocket Path: ${WS_PATH}"

# --- 2. 创建 sing-box 配置文件 (sb.json) ---
# 这是从 arop.py 脚本中提取的配置模板
cat > /app/sb.json <<EOL
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "127.0.0.1",
      "listen_port": ${PORT},
      "tcp_fast_open": true,
      "sniff": true,
      "sniff_override_destination": true,
      "proxy_protocol": false,
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOL

echo "sing-box configuration created."

# --- 3. 以后台模式启动 cloudflared ---
# URL 路径需要与 sing-box 的 WebSocket 路径完全匹配
# --no-autoupdate 推荐在容器中使用
# & 将进程放到后台
./cloudflared tunnel --url http://localhost:${PORT}${WS_PATH}?ed=2048 --edge-ip-version auto --no-autoupdate --protocol http2 > argo.log 2>&1 &

echo "Starting cloudflared in the background..."
sleep 5 # 等待 cloudflared 初始化并生成域名

# --- 4. 打印 Argo Tunnel 的域名和节点信息 ---
# 从 argo.log 文件中提取域名
ARGO_DOMAIN=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' argo.log | head -n 1)

if [ -z "$ARGO_DOMAIN" ]; then
    echo "Could not find Argo Tunnel domain. Tailing log for 10 seconds:"
    cat argo.log
    exit 1
fi

# 移除 https:// 前缀
ARGO_HOSTNAME=${ARGO_DOMAIN#https://}

echo "================================================================"
echo "Argo Tunnel Domain: ${ARGO_HOSTNAME}"
echo "----------------------------------------------------------------"
# 调用 python 脚本仅用于生成链接，而不是运行服务
# 我们传递域名、端口和 UUID 作为参数，但这需要修改 arop.py
# 为简单起见，我们直接在这里生成链接
VMESS_CONFIG=$(printf '{"v":"2","ps":"vmess-ws-tls-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s?ed=2048","tls":"tls","sni":"%s"}' "104.16.0.0" "${UUID}" "${ARGO_HOSTNAME}" "${WS_PATH}" "${ARGO_HOSTNAME}")
VMESS_LINK="vmess://$(echo -n $VMESS_CONFIG | base64 -w 0)"
echo "VMess Link (Example with TLS on port 443):"
echo "${VMESS_LINK}"
echo "================================================================"
echo "For more node variations, check the logic in arop.py"
echo "Tailing cloudflared log (argo.log):"
tail -f argo.log &

# --- 5. 以前台模式启动 sing-box ---
# 这将作为容器的主进程，保持容器运行
echo "Starting sing-box in the foreground..."
./sing-box run -c /app/sb.json
