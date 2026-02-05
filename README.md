# MT25076 - Network I/O Data Movement Cost Analysis

## Roll Number: MT25076

## Overview
This project implements and compares three different socket communication mechanisms to study the cost of data movement in network I/O:

1. **Two-Copy (A1)**: Baseline using `send()`/`recv()` socket primitives
2. **One-Copy (A2)**: Optimized using `sendmsg()` with iovec for scatter-gather I/O
3. **Zero-Copy (A3)**: Using `sendmsg()` with `MSG_ZEROCOPY` flag

## Files Structure

| File | Description |
|------|-------------|
| `MT25076_Part_A_common.h` | Common header with message structure and utilities |
| `MT25076_Part_A1_Server.c` | Two-copy server implementation |
| `MT25076_Part_A1_Client.c` | Two-copy client implementation |
| `MT25076_Part_A2_Server.c` | One-copy server implementation |
| `MT25076_Part_A2_Client.c` | One-copy client implementation |
| `MT25076_Part_A3_Server.c` | Zero-copy server implementation |
| `MT25076_Part_A3_Client.c` | Zero-copy client implementation |
| `MT25076_Part_C_run_experiments.sh` | Automated experiment runner |
| `MT25076_Part_D_plots.py` | Matplotlib plotting script |
| `Makefile` | Build configuration |

## Compilation

```bash
make clean
make all
```

This compiles all six executables:
- `MT25076_Part_A1_Server`, `MT25076_Part_A1_Client`
- `MT25076_Part_A2_Server`, `MT25076_Part_A2_Client`
- `MT25076_Part_A3_Server`, `MT25076_Part_A3_Client`

## Usage

### Running Server (in one terminal/namespace)
```bash
./MT25076_Part_A1_Server -p 8888 -s 16K
```

Options:
- `-p port`: Port number (default: 8888)
- `-s size`: Message size (e.g., 1K, 4K, 16K, 64K, 256K, 1M)

### Running Client (in another terminal/namespace)
```bash
./MT25076_Part_A1_Client -i 127.0.0.1 -p 8888 -s 16K -t 4 -d 10
```

Options:
- `-i ip`: Server IP address
- `-p port`: Port number
- `-s size`: Message size
- `-t threads`: Number of client threads
- `-d duration`: Test duration in seconds

## Running Automated Experiments

The experiment script requires sudo for network namespace setup:

```bash
chmod +x MT25076_Part_C_run_experiments.sh
sudo ./MT25076_Part_C_run_experiments.sh
```

This will:
1. Compile all implementations
2. Set up network namespaces (ns_server, ns_client)
3. Run experiments across all message sizes and thread counts
4. Collect perf profiling data
5. Output results to `MT25076_Part_B_results.csv`

## Generating Plots

```bash
python3 MT25076_Part_D_plots.py
```

Generates:
- `MT25076_Part_D_throughput_vs_msgsize.png`
- `MT25076_Part_D_latency_vs_threads.png`
- `MT25076_Part_D_cache_misses.png`
- `MT25076_Part_D_cycles_per_byte.png`

**Note**: Update hardcoded values in the script with actual measurements before generating final plots.

## Technical Details

### Two-Copy Mechanism (A1)
Data path: User Buffer → Kernel Socket Buffer → NIC DMA
- First copy: `send()` copies from user space to kernel socket buffer
- Second copy: Kernel copies from socket buffer to NIC for transmission

### One-Copy Mechanism (A2)
Uses `sendmsg()` with iovec for scatter-gather I/O:
- Eliminates user-space buffer concatenation
- Multiple buffers (8 message fields) sent directly without intermediate copy
- Kernel still copies to socket buffer

### Zero-Copy Mechanism (A3)
Uses `MSG_ZEROCOPY` flag:
- Kernel pins user pages instead of copying
- DMA directly from user buffer to NIC
- Requires polling error queue for completion notifications
- Adds overhead for small messages (page pinning cost)

## System Requirements

- Linux kernel 4.14+ (for MSG_ZEROCOPY support)
- GCC with pthread support
- perf tools (for profiling)
- Python 3 with matplotlib and numpy (for plotting)
- Root/sudo access (for network namespaces)

## Author
Roll Number: MT25076
