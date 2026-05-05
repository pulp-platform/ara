import re
import os
import matplotlib.pyplot as plt

script_dir = os.path.dirname(os.path.abspath(__file__))
logs_base = os.path.join(script_dir, '..', 'logs')

bytes_list = [8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136, 144, 152, 160, 168, 176, 184, 192, 200, 208, 216, 224, 232, 240, 248, 256, 264, 272, 512, 520, 528, 1024]
vlens = [4096, 8192, 16384]
banks_list = [8, 16, 32]
vlen_labels = {4096: '4K', 8192: '8K', 16384: '16K'}

# Fixed parameters for the two dedicated plots
fixed_vlen_for_banks_plot  = 4096   # vlen held constant while banks vary
fixed_banks_for_vlen_plot  = 32      # banks held constant while vlen varies

# Auto-discover kernels from subdirectories in the logs directory
kernels = sorted([
    d for d in os.listdir(logs_base)
    if os.path.isdir(os.path.join(logs_base, d))
])


def extract_util(kernel, bytes_, vlen, banks):
    fname = '4L_{}B__{}vlen_{}banks_0mem.log'.format(bytes_, vlen, banks)
    fpath = os.path.join(logs_base, kernel, fname)
    try:
        with open(fpath) as f:
            for line in f:
                m = re.search(r'\[FPU utilization\]:([0-9.]+)', line)
                if m:
                    return float(m.group(1))
    except FileNotFoundError:
        pass
    return None


def print_table(kernel, data):
    col_w = 12
    label_w = 12

    header1 = '{:<{}}'.format(kernel, label_w)
    for vlen in vlens:
        header1 += '{:^{}}'.format('vlen = {}'.format(vlen_labels[vlen]), col_w * len(banks_list))
    print(header1)

    header2 = '{:<{}}'.format('Bytes/Lane', label_w)
    for _ in vlens:
        for banks in banks_list:
            header2 += '{:^{}}'.format('{} banks'.format(banks), col_w)
    print(header2)

    print('-' * (label_w + col_w * len(vlens) * len(banks_list)))

    for i, bytes_ in enumerate(bytes_list):
        row = '{:<{}}'.format(bytes_, label_w)
        for vlen in vlens:
            for banks in banks_list:
                val = data[vlen][banks][i]
                row += '{:^{}}'.format('{:.2f}%'.format(val) if val is not None else 'N/A', col_w)
        print(row)


def _make_pos_map():
    """Return a position map for the non-uniform x-axis (shared by all plots)."""
    _extra_gap = 3
    _pos, pos_map = 0, {}
    for _i, _b in enumerate(bytes_list):
        if _i > 0 and (bytes_list[_i - 1], _b) in ((272, 512), (528, 1024)):
            _pos += _extra_gap
        pos_map[_b] = _pos
        _pos += 1
    return pos_map


def _draw_axis_breaks(ax, pos_map):
    """Draw // break marks between the non-contiguous regions of the x-axis."""
    for lo, hi in [(272, 512), (528, 1024)]:
        if lo not in pos_map or hi not in pos_map:
            continue
        bx = (pos_map[lo] + pos_map[hi]) / 2.0
        dy, dx = 4, 0.12
        for cx in [bx - 0.22, bx + 0.22]:
            ax.plot([cx - dx, cx + dx], [-dy, dy],
                    color='white', lw=5, clip_on=False, zorder=5)
            ax.plot([cx - dx, cx + dx], [-dy, dy],
                    color='black', lw=1.5, clip_on=False, zorder=6)


def _apply_common_axes(ax, pos_map, title):
    ax.set_xticks([pos_map[b] for b in bytes_list])
    ax.set_xticklabels([str(b) for b in bytes_list], rotation=90, fontsize=7)
    ax.set_xlabel('Bytes/Lane')
    ax.set_ylabel('Utilization (%)')
    ax.set_title(title)
    ax.set_ylim(0, 100)
    ax.legend(loc='lower right', fontsize=8)
    ax.grid(True, linestyle='--', alpha=0.5)


def plot_banks_vary(kernel, data, ax, pos_map):
    """Plot 1 – fixed vlen, banks vary."""
    colors  = {8: 'tab:blue', 16: 'tab:orange', 32: 'tab:green'}
    markers = {8: 'o',        16: 's',           32: '^'}
    vlen = fixed_vlen_for_banks_plot
    for banks in banks_list:
        vals = data[vlen][banks]
        x = [pos_map[bytes_list[i]] for i, v in enumerate(vals) if v is not None]
        y = [v for v in vals if v is not None]
        if not x:
            continue
        ax.plot(x, y,
                color=colors[banks],
                linestyle='-',
                marker=markers[banks],
                label='{} banks'.format(banks))
    _apply_common_axes(ax, pos_map,
        '{} Utilization  (VLEN={})'.format(kernel, vlen_labels[vlen]))
    _draw_axis_breaks(ax, pos_map)


def plot_vlen_vary(kernel, data, ax, pos_map):
    """Plot 2 – fixed banks, vlen varies."""
    colors  = {4096: 'tab:blue', 8192: 'tab:orange', 16384: 'tab:green'}
    markers = {4096: 'o',        8192: 's',           16384: '^'}
    banks = fixed_banks_for_vlen_plot
    for vlen in vlens:
        vals = data[vlen][banks]
        x = [pos_map[bytes_list[i]] for i, v in enumerate(vals) if v is not None]
        y = [v for v in vals if v is not None]
        if not x:
            continue
        ax.plot(x, y,
                color=colors[vlen],
                linestyle='-',
                marker=markers[vlen],
                label='VLEN={}'.format(vlen_labels[vlen]))
    _apply_common_axes(ax, pos_map,
        '{} Utilization  ({} banks)'.format(kernel, banks))
    _draw_axis_breaks(ax, pos_map)


pos_map = _make_pos_map()


for kernel in kernels:
    # Collect data for all (vlen, banks) combinations
    data = {}
    for vlen in vlens:
        data[vlen] = {}
        for banks in banks_list:
            data[vlen][banks] = [extract_util(kernel, b, vlen, banks) for b in bytes_list]

    print_table(kernel, data)
    print()

    # --- Plot 1: banks vary, vlen fixed ---
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_banks_vary(kernel, data, ax, pos_map)
    plt.tight_layout()
    out_banks = os.path.normpath(os.path.join(logs_base, kernel, 'util_banks_vary.png'))
    plt.savefig(out_banks, dpi=150)
    plt.close(fig)
    print('Banks-vary plot saved to: {}'.format(out_banks))

    # --- Plot 2: vlen varies, banks fixed ---
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_vlen_vary(kernel, data, ax, pos_map)
    plt.tight_layout()
    out_vlen = os.path.normpath(os.path.join(logs_base, kernel, 'util_vlen_vary.png'))
    plt.savefig(out_vlen, dpi=150)
    plt.close(fig)
    print('Vlen-vary plot saved to: {}'.format(out_vlen))

# --- Plot 3: Per-kernel baseline comparison: (4K, 8 banks) vs (16K, 32 banks) ---
baseline_configs = [(4096, 8), (16384, 32)]
baseline_labels  = {(4096, 8): '4K VLEN, 8 banks', (16384, 32): '16K VLEN, 32 banks'}
baseline_colors  = {(4096, 8): 'tab:blue',          (16384, 32): 'tab:green'}
baseline_markers = {(4096, 8): 'o',                 (16384, 32): '^'}

for kernel in kernels:
    fig, ax = plt.subplots(figsize=(9, 5))
    for cfg in baseline_configs:
        vlen, banks = cfg
        vals = [extract_util(kernel, b, vlen, banks) for b in bytes_list]
        x = [pos_map[bytes_list[i]] for i, v in enumerate(vals) if v is not None]
        y = [v for v in vals if v is not None]
        if not x:
            continue
        ax.plot(x, y,
                color=baseline_colors[cfg],
                linestyle='-',
                marker=baseline_markers[cfg],
                label=baseline_labels[cfg])
    ax.set_xticks([pos_map[b] for b in bytes_list])
    ax.set_xticklabels([str(b) for b in bytes_list], rotation=90, fontsize=7)
    ax.set_xlabel('Bytes/Lane')
    ax.set_ylabel('Utilization (%)')
    ax.set_title('{} Baseline Utilization'.format(kernel))
    ax.set_ylim(0, 100)
    ax.legend(loc='lower right', fontsize=8)
    ax.grid(True, linestyle='--', alpha=0.5)
    _draw_axis_breaks(ax, pos_map)
    plt.tight_layout()
    baseline_out = os.path.normpath(os.path.join(logs_base, kernel, 'baseline_comparison.png'))
    plt.savefig(baseline_out, dpi=150, bbox_inches='tight')
    plt.close(fig)
    print('Baseline comparison plot saved to: {}'.format(baseline_out))

plt.show()


