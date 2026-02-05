#!/bin/bash
# MT25076 - Part C: Automated Experiment Script
# Roll Number: MT25076
# Profiling is done on the SERVER side

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
PERF_PID=""

############################
# Cleanup
############################
cleanup() {
    log_info "Cleaning up..."

    # Kill perf process if it exists
    if [[ -n "${PERF_PID:-}" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
        kill -SIGINT "$PERF_PID" 2>/dev/null || true
        wait "$PERF_PID" 2>/dev/null || true
    fi

    # Kill server process if it exists
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -SIGTERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    # Kill any remaining processes
    pkill -9 -f MT25076_Part_A 2>/dev/null || true
    pkill -9 -f "perf stat" 2>/dev/null || true

    # Remove namespaces
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
    log_info "Compilation complete"
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
    local perf_log="/tmp/perf_$$.txt"

    # Ensure no previous processes are running
    pkill -9 -f "MT25076_Part_A.*Server" 2>/dev/null || true
    pkill -9 -f "perf stat" 2>/dev/null || true
    sleep 0.5

    # Start server WITHOUT perf (just plain server)
    ip netns exec ns_server "$server_bin" -p "$port" -s "$msg_size" \
        >"$server_log" 2>&1 &
    SERVER_PID=$!

    sleep 1
    
    # Verify server is running
    kill -0 "$SERVER_PID" 2>/dev/null || {
        log_error "Server failed to start"
        cat "$server_log"
        return 1
    }

    log_info "Server started with PID $SERVER_PID"

    # Start perf to profile the SERVER process
    # We use -p to attach to the running server process
    (perf stat -e cycles,cache-misses,L1-dcache-load-misses,LLC-load-misses,context-switches \
        -p "$SERVER_PID" 2>&1) > "$perf_log" 2>&1 &
    PERF_PID=$!

    sleep 1

    log_info "Perf monitoring started (PID: $PERF_PID) on server (PID: $SERVER_PID)"

    # Run client (drives the test duration)
    ip netns exec ns_client \
        "$client_bin" -i 10.0.0.1 -p "$port" -s "$msg_size" -t "$threads" -d "$DURATION" \
        > "$client_log" 2>&1 || true

    log_info "Client completed"

    # Give a brief moment for any pending data
    sleep 2

    # Stop perf profiling first (send SIGINT to allow it to print stats)
    log_info "Stopping perf profiling..."
    if [[ -n "${PERF_PID:-}" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
        kill -SIGINT "$PERF_PID" 2>/dev/null || true
        # Wait with timeout
        for i in {1..5}; do
            if ! kill -0 "$PERF_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force kill if still running
        kill -9 "$PERF_PID" 2>/dev/null || true
        wait "$PERF_PID" 2>/dev/null || true
        PERF_PID=""
    fi

    # Stop server
    log_info "Stopping server..."
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -SIGTERM "$SERVER_PID" 2>/dev/null || true
        # Wait with timeout
        for i in {1..5}; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force kill if still running
        kill -9 "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi

    sleep 1

    ############################
    # Parse client metrics
    ############################
    local throughput=$(grep THROUGHPUT_GBPS "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")
    local latency=$(grep LATENCY_US "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")
    local total_bytes=$(grep TOTAL_BYTES "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")

    ############################
    # Parse perf output from server profiling
    ############################
    local cycles=$(grep "cycles" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local cache_misses=$(grep "cache-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local l1_misses=$(grep "L1-dcache-load-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local llc_misses=$(grep "LLC-load-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local ctx_switches=$(grep "context-switches" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')

    # Ensure numeric values
    [[ "$cycles" =~ ^[0-9]+$ ]] || cycles=0
    [[ "$cache_misses" =~ ^[0-9]+$ ]] || cache_misses=0
    [[ "$l1_misses" =~ ^[0-9]+$ ]] || l1_misses=0
    [[ "$llc_misses" =~ ^[0-9]+$ ]] || llc_misses=0
    [[ "$ctx_switches" =~ ^[0-9]+$ ]] || ctx_switches=0

    ############################
    # Derived metric
    ############################
    local cycles_per_byte=0
    if [[ "$total_bytes" =~ ^[0-9]+$ ]] && [[ "$total_bytes" -gt 0 ]] && [[ "$cycles" -gt 0 ]]; then
        cycles_per_byte=$(echo "scale=4; $cycles / $total_bytes" | bc 2>/dev/null || echo "0")
    fi

    ############################
    # Write CSV row
    ############################
    echo "$impl_name,$msg_size,$threads,$throughput,$latency,$total_bytes,$cycles,$cache_misses,$l1_misses,$llc_misses,$ctx_switches,$cycles_per_byte" \
        >> "$OUTPUT_CSV"

    log_info "  -> Throughput=${throughput}Gbps Latency=${latency}us Cycles=${cycles}"

    # Show perf output for debugging
    log_info "  -> Server Perf output:"
    cat "$perf_log" 2>/dev/null | head -15 || true

    rm -f "$server_log" "$client_log" "$perf_log"
    sleep 1
}

############################
# Main
############################
main() {
    [[ $EUID -eq 0 ]] || { log_error "Run with sudo"; exit 1; }

    # Check perf availability
    if ! command -v perf &>/dev/null; then
        log_error "perf is not installed. Install with: apt install linux-tools-common linux-tools-generic linux-tools-\$(uname -r)"
        exit 1
    fi

    # Set perf paranoid to allow perf stat
    echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || log_warn "Could not set perf_event_paranoid"

    compile_all
    setup_namespaces

    echo "impl_type,msg_size,threads,throughput_gbps,latency_us,total_bytes,cpu_cycles,cache_misses,l1_misses,llc_misses,context_switches,cycles_per_byte" \
        > "$OUTPUT_CSV"

    local port=$BASE_PORT
    local total=$(( ${#IMPL_TYPES[@]} * ${#MESSAGE_SIZES[@]} * ${#THREAD_COUNTS[@]} ))
    local count=0

    for idx in "${!IMPL_TYPES[@]}"; do
        local impl_type="${IMPL_TYPES[$idx]}"
        local impl_name="${IMPL_NAMES[$idx]}"
        
        for msg in "${MESSAGE_SIZES[@]}"; do
            for th in "${THREAD_COUNTS[@]}"; do
                count=$((count + 1))
                log_info "======== Experiment $count/$total ========"
                run_experiment "$impl_type" "$impl_name" "$msg" "$th" "$port" || true
                port=$((port + 1))
            done
        done
    done

    log_info "Experiments complete"
    log_info "Results saved to $OUTPUT_CSV"
    echo ""
    echo "=== Final Results ==="
    cat "$OUTPUT_CSV"
}

main
