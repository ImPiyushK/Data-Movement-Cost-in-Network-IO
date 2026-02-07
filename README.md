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

All implementations use a **multithreaded TCP client–server model**, where the server sends fixed-size messages repeatedly to multiple concurrent clients. Experiments are conducted over **Linux network namespaces** connected via a **veth pair** on an Intel i7-12700 system.

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
| A1 | `send()` / `recv()` | Two copies (user-space serialization + user → kernel) |
| A2 | `sendmsg()` + `iovec` | One copy (kernel only; user-space serialization eliminated) |
| A3 | `sendmsg(MSG_ZEROCOPY)` | Zero data copies (kernel pins pages; DMA-based transfer) |

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
- Runs experiments across multiple message sizes (1K, 4K, 16K, 64K) and thread counts (1, 2, 4, 8)
- Uses `perf stat` for profiling
- Stores results in CSV format with parameter-encoded filenames
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

### Throughput
- Two-copy consistently achieves the **highest throughput** across all message sizes and thread counts, followed closely by one-copy, with zero-copy trailing.
- Throughput increases with message size for all implementations as fixed per-message overheads are amortized over larger payloads.
- Zero-copy throughput improves with message size but **does not surpass** two-copy or one-copy at any tested configuration, due to page pinning and completion notification overhead on the veth virtual interface (no real hardware DMA).

### Latency
- Latency behavior is **non-monotonic and irregular** across thread counts and message sizes.
- For 1K messages, two-copy latency spikes sharply at 8 threads (~500 µs), while zero-copy latency *decreases* to ~50 µs.
- For 64K messages, two-copy latency *drops* from ~275 µs (1 thread) to ~110 µs (8 threads).
- These patterns are attributable to interactions between per-message vs. aggregate latency measurement, kernel TCP batching/coalescing, Intel P-core/E-core scheduling heterogeneity, and measurement noise over short experiment durations.

### CPU Cycles per Byte
- All implementations show a clear downward trend as message size increases, reflecting amortization of system call overhead.
- Zero-copy consistently incurs the **highest cycles per byte**, especially at small message sizes (~25–35 cycles/byte at 1K), due to page pinning, DMA mapping, and completion notification overhead.
- Two-copy and one-copy track closely together (~7–17 cycles/byte at 1K) and converge with zero-copy below ~1 cycle/byte at 64K.
- The gap between zero-copy and the other implementations **widens as thread count increases**, indicating poor scalability of zero-copy kernel operations under concurrency.

### Cache Misses
- Cache miss behavior is **highly irregular** across implementations and configurations, with no single implementation consistently showing the lowest misses.
- At 1 thread, zero-copy shows the highest misses at 1K but the lowest at 64K. At 2 threads, one-copy has the highest misses across most message sizes. At 8 threads, zero-copy tends to have the lowest misses.
- The irregular patterns are likely attributable to measurement noise from short experiment durations, non-deterministic kernel scheduling, and the interplay between data copy cache pollution and metadata-driven cache activity in zero-copy.
- A general trend emerges at larger message sizes and higher thread counts: zero-copy tends to show fewer cache misses, consistent with eliminating bulk memory copies that pollute the LLC.

### Key Takeaways
- On this testbed (veth pair, no real NIC), **two-copy with optimized `memcpy()` outperforms** one-copy and zero-copy in throughput.
- Zero-copy's benefits are **not realized** without real hardware DMA; its kernel-level overheads dominate on virtual interfaces.
- Latency and cache behavior are complex, non-linear, and heavily influenced by thread scheduling, kernel batching, and CPU microarchitecture.

---

## Conclusion

This project demonstrates that **data movement cost is workload- and platform-dependent**. While reducing memory copies can improve CPU efficiency and cache behavior in theory, the benefits depend heavily on the underlying hardware and network interface.

On this testbed (network namespaces with veth pair), two-copy communication achieved the highest throughput due to optimized `memcpy()` implementations and cache-friendly contiguous buffer layouts. Zero-copy incurred the highest per-byte CPU cost because its page pinning and completion notification overheads were not offset by real hardware DMA savings. Latency patterns were non-monotonic, reflecting complex interactions between thread scheduling, kernel TCP batching, and CPU core heterogeneity.

These results underscore that **zero-copy techniques are most beneficial when paired with real hardware DMA, large transfer sizes, and workloads where CPU-based copies are the true bottleneck**.

---

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
- Help explain unexpected results (e.g., non-monotonic latency, irregular cache miss patterns)
- Assist with structuring and formatting the README and LaTeX report
