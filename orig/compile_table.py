#!/usr/bin/env python3
import subprocess
import re
import pandas as pd
import sys
from pathlib import Path

def run_bash_script(bash_script, input_tsv):
    """Run the bash script and return the log file path."""
    try:
        print(f"Running bash script: {bash_script}\n")
        print("=" * 70)

        process = subprocess.Popen(
            ['bash', bash_script, input_tsv],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        # Stream output in real-time
        for line in process.stdout:
            print(line, end='')

        # Wait for process to complete
        return_code = process.wait()

        print("=" * 70)

        if return_code != 0:
            print(f"\nWarning: Bash script exited with code {return_code}")
        else:
            print(f"\nBash script completed successfully\n")

        return 'results.log'  # The log file created by bash script

    except Exception as e:
        print(f"Error running bash script: {e}")
        sys.exit(1)

def parse_log_file(log_file):
    """Parse the log file and extract structured data."""
    records = []

    with open(log_file, 'r') as f:
        content = f.read()

    # Our results.log file has different commands separated by the pattern below,
    # so we can split up our 'sections' of different commands using this pattern
    sections = re.split(r'#{10,}\s*\n\s*#\s*REPORTING RESULTS OF DOWNLOAD ATTEMPT\s*#\s*\n\s*#{10,}', content)


    for section in sections:
        if not section.strip():
            continue


        current_record = {}

        # Go through all reported results and add them to our table
        for line in section.split('\n'):
            line = line.strip()
            if line.startswith('Command:'):
                current_record['Full Command'] = line.replace('Command:', '').strip()
            elif line.startswith('Tool:'):
                current_record['Tool'] = line.replace('Tool:', '').strip()
            elif line.startswith('URL:'):
                current_record['URL'] = line.replace('URL:', '').strip()
            elif line.startswith('IP:'):
                current_record['IP'] = line.replace('IP:', '').strip()
            elif line.startswith('Timestamp:'):
                current_record['Timestamp'] = line.replace('Timestamp:', '').strip()
            elif line.startswith('File Size:'):
                current_record['File Size'] = line.replace('File Size:', '').strip()
            elif line.startswith('Status:'):
                current_record['Status'] = line.replace('Status:', '').strip()
            elif line.startswith('Error Message:'):
                current_record['Error Message'] = line.replace('Error Message:', '').strip()

        # When we have all required fields, save the record
        if 'Tool' in current_record and 'Status' in current_record:
            records.append(current_record)

    return records

def create_dataframe(records):
    """Create a pandas DataFrame from the parsed records."""
    if not records:
        print("No records found in log file")
        return pd.DataFrame()

    df = pd.DataFrame(records)

    # Extract just protocol and server from URL
    if 'URL' in df.columns:
        df['URL'] = df['URL'].str.extract(r'^([a-z]+://[^/]+)', expand=False)

    # Ensure columns are in the desired order
    column_order = ['Tool', 'URL', 'Status', 'Error Message', 'IP', 'Time Stamp', 'File Size','Full Command']

    # Only include columns that exist
    existing_columns = [col for col in column_order if col in df.columns]
    df = df[existing_columns]

    return df

def main():
    if len(sys.argv) < 1:
        print("Usage: python parse_results.py <input.tsv> [bash_script.sh] [output.tsv]")
        print("  input.tsv: TSV file with URLs and tools")
        print("  bash_script.sh: Path to bash script (default: download_script.sh)")
        print("  output.tsv: Output TSV file (default: download_results.tsv)")
        sys.exit(1)

    input_tsv = sys.argv[1] if len(sys.argv) > 1 else 'inputs.tsv'
    bash_script = sys.argv[2] if len(sys.argv) > 2 else 'run_combinations.sh'
    output_tsv = sys.argv[3] if len(sys.argv) > 3 else 'results.tsv'

    # Check if input file exists
    if not Path(input_tsv).exists():
        print(f"Error: Input file '{input_tsv}' not found")
        sys.exit(1)

    # Check if bash script exists
    if not Path(bash_script).exists():
        print(f"Error: Bash script '{bash_script}' not found")
        sys.exit(1)

    print(f"Running bash script: {bash_script}")
    print(f"Input TSV: {input_tsv}")
    print("-" * 50)

    # Run the bash script
    results_log_file = run_bash_script(bash_script, input_tsv)

    print(f"\nParsing log file: {results_log_file}")

    # Parse the log file
    records = parse_log_file(results_log_file)

    print(f"Found {len(records)} download attempts")

    # Create DataFrame
    df = create_dataframe(records)

    if df.empty:
        print("No data to write")
        sys.exit(1)

    # Save to TSV
    df.to_csv(output_tsv, sep='\t', index=False)

    print(f"\nResults saved to: {output_tsv}")
    print(f"\nSummary:")
    print(f"  Total attempts: {len(df)}")
    if 'Status' in df.columns:
        print(f"  Successful: {(df['Status'] == 'Success').sum()}")
        print(f"  Failed: {(df['Status'] == 'Failure').sum()}")

    print("\nFirst few rows:")
    print(df.head().to_string())

if __name__ == '__main__':
    main()
