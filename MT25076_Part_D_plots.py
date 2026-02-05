# MT25076 - Part D: Plotting Script
# Roll Number: MT25076
#
# This script generates plots for the network I/O experiments.
# Values are hardcoded as per assignment requirements.

import matplotlib.pyplot as plt
import numpy as np

# Set style for better aesthetics
try:
    plt.style.use('seaborn-v0_8-whitegrid')
except:
    plt.style.use('seaborn-whitegrid')

plt.rcParams['figure.figsize'] = (10, 6)
plt.rcParams['font.size'] = 12
plt.rcParams['axes.labelsize'] = 14
plt.rcParams['axes.titlesize'] = 16
plt.rcParams['legend.fontsize'] = 11

# System configuration
SYSTEM_CONFIG = """
System Configuration:
- CPU: Intel Core (update with your CPU)
- RAM: 16GB (update with your RAM)
- OS: Linux (update with your kernel version)
- Network: veth pair (10 Gbps virtual)
"""

# ============================================================================
# HARDCODED DATA
# ============================================================================

# Message sizes
MESSAGE_SIZES = ['1K', '4K', '16K', '64K']
MESSAGE_SIZES_BYTES = [1024, 4096, 16384, 65536]

# Thread counts
THREAD_COUNTS = [1, 2, 4, 8]

# Throughput data (Gbps) - threads=4
THROUGHPUT_TWO_COPY = [17.98579, 63.634746, 183.827554, 286.10815]
THROUGHPUT_ONE_COPY = [16.644618, 57.282813, 171.330032, 280.350529]
THROUGHPUT_ZERO_COPY = [9.879754, 36.329875, 112.589125, 191.339962]

# Latency data (µs) - msg_size=16K
LATENCY_TWO_COPY = [307.5, 198.5, 286.75, 314.69]
LATENCY_ONE_COPY = [237.5, 161.5, 275.62, 196.06]
LATENCY_ZERO_COPY = [239.0, 179.25, 208.62, 93.81]

# Cache misses (L1) - threads=4
L1_MISSES_TWO_COPY = [630251181, 1156709117, 2893640691, 2641065458]
L1_MISSES_ONE_COPY = [489251084, 906371590, 2641258126, 2790605541]
L1_MISSES_ZERO_COPY = [488859392, 884021280, 2073444692, 2311763433]

# Cache misses (LLC) - threads=4
LLC_MISSES_TWO_COPY = [33022, 18385, 5409, 7075]
LLC_MISSES_ONE_COPY = [6614, 13377, 12826, 14503]
LLC_MISSES_ZERO_COPY = [2329, 3217, 5464, 405248]

# CPU cycles per byte - threads=4
CYCLES_PER_BYTE_TWO_COPY = [10.5805, 3.2342, 1.057, 0.6133]
CYCLES_PER_BYTE_ONE_COPY = [12.1811, 3.8543, 1.2327, 0.6546]
CYCLES_PER_BYTE_ZERO_COPY = [15.2312, 4.7019, 1.6929, 0.9804]

# ============================================================================
# PLOT 1: Throughput vs Message Size
# ============================================================================
def plot_throughput_vs_message_size():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    x = np.arange(len(MESSAGE_SIZES))
    width = 0.25
    
    bars1 = ax.bar(x - width, THROUGHPUT_TWO_COPY, width, label='Two-Copy', 
                   color='#e74c3c', edgecolor='black', linewidth=0.5)
    bars2 = ax.bar(x, THROUGHPUT_ONE_COPY, width, label='One-Copy', 
                   color='#3498db', edgecolor='black', linewidth=0.5)
    bars3 = ax.bar(x + width, THROUGHPUT_ZERO_COPY, width, label='Zero-Copy', 
                   color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax.set_xlabel('Message Size')
    ax.set_ylabel('Throughput (Gbps)')
    ax.set_title('Throughput vs Message Size\n(4 threads)')
    ax.set_xticks(x)
    ax.set_xticklabels(MESSAGE_SIZES)
    ax.legend(loc='upper left')
    
    # Add value labels
    for bars in [bars1, bars2, bars3]:
        for bar in bars:
            height = bar.get_height()
            ax.annotate(f'{height:.1f}',
                        xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 3),
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=9)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_throughput_vs_msgsize.png', dpi=150, bbox_inches='tight')
    plt.close()

# ============================================================================
# PLOT 2: Latency vs Thread Count
# ============================================================================
def plot_latency_vs_threads():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(THREAD_COUNTS, LATENCY_TWO_COPY, 'o-', label='Two-Copy', 
            color='#e74c3c', linewidth=2, markersize=8)
    ax.plot(THREAD_COUNTS, LATENCY_ONE_COPY, 's-', label='One-Copy', 
            color='#3498db', linewidth=2, markersize=8)
    ax.plot(THREAD_COUNTS, LATENCY_ZERO_COPY, '^-', label='Zero-Copy', 
            color='#2ecc71', linewidth=2, markersize=8)
    
    ax.set_xlabel('Number of Threads')
    ax.set_ylabel('Latency (µs)')
    ax.set_title('Latency vs Thread Count\n(16K message size)')
    ax.set_xticks(THREAD_COUNTS)
    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_latency_vs_threads.png', dpi=150, bbox_inches='tight')
    plt.close()

# ============================================================================
# PLOT 3: Cache Misses vs Message Size
# ============================================================================
def plot_cache_misses():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    
    x = np.arange(len(MESSAGE_SIZES))
    width = 0.25
    
    # L1 Cache Misses
    ax1.bar(x - width, np.array(L1_MISSES_TWO_COPY), width, label='Two-Copy', 
            color='#e74c3c', edgecolor='black', linewidth=0.5)
    ax1.bar(x, np.array(L1_MISSES_ONE_COPY), width, label='One-Copy', 
            color='#3498db', edgecolor='black', linewidth=0.5)
    ax1.bar(x + width, np.array(L1_MISSES_ZERO_COPY), width, label='Zero-Copy', 
            color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax1.set_xlabel('Message Size')
    ax1.set_ylabel('L1 Cache Misses')
    ax1.set_title('L1 Data Cache Misses vs Message Size')
    ax1.set_xticks(x)
    ax1.set_xticklabels(MESSAGE_SIZES)
    ax1.legend(loc='upper left')
    ax1.set_yscale('log')
    
    # LLC Cache Misses
    ax2.bar(x - width, np.array(LLC_MISSES_TWO_COPY), width, label='Two-Copy', 
            color='#e74c3c', edgecolor='black', linewidth=0.5)
    ax2.bar(x, np.array(LLC_MISSES_ONE_COPY), width, label='One-Copy', 
            color='#3498db', edgecolor='black', linewidth=0.5)
    ax2.bar(x + width, np.array(LLC_MISSES_ZERO_COPY), width, label='Zero-Copy', 
            color='#2ecc71', edgecolor='black', linewidth=0.5)
    
    ax2.set_xlabel('Message Size')
    ax2.set_ylabel('LLC Misses')
    ax2.set_title('Last Level Cache Misses vs Message Size')
    ax2.set_xticks(x)
    ax2.set_xticklabels(MESSAGE_SIZES)
    ax2.legend(loc='upper left')
    ax2.set_yscale('log')
    
    plt.suptitle('Cache Misses vs Message Size (4 threads)', fontsize=14, y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cache_misses.png', dpi=150, bbox_inches='tight')
    plt.close()

# ============================================================================
# PLOT 4: CPU Cycles per Byte Transferred
# ============================================================================
def plot_cycles_per_byte():
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_TWO_COPY, 'o-', label='Two-Copy', 
            color='#e74c3c', linewidth=2, markersize=8)
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ONE_COPY, 's-', label='One-Copy', 
            color='#3498db', linewidth=2, markersize=8)
    ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ZERO_COPY, '^-', label='Zero-Copy', 
            color='#2ecc71', linewidth=2, markersize=8)
    
    ax.set_xlabel('Message Size')
    ax.set_ylabel('CPU Cycles per Byte')
    ax.set_title('CPU Cycles per Byte Transferred vs Message Size\n(4 threads)')
    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)
    
    # Add annotations for max/min
    for i in [0, len(MESSAGE_SIZES)-1]:
        ax.annotate(f'{CYCLES_PER_BYTE_TWO_COPY[i]:.1f}', 
                   (MESSAGE_SIZES[i], CYCLES_PER_BYTE_TWO_COPY[i]), 
                   textcoords="offset points", xytext=(10,0), ha='left', fontsize=9)
    
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cycles_per_byte.png', dpi=150, bbox_inches='tight')
    plt.close()

if __name__ == "__main__":
    plot_throughput_vs_message_size()
    plot_latency_vs_threads()
    plot_cache_misses()
    plot_cycles_per_byte()
