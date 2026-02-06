# MT25076 - Part D: Plotting Script
# Roll Number: MT25076
#
# This script generates plots for the network I/O experiments.
# Values are hardcoded as per assignment requirements.

import matplotlib.pyplot as plt
import numpy as np

# Set style for better aesthetics
plt.rcParams['figure.figsize'] = (12, 7)
plt.rcParams['font.size'] = 12
plt.rcParams['axes.labelsize'] = 14
plt.rcParams['axes.titlesize'] = 16
plt.rcParams['legend.fontsize'] = 11

# ============================================================================
# SYSTEM CONFIGURATION (mention in plots)
# ============================================================================
SYSTEM_CONFIG = """
System: Linux (Ubuntu 22.04), Network Namespace (veth pair)
CPU: 12th Gen Intel(R) Core(TM) i7-12700
RAM: 16G DDR4 system memory
"""


# ============================================================================
# HARDCODED DATA FROM CSV FILES
# ============================================================================

MESSAGE_SIZES = ['1K', '4K', '16K', '64K']
MESSAGE_SIZES_BYTES = [1024, 4096, 16384, 65536]
THREAD_COUNTS = [1, 2, 4, 8]

# ============================================================================
# THROUGHPUT DATA (Gbps)
# Format: [1K, 4K, 16K, 64K] for each thread count
# ============================================================================

THROUGHPUT_TWO_COPY = {
    1: [4.615807, 16.232727, 46.174722, 75.652572],
    2: [8.855352, 29.990700, 94.539990, 146.207362],
    4: [17.521864, 57.860303, 174.731369, 276.608973],
    8: [28.292795, 90.963403, 251.375723, 425.910446]
}

THROUGHPUT_ONE_COPY = {
    1: [4.172880, 13.001204, 44.540369, 74.248405],
    2: [8.349704, 25.409883, 83.164137, 142.941398],
    4: [16.287560, 47.809165, 161.167867, 276.784096],
    8: [24.270321, 75.473388, 232.874525, 402.620688]
}

THROUGHPUT_ZERO_COPY = {
    1: [2.248523, 8.553750, 27.380311, 53.251939],
    2: [4.454806, 16.817311, 53.300906, 101.629063],
    4: [8.675462, 32.499410, 101.887663, 191.585778],
    8: [12.698369, 48.609677, 158.049715, 289.060675]
}

# ============================================================================
# LATENCY DATA (µs)
# Format: [threads=1, threads=2, threads=4, threads=8]
# ============================================================================

LATENCY_DATA = {
    '1K': {
        'two_copy': [120.50, 95.875, 63.815, 6609.06],
        'one_copy': [51.25, 115.00, 83.88, 6513.59],
        'zero_copy': [87.75, 52.125, 125.37, 59.875]
    },
    '4K': {
        'two_copy': [49.25, 99.75, 62.25, 39.75],
        'one_copy': [130.50, 103.00, 92.50, 68.50],
        'zero_copy': [112.50, 115.00, 145.625, 30.155]
    },
    '16K': {
        'two_copy': [56.00, 64.625, 112.625, 78.375],
        'one_copy': [155.50, 59.25, 76.31, 164.25],
        'zero_copy': [77.00, 73.875, 63.44, 272.56]
    },
    '64K': {
        'two_copy': [278.75, 80.125, 164.185, 110.565],
        'one_copy': [166.25, 206.875, 174.25, 198.875],
        'zero_copy': [262.00, 112.375, 139.31, 96.065]
    }
}

# ============================================================================
# CACHE MISSES DATA (server-side perf)
# Format: [1K, 4K, 16K, 64K]
# ============================================================================

CACHE_MISSES_TWO_COPY = {
    1: [62106, 106494, 117877, 127023],
    2: [3340878, 10338746, 11993654, 44583047],
    4: [56584051, 2963075, 18858864, 2968711],
    8: [3496979, 30437211, 16182762, 4427568]
}

CACHE_MISSES_ONE_COPY = {
    1: [79091, 5259144, 141860, 75557],
    2: [157541, 107861, 15280041, 77249213],
    4: [96489, 14383645, 24748060, 49175101],
    8: [985950, 3295832, 7488676, 17753189]
}

CACHE_MISSES_ZERO_COPY = {
    1: [4463918, 137575, 39379, 73638],
    2: [10799626, 11721832, 11739668, 6279356],
    4: [3794792, 26110613, 1772530, 4291612],
    8: [2079335, 773766, 1248310, 3887099]
}

# ============================================================================
# CPU CYCLES PER BYTE
# Format: [1K, 4K, 16K, 64K]
# ============================================================================

CYCLES_PER_BYTE_TWO_COPY = {
    1: [7.37, 2.11, 0.74, 0.60],
    2: [9.85, 3.58, 1.13, 0.80],
    4: [10.31, 3.14, 1.19, 0.79],
    8: [15.42, 4.87, 1.78, 1.06]
}

CYCLES_PER_BYTE_ONE_COPY = {
    1: [7.89, 3.76, 0.76, 0.46],
    2: [9.34, 2.65, 1.40, 0.73],
    4: [8.03, 3.56, 1.35, 0.75],
    8: [16.90, 5.93, 1.91, 1.11]
}

CYCLES_PER_BYTE_ZERO_COPY = {
    1: [24.96, 3.95, 1.24, 0.63],
    2: [25.99, 5.47, 1.99, 1.11],
    4: [26.44, 6.70, 2.26, 1.16],
    8: [35.23, 9.19, 2.84, 1.35]
}

# ============================================================================
# PLOT 1: Throughput vs Message Size
# ============================================================================
def plot_throughput_vs_message_size():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    colors = {'two': '#e74c3c', 'one': '#3498db', 'zero': '#2ecc71'}

    for i, t in enumerate(THREAD_COUNTS):
        ax = axes[i]
        x = np.arange(len(MESSAGE_SIZES))
        w = 0.25

        ax.bar(x - w, THROUGHPUT_TWO_COPY[t], w, label='Two-Copy', color=colors['two'])
        ax.bar(x, THROUGHPUT_ONE_COPY[t], w, label='One-Copy', color=colors['one'])
        ax.bar(x + w, THROUGHPUT_ZERO_COPY[t], w, label='Zero-Copy', color=colors['zero'])

        ax.set_xticks(x)
        ax.set_xticklabels(MESSAGE_SIZES)
        ax.set_xlabel('Message Size')
        ax.set_ylabel('Throughput (Gbps)')
        ax.set_title(f'{t} Thread(s)')
        ax.legend()
        ax.grid(axis='y', alpha=0.3)

    fig.suptitle(f'Throughput vs Message Size\n{SYSTEM_CONFIG}', y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_throughput_vs_msgsize.png', dpi=150)
    plt.close()

# ============================================================================
# PLOT 2: Latency vs Thread Count
# ============================================================================
def plot_latency_vs_threads():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    colors = {'two_copy': '#e74c3c', 'one_copy': '#3498db', 'zero_copy': '#2ecc71'}

    for i, msg in enumerate(MESSAGE_SIZES):
        ax = axes[i]
        for impl, vals in LATENCY_DATA[msg].items():
            capped = [min(v, 500) for v in vals]
            ax.plot(THREAD_COUNTS, capped, marker='o', label=impl.replace('_', '-').title())

        ax.set_xlabel('Number of Threads')
        ax.set_ylabel('Latency (µs)')
        ax.set_title(f'Message Size: {msg}')
        ax.set_xticks(THREAD_COUNTS)
        ax.legend()
        ax.grid(True, alpha=0.3)

    fig.suptitle(f'Latency vs Thread Count\n{SYSTEM_CONFIG}', y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_latency_vs_threads.png', dpi=150)
    plt.close()

# ============================================================================
# PLOT 3: Cache Misses vs Message Size
# ============================================================================
def plot_cache_misses():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()

    for i, t in enumerate(THREAD_COUNTS):
        ax = axes[i]
        x = np.arange(len(MESSAGE_SIZES))
        w = 0.25

        ax.bar(x - w, CACHE_MISSES_TWO_COPY[t], w, label='Two-Copy')
        ax.bar(x, CACHE_MISSES_ONE_COPY[t], w, label='One-Copy')
        ax.bar(x + w, CACHE_MISSES_ZERO_COPY[t], w, label='Zero-Copy')

        ax.set_xticks(x)
        ax.set_xticklabels(MESSAGE_SIZES)
        ax.set_yscale('log')
        ax.set_xlabel('Message Size')
        ax.set_ylabel('Cache Misses')
        ax.set_title(f'{t} Thread(s)')
        ax.legend()
        ax.grid(axis='y', alpha=0.3)

    fig.suptitle(f'Cache Misses vs Message Size\n{SYSTEM_CONFIG}', y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cache_misses.png', dpi=150)
    plt.close()

# ============================================================================
# PLOT 4: CPU Cycles per Byte
# ============================================================================
def plot_cycles_per_byte():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()

    for i, t in enumerate(THREAD_COUNTS):
        ax = axes[i]
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_TWO_COPY[t], marker='o', label='Two-Copy')
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ONE_COPY[t], marker='s', label='One-Copy')
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ZERO_COPY[t], marker='^', label='Zero-Copy')

        ax.set_xlabel('Message Size')
        ax.set_ylabel('CPU Cycles per Byte')
        ax.set_title(f'{t} Thread(s)')
        ax.legend()
        ax.grid(True, alpha=0.3)

    fig.suptitle(f'CPU Cycles per Byte Transferred\n{SYSTEM_CONFIG}', y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cycles_per_byte.png', dpi=150)
    plt.close()

# ============================================================================
# MAIN
# ============================================================================
if __name__ == "__main__":
    print("Generating plots for Network I/O Performance Analysis...")
    plot_throughput_vs_message_size()
    plot_latency_vs_threads()
    plot_cache_misses()
    plot_cycles_per_byte()
    print("All plots generated successfully.")
