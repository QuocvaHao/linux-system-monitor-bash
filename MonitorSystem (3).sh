#!/bin/bash

# ==============================
# CONFIG
# ==============================
LOG_FILE="system.log"
CSV_FILE="system.csv"

CPU_THRESHOLD=80
MEM_THRESHOLD=80
DISK_THRESHOLD=80

# ==============================
# COLORS
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ==============================
# INIT
# ==============================
init_csv() {
    if [ ! -f "$CSV_FILE" ]; then
        echo "time,cpu,mem,disk" > "$CSV_FILE"
    fi
}

# ==============================
# SYSTEM DATA
# ==============================

get_cpu_usage() {
    top -bn1 | awk '/Cpu/ {printf("%.0f", $2 + $4)}'
}

get_mem_usage() {
    free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}'
}

get_disk_usage() {
    df / | awk 'END {gsub("%","",$5); print $5}'
}

get_load_avg() {
    uptime | awk -F'load average:' '{print $2}'
}

get_network_usage() {
    INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
    RX=$(awk -v iface="$INTERFACE" '$1 ~ iface {print $2}' /proc/net/dev)
    TX=$(awk -v iface="$INTERFACE" '$1 ~ iface {print $10}' /proc/net/dev)
    echo "RX:$RX TX:$TX"
}

# ==============================
# STATUS
# ==============================

get_system_status() {
    CPU=$(get_cpu_usage)
    MEM=$(get_mem_usage)

    if [ "$CPU" -gt 80 ] || [ "$MEM" -gt 80 ]; then
        echo -e "${RED}CRITICAL${NC}"
    elif [ "$CPU" -gt 50 ]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${GREEN}STABLE${NC}"
    fi
}

# ==============================
# UI BAR
# ==============================

draw_bar() {
    VALUE=$1
    BAR=""
    FILLED=$((VALUE / 2))

    for ((i=0;i<FILLED;i++)); do
        BAR+="█"
    done

    if [ "$VALUE" -gt 80 ]; then
        echo -e "${RED}$BAR $VALUE%${NC}"
    elif [ "$VALUE" -gt 50 ]; then
        echo -e "${YELLOW}$BAR $VALUE%${NC}"
    else
        echo -e "${GREEN}$BAR $VALUE%${NC}"
    fi
}

# ==============================
# LOGGING
# ==============================

log_data() {
    CPU=$(get_cpu_usage)
    MEM=$(get_mem_usage)
    DISK=$(get_disk_usage)
    TIME=$(date "+%Y-%m-%d %H:%M:%S")

    if [[ -z "$CPU" || -z "$MEM" || -z "$DISK" ]]; then
        return
    fi

    echo "$TIME | CPU:$CPU% | MEM:$MEM% | DISK:$DISK%" >> "$LOG_FILE"
    echo "$TIME,$CPU,$MEM,$DISK" >> "$CSV_FILE"
}

# ==============================
# ALERT
# ==============================

check_alerts() {
    CPU=$(get_cpu_usage)
    MEM=$(get_mem_usage)
    DISK=$(get_disk_usage)

    if [ "$CPU" -gt "$CPU_THRESHOLD" ]; then
        echo -e "${RED}⚠ CPU cao: $CPU%${NC}"
        echo -e "\a"
    fi

    if [ "$MEM" -gt "$MEM_THRESHOLD" ]; then
        echo -e "${RED}⚠ RAM cao: $MEM%${NC}"
    fi

    if [ "$DISK" -gt "$DISK_THRESHOLD" ]; then
        echo -e "${RED}⚠ DISK cao: $DISK%${NC}"
    fi
}

# ==============================
# DASHBOARD
# ==============================

dashboard() {
    while true; do
        clear

        CPU=$(get_cpu_usage)
        MEM=$(get_mem_usage)
        DISK=$(get_disk_usage)

        echo -e "${GREEN}==============================${NC}"
        echo -e "${GREEN}   LINUX MONITOR DASHBOARD${NC}"
        echo -e "${GREEN}==============================${NC}"

        echo ""
        echo -e "CPU  : $(draw_bar $CPU)"
        echo -e "RAM  : $(draw_bar $MEM)"
        echo -e "DISK : $(draw_bar $DISK)"

        echo ""
        echo "Load Avg: $(get_load_avg)"
        echo "Network : $(get_network_usage)"
        echo "Status  : $(get_system_status)"

        echo ""
        echo -e "${YELLOW}Top CPU:${NC}"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

        echo ""
        echo -e "${YELLOW}Top RAM:${NC}"
        ps -eo pid,comm,%mem --sort=-%mem | head -n 6

        echo ""
        echo "Users:"
        who

        echo ""
        echo "Uptime:"
        uptime -p

        echo ""
        echo -e "${RED}Alerts:${NC}"
        check_alerts

        log_data

        echo ""
        echo "Ctrl + C để thoát..."
        sleep 2
    done
}

# ==============================
# ANALYSIS
# ==============================

analyze_log() {
    if [ ! -f "$CSV_FILE" ]; then
        echo "Chưa có dữ liệu!"
        return
    fi

    awk -F',' '
    NR>1 {
        cpu+=$2; mem+=$3; disk+=$4;
        if($2>cpu_max) cpu_max=$2;
        if(cpu_min=="" || $2<cpu_min) cpu_min=$2;
    }
    END {
        print "CPU avg:", cpu/NR "%";
        print "CPU max:", cpu_max "%";
        print "CPU min:", cpu_min "%";
        print "RAM avg:", mem/NR "%";
        print "DISK avg:", disk/NR "%";
    }' "$CSV_FILE"
}

# ==============================
# EXPORT REPORT
# ==============================

export_report() {
    {
        echo "====== SYSTEM REPORT ======"
        echo "Time: $(date)"
        echo ""

        echo "System status:"
        get_system_status
        echo ""

        echo "Load Average:"
        get_load_avg
        echo ""

        echo "Top Process:"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

        echo ""
        echo "Last logs:"
        tail -n 10 "$LOG_FILE"

        echo ""
        echo "Summary:"
        analyze_log

    } > report.txt

    echo "✔ Đã tạo report.txt"
}

# ==============================
# EXPORT GRAPH
# ==============================

export_graph() {
    gnuplot <<EOF
set terminal png
set output "cpu.png"
set title "CPU Usage"
set datafile separator ","
plot "$CSV_FILE" using 2 with lines title "CPU"
EOF

    echo "✔ Đã xuất cpu.png"
}

# ==============================
# CRON
# ==============================

setup_cron() {
    if ! command -v crontab &> /dev/null; then
        echo "❌ Chưa cài cron. Hãy chạy: sudo apt install cron"
        return
    fi

    (crontab -l 2>/dev/null; echo "* * * * * $(pwd)/monitor.sh --log") | crontab -
    echo "✔ Auto log mỗi phút"
}       

# ==============================
# AUTO MODE
# ==============================

if [ "$1" == "--log" ]; then
    init_csv
    log_data
    exit
fi

# ==============================
# MENU
# ==============================

init_csv

while true; do
    echo ""
    echo "========= MENU ========="
    echo "1. Dashboard realtime"
    echo "2. Ghi log"
    echo "3. Xem log"
    echo "4. Phân tích dữ liệu"
    echo "5. Export report"
    echo "6. Auto log (cron)"
    echo "7. Export graph"
    echo "8. Xóa log"
    echo "0. Thoát"
    echo "========================"
    read -p "Chọn: " choice

    case $choice in
        1) dashboard ;;
        2) log_data; echo "✔ Đã ghi!" ;;
        3) cat "$LOG_FILE" ;;
        4) analyze_log ;;
        5) export_report ;;
        6) setup_cron ;;
        7) export_graph ;;
        8) > "$LOG_FILE"; > "$CSV_FILE"; echo "✔ Đã xóa log!" ;;
        0) exit ;;
        *) echo "Sai lựa chọn!" ;;
    esac
done