#!/usr/bin/env python3

import argparse
import subprocess
import sys

PAGE_SIZE = 0x1000          # 4 KiB
BLOCK_SIZE = 0x100000       # 1 MiB
PFN_PER_BLOCK = BLOCK_SIZE // PAGE_SIZE  # 256

# Aman terhadap batas panjang command line
CHUNK_SIZE = 128


def parse_addr(addr):
    addr = addr.strip()
    if addr.lower().startswith("0x"):
        addr = addr[2:]
    return int(addr, 16)


def run(cmd):
    print(">", " ".join(cmd))
    subprocess.run(cmd, check=True)


parser = argparse.ArgumentParser(
    description="Blacklist 1 MiB RAM blocks into Windows BCD."
)
parser.add_argument(
    "address",
    nargs="+",
    help="Physical address(es), contoh: 1C9E00000 1D4200000"
)

args = parser.parse_args()

# Kumpulkan seluruh PFN
pfns = set()

for a in args.address:
    addr = parse_addr(a)

    if addr % PAGE_SIZE != 0:
        print(f"Warning: {a} bukan kelipatan 4 KiB.")

    start_pfn = addr >> 12

    for i in range(PFN_PER_BLOCK):
        pfns.add(start_pfn + i)

pfns = sorted(pfns)

try:
    # Enable badmemory
    run([
        "bcdedit",
        "/set",
        "{badmemory}",
        "badmemoryaccess",
        "no"
    ])

    # Tambahkan PFN
    for i in range(0, len(pfns), CHUNK_SIZE):
        chunk = pfns[i:i + CHUNK_SIZE]

        cmd = [
            "bcdedit",
            "/set",
            "{badmemory}",
            "badmemorylist",
        ]

        cmd.extend(f"0x{x:X}" for x in chunk)

        run(cmd)

    print("\nSelesai.")
    print("Restart Windows agar perubahan berlaku.")

except subprocess.CalledProcessError:
    print("\nERROR:")
    print("Pastikan Command Prompt / Terminal dijalankan sebagai Administrator.")
    sys.exit(1)