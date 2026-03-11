import os
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
from matplotlib.colors import LogNorm
from matplotlib.lines import Line2D

# Configuration
PROJECT_ROOT = Path(__file__).resolve().parent.parent
INPUT_FILE = PROJECT_ROOT / 'data' / 'energy_stats.csv'
RAW_OUTPUT_DIR = PROJECT_ROOT / 'graphs' / 'raw'
SUMMARY_OUTPUT_DIR = PROJECT_ROOT / 'graphs' / 'summary'

METRIC_SPECS = [
    {
        'key': 'energy',
        'column': 'Package Joules Mean',
        'label': 'Energy',
        'axis_label': 'Energy (Joules)',
        'ci_low': 'Package Joules CI 95% Low',
        'ci_high': 'Package Joules CI 95% High',
        'title_suffix': 'Energy vs Frequency',
        'filename_suffix': 'energy',
    },
    {
        'key': 'time',
        'column': 'Time Elapsed Mean (ms)',
        'label': 'Time',
        'axis_label': 'Time (ms)',
        'ci_low': 'Elapsed Time CI 95% Low',
        'ci_high': 'Elapsed Time CI 95% High',
        'title_suffix': 'Time vs Frequency',
        'filename_suffix': 'time',
    },
    {
        'key': 'edp',
        'column': 'EDP Mean',
        'label': 'EDP',
        'axis_label': 'EDP (J·s)',
        'ci_low': 'EDP CI 95% Low',
        'ci_high': 'EDP CI 95% High',
        'title_suffix': 'EDP vs Frequency',
        'filename_suffix': 'edp',
    },
    {
        'key': 'edp2',
        'column': 'EDP2 Mean',
        'label': 'EDP2',
        'axis_label': 'E²DP (J²·s)',
        'ci_low': 'EDP2 CI 95% Low',
        'ci_high': 'EDP2 CI 95% High',
        'title_suffix': 'E²DP vs Frequency',
        'filename_suffix': 'edp2',
    },
]


def parse_heap_size(heap_str):
    """Parses heap size string (e.g., '100m') to integer MB."""
    if pd.isna(heap_str):
        return 0
    heap_str = str(heap_str).lower()
    if heap_str.endswith('m'):
        return int(heap_str[:-1])
    if heap_str.endswith('g'):
        return int(heap_str[:-1]) * 1024
    try:
        return int(heap_str)
    except ValueError:
        return 0


def parse_frequency(freq_str):
    """Parses frequency string (e.g., '1.2GHz', '400MHz') to float MHz."""
    freq_str = str(freq_str).strip()
    if freq_str.endswith('GHz'):
        return float(freq_str[:-3]) * 1000
    if freq_str.endswith('MHz'):
        return float(freq_str[:-3])
    try:
        return float(freq_str)
    except ValueError:
        return 0.0


def get_heap_multiplier(heap_val, min_heap):
    """Calculates heap multiplier (e.g., 1x, 2x)."""
    if min_heap == 0:
        return "Unknown"
    mult = heap_val / min_heap
    if abs(mult - round(mult)) < 0.1:
        return f"{int(round(mult))}x"
    return f"{mult:.1f}x"


def short_frequency_label(freq_label):
    """Shortens frequency labels to fit table annotations."""
    freq_label = str(freq_label)
    if freq_label.endswith('GHz'):
        return freq_label.replace('GHz', 'G')
    if freq_label.endswith('MHz'):
        return freq_label.replace('MHz', 'M')
    return freq_label


def prepare_dataframe(df):
    """Adds parsed and normalized columns for detailed and summary plots."""
    df = df.copy()
    df['Heap Size MB'] = df['Heap Size'].apply(parse_heap_size)
    df['Frequency (MHz)'] = df['CPU Frequency (MHz)'].apply(parse_frequency)

    min_heap = df.groupby('Benchmark')['Heap Size MB'].transform('min')
    df['Heap Multiplier Value'] = df['Heap Size MB'] / min_heap
    df['Heap Label'] = df.apply(
        lambda row: get_heap_multiplier(row['Heap Size MB'], min_heap.loc[row.name]),
        axis=1,
    )

    for spec in METRIC_SPECS:
        metric_min = df.groupby('Benchmark')[spec['column']].transform('min')
        df[f"{spec['key']}_norm"] = df[spec['column']] / metric_min

    df['Config Label'] = df.apply(
        lambda row: f"{row['CPU Frequency (MHz)']}\n{row['Heap Label']}",
        axis=1,
    )
    return df.sort_values(by=['Benchmark', 'Frequency (MHz)', 'Heap Size MB']).reset_index(drop=True)


def build_heap_order(bench_df):
    """Builds a stable heap order based on numeric heap size."""
    heap_info = (
        bench_df[['Heap Label', 'Heap Size MB']]
        .drop_duplicates()
        .sort_values('Heap Size MB')
    )
    return heap_info['Heap Label'].tolist()


def generate_benchmark_plots(df):
    """Keeps the detailed per-benchmark plots for appendix use."""
    for benchmark, bench_df in df.groupby('Benchmark'):
        heap_order = build_heap_order(bench_df)
        palette = sns.color_palette("tab10", len(heap_order))
        label_to_color = dict(zip(heap_order, palette))

        for spec in METRIC_SPECS:
            plt.figure(figsize=(10, 6))
            sns.lineplot(
                data=bench_df,
                x='Frequency (MHz)',
                y=spec['column'],
                hue='Heap Label',
                hue_order=heap_order,
                palette=label_to_color,
                marker='o',
                style='Heap Label',
                style_order=heap_order,
            )

            for label in heap_order:
                subset = bench_df[bench_df['Heap Label'] == label].sort_values('Frequency (MHz)')
                if subset.empty:
                    continue
                plt.fill_between(
                    subset['Frequency (MHz)'],
                    subset[spec['ci_low']],
                    subset[spec['ci_high']],
                    color=label_to_color[label],
                    alpha=0.15,
                )

            non_outlier = bench_df[bench_df['Heap Label'] != '1x']
            if not non_outlier.empty:
                y_max = non_outlier[spec['column']].max()
                ci_max = non_outlier[spec['ci_high']].max()
                if pd.notna(ci_max):
                    y_max = max(y_max, ci_max)
                if pd.notna(y_max) and y_max > 0:
                    plt.ylim(0, y_max * 1.1)

            plt.title(f'{benchmark} - {spec["title_suffix"]}')
            plt.xlabel('Frequency (MHz)')
            plt.ylabel(spec['axis_label'])
            plt.grid(True, linestyle='--', alpha=0.7)
            plt.legend(title='Heap Size')

            output_path = RAW_OUTPUT_DIR / f'{benchmark}_{spec["filename_suffix"]}.png'
            plt.tight_layout()
            plt.savefig(output_path, dpi=200, bbox_inches='tight')
            plt.close()
            print(f"Generated {output_path}")


def write_latex_table(df, output_path):
    """Writes a simple LaTeX tabular without optional pandas dependencies."""
    latex_df = df.copy()
    for column in latex_df.columns:
        if pd.api.types.is_numeric_dtype(latex_df[column]):
            latex_df[column] = latex_df[column].map(lambda value: f"{value:.3f}")

    def escape_latex(text):
        return (
            str(text)
            .replace('\\', '\\textbackslash{}')
            .replace('&', '\\&')
            .replace('%', '\\%')
            .replace('_', '\\_')
            .replace('#', '\\#')
        )

    lines = [
        '\\begin{tabular}{' + ('l' * len(latex_df.columns)) + '}',
        '\\hline',
        ' & '.join(escape_latex(col) for col in latex_df.columns) + ' \\\\',
        '\\hline',
    ]

    for _, row in latex_df.iterrows():
        lines.append(' & '.join(escape_latex(value) for value in row.tolist()) + ' \\\\')

    lines.extend(['\\hline', '\\end{tabular}'])

    with open(output_path, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines) + '\n')


def build_tie_tables(df):
    """Builds tie-aware summaries using CI overlap with the lowest-mean configuration."""
    tie_rows = []
    objective_rows = []
    benchmark_rows = []

    for benchmark, bench_df in df.groupby('Benchmark'):
        objective_index_sets = {}

        for spec in METRIC_SPECS:
            reference = bench_df.loc[bench_df[spec['column']].idxmin()]
            tie_mask = (
                (bench_df[spec['ci_low']] <= reference[spec['ci_high']]) &
                (bench_df[spec['ci_high']] >= reference[spec['ci_low']])
            )
            tied_df = bench_df[tie_mask].sort_values(['Frequency (MHz)', 'Heap Size MB'])
            objective_index_sets[spec['key']] = set(tied_df.index.tolist())

            tied_freqs = (
                tied_df[['Frequency (MHz)', 'CPU Frequency (MHz)']]
                .drop_duplicates()
                .sort_values('Frequency (MHz)')
            )
            tied_heaps = (
                tied_df[['Heap Multiplier Value', 'Heap Label']]
                .drop_duplicates()
                .sort_values('Heap Multiplier Value')
            )

            objective_rows.append(
                {
                    'Benchmark': benchmark,
                    'Objective': spec['label'],
                    'Reference Lowest Mean Config': (
                        f"{reference['CPU Frequency (MHz)']} / {reference['Heap Label']}"
                    ),
                    'Reference Lowest Mean': reference[spec['column']],
                    'Reference CI Low': reference[spec['ci_low']],
                    'Reference CI High': reference[spec['ci_high']],
                    'Tied Config Count': int(tie_mask.sum()),
                    'Tied Frequencies': ', '.join(tied_freqs['CPU Frequency (MHz)'].tolist()),
                    'Tied Heaps': ', '.join(tied_heaps['Heap Label'].tolist()),
                    'Tied Configs': '; '.join(
                        f"{row['CPU Frequency (MHz)']} / {row['Heap Label']}"
                        for _, row in tied_df.iterrows()
                    ),
                }
            )

            for _, row in bench_df.iterrows():
                tie_rows.append(
                    {
                        'Benchmark': benchmark,
                        'Objective': spec['label'],
                        'CPU Frequency (MHz)': row['CPU Frequency (MHz)'],
                        'Frequency (MHz)': row['Frequency (MHz)'],
                        'Heap Label': row['Heap Label'],
                        'Heap Multiplier Value': row['Heap Multiplier Value'],
                        'Heap Size MB': row['Heap Size MB'],
                        'Mean': row[spec['column']],
                        'CI Low': row[spec['ci_low']],
                        'CI High': row[spec['ci_high']],
                        'Tied With Lowest Mean CI': bool(tie_mask.loc[row.name]),
                    }
                )

        energy_time_overlap = objective_index_sets['energy'] & objective_index_sets['time']
        overlap_df = bench_df.loc[list(energy_time_overlap)].sort_values(['Frequency (MHz)', 'Heap Size MB'])
        benchmark_rows.append(
            {
                'Benchmark': benchmark,
                'Energy Tied Count': len(objective_index_sets['energy']),
                'Time Tied Count': len(objective_index_sets['time']),
                'EDP Tied Count': len(objective_index_sets['edp']),
                'EDP2 Tied Count': len(objective_index_sets['edp2']),
                'Energy/Time Overlap Count': len(energy_time_overlap),
                'Energy/Time Overlap Configs': '; '.join(
                    f"{row['CPU Frequency (MHz)']} / {row['Heap Label']}"
                    for _, row in overlap_df.iterrows()
                ),
            }
        )

    tie_df = pd.DataFrame(tie_rows)
    objective_df = pd.DataFrame(objective_rows).sort_values(['Benchmark', 'Objective']).reset_index(drop=True)
    benchmark_df = pd.DataFrame(benchmark_rows).sort_values('Benchmark').reset_index(drop=True)

    low_heap_df = df[df['Heap Multiplier Value'] <= 2.0]
    high_heap_df = df[df['Heap Multiplier Value'] >= 3.0]
    overall_df = pd.DataFrame(
        [
            {'Statistic': 'benchmarks_analyzed', 'Value': float(benchmark_df.shape[0])},
            {
                'Statistic': 'benchmarks_with_energy_time_overlap',
                'Value': float((benchmark_df['Energy/Time Overlap Count'] > 0).sum()),
            },
            {
                'Statistic': 'median_energy_tied_count',
                'Value': float(benchmark_df['Energy Tied Count'].median()),
            },
            {
                'Statistic': 'median_time_tied_count',
                'Value': float(benchmark_df['Time Tied Count'].median()),
            },
            {
                'Statistic': 'median_edp_tied_count',
                'Value': float(benchmark_df['EDP Tied Count'].median()),
            },
            {
                'Statistic': 'median_edp2_tied_count',
                'Value': float(benchmark_df['EDP2 Tied Count'].median()),
            },
            {
                'Statistic': 'median_energy_time_overlap_count',
                'Value': float(benchmark_df['Energy/Time Overlap Count'].median()),
            },
            {
                'Statistic': 'median_energy_norm_for_heaps_up_to_2x',
                'Value': float(low_heap_df['energy_norm'].median()),
            },
            {
                'Statistic': 'median_energy_norm_for_heaps_from_3x',
                'Value': float(high_heap_df['energy_norm'].median()),
            },
            {
                'Statistic': 'median_time_norm_for_heaps_up_to_2x',
                'Value': float(low_heap_df['time_norm'].median()),
            },
            {
                'Statistic': 'median_time_norm_for_heaps_from_3x',
                'Value': float(high_heap_df['time_norm'].median()),
            },
        ]
    )

    tied_only = tie_df[tie_df['Tied With Lowest Mean CI']].copy()

    frequency_coverage_df = (
        tied_only.groupby(['Objective', 'CPU Frequency (MHz)', 'Frequency (MHz)'])
        .agg(
            Benchmark_Coverage=('Benchmark', 'nunique'),
            Tie_Config_Count=('Benchmark', 'size'),
        )
        .reset_index()
        .sort_values(['Objective', 'Frequency (MHz)'])
        .reset_index(drop=True)
    )

    heap_coverage_df = (
        tied_only.groupby(['Objective', 'Heap Label', 'Heap Multiplier Value'])
        .agg(
            Benchmark_Coverage=('Benchmark', 'nunique'),
            Tie_Config_Count=('Benchmark', 'size'),
        )
        .reset_index()
        .sort_values(['Objective', 'Heap Multiplier Value'])
        .reset_index(drop=True)
    )

    config_coverage_df = (
        tied_only.groupby(
            ['Objective', 'CPU Frequency (MHz)', 'Frequency (MHz)', 'Heap Label', 'Heap Multiplier Value']
        )
        .agg(
            Benchmark_Coverage=('Benchmark', 'nunique'),
            Tie_Config_Count=('Benchmark', 'size'),
        )
        .reset_index()
    )
    config_coverage_df['Configuration'] = (
        config_coverage_df['CPU Frequency (MHz)'] + ' / ' + config_coverage_df['Heap Label']
    )
    config_coverage_df = config_coverage_df.sort_values(
        ['Objective', 'Benchmark_Coverage', 'Tie_Config_Count', 'Frequency (MHz)', 'Heap Multiplier Value'],
        ascending=[True, False, False, True, True],
    ).reset_index(drop=True)

    tie_df.to_csv(SUMMARY_OUTPUT_DIR / 'summary_ties.csv', index=False)
    objective_df.round(3).to_csv(SUMMARY_OUTPUT_DIR / 'summary_tie_sets.csv', index=False)
    benchmark_output = benchmark_df.copy()
    benchmark_output.to_csv(SUMMARY_OUTPUT_DIR / 'summary_tie_benchmarks.csv', index=False)
    frequency_coverage_df.to_csv(SUMMARY_OUTPUT_DIR / 'summary_tie_frequency_coverage.csv', index=False)
    heap_coverage_df.to_csv(SUMMARY_OUTPUT_DIR / 'summary_tie_heap_coverage.csv', index=False)
    config_coverage_df.to_csv(SUMMARY_OUTPUT_DIR / 'summary_tie_top_configs.csv', index=False)
    compact_table = benchmark_output[
        [
            'Benchmark',
            'Energy Tied Count',
            'Time Tied Count',
            'EDP Tied Count',
            'EDP2 Tied Count',
            'Energy/Time Overlap Count',
        ]
    ]
    write_latex_table(compact_table, SUMMARY_OUTPUT_DIR / 'summary_tie_table.tex')
    overall_df.round(3).to_csv(SUMMARY_OUTPUT_DIR / 'summary_overall_stats.csv', index=False)

    return tie_df, objective_df, benchmark_df, frequency_coverage_df, heap_coverage_df, config_coverage_df


def generate_summary_heatmaps(df):
    """Shows the full benchmark x configuration surface in two figures."""
    heatmap_specs = [
        ('energy_norm', 'Normalized package energy'),
        ('time_norm', 'Normalized execution time'),
    ]

    column_order = (
        df[['Frequency (MHz)', 'CPU Frequency (MHz)', 'Heap Multiplier Value', 'Config Label']]
        .drop_duplicates()
        .sort_values(['Frequency (MHz)', 'Heap Multiplier Value'])
    )
    ordered_columns = column_order['Config Label'].tolist()
    benchmarks = sorted(df['Benchmark'].unique())

    fig, axes = plt.subplots(len(heatmap_specs), 1, figsize=(22, 12), constrained_layout=True)
    if len(heatmap_specs) == 1:
        axes = [axes]

    for ax, (metric_col, title) in zip(axes, heatmap_specs):
        pivot = (
            df.pivot_table(index='Benchmark', columns='Config Label', values=metric_col, aggfunc='first')
            .reindex(index=benchmarks, columns=ordered_columns)
        )
        finite_values = pivot.to_numpy().ravel()
        finite_values = finite_values[pd.notna(finite_values)]
        vmax = max(float(pd.Series(finite_values).quantile(0.95)), 1.2) if len(finite_values) else 1.2

        sns.heatmap(
            pivot,
            ax=ax,
            cmap='viridis',
            mask=pivot.isna(),
            norm=LogNorm(vmin=1.0, vmax=vmax),
            linewidths=0.2,
            cbar_kws={'label': title},
        )
        ax.set_title(f'{title} across benchmarks, frequencies, and heap multipliers')
        ax.set_xlabel('Frequency / relative heap')
        ax.set_ylabel('Benchmark')
        ax.tick_params(axis='x', rotation=90)
        ax.tick_params(axis='y', rotation=0)

    fig.suptitle(
        'Whole-study heatmaps (each cell divided by the best value for that benchmark)',
        y=1.02,
    )
    fig.text(
        0.5,
        0.01,
        'Blank cells indicate configurations that were not measured for that benchmark.',
        ha='center',
        fontsize=10,
    )
    output_path = SUMMARY_OUTPUT_DIR / 'summary_heatmaps.png'
    fig.savefig(output_path, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Generated {output_path}")


def generate_tie_coverage_plot(frequency_coverage_df, heap_coverage_df):
    """Shows distinct-benchmark coverage by frequency and by heap."""
    objective_order = ['Energy', 'Time', 'EDP', 'EDP2']
    freq_labels = (
        frequency_coverage_df[['Frequency (MHz)', 'CPU Frequency (MHz)']]
        .drop_duplicates()
        .sort_values('Frequency (MHz)')
    )['CPU Frequency (MHz)'].tolist()
    heap_labels = (
        heap_coverage_df[['Heap Multiplier Value', 'Heap Label']]
        .drop_duplicates()
        .sort_values('Heap Multiplier Value')
    )['Heap Label'].tolist()

    freq_pivot = (
        frequency_coverage_df.pivot(index='Objective', columns='CPU Frequency (MHz)', values='Benchmark_Coverage')
        .reindex(index=objective_order, columns=freq_labels)
        .fillna(0)
    )
    heap_pivot = (
        heap_coverage_df.pivot(index='Objective', columns='Heap Label', values='Benchmark_Coverage')
        .reindex(index=objective_order, columns=heap_labels)
        .fillna(0)
    )

    fig, axes = plt.subplots(2, 1, figsize=(12, 8), constrained_layout=True)

    sns.heatmap(
        freq_pivot,
        ax=axes[0],
        cmap='Greens',
        annot=True,
        fmt='.0f',
        linewidths=0.4,
        cbar_kws={'label': 'Benchmarks covered'},
    )
    axes[0].set_title('Tie-set benchmark coverage by frequency')
    axes[0].set_xlabel('CPU frequency')
    axes[0].set_ylabel('Objective')
    axes[0].tick_params(axis='x', rotation=45)
    axes[0].tick_params(axis='y', rotation=0)

    sns.heatmap(
        heap_pivot,
        ax=axes[1],
        cmap='Purples',
        annot=True,
        fmt='.0f',
        linewidths=0.4,
        cbar_kws={'label': 'Benchmarks covered'},
    )
    axes[1].set_title('Tie-set benchmark coverage by heap multiplier')
    axes[1].set_xlabel('Heap multiplier')
    axes[1].set_ylabel('Objective')
    axes[1].tick_params(axis='x', rotation=0)
    axes[1].tick_params(axis='y', rotation=0)

    output_path = SUMMARY_OUTPUT_DIR / 'summary_tie_coverage.png'
    fig.savefig(output_path, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Generated {output_path}")


def main():
    os.makedirs(RAW_OUTPUT_DIR, exist_ok=True)
    os.makedirs(SUMMARY_OUTPUT_DIR, exist_ok=True)

    try:
        df = pd.read_csv(INPUT_FILE)
    except FileNotFoundError:
        print(f"Error: File {INPUT_FILE} not found.")
        return

    df = prepare_dataframe(df)
    generate_benchmark_plots(df)
    tie_df, objective_df, benchmark_df, frequency_coverage_df, heap_coverage_df, config_coverage_df = build_tie_tables(df)
    generate_summary_heatmaps(df)
    generate_tie_coverage_plot(frequency_coverage_df, heap_coverage_df)

    print(f"Generated {len(benchmark_df)} benchmark tie summaries")
    print(f"\nAll graphs generated in {PROJECT_ROOT / 'graphs'}")


if __name__ == "__main__":
    main()
