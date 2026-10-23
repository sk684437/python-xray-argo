#!/usr/bin/env bash

set -e
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null)}
export DEBIAN_FRONTEND=noninteractive

# 安装目录
APP_DIR="$PWD"
STATE_FILE="${APP_DIR}/.project_type"
APP_NAME=$(tr -dc a-z </dev/urandom | head -c 6)
export ARGO_PORT=${ARGO_PORT:-'8001'} 
export ARGO_DOMAIN=${ARGO_DOMAIN}
export ARGO_AUTH=${ARGO_AUTH}
export NEZHA_SERVER=${NEZHA_SERVER}
export NEZHA_PORT=${NEZHA_PORT}
export NEZHA_KEY=${NEZHA_KEY}
export SUB_PATH=${SUB_PATH}

# 运行前先清理可能重复运行的旧进程
pkill -f '\.npm/' >/dev/null 2>&1 || true
pkill -f '\.cache/' >/dev/null 2>&1 || true
screen -ls | grep ${APP_NAME} | awk '{print $1}' | xargs -I {} screen -X -S {} quit >/dev/null 2>&1 || true

# 卸载模式：支持 -u 或 uni
if [[ "$1" == "-u" || "$1" == "u" || "$1" == "uninstall" ]]; then
    echo "执行卸载操作..."

    if [[ -f "${STATE_FILE}" ]]; then
        INSTALLED_TYPE=$(cat "${STATE_FILE}")
        echo "检测到已安装项目: ${INSTALLED_TYPE}"
    else
        echo "未检测到项目状态文件，将执行清理..."
        INSTALLED_TYPE="unknown"
    fi
    
    # 清理进程和screen
    pkill -f '\.npm/' >/dev/null 2>&1 || true
    pkill -f '\.cache/' >/dev/null 2>&1 || true
    screen -ls | grep ${APP_NAME} | awk '{print $1}' | xargs -I {} screen -X -S {} quit 2>/dev/null || true

    echo "删除项目目录"
    rm -rf "${APP_DIR}"

    echo ""
    echo -e "\e[1;32m卸载完成\033[0m"
    exit 0
fi

# 固定使用 Python 项目
PROJECT_TYPE="python"

# 安装公共依赖
echo "安装系统依赖中，请稍等..."

apt-get update -qq

apt-get install -y -qq \
curl \
wget \
git \
screen \
ca-certificates \
gnupg >/dev/null 2>&1

mkdir -p "${APP_DIR}"
echo "${PROJECT_TYPE}" > "${STATE_FILE}"
cd "${APP_DIR}"

# Python 项目流程
if [[ "$PROJECT_TYPE" == "python" ]]; then
    if ! command -v python3 &> /dev/null; then
        echo "正在安装 Python3，请稍等..."
        apt-get install -y -qq python3 python3-venv python3-pip >/dev/null 2>&1
    else
        echo "Python3 已安装，跳过"
    fi
    
    if ! command -v python3 &> /dev/null; then
        echo -e "\e[1;31mPython3 安装失败\033[0m"
        exit 1
    fi

    echo "下载 Python 项目文件..."
    wget -q -O app.py https://raw.githubusercontent.com/eooce/python-xray-argo/native/app.py
    wget -q -O index.html https://raw.githubusercontent.com/sk684437/hello2/refs/heads/main/index.html
    echo "创建 Python 虚拟环境..."
    python3 -m venv venv
    source venv/bin/activate
    echo "安装 Python 依赖..."
    pip install requests python-dotenv cryptography -qqq 
    echo "配置环境变量..."
    echo "UUID=${UUID}" > "${APP_DIR}/.env"
    echo "SHOW_LOG=no" >> "${APP_DIR}/.env"
    [[ -n "${SUB_PATH}" ]] && echo "SUB_PATH=${SUB_PATH}" >> "${APP_DIR}/.env"
    [[ -n "${NEZHA_SERVER}" ]] && echo "NEZHA_SERVER=${NEZHA_SERVER}" >> "${APP_DIR}/.env"
    [[ -n "${NEZHA_PORT}" ]] && echo "NEZHA_PORT=${NEZHA_PORT}" >> "${APP_DIR}/.env"
    [[ -n "${NEZHA_KEY}" ]] && echo "NEZHA_KEY=${NEZHA_KEY}" >> "${APP_DIR}/.env"
    [[ -n "${ARGO_DOMAIN}" ]] && echo "ARGO_DOMAIN=${ARGO_DOMAIN}" >> "${APP_DIR}/.env"
    [[ -n "${ARGO_AUTH}" ]] && echo "ARGO_AUTH=${ARGO_AUTH}" >> "${APP_DIR}/.env"
    [[ -n "${ARGO_PORT}" ]] && echo "ARGO_PORT=${ARGO_PORT}" >> "${APP_DIR}/.env"

    echo "正在混淆 Python 代码..."
    # 读取文件内容并进行 JSON 转义
    CODE_JSON=$(cat app.py | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    
    # 调用混淆 API 并提取 obfuscated 字段
    OBFUSCATED=$(curl -s -X POST https://obf.eooce.com/api/obfuscate \
        -H "Content-Type: application/json" \
        -d "{\"code\": ${CODE_JSON}}" | \
        grep -o '"obfuscated":"[^"]*"' | \
        sed 's/"obfuscated":"//' | \
        sed 's/"$//' | \
        sed 's/\\n/\n/g' | \
        sed 's/\\"/"/g' | \
        sed 's/\\\\/\\/g')
    
    if [[ -n "${OBFUSCATED}" ]]; then
        echo "${OBFUSCATED}" > ${APP_NAME}.py
        rm -f app.py  >/dev/null 2>&1
    else
        echo -e "\e[1;33m警告：代码混淆失败，使用原始代码\033[0m"
    fi

    echo "启动 Python 项目..."
    set -a; source "${APP_DIR}/.env"; set +a
    screen -dm -S ${APP_NAME} ${APP_DIR}/venv/bin/python3 ${APP_NAME}.py
fi

echo "请稍等35秒，等待项目启动并生成节点..."
sleep 35

echo ""
echo -e "\e[1;32m安装完成\033[0m"
echo ""
echo "项目类型: ${PROJECT_TYPE}"
echo "APP_NAME: ${APP_NAME}"
echo "节点信息如下: "
cat ${APP_DIR}/.cache/sub.txt
echo ""
exit 0