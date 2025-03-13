import matplotlib.pyplot as plt
import numpy as np

# Data
# categories = ["64x64x64"]
categories = ["64x64x64", "32x32x32", "16x16x16"]

# Without any added memory Latency
cva6_baseline = [93.2, 72.0, 41.3]
cva6_sequencer = [95.7, 76.3, 42.4]
ideal_baseline = [96.0, 87.2, 66.8]
ideal_sequencer = [97.2, 93.9, 75.1]

# With memory latency of 16 (mem_latency=8)
# cva6_baseline = [77.6, 51.7, 23.7]
# cva6_sequencer = [80.6, 53.0, 24.1]
# ideal_baseline = [96.0, 86.8, 63.9]
# ideal_sequencer = [97.0, 93.4, 71.4]

# With memory latency of 64 (mem_latency=32)
# cva6_baseline = [48.9]
# cva6_sequencer = [49.2]
# ideal_baseline = [95.7]
# ideal_sequencer = [96.8]

x = np.arange(len(categories))

# Plot
fig, ax = plt.subplots(figsize=(8, 5))
width = 0.3

# Column plot for w/ CVA6
bars1 = ax.bar(x - width/2, cva6_baseline, width, label="w/ CVA6 - Baseline", color="C0")
bars2 = ax.bar(x + width/2, cva6_sequencer, width, label="w/ CVA6 - Sequencer-opt", color="C1")

# Scatter plot for Ideal
scatter1 = ax.scatter(x - width/2, ideal_baseline, color="C0", label="Ideal - Baseline", marker='x', s=80, edgecolors='black')
scatter2 = ax.scatter(x + width/2, ideal_sequencer, color="C1", label="Ideal - Sequencer-opt", marker='x', s=80, edgecolors='black')

# Add data labels for bars
for bar in bars1 + bars2:
    height = bar.get_height()
    ax.text(bar.get_x() + bar.get_width() / 2, height - bar.get_height()/8, f"{height:.1f}", ha='center', va='bottom', fontsize=10, color='black')

# Add data labels for scatter points
for i, (ib, isq) in enumerate(zip(ideal_baseline, ideal_sequencer)):
    ax.text(x[i]- width*0.5, ib + 2, f"{ib:.1f}", ha='center', va='bottom', fontsize=10, color='black')
    ax.text(x[i]+ width*0.5, isq + 2, f"{isq:.1f}", ha='center', va='bottom', fontsize=10, color='black')

# Labels and formatting
ax.set_xticks(x)
ax.set_xticklabels(categories)
ax.set_xlabel("Kernel")
ax.set_ylabel("FPU utilization (%)")
ax.set_title("Comparison of w/ CVA6 vs Ideal (Added Memory Latency = 32)")
ax.legend(loc="lower center")
ax.grid(axis='y', linestyle='--', alpha=0.7)

plt.show()
