import socket
import subprocess
from urllib.parse import urlparse
import os


def get_ip():
    # From https://stackoverflow.com/a/28950776
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0)
    try:
        # doesn't even have to be reachable
        s.connect(("8.8.8.8", 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = "127.0.0.1"
    finally:
        s.close()
    return IP


tools = {
    "wget": 'wget -d --no-passive-ftp --tries=2 --progress=dot:giga -O {filename} "{url}"',
    "curl": 'curl -v -L --max-time 300 "{url}" -o "{filename}"',
    "lftp": 'lftp -d -e "set net:max-retries 1; set net:persist-retries 0; set dns:max-retries 1; net:timeout 5; get {filepath} -o {filename}; bye" {server}',
}

urls = {
        "https": "https://www.arb-silva.de/fileadmin/silva_databases/release_138_1/Exports/SILVA_138.1_LSURef_NR99_tax_silva.fasta.gz",
        "https_ftpsite": "https://ftp.arb-silva.de/release_138_1/Exports/SILVA_138.1_LSURef_NR99_tax_silva.fasta.gz",
        "ftp": "ftp://ftp.arb-silva.de/release_138_1/Exports/SILVA_138.1_LSURef_NR99_tax_silva.fasta.gz",
}
results = []

for tool, cmd in tools.items():
    for url_name, url in urls.items():
        parsed = urlparse(url)
        filepath = parsed.path
        server = parsed.netloc
        protocol = parsed.scheme
        filename = f"{tool}_{url_name}.fastq.gz"
        filled_cmd= cmd.format(cmd, url=url, filename=filename, filepath=filepath, server=server)
        print(f"#### {url}")
        print(f"#### {filled_cmd}")
        p = subprocess.run(filled_cmd, universal_newlines=True, shell=True)

        result = {}
        result['exitcode_0'] = p.returncode == 0
        result['size'] = os.stat(filename).st_size if os.path.exists(filename) else 0
        result['tool'] = tool
        result['cmd'] = cmd
        result['url'] = url
        result['protocol'] = protocol
        result['ip'] = get_ip()
        results.append(result)


pandas.DataFrame(results).to_csv("output.tsv", sep="\t")
