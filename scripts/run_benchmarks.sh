#!/usr/bin/env bash
# Suite de benchmarks com 30 repeticoes + estatistica (IC 95% e teste de hipotese)
# Atende ao roadmap: >=30 repeticoes por condicao, IC 95%, teste de hipotese.
#
# Uso:
#   ./run_benchmarks.sh native   # roda no host (WSL2 ou macOS)
#   ./run_benchmarks.sh docker   # roda dentro de um container
#
# Depois de rodar nos DOIS modos em cada ambiente, gere a analise:
#   python3 scripts/analyze.py
set -euo pipefail

MODE="${1:-native}"
RUNS="${RUNS:-30}"              # >= 30 conforme roadmap
WARMUP=2
OS="$(uname -s)"
OUT="results/${MODE}_${OS}"
mkdir -p "$OUT"
echo "==> Modo: $MODE | Repeticoes: $RUNS (+$WARMUP warm-up) | Saida: $OUT"

# ---------- Memoria (sysbench) ----------
echo "==> Memoria (sysbench, 10G)"
for op in write read; do
  echo "run,MiBps" > "$OUT/mem_${op}.csv"
  total=$((RUNS + WARMUP))
  for i in $(seq 1 $total); do
    val=$(sysbench memory --memory-block-size=1K --memory-total-size=10G \
          --memory-oper=$op run 2>/dev/null \
          | grep -i "transferred" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [ "$i" -gt "$WARMUP" ] && echo "$((i-WARMUP)),$val" >> "$OUT/mem_${op}.csv"
    echo "  mem $op $i/$total: ${val:-NA} MiB/s"
  done
done

# ---------- I/O de disco (fio) ----------
echo "==> I/O de disco (fio, 512M, 30s)"
declare -A PATTERNS=( [read]=1M [write]=1M [randread]=4K [randwrite]=4K )
for rw in "${!PATTERNS[@]}"; do
  bs="${PATTERNS[$rw]}"
  echo "run,value" > "$OUT/fio_${rw}.csv"
  total=$((RUNS + WARMUP))
  for i in $(seq 1 $total); do
    out=$(fio --name=$rw --rw=$rw --bs=$bs --size=512M --runtime=30 --time_based \
          --ioengine=libaio --direct=1 --group_reporting --minimal 2>/dev/null \
          || fio --name=$rw --rw=$rw --bs=$bs --size=512M --runtime=30 --time_based \
          --group_reporting --minimal 2>/dev/null)
    if [ "$i" -gt "$WARMUP" ]; then
      echo "$out" | awk -F';' -v rw="$rw" -v r=$((i-WARMUP)) '{
        if (rw ~ /rand/) { v = (rw=="randread") ? $8 : $49 }
        else             { v = (rw=="read")     ? $7/1024 : $48/1024 }
        printf "%d,%s\n", r, v
      }' >> "$OUT/fio_${rw}.csv"
    fi
    echo "  fio $rw $i/$total"
  done
done

# ---------- Startup de container (hyperfine) ----------
if [ "$MODE" = "native" ]; then
  echo "==> Startup de container (hyperfine, $RUNS runs)"
  hyperfine --warmup $WARMUP --runs $RUNS 'docker run --rm alpine echo ok' \
    --export-csv "$OUT/startup.csv" || echo "hyperfine/docker indisponivel"
fi

echo "==> Concluido. Rode: python3 scripts/analyze.py"
