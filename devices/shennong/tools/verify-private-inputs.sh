#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
device_dir="$(cd -- "${script_dir}/.." && pwd)"
expected_bundle_sha256="028bb44b118651ba0ce746f71f3b303f90b21d378719eb606531d5837c9bded1"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 STOCK_A_DIRECTORY [KERNEL_BUNDLE.tar.zst]" >&2
    exit 2
fi

stock_dir="$(realpath "$1")"
[ -d "$stock_dir" ] || {
    echo "Stock directory does not exist: $stock_dir" >&2
    exit 1
}

echo "Verifying OS3.0.308.0 stock A-slot inputs..."
(
    cd "$stock_dir"
    sha256sum --check --strict \
        "$device_dir/reference/OS3.0.308.0-stock-a.sha256"
)

if [ "$#" -eq 2 ]; then
    kernel_bundle="$(realpath "$2")"
    actual_bundle_sha256="$(sha256sum "$kernel_bundle" | awk '{print $1}')"
    [ "$actual_bundle_sha256" = "$expected_bundle_sha256" ] || {
        echo "Kernel bundle hash mismatch." >&2
        echo "Expected: $expected_bundle_sha256" >&2
        echo "Actual:   $actual_bundle_sha256" >&2
        exit 1
    }
    echo "Kernel/module bundle: OK"
fi

echo "All supplied private inputs are verified."
