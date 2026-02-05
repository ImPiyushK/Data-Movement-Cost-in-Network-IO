#!/bin/bash
# MT25076 - Part C: Automated Experiment Script
# Roll Number: MT25076
#
# This script:
# - Compiles all implementations
# - Sets up network namespaces for client/server isolation
# - Runs experiments across message sizes and thread counts
# - Collects profiling data using perf stat
# - Outputs results in CSV format

set -e

# Configuration
DURATION=5  # Duration per experiment in seconds
BASE_PORT=8888

# Message sizes to test (at least 4 as required)
MESSAGE_SIZES=("1K" "4K" "16K" "64K")

# Thread counts to test (at least 4 as required)
THREAD_COUNTS=(1 2 4 8)

# Implementation types
IMPL_TYPES=("A1" "A2" "A3")
IMPL_NAMES=("two_copy" "one_copy" "zero_copy")

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output CSV file
OUTPUT_CSV="MT25076_Part_B_results.csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Global server PID
SERVER_PID=""

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Kill server if running
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        kill -9 $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
    
    # Kill any remaining server/client processes
    pkill -9 -f "MT25076_Part_A" 2>/dev/null || true
    
    # Remove network namespaces if they exist
    ip netns del ns_server 2>/dev/null || true
    ip netns del ns_client 2>/dev/null || true
    
    # Remove veth interfaces
    ip link del veth_server 2>/dev/null || true
}

# Setup network namespaces
setup_namespaces() {
    log_info "Setting up network namespaces..."
    
    # Clean up first
    cleanup
    
    # Create namespaces
    ip netns add ns_server
    ip netns add ns_client
    
    # Create veth pair
    ip link add veth_server type veth peer name veth_client
    
    # Move interfaces to namespaces
    ip link set veth_server netns ns_server
    ip link set veth_client netns ns_client
    
    # Configure server namespace
    ip netns exec ns_server ip addr add 10.0.0.1/24 dev veth_server
    ip netns exec ns_server ip link set veth_server up
    ip netns exec ns_server ip link set lo up
    
    # Configure client namespace
    ip netns exec ns_client ip addr add 10.0.0.2/24 dev veth_client
    ip netns exec ns_client ip link set veth_client up
    ip netns exec ns_client ip link set lo up
    
    # Wait for interfaces to be ready
    sleep 1
    
    # Verify connectivity
    if ip netns exec ns_client ping -c 1 -W 2 10.0.0.1 > /dev/null 2>&1; then
        log_info "Network namespaces configured successfully"
    else
        log_error "Failed to configure network namespaces"
        exit 1
    fi
}

# Compile all implementations
compile_all() {
    log_info "Compiling all implementations..."
    make clean
    make all
    log_info "Compilation complete"
}

# Run a single experiment
run_experiment() {
    local impl_type=$1
    local impl_name=$2
    local msg_size=$3
    local threads=$4
    local port=$5
    
    local server_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Server"
    local client_bin="$SCRIPT_DIR/MT25076_Part_${impl_type}_Client"
    
    log_info "Running: $impl_name, size=$msg_size, threads=$threads, port=$port"
    
    # Start server in ns_server namespace (background)
    ip netns exec ns_server timeout $((DURATION + 10)) $server_bin -p $port -s $msg_size > /tmp/server_output_$$.txt 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 2
    
    # Check if server is running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_error "Server failed to start"
        cat /tmp/server_output_$$.txt 2>/dev/null || true
        return 1
    fi
    
    # Run client with perf stat in ns_client namespace
    local perf_output_file="/tmp/perf_output_$$.txt"
    local client_output_file="/tmp/client_output_$$.txt"
    
    # Run perf stat with timeout
    ip netns exec ns_client perf stat -e cycles,instructions,cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,context-switches \
        -o "$perf_output_file" \
        timeout $((DURATION + 5)) $client_bin -i 10.0.0.1 -p $port -s $msg_size -t $threads -d $DURATION \
        > "$client_output_file" 2>&1
    
    local client_exit=$?
    
    # Stop server
    if kill -0 $SERVER_PID 2>/dev/null; then
        kill -TERM $SERVER_PID 2>/dev/null || true
        sleep 1
        kill -9 $SERVER_PID 2>/dev/null || true
    fi
    wait $SERVER_PID 2>/dev/null || true
    SERVER_PID=""
    
    # Parse client output for metrics
    local throughput=$(grep "THROUGHPUT_GBPS" "$client_output_file" 2>/dev/null | cut -d',' -f2 | tr -d ' ')
    local latency=$(grep "LATENCY_US" "$client_output_file" 2>/dev/null | cut -d',' -f2 | tr -d ' ')
    local total_bytes=$(grep "TOTAL_BYTES" "$client_output_file" 2>/dev/null | cut -d',' -f2 | tr -d ' ')
    
    # Parse perf output
    local cycles=$(grep -E "cycles" "$perf_output_file" 2>/dev/null | head -1 | awk '{gsub(",","",$1); print $1}')
    local cache_misses=$(grep "cache-misses" "$perf_output_file" 2>/dev/null | awk '{gsub(",","",$1); print $1}')
    local l1_misses=$(grep "L1-dcache-load-misses" "$perf_output_file" 2>/dev/null | awk '{gsub(",","",$1); print $1}')
    local ctx_switches=$(grep "context-switches" "$perf_output_file" 2>/dev/null | awk '{gsub(",","",$1); print $1}')
    
    # Default values if parsing failed
    throughput=${throughput:-0}
    latency=${latency:-0}
    total_bytes=${total_bytes:-0}
    cycles=${cycles:-0}
    cache_misses=${cache_misses:-0}
    l1_misses=${l1_misses:-0}
    ctx_switches=${ctx_switches:-0}
    
    # Calculate cycles per byte
    local cycles_per_byte=0
    if [ "$total_bytes" != "0" ] && [ -n "$total_bytes" ] && [ -n "$cycles" ]; then
        cycles_per_byte=$(echo "scale=2; $cycles / $total_bytes" | bc 2>/dev/null || echo "0")
    fi
    
    # Append to main CSV
    echo "$impl_name,$msg_size,$threads,$throughput,$latency,$total_bytes,$cycles,$cache_misses,$l1_misses,$ctx_switches,$cycles_per_byte" >> "$OUTPUT_CSV"
    
    log_info "  -> Throughput: ${throughput} Gbps, Latency: ${latency} us"
    
    # Cleanup temp files
    rm -f "$perf_output_file" "$client_output_file" /tmp/server_output_$$.txt
    
    # Small delay between experiments
    sleep 2
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "MT25076 - Network I/O Experiment Runner"
    log_info "=========================================="
    
    # Check for root privileges
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires root privileges"
        log_info "Please run: sudo $0"
        exit 1
    fi
    
    # Check for required tools
    if ! command -v perf &> /dev/null; then
        log_warn "perf not found, installing linux-tools..."
        apt-get update && apt-get install -y linux-tools-common linux-tools-generic || true
    fi
    
    # Compile
    compile_all
    
    # Setup namespaces
    setup_namespaces
    
    # Initialize CSV file
    echo "impl_type,msg_size,threads,throughput_gbps,latency_us,total_bytes,cpu_cycles,cache_misses,l1_misses,context_switches,cycles_per_byte" > "$OUTPUT_CSV"
    
    # Run experiments
    local port=$BASE_PORT
    local exp_count=0
    local total_exp=$((${#IMPL_TYPES[@]} * ${#MESSAGE_SIZES[@]} * ${#THREAD_COUNTS[@]}))
    
    for i in "${!IMPL_TYPES[@]}"; do
        impl_type=${IMPL_TYPES[$i]}
        impl_name=${IMPL_NAMES[$i]}
        
        log_info "--- Testing $impl_name implementation ---"
        
        for msg_size in "${MESSAGE_SIZES[@]}"; do
            for threads in "${THREAD_COUNTS[@]}"; do
                exp_count=$((exp_count + 1))
                log_info "Experiment $exp_count/$total_exp"
                
                if ! run_experiment "$impl_type" "$impl_name" "$msg_size" "$threads" "$port"; then
                    log_warn "Experiment failed, continuing..."
                fi
                
                port=$((port + 1))
            done
        done
    done
    
    # Cleanup
    cleanup
    
    log_info "=========================================="
    log_info "Experiments complete!"
    log_info "Results saved to: $OUTPUT_CSV"
    log_info "=========================================="
    
    # Display results
    echo ""
    echo "=== Results Summary ==="
    cat "$OUTPUT_CSV"
}

# Trap for cleanup on exit/interrupt
trap cleanup EXIT INT TERM

# Run main
main "$@"
