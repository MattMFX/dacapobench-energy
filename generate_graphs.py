import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Configuration
INPUT_FILE = 'benchmarks/energy_stats.csv'
OUTPUT_DIR = 'benchmarks/graphs'

def parse_heap_size(heap_str):
    """Parses heap size string (e.g., '100m') to integer MB."""
    if pd.isna(heap_str):
        return 0
    heap_str = str(heap_str).lower()
    if heap_str.endswith('m'):
        return int(heap_str[:-1])
    elif heap_str.endswith('g'):
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
    elif freq_str.endswith('MHz'):
        return float(freq_str[:-3])
    else:
        try:
            return float(freq_str)
        except ValueError:
            return 0.0

def get_heap_multiplier(heap_val, min_heap):
    """Calculates heap multiplier (e.g., 1x, 2x)."""
    if min_heap == 0:
        return "Unknown"
    mult = heap_val / min_heap
    # Return formatted string (e.g., "1x", "2x")
    # If it's close to an integer, return as integer
    if abs(mult - round(mult)) < 0.1:
        return f"{int(round(mult))}x"
    else:
        return f"{mult:.1f}x"

def main():
    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Load data
    try:
        df = pd.read_csv(INPUT_FILE)
    except FileNotFoundError:
        print(f"Error: File {INPUT_FILE} not found.")
        return

    # Preprocess Data
    # Convert 'Heap Size' to numeric MB for sorting/calculation
    df['Heap Size MB'] = df['Heap Size'].apply(parse_heap_size)
    
    # Get list of unique benchmarks
    benchmarks = df['Benchmark'].unique()

    for benchmark in benchmarks:
        bench_df = df[df['Benchmark'] == benchmark].copy()
        
        if bench_df.empty:
            continue

        # Calculate Heap Size Multipliers
        min_heap = bench_df['Heap Size MB'].min()
        bench_df['Heap Label'] = bench_df['Heap Size MB'].apply(
            lambda x: get_heap_multiplier(x, min_heap)
        )
        
        # Convert Frequency to MHz
        bench_df['Frequency (MHz)'] = bench_df['CPU Frequency (MHz)'].apply(parse_frequency)
        
        # Sort for consistent plotting
        bench_df = bench_df.sort_values(by=['Frequency (MHz)', 'Heap Size MB'])

        # Define plots to generate
        plot_configs = [
            {
                'y_col': 'EDP Mean',
                'y_label': 'EDP (J⋅s)',
                'ci_low': 'EDP CI 95% Low',
                'ci_high': 'EDP CI 95% High',
                'title': f'{benchmark} - EDP vs Frequency',
                'filename': f'{benchmark}_edp.png'
            },
            {
                'y_col': 'EDP2 Mean',
                'y_label': 'E²DP (J²⋅s)',
                'ci_low': 'EDP2 CI 95% Low',
                'ci_high': 'EDP2 CI 95% High',
                'title': f'{benchmark} - E²DP vs Frequency',
                'filename': f'{benchmark}_edp2.png'
            },
            {
                'y_col': 'Package Joules Mean',
                'y_label': 'Energy (Joules)',
                'ci_low': 'Package Joules CI 95% Low',
                'ci_high': 'Package Joules CI 95% High',
                'title': f'{benchmark} - Energy vs Frequency',
                'filename': f'{benchmark}_energy.png'
            },
            {
                'y_col': 'Time Elapsed Mean (ms)',
                'y_label': 'Time (ms)',
                'ci_low': 'Elapsed Time CI 95% Low',
                'ci_high': 'Elapsed Time CI 95% High',
                'title': f'{benchmark} - Time vs Frequency',
                'filename': f'{benchmark}_time.png'
            }
        ]

        # Get sorted heap labels for consistent coloring
        heap_info = bench_df[['Heap Label', 'Heap Size MB']].drop_duplicates().sort_values('Heap Size MB')
        heap_order = heap_info['Heap Label'].tolist()
        
        # Create palette
        palette = sns.color_palette("tab10", len(heap_order))
        label_to_color = dict(zip(heap_order, palette))

        for config in plot_configs:
            plt.figure(figsize=(10, 6))
            
            # Create plot
            # We want a line for each Heap Size (Heap Label)
            sns.lineplot(
                data=bench_df,
                x='Frequency (MHz)',
                y=config['y_col'],
                hue='Heap Label',
                hue_order=heap_order,
                palette=label_to_color,
                marker='o',
                style='Heap Label',
                style_order=heap_order
            )
            
            # Add Confidence Intervals
            for label in heap_order:
                subset = bench_df[bench_df['Heap Label'] == label].sort_values('Frequency (MHz)')
                if not subset.empty:
                    plt.fill_between(
                        subset['Frequency (MHz)'],
                        subset[config['ci_low']],
                        subset[config['ci_high']],
                        color=label_to_color[label],
                        alpha=0.15  # Tuned opacity (was 0.2)
                    )
            
            # Set Y-axis limit to exclude outliers (1x heap)
            non_outlier = bench_df[bench_df['Heap Label'] != '1x']
            if not non_outlier.empty:
                # Calculate max value from non-outlier data (considering CI if available)
                y_max = non_outlier[config['y_col']].max()
                if config['ci_high'] in non_outlier.columns:
                    ci_max = non_outlier[config['ci_high']].max()
                    if pd.notna(ci_max):
                        y_max = max(y_max, ci_max)
                
                if pd.notna(y_max) and y_max > 0:
                    plt.ylim(0, y_max * 1.1)

            plt.title(config['title'])
            plt.xlabel('Frequency (MHz)')
            plt.ylabel(config['y_label'])
            plt.grid(True, linestyle='--', alpha=0.7)
            plt.legend(title='Heap Size')
            
            # Save
            output_path = os.path.join(OUTPUT_DIR, config['filename'])
            plt.savefig(output_path)
            plt.close()
            print(f"Generated {output_path}")

    print(f"\nAll graphs generated in {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
