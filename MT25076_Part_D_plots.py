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
# HARDCODED DATA FROM CSV FILES
# ============================================================================

MESSAGE_SIZES = ['1K', '4K', '16K', '64K']
MESSAGE_SIZES_BYTES = [1024, 4096, 16384, 65536]
THREAD_COUNTS = [1, 2, 4, 8]

# ============================================================================
# THROUGHPUT DATA (Gbps) - Averaged from S_to_C and C_to_S directions
# Format: [1K, 4K, 16K, 64K] for each thread count
# ============================================================================

# Two-Copy Throughput
THROUGHPUT_TWO_COPY = {
    1: [4.615807, 16.232727, 46.174722, 75.652572],   # threads=1
    2: [8.855352, 29.990700, 94.539990, 146.207362],  # threads=2
    4: [17.521864, 57.860303, 174.731369, 276.608973], # threads=4
    8: [28.292795, 90.963403, 251.375723, 425.910446]  # threads=8
}

# One-Copy Throughput
THROUGHPUT_ONE_COPY = {
    1: [4.172880, 13.001204, 44.540369, 74.248405],
    2: [8.349704, 25.409883, 83.164137, 142.941398],
    4: [16.287560, 47.809165, 161.167867, 276.784096],
    8: [24.270321, 75.473388, 232.874525, 402.620688]
}

# Zero-Copy Throughput
THROUGHPUT_ZERO_COPY = {
    1: [2.248523, 8.553750, 27.380311, 53.251939],
    2: [4.454806, 16.817311, 53.300906, 101.629063],
    4: [8.675462, 32.499410, 101.887663, 191.585778],
    8: [12.698369, 48.609677, 158.049715, 289.060675]
}

# ============================================================================
# LATENCY DATA (µs) - Averaged from both directions
# Format: [threads=1, threads=2, threads=4, threads=8] for each msg size
# ============================================================================

# Latency for 16K message size
LATENCY_16K_TWO_COPY = [56.00, 64.625, 112.625, 78.375]
LATENCY_16K_ONE_COPY = [155.50, 59.25, 76.31, 164.25]
LATENCY_16K_ZERO_COPY = [77.00, 73.875, 63.44, 272.56]

# Latency for different msg sizes (threads=4)
LATENCY_4THREADS_TWO_COPY = [63.815, 62.25, 112.625, 164.185]
LATENCY_4THREADS_ONE_COPY = [83.88, 92.50, 76.31, 174.25]
LATENCY_4THREADS_ZERO_COPY = [125.37, 145.625, 63.44, 139.31]

# ============================================================================
# CACHE MISSES DATA (from perf - server_sender S->C direction)
# Format: [1K, 4K, 16K, 64K]
# ============================================================================

# L1 Cache Misses (threads=4)
L1_MISSES_TWO_COPY_4T = [268870315, 451680979, 1758628802, 2371369969]
L1_MISSES_ONE_COPY_4T = [276123745, 411803975, 1683582636, 2342346615]
L1_MISSES_ZERO_COPY_4T = [267479753, 282096206, 1108023088, 1819643628]

# Cache misses (cache-misses counter) for threads=4
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
# CPU CYCLES PER BYTE (from perf - averaged across directions)
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
# PLOT 1: Throughput vs Message Size (for each thread count)
# ============================================================================
def plot_throughput_vs_message_size():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    
    colors = {'two_copy': '#e74c3c', 'one_copy': '#3498db', 'zero_copy': '#2ecc71'}
    
    for idx, threads in enumerate(THREAD_COUNTS):
        ax = axes[idx]
        x = np.arange(len(MESSAGE_SIZES))
        width = 0.25
        
        bars1 = ax.bar(x - width, THROUGHPUT_TWO_COPY[threads], width, 
                       label='Two-Copy', color=colors['two_copy'], edgecolor='black', linewidth=0.5)
        bars2 = ax.bar(x, THROUGHPUT_ONE_COPY[threads], width, 
                       label='One-Copy', color=colors['one_copy'], edgecolor='black', linewidth=0.5)
        bars3 = ax.bar(x + width, THROUGHPUT_ZERO_COPY[threads], width, 
                       label='Zero-Copy', color=colors['zero_copy'], edgecolor='black', linewidth=0.5)
        
        ax.set_xlabel('Message Size')
        ax.set_ylabel('Throughput (Gbps)')
        ax.set_title(f'{threads} Thread(s)')
        ax.set_xticks(x)
        ax.set_xticklabels(MESSAGE_SIZES)
        ax.legend(loc='upper left', fontsize=9)
        ax.grid(axis='y', alpha=0.3)
    
    fig.suptitle(f'Throughput vs Message Size\n', fontsize=14, y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_throughput_vs_msgsize.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_throughput_vs_msgsize.png")

# ============================================================================
# PLOT 2: Latency vs Thread Count (for each message size)
# ============================================================================
def plot_latency_vs_threads():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    
    # Latency data organized by message size
    # [threads=1, threads=2, threads=4, threads=8]
    latency_data = {
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
    
    colors = {'two_copy': '#e74c3c', 'one_copy': '#3498db', 'zero_copy': '#2ecc71'}
    markers = {'two_copy': 'o', 'one_copy': 's', 'zero_copy': '^'}
    
    for idx, msg_size in enumerate(MESSAGE_SIZES):
        ax = axes[idx]
        data = latency_data[msg_size]
        
        for impl, values in data.items():
            # Cap extreme values for visualization
            capped_values = [min(v, 500) for v in values]
            label = impl.replace('_', '-').title()
            ax.plot(THREAD_COUNTS, capped_values, f'{markers[impl]}-', 
                   label=label, color=colors[impl], linewidth=2, markersize=8)
        
        ax.set_xlabel('Number of Threads')
        ax.set_ylabel('Latency (µs)')
        ax.set_title(f'Message Size: {msg_size}')
        ax.set_xticks(THREAD_COUNTS)
        ax.legend(loc='upper right', fontsize=9)
        ax.grid(True, alpha=0.3)
    
    fig.suptitle(f'Latency vs Thread Count\n', fontsize=14, y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_latency_vs_threads.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_latency_vs_threads.png")

# ============================================================================
# PLOT 3: Cache Misses vs Message Size (for each thread count)
# ============================================================================
def plot_cache_misses():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    
    colors = {'two_copy': '#e74c3c', 'one_copy': '#3498db', 'zero_copy': '#2ecc71'}
    
    for idx, threads in enumerate(THREAD_COUNTS):
        ax = axes[idx]
        x = np.arange(len(MESSAGE_SIZES))
        width = 0.25
        
        ax.bar(x - width, CACHE_MISSES_TWO_COPY[threads], width, 
               label='Two-Copy', color=colors['two_copy'], edgecolor='black', linewidth=0.5)
        ax.bar(x, CACHE_MISSES_ONE_COPY[threads], width, 
               label='One-Copy', color=colors['one_copy'], edgecolor='black', linewidth=0.5)
        ax.bar(x + width, CACHE_MISSES_ZERO_COPY[threads], width, 
               label='Zero-Copy', color=colors['zero_copy'], edgecolor='black', linewidth=0.5)
        
        ax.set_xlabel('Message Size')
        ax.set_ylabel('Cache Misses')
        ax.set_title(f'{threads} Thread(s)')
        ax.set_xticks(x)
        ax.set_xticklabels(MESSAGE_SIZES)
        ax.legend(loc='upper left', fontsize=9)
        ax.set_yscale('log')
        ax.grid(axis='y', alpha=0.3)
    
    fig.suptitle(f'Cache Misses vs Message Size\n', fontsize=14, y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cache_misses.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_cache_misses.png")

# ============================================================================
# PLOT 4: CPU Cycles per Byte Transferred (for each thread count)
# ============================================================================
def plot_cycles_per_byte():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    
    colors = {'two_copy': '#e74c3c', 'one_copy': '#3498db', 'zero_copy': '#2ecc71'}
    markers = {'two_copy': 'o', 'one_copy': 's', 'zero_copy': '^'}
    
    for idx, threads in enumerate(THREAD_COUNTS):
        ax = axes[idx]
        
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_TWO_COPY[threads], 'o-', 
               label='Two-Copy', color=colors['two_copy'], linewidth=2, markersize=8)
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ONE_COPY[threads], 's-', 
               label='One-Copy', color=colors['one_copy'], linewidth=2, markersize=8)
        ax.plot(MESSAGE_SIZES, CYCLES_PER_BYTE_ZERO_COPY[threads], '^-', 
               label='Zero-Copy', color=colors['zero_copy'], linewidth=2, markersize=8)
        
        ax.set_xlabel('Message Size')
        ax.set_ylabel('CPU Cycles per Byte')
        ax.set_title(f'{threads} Thread(s)')
        ax.legend(loc='upper right', fontsize=9)
        ax.grid(True, alpha=0.3)
        
        # Annotate values
        for i, msg in enumerate(MESSAGE_SIZES):
            ax.annotate(f'{CYCLES_PER_BYTE_TWO_COPY[threads][i]:.1f}', 
                       (msg, CYCLES_PER_BYTE_TWO_COPY[threads][i]),
                       textcoords="offset points", xytext=(0, 8), ha='center', fontsize=8)
    
    fig.suptitle(f'CPU Cycles per Byte Transferred\n', fontsize=14, y=1.02)
    plt.tight_layout()
    plt.savefig('MT25076_Part_D_cycles_per_byte.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("Generated: MT25076_Part_D_cycles_per_byte.png")

# ============================================================================
# Main
# ============================================================================
if __name__ == "__main__":
    print("Generating plots for Network I/O Performance Analysis...")
    print("=" * 60)
    
    plot_throughput_vs_message_size()
    plot_latency_vs_threads()
    plot_cache_misses()
    plot_cycles_per_byte()
    
    print("=" * 60)
    print("All plots generated successfully!")
    print("\nGenerated files:")
    print("  - MT25076_Part_D_throughput_vs_msgsize.png")
    print("  - MT25076_Part_D_latency_vs_threads.png")
    print("  - MT25076_Part_D_cache_misses.png")
    print("  - MT25076_Part_D_cycles_per_byte.png")
