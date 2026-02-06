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
