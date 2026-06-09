#!/usr/bin/env bash
# Suite de benchmarks: overhead de containerizacao Docker (WSL2 / macOS)
# Uso:
#   ./run_benchmarks.sh native   # roda no host (WSL2 ou macOS shell)
#   ./run_benchmarks.sh docker   # roda dentro de um container
set -euo pipefail

MODE="${1:-native}"
OUT="results/${MODE}_$(uname -s)_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
echo "==> Modo: $MODE | Saida: $OUT"

# ---------- Memoria (sysbench) ----------
echo "==> Memoria (sysbench, 10G)"
for op in write read; do
  sysbench memory --memory-block-size=1K --memory-total-size=10G \
    --memory-oper=$op run | tee "$OUT/mem_${op}.txt"
done

# ---------- I/O de disco (fio) ----------
echo "==> I/O de disco (fio, 512M, 30s)"
declare -A PATTERNS=( [read]=1M [write]=1M [randread]=4K [randwrite]=4K )
for rw in "${!PATTERNS[@]}"; do
  bs="${PATTERNS[$rw]}"
  fio --name=$rw --rw=$rw --bs=$bs --size=512M --runtime=30 --time_based \
    --ioengine=libaio --direct=1 --group_reporting \
    --output="$OUT/fio_${rw}.txt" || \
  fio --name=$rw --rw=$rw --bs=$bs --size=512M --runtime=30 --time_based \
    --group_reporting --output="$OUT/fio_${rw}.txt"
done

# ---------- Startup de container (hyperfine) ----------
# Roda apenas no host, pois mede 'docker run'
if [ "$MODE" = "native" ]; then
  echo "==> Startup de container (hyperfine, 9 runs)"
  hyperfine --warmup 1 --runs 9 'docker run --rm alpine echo ok' \
    --export-json "$OUT/startup.json" || echo "hyperfine/docker indisponivel"
fi

echo "==> Concluido. Resultados em $OUT"
