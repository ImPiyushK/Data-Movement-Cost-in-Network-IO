# MT25076 - Part D: Plotting Script
# Roll Number: MT25076
#
# This script generates plots for the network I/O experiments.
# Values are hardcoded as per assignment requirements.
# Run this script to generate plots for the report.

import matplotlib.pyplot as plt
import numpy as np

# Set style for better aesthetics
plt.style.use('seaborn-v0_8-whitegrid')
plt.rcParams['figure.figsize'] = (10, 6)
plt.rcParams['font.size'] = 12
plt.rcParams['axes.labelsize'] = 14
plt.rcParams['axes.titlesize'] = 16
plt.rcParams['legend.fontsize'] = 11

# System configuration (update this based on your system)
SYSTEM_CONFIG = """
System Configuration:
- CPU: Intel Core (update with your CPU)
- RAM: 16GB (update with your RAM)
- OS: Linux (update with your kernel version)
- Network: veth pair (10 Gbps virtual)
"""

# ============================================================================
# HARDCODED DATA - Replace with actual measurements from experiments
# ============================================================================

# Message sizes in bytes (for x-axis)
MESSAGE_SIZES = ['1K', '4K', '16K', '64K', '256K', '1M']
MESSAGE_SIZES_BYTES = [1024, 4096, 16384, 65536, 262144, 1048576]

# Thread counts
THREAD_COUNTS = [1, 2, 4, 8]

# Throughput data (Gbps) - [two_copy, one_copy, zero_copy] for each message size
# Format: throughput[impl_type][msg_size_index]
THROUGHPUT_TWO_COPY = [0.85, 1.42, 2.15, 3.21, 4.05, 4.52]
THROUGHPUT_ONE_COPY = [0.92, 1.58, 2.45, 3.68, 4.82, 5.21]
THROUGHPUT_ZERO_COPY = [0.78, 1.35, 2.68, 4.12, 5.45, 6.18]

# Latency data (µs) for different thread counts with 16K message size
# Format: latency[impl_type][thread_count_index]
LATENCY_TWO_COPY = [45.2, 52.8, 68.5, 95.2]
LATENCY_ONE_COPY = [38.5, 44.2, 58.8, 82.5]
LATENCY_ZERO_COPY = [42.8, 48.5, 62.2, 88.5]

# Cache misses (L1) for each message size with 4 threads
# Format: l1_misses[impl_type][msg_size_index]
L1_MISSES_TWO_COPY = [125000, 285000, 520000, 985000, 1850000, 3250000]
L1_MISSES_ONE_COPY = [98000, 215000, 385000, 725000, 1420000, 2580000]
L1_MISSES_ZERO_COPY = [85000, 178000, 312000, 585000, 1150000, 2150000]

# Cache misses (LLC) for each message size with 4 threads
LLC_MISSES_TWO_COPY = [8500, 18500, 42000, 95000, 185000, 325000]
LLC_MISSES_ONE_COPY = [6200, 14200, 32500, 72000, 145000, 265000]
LLC_MISSES_ZERO_COPY = [4800, 11500, 25800, 58000, 118000, 218000]

# CPU cycles per byte transferred for each message size
CYCLES_PER_BYTE_TWO_COPY = [285.5, 168.2, 112.5, 78.5, 52.8, 38.2]
CYCLES_PER_BYTE_ONE_COPY = [245.2, 142.5, 92.8, 62.5, 42.5, 31.5]
CYCLES_PER_BYTE_ZERO_COPY = [312.8, 185.2, 98.5, 58.2, 38.5, 28.5]

# ============================================================================
# PLOT 1: Throughput vs Message Size
# ============================================================================
def plot_throughput_vs_message_size():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    x = np.arange(len(MESSAGE_SIZES))
    width = 0.25
    
    bars1 = ax.bar(x - width, THROUGHPUT_TWO_COPY, width, label='Two-Copy (send/recv)', 
                   color='#e74c3c', edgecolor='black', linewidth=0.5)
    bars2 = ax.bar(x, THROUGHPUT_ONE_COPY, width, label='One-Copy (sendmsg/iovec)', 
                   color='#3498db', edgecolor='black', linewidth=0.5)
    bars3 = ax.bar(x + width, THROUGHPUT_ZERO_COPY, width, label='Zero-Copy (MSG_ZEROCOPY)', 
                   color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax.set_xlabel('Message Size')
    ax.set_ylabel('Throughput (Gbps)')
    ax.set_title('Throughput vs Message Size\n(4 threads, 5 second duration)')
    ax.set_xticks(x)
    ax.set_xticklabels(MESSAGE_SIZES)
    ax.legend(loc='upper left')
    ax.set_ylim(0, max(max(THROUGHPUT_TWO_COPY), max(THROUGHPUT_ONE_COPY), max(THROUGHPUT_ZERO_COPY)) * 1.15)
    
    # Add value labels on bars
    for bars in [bars1, bars2, bars3]:
        for bar in bars:
            height = bar.get_height()
            ax.annotate(f'{height:.2f}',
                       xy=(bar.get_x() + bar.get_width() / 2, height),
                       xytext=(0, 3),
                       textcoords="offset points",
                       ha='center', va='bottom', fontsize=8)
    
    plt.figtext(0.99, 0.01, SYSTEM_CONFIG, ha='right', fontsize=8, 
                style='italic', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_throughput_vs_msgsize.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_throughput_vs_msgsize.png")

# ============================================================================
# PLOT 2: Latency vs Thread Count
# ============================================================================
def plot_latency_vs_threads():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(THREAD_COUNTS, LATENCY_TWO_COPY, 'o-', label='Two-Copy (send/recv)', 
            color='#e74c3c', linewidth=2, markersize=8)
    ax.plot(THREAD_COUNTS, LATENCY_ONE_COPY, 's-', label='One-Copy (sendmsg/iovec)', 
            color='#3498db', linewidth=2, markersize=8)
    ax.plot(THREAD_COUNTS, LATENCY_ZERO_COPY, '^-', label='Zero-Copy (MSG_ZEROCOPY)', 
            color='#2ecc71', linewidth=2, markersize=8)
    
    ax.set_xlabel('Number of Threads')
    ax.set_ylabel('Latency (µs)')
    ax.set_title('Latency vs Thread Count\n(16K message size, 5 second duration)')
    ax.set_xticks(THREAD_COUNTS)
    ax.legend(loc='upper left')
    ax.grid(True, alpha=0.3)
    
    # Add value annotations
    for i, (tc, l1, l2, l3) in enumerate(zip(THREAD_COUNTS, LATENCY_TWO_COPY, LATENCY_ONE_COPY, LATENCY_ZERO_COPY)):
        ax.annotate(f'{l1:.1f}', (tc, l1), textcoords="offset points", xytext=(0,10), ha='center', fontsize=8)
        ax.annotate(f'{l2:.1f}', (tc, l2), textcoords="offset points", xytext=(0,10), ha='center', fontsize=8)
        ax.annotate(f'{l3:.1f}', (tc, l3), textcoords="offset points", xytext=(0,-15), ha='center', fontsize=8)
    
    plt.figtext(0.99, 0.01, SYSTEM_CONFIG, ha='right', fontsize=8, 
                style='italic', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_latency_vs_threads.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_latency_vs_threads.png")

# ============================================================================
# PLOT 3: Cache Misses vs Message Size
# ============================================================================
def plot_cache_misses():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    
    x = np.arange(len(MESSAGE_SIZES))
    width = 0.25
    
    # L1 Cache Misses
    ax1.bar(x - width, np.array(L1_MISSES_TWO_COPY)/1000, width, label='Two-Copy', 
            color='#e74c3c', edgecolor='black', linewidth=0.5)
    ax1.bar(x, np.array(L1_MISSES_ONE_COPY)/1000, width, label='One-Copy', 
            color='#3498db', edgecolor='black', linewidth=0.5)
    ax1.bar(x + width, np.array(L1_MISSES_ZERO_COPY)/1000, width, label='Zero-Copy', 
            color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax1.set_xlabel('Message Size')
    ax1.set_ylabel('L1 Cache Misses (thousands)')
    ax1.set_title('L1 Data Cache Misses vs Message Size')
    ax1.set_xticks(x)
    ax1.set_xticklabels(MESSAGE_SIZES)
    ax1.legend(loc='upper left')
    ax1.set_yscale('log')
    
    # LLC Cache Misses
    ax2.bar(x - width, np.array(LLC_MISSES_TWO_COPY)/1000, width, label='Two-Copy', 
            color='#e74c3c', edgecolor='black', linewidth=0.5)
    ax2.bar(x, np.array(LLC_MISSES_ONE_COPY)/1000, width, label='One-Copy', 
            color='#3498db', edgecolor='black', linewidth=0.5)
    ax2.bar(x + width, np.array(LLC_MISSES_ZERO_COPY)/1000, width, label='Zero-Copy', 
            color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax2.set_xlabel('Message Size')
    ax2.set_ylabel('LLC Misses (thousands)')
    ax2.set_title('Last Level Cache Misses vs Message Size')
    ax2.set_xticks(x)
    ax2.set_xticklabels(MESSAGE_SIZES)
    ax2.legend(loc='upper left')
    ax2.set_yscale('log')
    
    plt.suptitle('Cache Misses vs Message Size (4 threads)', fontsize=14, y=1.02)
    
    plt.figtext(0.99, 0.01, SYSTEM_CONFIG, ha='right', fontsize=8, 
                style='italic', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cache_misses.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_cache_misses.png")

# ============================================================================
# PLOT 4: CPU Cycles per Byte Transferred
# ============================================================================
def plot_cycles_per_byte():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_TWO_COPY, 'o-', label='Two-Copy (send/recv)', 
            color='#e74c3c', linewidth=2, markersize=8)
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ONE_COPY, 's-', label='One-Copy (sendmsg/iovec)', 
            color='#3498db', linewidth=2, markersize=8)
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ZERO_COPY, '^-', label='Zero-Copy (MSG_ZEROCOPY)', 
            color='#2ecc71', linewidth=2, markersize=8)
    
    ax.set_xlabel('Message Size')
    ax.set_ylabel('CPU Cycles per Byte')
    ax.set_title('CPU Cycles per Byte Transferred vs Message Size\n(4 threads, 5 second duration)')
    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)
    
    # Add value annotations for key points
    for i in [0, len(MESSAGE_SIZES)-1]:
        ax.annotate(f'{CYCLES_PER_BYTE_TWO_COPY[i]:.1f}', 
                   (MESSAGE_SIZES[i], CYCLES_PER_BYTE_TWO_COPY[i]), 
                   textcoords="offset points", xytext=(10,0), ha='left', fontsize=9)
        ax.annotate(f'{CYCLES_PER_BYTE_ONE_COPY[i]:.1f}', 
                   (MESSAGE_SIZES[i], CYCLES_PER_BYTE_ONE_COPY[i]), 
                   textcoords="offset points", xytext=(10,0), ha='left', fontsize=9)
        ax.annotate(f'{CYCLES_PER_BYTE_ZERO_COPY[i]:.1f}', 
                   (MESSAGE_SIZES[i], CYCLES_PER_BYTE_ZERO_COPY[i]), 
                   textcoords="offset points", xytext=(10,0), ha='left', fontsize=9)
    
    plt.figtext(0.99, 0.01, SYSTEM_CONFIG, ha='right', fontsize=8, 
                style='italic', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cycles_per_byte.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_cycles_per_byte.png")

# ============================================================================
# MAIN: Generate all plots
# ============================================================================
if __name__ == "__main__":
    print("MT25076 - Generating plots for Network I/O experiments...")
    print("=" * 60)
    
    plot_throughput_vs_message_size()
    plot_latency_vs_threads()
    plot_cache_misses()
    plot_cycles_per_byte()
    
    print("=" * 60)
    print("All plots generated successfully!")
    print("\nNote: Update the hardcoded values with actual measurements")
    print("from your experiments before final submission.")
