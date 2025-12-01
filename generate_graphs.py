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
        # Note: Assuming current data is in kHz as per CSV header
        bench_df['Frequency (MHz)'] = bench_df['CPU Frequency (kHz)'] / 1000.0

        # Sort for consistent plotting
        bench_df = bench_df.sort_values(by=['Frequency (MHz)', 'Heap Size MB'])

        # Define plots to generate
        plot_configs = [
            {
                'y_col': 'EDP Mean',
                'y_label': 'EDP (J⋅s)',
                'title': f'{benchmark} - EDP vs Frequency',
                'filename': f'{benchmark}_edp.png'
            },
            {
                'y_col': 'EDP2 Mean',
                'y_label': 'EDP² (J⋅s²)',
                'title': f'{benchmark} - EDP² vs Frequency',
                'filename': f'{benchmark}_edp2.png'
            }
        ]

        for config in plot_configs:
            plt.figure(figsize=(10, 6))
            
            # Create plot
            # We want a line for each Heap Size (Heap Label)
            sns.lineplot(
                data=bench_df,
                x='Frequency (MHz)',
                y=config['y_col'],
                hue='Heap Label',
                marker='o',
                style='Heap Label'
            )
            
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

