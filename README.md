# MT25076 – PA02: Experimental Analysis of Network I/O Data Movement

> **Roll Number:** MT25076  
> **Course:** Graduate Systems  
> **Assignment:** PA02 – Analysis of Network I/O Primitives  

---

## 1. Objective

The objective of this assignment is to experimentally study the cost of data movement in network I/O by implementing and comparing:

1. Standard two-copy socket communication  
2. One-copy optimized socket communication  
3. Zero-copy socket communication  

The study focuses on micro-architectural effects such as CPU cycles, cache behavior, context switches, throughput, and latency. All experiments are conducted using multithreaded TCP client–server programs in C and profiled using Linux `perf`.

---

## 2. Implementation Overview

Three versions of a TCP-based client–server application are implemented.

### Common Properties (All Versions)

**Server**
- Accepts multiple concurrent clients  
- Uses one thread per client  
- Transfers fixed-size messages repeatedly  
- Sends a message consisting of 8 dynamically allocated string fields  
- Each field is heap-allocated using `malloc()`  

**Client**
- Connects to the server  
- Receives data continuously for a fixed duration  
- Controls experiment termination and throughput measurement  

**Runtime Parameters**
- Message size  
- Number of threads  
- Experiment duration  

All parameters are configurable at runtime via command-line arguments.

---

## 3. Directory Structure

```
GRS_PA02/
│
├── Makefile
├── MT25076_Part_A_common.h
│
├── MT25076_Part_A1_Server.c
├── MT25076_Part_A1_Client.c
│
├── MT25076_Part_A2_Server.c
├── MT25076_Part_A2_Client.c
│
├── MT25076_Part_A3_Server.c
├── MT25076_Part_A3_Client.c
│
├── MT25076_Part_C_run_experiments.sh
├── MT25076_Part_D_plots.py
│
├── MT25076_Part_B_app_results.csv
├── MT25076_Part_B_perf_server_sender.csv
├── MT25076_Part_B_perf_client_sender.csv
│
├── MT25076_Report.pdf
└── README.md
```

---

## 4. Part A – Socket Implementations

### A1. Two-Copy Implementation (Baseline)

- Uses `send()` / `recv()`  
- The 8 message fields are serialized into a single contiguous buffer  
- Copies involved:
  1. User-space aggregation copy during serialization  
  2. Kernel copy into the socket buffer  

This version serves as the baseline for comparison.

---

### A2. One-Copy Implementation

- Uses `sendmsg()` with `struct iovec`  
- Sends the 8 heap-allocated fields directly using scatter–gather I/O  
- Eliminates the user-space aggregation copy  
- Kernel copy into socket buffer still exists  

---

### A3. Zero-Copy Implementation

- Uses `sendmsg()` with the `MSG_ZEROCOPY` flag  
- Kernel pins user pages and transfers data via DMA  
- No payload copy into kernel socket buffers  
- Completion is handled via the socket error queue  

---

## 5. Part B – Profiling and Measurement

### Profiling Location

All micro-architectural profiling is performed on the server side. The server performs all send-side operations, where data copies, page pinning, DMA mapping, and cache effects occur.

### Metrics Collected (using `perf stat`)
- CPU cycles  
- Instructions  
- L1 data cache misses  
- Last Level Cache (LLC) misses  
- Context switches  

### Experimental Coverage
- Message sizes: 1K, 4K, 16K, 64K  
- Thread counts: 1, 2, 4, 8  

---

## 6. Part C – Automated Experiment Script

The script `MT25076_Part_C_run_experiments.sh`:
1. Cleans and recompiles all implementations  
2. Iterates over message sizes and thread counts  
3. Runs the server under `perf stat`  
4. Launches the client workload  
5. Collects results in CSV format  

The script runs fully automatically with no manual intervention.

---

## 7. Part D – Plotting

Plots are generated using matplotlib only.

**Important constraints**
- CSV files are NOT used as input to the plotting script  
- All plot values are hardcoded inside the Python file  
- The plotting script can be executed directly during the demo  

**Plots generated**
1. Throughput vs Message Size  
2. Latency vs Thread Count  
3. Cache Misses vs Message Size  
4. CPU Cycles per Byte Transferred  

Script used: `MT25076_Part_D_plots.py`

---

## 8. Build and Run Instructions

### Build
```
make clean
make
```

### Executable
```
sudo chmod +x MT25076_Part_C_run_experiments.sh
```

### Run Experiments
```
sudo ./MT25076_Part_C_run_experiments.sh
```

### Generate Plots
```
python3 MT25076_Part_D_plots.py
```

**End of README**
