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

# Message sizes to test
MESSAGE_SIZES=("1K" "4K" "16K" "64K" "256K" "1M")

# Thread counts to test
THREAD_COUNTS=(1 2 4 8)

# Implementation types
IMPL_TYPES=("A1" "A2" "A3")
IMPL_NAMES=("two_copy" "one_copy" "zero_copy")

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output CSV file
OUTPUT_CSV="MT25076_Part_B_results.csv"
PERF_OUTPUT="MT25076_Part_B_perf_results.csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    # Kill any running server/client processes
    pkill -f "MT25076_Part_A" 2>/dev/null || true
    
    # Remove network namespaces if they exist
    sudo ip netns del ns_server 2>/dev/null || true
    sudo ip netns del ns_client 2>/dev/null || true
    
    # Remove veth interfaces
    sudo ip link del veth_server 2>/dev/null || true
}

# Setup network namespaces
setup_namespaces() {
    log_info "Setting up network namespaces..."
    
    # Clean up first
    cleanup
    
    # Create namespaces
    sudo ip netns add ns_server
    sudo ip netns add ns_client
    
    # Create veth pair
    sudo ip link add veth_server type veth peer name veth_client
    
    # Move interfaces to namespaces
    sudo ip link set veth_server netns ns_server
    sudo ip link set veth_client netns ns_client
    
    # Configure server namespace
    sudo ip netns exec ns_server ip addr add 10.0.0.1/24 dev veth_server
    sudo ip netns exec ns_server ip link set veth_server up
    sudo ip netns exec ns_server ip link set lo up
    
    # Configure client namespace
    sudo ip netns exec ns_client ip addr add 10.0.0.2/24 dev veth_client
    sudo ip netns exec ns_client ip link set veth_client up
    sudo ip netns exec ns_client ip link set lo up
    
    # Verify connectivity
    if sudo ip netns exec ns_client ping -c 1 10.0.0.1 > /dev/null 2>&1; then
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
    
    local server_bin="./MT25076_Part_${impl_type}_Server"
    local client_bin="./MT25076_Part_${impl_type}_Client"
    
    log_info "Running: $impl_name, size=$msg_size, threads=$threads"
    
    # Start server in ns_server namespace
    sudo ip netns exec ns_server $server_bin -p $port -s $msg_size &
    local server_pid=$!
    sleep 1
    
    # Check if server started
    if ! kill -0 $server_pid 2>/dev/null; then
        log_error "Server failed to start"
        return 1
    fi
    
    # Run client with perf stat in ns_client namespace
    local perf_output_file=$(mktemp)
    
    sudo ip netns exec ns_client perf stat -e cycles,instructions,cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,context-switches -o "$perf_output_file" \
        $client_bin -i 10.0.0.1 -p $port -s $msg_size -t $threads -d $DURATION 2>&1 | tee /tmp/client_output.txt
    
    # Stop server
    sudo kill $server_pid 2>/dev/null || true
    wait $server_pid 2>/dev/null || true
    
    # Parse client output for metrics
    local throughput=$(grep "THROUGHPUT_GBPS" /tmp/client_output.txt | cut -d',' -f2)
    local latency=$(grep "LATENCY_US" /tmp/client_output.txt | cut -d',' -f2)
    local total_bytes=$(grep "TOTAL_BYTES" /tmp/client_output.txt | cut -d',' -f2)
    
    # Parse perf output
    local cycles=$(grep -E "^\s*[0-9,]+\s+cycles" "$perf_output_file" | awk '{gsub(",","",$1); print $1}')
    local cache_misses=$(grep "cache-misses" "$perf_output_file" | awk '{gsub(",","",$1); print $1}')
    local l1_misses=$(grep "L1-dcache-load-misses" "$perf_output_file" | awk '{gsub(",","",$1); print $1}')
    local llc_misses=$(grep "LLC-load-misses" "$perf_output_file" | awk '{gsub(",","",$1); print $1}')
    local ctx_switches=$(grep "context-switches" "$perf_output_file" | awk '{gsub(",","",$1); print $1}')
    
    # Default values if parsing failed
    throughput=${throughput:-0}
    latency=${latency:-0}
    total_bytes=${total_bytes:-0}
    cycles=${cycles:-0}
    cache_misses=${cache_misses:-0}
    l1_misses=${l1_misses:-0}
    llc_misses=${llc_misses:-0}
    ctx_switches=${ctx_switches:-0}
    
    # Calculate cycles per byte
    local cycles_per_byte=0
    if [ "$total_bytes" -gt 0 ] 2>/dev/null; then
        cycles_per_byte=$(echo "scale=2; $cycles / $total_bytes" | bc 2>/dev/null || echo "0")
    fi
    
    # Append to main CSV
    echo "$impl_name,$msg_size,$threads,$throughput,$latency,$total_bytes,$cycles,$cache_misses,$l1_misses,$llc_misses,$ctx_switches,$cycles_per_byte" >> "$OUTPUT_CSV"
    
    rm -f "$perf_output_file" /tmp/client_output.txt
    
    # Small delay between experiments
    sleep 1
    
    return 0
}

# Main execution
main() {
    log_info "=========================================="
    log_info "MT25076 - Network I/O Experiment Runner"
    log_info "=========================================="
    
    # Compile
    compile_all
    
    # Setup namespaces
    setup_namespaces
    
    # Initialize CSV files
    echo "impl_type,msg_size,threads,throughput_gbps,latency_us,total_bytes,cpu_cycles,cache_misses,l1_misses,llc_misses,context_switches,cycles_per_byte" > "$OUTPUT_CSV"
    
    # Run experiments
    local port=$BASE_PORT
    local exp_count=0
    local total_exp=$((${#IMPL_TYPES[@]} * ${#MESSAGE_SIZES[@]} * ${#THREAD_COUNTS[@]}))
    
    for i in "${!IMPL_TYPES[@]}"; do
        impl_type=${IMPL_TYPES[$i]}
        impl_name=${IMPL_NAMES[$i]}
        
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
    
    # Display summary
    echo ""
    echo "=== Summary ==="
    head -20 "$OUTPUT_CSV"
    echo "..."
}

# Trap for cleanup on exit
trap cleanup EXIT

# Check for root/sudo privileges
if [ "$EUID" -ne 0 ]; then
    log_warn "This script requires sudo privileges for network namespaces"
    log_info "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# Run main
main "$@"
