#!/bin/bash
# MT25076 - Part C: Automated Experiment Script (FIXED)
# Roll Number: MT25076

set -euo pipefail

############################
# Configuration
############################
DURATION=5
BASE_PORT=8888

MESSAGE_SIZES=("1K" "4K" "16K" "64K")
THREAD_COUNTS=(1 2 4 8)

IMPL_TYPES=("A1" "A2" "A3")
IMPL_NAMES=("two_copy" "one_copy" "zero_copy")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_CSV="MT25076_Part_B_results.csv"

############################
# Logging helpers
############################
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SERVER_PID=""

############################
# Cleanup
############################
cleanup() {
    log_info "Cleaning up..."

    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -9 "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    pkill -9 -f MT25076_Part_A 2>/dev/null || true

    ip netns del ns_server 2>/dev/null || true
    ip netns del ns_client 2>/dev/null || true
    ip link del veth_server 2>/dev/null || true
}

trap cleanup EXIT INT TERM

############################
# Namespace setup
############################
setup_namespaces() {
    cleanup

    log_info "Setting up network namespaces..."

    ip netns add ns_server
    ip netns add ns_client

    ip link add veth_server type veth peer name veth_client

    ip link set veth_server netns ns_server
    ip link set veth_client netns ns_client

    ip netns exec ns_server ip addr add 10.0.0.1/24 dev veth_server
    ip netns exec ns_server ip link set veth_server up
    ip netns exec ns_server ip link set lo up

    ip netns exec ns_client ip addr add 10.0.0.2/24 dev veth_client
    ip netns exec ns_client ip link set veth_client up
    ip netns exec ns_client ip link set lo up

    sleep 1

    ip netns exec ns_client ping -c 1 -W 1 10.0.0.1 >/dev/null
    log_info "Namespaces ready"
}

############################
# Build
############################
compile_all() {
    log_info "Compiling all implementations..."
    make clean
    make all
}

############################
# Run single experiment
############################
run_experiment() {
    local impl_type=$1
    local impl_name=$2
    local msg_size=$3
    local threads=$4
    local port=$5

    local server_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Server"
    local client_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Client"

    log_info "Running: $impl_name size=$msg_size threads=$threads port=$port"

    local server_log="/tmp/server_$$.log"
    local client_log="/tmp/client_$$.log"
    local perf_log="/tmp/perf_$$.csv"

    # Start server
    ip netns exec ns_server "$server_bin" -p "$port" -s "$msg_size" \
        >"$server_log" 2>&1 &
    SERVER_PID=$!

    sleep 2
    kill -0 "$SERVER_PID" 2>/dev/null || {
        log_error "Server failed"
        cat "$server_log"
        return 1
    }

    # Run client with perf (CSV-safe)
    ip netns exec ns_client perf stat -x, \
        -e cycles,cache-misses,L1-dcache-load-misses,context-switches \
        -o "$perf_log" \
        timeout $((DURATION + 5)) \
        "$client_bin" -i 10.0.0.1 -p "$port" -s "$msg_size" -t "$threads" -d "$DURATION" \
        >"$client_log" 2>&1 || true

    # Stop server
    kill -9 "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""

    ############################
    # Parse client metrics
    ############################
    throughput=$(grep THROUGHPUT_GBPS "$client_log" | cut -d',' -f2 || echo 0)
    latency=$(grep LATENCY_US "$client_log" | cut -d',' -f2 || echo 0)
    total_bytes=$(grep TOTAL_BYTES "$client_log" | cut -d',' -f2 || echo 0)

    ############################
    # Parse perf CSV (safe)
    ############################
    cycles=$(awk -F, '$3=="cycles"{print $1}' "$perf_log")
    cache_misses=$(awk -F, '$3=="cache-misses"{print $1}' "$perf_log")
    l1_misses=$(awk -F, '$3=="L1-dcache-load-misses"{print $1}' "$perf_log")
    ctx_switches=$(awk -F, '$3=="context-switches"{print $1}' "$perf_log")

    cycles=${cycles:-0}
    cache_misses=${cache_misses:-0}
    l1_misses=${l1_misses:-0}
    ctx_switches=${ctx_switches:-0}

    ############################
    # Derived metric
    ############################
    if [[ "$total_bytes" -gt 0 ]]; then
        cycles_per_byte=$(echo "scale=4; $cycles / $total_bytes" | bc)
    else
        cycles_per_byte=0
    fi

    ############################
    # Write ONE clean CSV row
    ############################
    echo "$impl_name,$msg_size,$threads,$throughput,$latency,$total_bytes,$cycles,$cache_misses,$l1_misses,$ctx_switches,$cycles_per_byte" \
        >> "$OUTPUT_CSV"

    log_info "  -> Throughput=${throughput}Gbps Latency=${latency}us"

    rm -f "$server_log" "$client_log" "$perf_log"
    sleep 1
}

############################
# Main
############################
main() {
    [[ $EUID -eq 0 ]] || { log_error "Run with sudo"; exit 1; }

    compile_all
    setup_namespaces

    echo "impl_type,msg_size,threads,throughput_gbps,latency_us,total_bytes,cpu_cycles,cache_misses,l1_misses,context_switches,cycles_per_byte" \
        > "$OUTPUT_CSV"

    local port=$BASE_PORT
    local total=$(( ${#IMPL_TYPES[@]} * ${#MESSAGE_SIZES[@]} * ${#THREAD_COUNTS[@]} ))
    local count=0

    for i in "${!IMPL_TYPES[@]}"; do
        for msg in "${MESSAGE_SIZES[@]}"; do
            for th in "${THREAD_COUNTS[@]}"; do
                count=$((count + 1))
                log_info "Experiment $count/$total"
                run_experiment "${IMPL_TYPES[$i]}" "${IMPL_NAMES[$i]}" "$msg" "$th" "$port" || true
                port=$((port + 1))
            done
        done
    done

    log_info "Experiments complete"
    log_info "Results saved to $OUTPUT_CSV"
}

main
