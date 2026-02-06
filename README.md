# CSE638 PA02: Data Movement Cost in Network I/O  
**Roll Number:** MT25076  
**Course:** CSE638 – Graduate Systems  

---

## Overview

This assignment experimentally studies the **cost of data movement in network I/O** by implementing and comparing three socket communication mechanisms:

1. **Two-Copy Communication (Baseline)** using `send()` / `recv()`
2. **One-Copy Communication** using `sendmsg()` with scatter–gather I/O
3. **Zero-Copy Communication** using `sendmsg()` with `MSG_ZEROCOPY`

The goal is to quantify the impact of these mechanisms on **throughput, latency, CPU cycles, cache behavior, and scalability** under varying **message sizes** and **thread counts**.

All implementations use a **multithreaded TCP client–server model**, where the server sends fixed-size messages repeatedly to multiple concurrent clients.

---

## Implementation Summary

### Common Design (All Versions)
- **Server**
  - Accepts multiple concurrent clients
  - Uses **one thread per client**
  - Sends **fixed-size messages repeatedly**
  - Message structure consists of **8 dynamically allocated string fields**
- **Client**
  - Connects to server
  - Receives data continuously for a fixed duration
- **Runtime Parameters**
  - Message size
  - Thread count
  - Experiment duration

### Implementation Variants

| Version | Mechanism | Copies Involved |
|------|---------|----------------|
| A1 | `send()` / `recv()` | Two copies (user → kernel → user) |
| A2 | `sendmsg()` + `iovec` | One copy (kernel only) |
| A3 | `sendmsg(MSG_ZEROCOPY)` | Zero data copies |

---

## Build Instructions

```bash
# Compile all implementations
make all

# Clean build artifacts
make clean
```


---

## Automated Experiments (Part C)

```bash
chmod +x MT25076_Part_C_run_experiments.sh
./MT25076_Part_C_run_experiments.sh
```

The script:
- Compiles all implementations
- Runs experiments across multiple message sizes and thread counts
- Uses `perf stat` for profiling
- Stores results in CSV format
- Requires no manual intervention

---

## Profiling & Measurement (Part B)

### Metrics Collected

| Metric | Tool | Side |
|-----|-----|-----|
| Throughput (Gbps) | Application-level | Client |
| Latency (µs) | Application-level | Client |
| CPU cycles | `perf stat` | Server |
| Cache misses (L1, LLC) | `perf stat` | Server |
| Context switches | `perf stat` | Server |

All micro-architectural measurements are performed on the **server side**.

---

## Analysis Summary (Part D)

- Two-copy incurs the highest cache misses due to repeated memory copies.
- One-copy reduces cache pressure by eliminating user-space aggregation.
- Zero-copy performs worst for small messages due to page pinning overhead, but best for large messages due to DMA-based transfer.
- Throughput increases with message size across all implementations.
- Zero-copy benefits appear only when overheads are amortized.
- Increasing thread count leads to cache contention and higher latency.


---

## Conclusion

This project demonstrates that **data movement dominates network performance** and that reducing memory copies can significantly improve CPU efficiency and cache behavior, but only under appropriate workload conditions.

## AI Usage Declaration

This project was developed with the assistance of Large Language Model (LLM) tools.  
In compliance with the course AI usage policy, the following section explicitly
documents **where and how AI tools were used**, including representative prompts.
All AI-assisted outputs were reviewed, tested, and validated by the author.

---

### Components Where AI Tools Were Used

#### 1. Code Development and Implementation
AI tools were used to:
- Generate initial C socket client–server code skeletons
- Suggest correct usage of `send()`, `sendmsg()`, `iovec`, and `MSG_ZEROCOPY`
- Assist with POSIX thread (`pthread`) usage and synchronization
- Help debug compilation errors, runtime crashes, and incorrect behavior
- Refactor code to meet assignment constraints and improve clarity

---

#### 2. Experimental Design and Parameter Selection
AI tools were used to:
- Suggest reasonable message sizes and thread counts
- Help design experiments aligned with assignment requirements
- Identify relevant metrics for evaluating network I/O performance


---

#### 3. Automation, Profiling, and Data Collection
AI tools were used to:
- Assist in writing bash scripts for automated experiment execution
- Suggest correct usage of `perf stat` and relevant hardware counters
- Help parse profiling output into structured CSV files


---

#### 4. Plotting and Visualization
AI tools were used to:
- Generate Python/matplotlib scripts for plotting CSV data
- Suggest plot layouts, axis labels, legends, and scales

---

#### 5. Analysis and Documentation
AI tools were used to:
- Assist in interpreting performance trends and anomalies
- Help explain unexpected results (e.g., zero-copy overhead for small messages)
- Assist with structuring and formatting the README and LaTeX report
