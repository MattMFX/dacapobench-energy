import argparse
import pandas as pd
import numpy as np
from scipy.stats import bootstrap
from pathlib import Path

# Configuration
PROJECT_ROOT = Path(__file__).resolve().parent.parent
INPUT_FILE = PROJECT_ROOT / 'data' / 'energy.csv'
OUTPUT_FILE = PROJECT_ROOT / 'data' / 'energy_stats.csv'
DEFAULT_INPUT_FILE = str(INPUT_FILE)
DEFAULT_OUTPUT_FILE = str(OUTPUT_FILE)
N_BOOTSTRAP = 1000
CONFIDENCE = 0.95


def parse_args():
    parser = argparse.ArgumentParser(
        description='Process energy benchmark CSV and compute statistics (mean, CI).'
    )
    parser.add_argument(
        '-i', '--input',
        default=DEFAULT_INPUT_FILE,
        metavar='CSV',
        help=f'Input energy CSV file (default: {DEFAULT_INPUT_FILE})',
    )
    parser.add_argument(
        '-o', '--output',
        default=DEFAULT_OUTPUT_FILE,
        metavar='CSV',
        help=f'Output stats CSV file (default: {DEFAULT_OUTPUT_FILE})',
    )
    return parser.parse_args()

def get_ci(data):
    """Calculates the confidence interval of the mean using bootstrap."""
    if len(data) < 2:
        return pd.Series([data.mean(), data.mean(), data.mean()], index=['mean', 'ci_low', 'ci_high'])
    
    res = bootstrap((data,), np.mean, confidence_level=CONFIDENCE, n_resamples=N_BOOTSTRAP, method='percentile')
    return pd.Series([data.mean(), res.confidence_interval.low, res.confidence_interval.high], index=['mean', 'ci_low', 'ci_high'])

def main():
    args = parse_args()
    input_file = args.input
    output_file = args.output

    try:
        # Load data
        df = pd.read_csv(input_file)
    except FileNotFoundError:
        print(f"Error: File {input_file} not found.")
        return

    # Filter warmup = false
    # Convert string 'false'/'true' to boolean if necessary, or just compare strings
    # Check if 'warmup' is string or boolean in the CSV loaded by pandas
    # Inspecting the file content provided earlier, it looks like "true"/"false" strings.
    # Pandas might infer boolean, but let's be safe.
    if df['warmup'].dtype == object:
        df = df[df['warmup'].str.lower() == 'false'].copy()
    else:
         df = df[df['warmup'] == False].copy()

    # Calculate derived metrics
    # Time in seconds
    df['time_s'] = df['elapsed_ms'] / 1000.0
    
    # EDP = Package Joules * Time
    df['edp'] = df['package_j'] * df['time_s']
    
    # EDP2 = Package Joules^2 * Time (Giving energy greater weight)
    df['edp2'] = (df['package_j'] ** 2) * df['time_s']

    # Columns to analyze
    metrics = {
        'elapsed_ms': 'Elapsed Time',
        'dram_j': 'DRAM Joules',
        'cpu_j': 'CPU Joules',
        'package_j': 'Package Joules',
        'edp': 'EDP',
        'edp2': 'EDP2'
    }

    # Grouping columns
    group_cols = ['benchmark', 'heap_size', 'cpu_freq_mhz']
    
    # Result storage
    results = []

    # Group by
    grouped = df.groupby(group_cols)

    for name, group in grouped:
        benchmark, heap_size, cpu_freq_mhz = name
        
        row = {
            'Benchmark': benchmark,
            'Heap Size': heap_size,
            'CPU Frequency (MHz)': cpu_freq_mhz
        }
        
        for metric_col, metric_name in metrics.items():
            stats = get_ci(group[metric_col].values)
            row[f'{metric_name} Mean'] = stats['mean']
            
            # Special handling for units if needed, but request asked for specific names
            # "Time Elapsed Mean", "DRAM joules mean", etc.
            # Adjusting keys to match request exactly
            
            if metric_col == 'elapsed_ms':
                row['Time Elapsed Mean (ms)'] = stats['mean']
                row['Elapsed Time CI 95% Low'] = stats['ci_low']
                row['Elapsed Time CI 95% High'] = stats['ci_high']
            elif metric_name == 'EDP':
                 row['EDP Mean'] = stats['mean']
                 row['EDP CI 95% Low'] = stats['ci_low']
                 row['EDP CI 95% High'] = stats['ci_high']
            elif metric_name == 'EDP2':
                 row['EDP2 Mean'] = stats['mean']
                 row['EDP2 CI 95% Low'] = stats['ci_low']
                 row['EDP2 CI 95% High'] = stats['ci_high']
            else:
                # Generic handling for Joules
                row[f'{metric_name} Mean'] = stats['mean']
                row[f'{metric_name} CI 95% Low'] = stats['ci_low']
                row[f'{metric_name} CI 95% High'] = stats['ci_high']

        results.append(row)

    # Create result DataFrame
    result_df = pd.DataFrame(results)
    
    # Sort
    result_df = result_df.sort_values(by=['Benchmark', 'Heap Size', 'CPU Frequency (MHz)'])
    
    # Select and Reorder columns to match requirements
    columns_order = [
        'Benchmark', 'Heap Size', 'CPU Frequency (MHz)',
        'Time Elapsed Mean (ms)', 
        'DRAM Joules Mean', 
        'CPU Joules Mean', 
        'Package Joules Mean',
        'Elapsed Time CI 95% Low', 'Elapsed Time CI 95% High',
        'DRAM Joules CI 95% Low', 'DRAM Joules CI 95% High',
        'CPU Joules CI 95% Low', 'CPU Joules CI 95% High',
        'Package Joules CI 95% Low', 'Package Joules CI 95% High',
        'EDP Mean', 'EDP CI 95% Low', 'EDP CI 95% High',
        'EDP2 Mean', 'EDP2 CI 95% Low', 'EDP2 CI 95% High'
    ]
    
    # Ensure all columns exist (in case some were missed in logic, though they shouldn't be)
    # This reindex will put NaNs if something is missing, which is better than crashing, but we want to be correct.
    result_df = result_df[columns_order]

    # Write to CSV
    result_df.to_csv(output_file, index=False)
    print(f"Successfully created {output_file}")

if __name__ == "__main__":
    main()
