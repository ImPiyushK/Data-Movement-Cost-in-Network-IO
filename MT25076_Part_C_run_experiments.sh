#!/bin/bash
# ----------------------------------------------------------------------------
# AI USAGE DECLARATION
# ----------------------------------------------------------------------------
#
# Components utilizing AI:
# - Experiment automation logic.
# - Namespace and cleanup handling.
#
# Verification:
# The generated code was manually reviewed and tested.
# ----------------------------------------------------------------------------
# MT25076 - Part C: Automated Experiment Script
# Roll Number: MT25076
# Profiling is done on the PROCESS THAT IS SENDING (or as requested, bidirectional)

set -euo pipefail

############################
# Configuration
############################
DURATION=3
BASE_PORT=8888

MESSAGE_SIZES=("1K" "4K" "16K" "64K")
THREAD_COUNTS=(1 2 4 8)

IMPL_TYPES=("A1" "A2" "A3")
IMPL_NAMES=("two_copy" "one_copy" "zero_copy")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_APP_CSV="MT25076_Part_B_app_results.csv"
OUTPUT_PERF_S_CSV="MT25076_Part_B_perf_server_sender.csv"
OUTPUT_PERF_C_CSV="MT25076_Part_B_perf_client_sender.csv"

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
CLIENT_PID=""
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

    # Kill server process
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -SIGTERM "$SERVER_PID" 2>/dev/null || true
    fi
     if [[ -n "${CLIENT_PID:-}" ]] && kill -0 "$CLIENT_PID" 2>/dev/null; then
        kill -SIGTERM "$CLIENT_PID" 2>/dev/null || true
    fi

    # Kill any remaining processes
    pkill -9 -f "MT25076_Part_A.*Server" 2>/dev/null || true
    pkill -9 -f "MT25076_Part_A.*Client" 2>/dev/null || true
    pkill -9 -f "perf stat" 2>/dev/null || true

    # Remove namespaces
    ip netns del ns_server 2>/dev/null || true
    ip netns del ns_client 2>/dev/null || true
    ip link del veth_server 2>/dev/null || true
    ip link del veth_client 2>/dev/null || true
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

check_namespaces() {
    if ! ip netns list | grep -q "ns_server" || ! ip netns list | grep -q "ns_client"; then
        log_warn "Namespaces missing, restoring..."
        setup_namespaces
    fi
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
# Parse Perf Output
############################
parse_perf() {
    local perf_log="$1"
    local impl_name="$2"
    local msg_size="$3"
    local threads="$4"
    local output_csv="$5"
    local bytes="$6"

    local cycles=$(grep "cycles" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local cache_misses=$(grep "cache-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local l1_misses=$(grep "L1-dcache-load-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local llc_misses=$(grep "LLC-load-misses" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')
    local ctx_switches=$(grep "context-switches" "$perf_log" 2>/dev/null | awk '{gsub(/,/,"",$1); sum+=$1} END {printf "%.0f", (sum == "" ? 0 : sum)}')

    [[ "$cycles" =~ ^[0-9]+$ ]] || cycles=0
    [[ "$cache_misses" =~ ^[0-9]+$ ]] || cache_misses=0
    [[ "$l1_misses" =~ ^[0-9]+$ ]] || l1_misses=0
    [[ "$llc_misses" =~ ^[0-9]+$ ]] || llc_misses=0
    [[ "$ctx_switches" =~ ^[0-9]+$ ]] || ctx_switches=0

    local cycles_per_byte=0
    if [[ "$bytes" =~ ^[0-9]+$ ]] && [[ "$bytes" -gt 0 ]] && [[ "$cycles" -gt 0 ]]; then
        cycles_per_byte=$(echo "scale=4; $cycles / $bytes" | bc 2>/dev/null || echo "0")
    fi

    log_info "  -> Perf: Cycles=${cycles} CacheMiss=${cache_misses} CPB=${cycles_per_byte}"
    echo "$impl_name,$msg_size,$threads,$cycles,$cache_misses,$l1_misses,$llc_misses,$ctx_switches,$cycles_per_byte" >> "$output_csv"
}

############################
# Run Experiment
############################
run_experiment() {
    local impl_type=$1    # A1, A2, A3
    local impl_name=$2    # two_copy, etc
    local msg_size=$3
    local threads=$4
    local port=$5
    local direction=$6    # "S_to_C" or "C_to_S"

    check_namespaces

    local server_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Server"
    local client_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Client"
    
    local server_log="/tmp/server_$$.log"
    local client_log="/tmp/client_$$.log"
    local perf_log="/tmp/perf_$$.txt"
    
    log_info "Running [$direction]: $impl_name size=$msg_size threads=$threads port=$port"

    # Setup flags based on direction
    local s_mode="sender"
    local c_mode="receiver"
    local monitor_pid_var="SERVER_PID"
    local perf_csv="$OUTPUT_PERF_S_CSV"
    
    if [[ "$direction" == "C_to_S" ]]; then
        s_mode="receiver"
        c_mode="sender"
        monitor_pid_var="CLIENT_PID"
        perf_csv="$OUTPUT_PERF_C_CSV"
    fi

    # Kill strays and wait for ports to be released
    pkill -9 -f "MT25076_Part_A.*Server" 2>/dev/null || true
    pkill -9 -f "MT25076_Part_A.*Client" 2>/dev/null || true
    pkill -9 -f "perf stat" 2>/dev/null || true
    sleep 0.5

    # Start Server
    ip netns exec ns_server "$server_bin" -p "$port" -s "$msg_size" -m "$s_mode" \
        > "$server_log" 2>&1 &
    SERVER_PID=$!
    
    sleep 0.5
    kill -0 "$SERVER_PID" 2>/dev/null || { log_error "Server failed start"; cat "$server_log"; return 1; }
    
    # Start Perf on Server if S->C
    if [[ "$direction" == "S_to_C" ]]; then
        perf stat -e cycles,cache-misses,L1-dcache-load-misses,LLC-load-misses,context-switches \
             -p "$SERVER_PID" > "$perf_log" 2>&1 &
        PERF_PID=$!
        log_info "Monitoring Server PID $SERVER_PID"
    fi

    # Start Client
    ip netns exec ns_client "$client_bin" -i 10.0.0.1 -p "$port" -s "$msg_size" -t "$threads" -d "$DURATION" -m "$c_mode" \
        > "$client_log" 2>&1 &
    CLIENT_PID=$!
    
    # Start Perf on Client if C->S - need to wait for client to fully start
    if [[ "$direction" == "C_to_S" ]]; then
        sleep 0.5
        if kill -0 "$CLIENT_PID" 2>/dev/null; then
            perf stat -e cycles,cache-misses,L1-dcache-load-misses,LLC-load-misses,context-switches \
                 -p "$CLIENT_PID" > "$perf_log" 2>&1 &
            PERF_PID=$!
            log_info "Monitoring Client PID $CLIENT_PID"
        else
            log_warn "Client already finished, skipping perf"
        fi
    fi

    # Wait for Client to finish
    wait "$CLIENT_PID" || true
    CLIENT_PID=""

    # Stop Server FIRST - this causes perf to exit naturally
    kill -SIGTERM "$SERVER_PID" 2>/dev/null || true
    sleep 0.3
    kill -SIGKILL "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""

    # Now wait for Perf to finish (it exits when target process dies)
    if [[ -n "${PERF_PID:-}" ]]; then
        log_info "Waiting for Perf PID $PERF_PID..."
        # Give perf time to write output
        sleep 0.5
        # If still running, force stop
        if kill -0 "$PERF_PID" 2>/dev/null; then
            kill -SIGINT "$PERF_PID" 2>/dev/null || true
            sleep 0.3
            kill -SIGKILL "$PERF_PID" 2>/dev/null || true
        fi
        wait "$PERF_PID" 2>/dev/null || true
        PERF_PID=""
    fi

    # Parse App Metrics (Always from Client log)
    local throughput=$(grep THROUGHPUT_GBPS "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")
    local latency=$(grep LATENCY_US "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")
    local total_bytes=$(grep TOTAL_BYTES "$client_log" 2>/dev/null | cut -d',' -f2 | tr -d ' ' || echo "0")

    log_info "  -> App: Tput=${throughput}Gbps Lat=${latency}us Bytes=${total_bytes}"
    echo "$impl_name,$direction,$msg_size,$threads,$throughput,$latency,$total_bytes" >> "$OUTPUT_APP_CSV"
    
    # Parse Perf Metrics
    parse_perf "$perf_log" "$impl_name" "$msg_size" "$threads" "$perf_csv" "$total_bytes"

    # Cleanup logs and wait for resources
    rm -f "$server_log" "$client_log" "$perf_log"
    sleep 0.5
}

############################
# Main
############################
main() {
    [[ $EUID -eq 0 ]] || { log_error "Run with sudo"; exit 1; }
    if ! command -v perf &>/dev/null; then
        log_error "perf missing (apt install linux-tools-generic)"
        # exit 1  <-- Don't exit, maybe running where perf is restricted but we want app metrics
    fi
    echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true

    compile_all
    setup_namespaces

    # Init CSVs
    echo "impl_type,direction,msg_size,threads,throughput_gbps,latency_us,total_bytes" > "$OUTPUT_APP_CSV"
    echo "impl_type,msg_size,threads,cpu_cycles,cache_misses,l1_misses,llc_misses,context_switches,cycles_per_byte" > "$OUTPUT_PERF_S_CSV"
    echo "impl_type,msg_size,threads,cpu_cycles,cache_misses,l1_misses,llc_misses,context_switches,cycles_per_byte" > "$OUTPUT_PERF_C_CSV"

    local port=$BASE_PORT
    local total=$(( ${#IMPL_TYPES[@]} * ${#MESSAGE_SIZES[@]} * ${#THREAD_COUNTS[@]} * 2 ))
    local count=0

    for idx in "${!IMPL_TYPES[@]}"; do
        local impl_type="${IMPL_TYPES[$idx]}"
        local impl_name="${IMPL_NAMES[$idx]}"
        
        for msg in "${MESSAGE_SIZES[@]}"; do
            for th in "${THREAD_COUNTS[@]}"; do
                
                # Test 1: Server -> Client
                count=$((count + 1))
                log_info "==== Exp $count/$total : $impl_name S->C ===="
                run_experiment "$impl_type" "$impl_name" "$msg" "$th" "$port" "S_to_C"
                port=$((port + 1))
                
                # Test 2: Client -> Server
                count=$((count + 1))
                log_info "==== Exp $count/$total : $impl_name C->S ===="
                run_experiment "$impl_type" "$impl_name" "$msg" "$th" "$port" "C_to_S"
                port=$((port + 1))
                
            done
        done
    done

    log_info "Done. Results:"
    log_info "App: $OUTPUT_APP_CSV"
    log_info "Perf(S): $OUTPUT_PERF_S_CSV"
    log_info "Perf(C): $OUTPUT_PERF_C_CSV"
}
main
