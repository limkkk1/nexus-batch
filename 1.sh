#!/bin/bash

# Nexus 多ID运行管理工具（v4.2.1）
# 功能：管理 Nexus 网络节点的批量启动、轮换、状态检查和分组操作

# 预设路径
export PATH="$HOME/local/bin:$PATH"

# 使用指定目录下的 screen
SCREEN_BIN="/home/user/app/nexus-batch/screen"

NEXUS_BIN="/home/user/app/nexus-batch/nexus-network"
ALL_IDS_FILE="/home/user/app/nexus-batch/id.txt"
GROUPS_DIR="/home/user/app/nexus-batch/groups"
LOG_DIR="/home/user/app/nexus-batch/logs"
BATCH_LOG="$LOG_DIR/batch_history.log"
ROTATION_LOG="$LOG_DIR/rotation_schedule.log"
LAST_INDEX_FILE="/home/user/app/nexus-batch/last_batch_index.txt"
BATCH_SIZE=100

# 初始化目录
mkdir -p "$LOG_DIR" "$GROUPS_DIR"

# 授权检查
AUTH_FILE="/home/user/app/nexus-batch/authorized.txt"
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "unknown")

if [ -f "$AUTH_FILE" ]; then
    AUTHORIZED_ID=$(cat "$AUTH_FILE")
    if [ "$MACHINE_ID" != "$AUTHORIZED_ID" ]; then
        echo "❌ 授权失败！此机器未获得 Nexus 运行权限。"
        exit 1
    fi
else
    echo "$MACHINE_ID" > "$AUTH_FILE"
    echo "✅ 已生成授权文件: $AUTH_FILE"
fi

# 检查必要文件
if [ ! -f "$ALL_IDS_FILE" ]; then
    echo "错误：$ALL_IDS_FILE 不存在，请确保文件已创建并包含节点 ID 列表。"
    exit 1
fi
if [ ! -f "$NEXUS_BIN" ]; then
    echo "错误：$NEXUS_BIN 不存在或不可执行，请检查路径。"
    exit 1
fi

# 计算总批次
get_total_batches() {
    mapfile -t IDS < "$ALL_IDS_FILE"
    total=${#IDS[@]}
    echo $(((total + BATCH_SIZE - 1) / BATCH_SIZE))
}

# 启动指定批次
start_batch() {
    batch_num=$1
    mapfile -t IDS < "$ALL_IDS_FILE"
    start_idx=$(((batch_num - 1) * BATCH_SIZE))
    BATCH_IDS=("${IDS[@]:$start_idx:$BATCH_SIZE}")

    echo "正在启动第 $batch_num 批..."
    for id in "${BATCH_IDS[@]}"; do
        if $SCREEN_BIN -ls | grep -q "nexu_${id}"; then
            echo "ID $id 已在运行，跳过。"
        else
            $SCREEN_BIN -S "nexu_${id}" -dm bash -c "$NEXUS_BIN start --node-id $id --max-difficulty extra_large"
            if $SCREEN_BIN -ls | grep -q "nexu_${id}"; then
                echo "已启动ID：$id"
                WAIT=1
                echo -n "等待 $WAIT 秒"
                for ((i=WAIT; i>0; i--)); do
                    echo -ne "\r等待 $i 秒  "
                    sleep 1
                done
                echo -e "\r等待完成，开始启动下一个ID。   "
            else
                echo "启动ID $id 失败。"
            fi
        fi
    done

    echo "运行编号: $(date +%s)" >> "$BATCH_LOG"
    echo "批次: 第 $batch_num 批" >> "$BATCH_LOG"
    echo "时间: $(date +'%F %T')" >> "$BATCH_LOG"
    echo "ID列表: ${BATCH_IDS[*]}" >> "$BATCH_LOG"
    echo "-----" >> "$BATCH_LOG"
    echo "$batch_num" > "$LAST_INDEX_FILE"
    read -p "批次启动完成。按回车返回当前子菜单..."
    clear
    batch_menu
}

# 查看节点状态
view_node_status() {
    sessions=$($SCREEN_BIN -ls | grep "nexu_" | awk '{print $1}' | tr -d '\0')
    running_count=0
    echo "运行ID实时状态如下："
    if [ -z "$sessions" ]; then
        echo "无ID运行"
    else
        for s in $sessions; do
            $SCREEN_BIN -S "$s" -X hardcopy "/tmp/${s}.log"
            if [ -f "/tmp/${s}.log" ]; then
                fifth=$(sed -n '5p' "/tmp/${s}.log" | strings | tr -d '\0' | tr -d '\n')
                echo "$fifth"
                running_count=$((running_count + 1))
            else
                echo "（无日志）"
            fi
            rm -f "/tmp/${s}.log"
        done
    fi
    echo "共计 $running_count 个运行"
    read -p "按回车返回主菜单..."
    return
}

# 关闭所有节点
stop_all_nodes() {
    echo "关闭所有 ID 的 screen 会话..."
    for s in $($SCREEN_BIN -ls | grep "nexu_" | awk '{print $1}'); do
        $SCREEN_BIN -S "$s" -X quit
        echo "已关闭 $s"
    done
    read -p "操作完成。按回车返回主菜单..."
    return
}

# 进入某个 ID 的运行界面
enter_node_session() {
    clear
    echo "当前所有 screen 会话："
    sessions=($($SCREEN_BIN -ls | grep "nexu_" | awk '{print $1}'))
    for i in ${!sessions[@]}; do
        echo "$((i+1))) ${sessions[$i]}"
    done
    echo "请输入要进入的会话编号（或输入 0 返回）: "
    read session_num
    if [[ "$session_num" -ge 1 && "$session_num" -le ${#sessions[@]} ]]; then
        $SCREEN_BIN -r "${sessions[$((session_num-1))]}"
    elif [[ "$session_num" == "0" ]]; then
        echo "返回主菜单。"
    else
        echo "无效的编号，请重新输入。"
    fi
    read -p "按回车返回主菜单..."
}

# 显示主菜单
show_menu() {
    clear
    echo "=============================================="
    echo " Nexus 多ID运行管理工具（v4.2.1）By:Ccool"
    echo "=============================================="
    echo " 1) 一键后台启动ID"
    echo " 2) 一键关闭所有 ID"
    echo " 3) 进入某个 ID 的运行界面"
    echo " 4) 一键退出脚本（ID仍保持运行）"
    echo "=============================================="
    echo -n "请选择操作 (1-4): "
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1) start_batch 1 ;;
        2) stop_all_nodes ;;
        3) enter_node_session ;;
        4)
            read -p "确认退出？运行中的ID不会受到影响 (y/n): " confirm
            [ "$confirm" == "y" ] && echo "感谢使用，已退出。" && exit 0
            ;;
        *) echo "无效选项，请重新输入"; read; clear ;;
    esac
done