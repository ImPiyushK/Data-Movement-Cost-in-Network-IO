# MT25076 – GRS PA02: Analysis of Network I/O Primitives

> **Roll Number:** MT25076\
> **Course:** Graduate Systems (CSE638)\
> **Assignment:** PA02 – Analysis of Network I/O primitives using `perf`

---

## 1. Overview

This assignment experimentally studies the **cost of data movement in network I/O** by implementing and comparing three TCP-based client–server communication mechanisms:

1. **Two-Copy Socket Communication (Baseline)** – using `send()` / `recv()`
2. **One-Copy Optimized Communication** – using `sendmsg()` with `iovec`
3. **Zero-Copy Communication** – using `sendmsg()` with `MSG_ZEROCOPY`

All implementations are **multithreaded**, parameterized at runtime, and profiled using the Linux `perf` tool to analyze CPU cycles, cache behavior, and context switches.

---

## 2. Directory & File Structure

All files follow the **mandatory naming convention** prescribed in the assignment.

```
GRS_PA02/
│
├── Makefile
├── MT25076_Part_A_common.h
│
├── MT25076_Part_A1_Client.c
├── MT25076_Part_A1_Server.c
│
├── MT25076_Part_A2_Client.c
├── MT25076_Part_A2_Server.c
│
├── MT25076_Part_A3_Client.c
├── MT25076_Part_A3_Server.c
│
├── MT25076_Part_C_run_experiments.sh
├── MT25076_Part_D_plots.py
│
├── MT25076_Part_B_results_*.csv
├── MT25076_Report.pdf
└── README.md
```

⚠️ **Note:** No binary files or plot images are included, as per assignment rules.

---

## 3. Part A – Socket Implementations

### A1. Two-Copy (Baseline)

- Uses `send()` / `recv()`
- Data copied:
  1. User buffer → kernel socket buffer
  2. Kernel socket buffer → NIC (DMA)
- Serves as baseline for comparison

### A2. One-Copy Optimization

- Uses `sendmsg()` with `struct iovec`
- Eliminates **one user-space aggregation copy**
- Kernel → NIC DMA copy still exists

### A3. Zero-Copy Implementation

- Uses `sendmsg()` with `MSG_ZEROCOPY`
- Kernel directly references user pages
- Data is sent via DMA without copying payload into kernel buffers
- Completion handled via error queue

Each server:

- Accepts multiple concurrent clients
- Uses **one thread per client**
- Sends fixed-size messages composed of **8 heap-allocated string fields**

Each client:

- Sends data continuously for a fixed duration

Message size and thread count are **runtime parameters**.

---

## 4. Part B – Profiling & Measurement

### Profiling Location

📌 **All profiling is done on the SERVER side**.

This is because:

- The server performs the critical send-side operations (`send`, `sendmsg`, `MSG_ZEROCOPY`)
- Data-copy, DMA mapping, page pinning, and cache effects occur on the sender
- Profiling the client would not capture zero-copy benefits accurately

### Metrics Collected (using `perf stat`)

- CPU cycles
- L1 data cache misses
- Last Level Cache (LLC) misses
- Context switches
- Instructions

### Experimental Coverage

- **Message sizes:** 1K, 4K, 16K, 64K
- **Thread counts:** 1, 2, 4, 8

---

## 5. Part C – Automated Experiment Script

`MT25076_Part_C_run_experiments.sh` performs the following automatically:

1. Cleans and recompiles all implementations
2. Iterates over message sizes and thread counts
3. Runs server under `perf stat`
4. Launches client workload
5. Collects results in CSV format

✔️ No manual intervention is required once the script starts.

---

## 6. Part D – Plotting

Plots are generated using **matplotlib only**, as required.

- CSV files are **NOT** used as input
- All values are **hardcoded** inside the Python script
- Plots generated:
  - Throughput vs Message Size
  - Latency vs Thread Count
  - Cache Misses vs Message Size
  - CPU Cycles per Byte Transferred

The script used:

- `MT25076_Part_D_plots.py`

Plots are included **only in the report**, not in the submission zip.

---

## 7. AI Usage Declaration

AI tools (ChatGPT) were used **in a limited and transparent manner**, as permitted.

### AI-Assisted Components

- Initial socket programming skeletons (client/server structure)
- Guidance on correct usage of `sendmsg()` and `MSG_ZEROCOPY`
- Help in structuring the experiment automation script
- Assistance in interpreting `perf` metrics and expected trends

### Non-AI Components

- Final code logic and debugging
- All experimental runs and data collection
- Analysis, reasoning, and interpretation of results
- Plot data selection and report writing

### Example Prompts Used

- "Explain the difference between two-copy, one-copy, and zero-copy socket communication in Linux"
- "How does MSG\_ZEROCOPY work internally in the Linux kernel?"
- "What perf counters best reflect cache behavior in network I/O?"

All AI-generated guidance was **reviewed, understood, and manually adapted**.

---

## 8. Build & Run Instructions

### Build

```bash
make clean
make
```

### Run Experiments

```bash
sudo bash MT25076_Part_C_run_experiments.sh
```

### Generate Plots

```bash
python3 MT25076_Part_D_plots.py
```

---

## 9. System Configuration

- OS: Linux
- CPU: x86\_64 (details mentioned in report)
- Network: Local host / veth-based testing

---

## 10. GitHub Repository

🔗 **Public Repository URL:** (Added in the report as required)

---

**End of README**
