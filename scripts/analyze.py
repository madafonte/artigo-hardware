#!/usr/bin/env python3
"""
Analise estatistica dos benchmarks (roadmap: media +- DP, IC 95%, teste de hipotese).

Le os CSVs gerados por run_benchmarks.sh em results/{native,docker}_{OS}/ e produz:
  - data/estatisticas.csv  : media, DP, IC95, n por condicao
  - data/testes_hipotese.csv : t de Student (ou Wilcoxon) nativo vs docker
  - figs/*.png : graficos de barras COM barras de erro (IC 95%)

H0: nao ha diferenca de desempenho entre execucao nativa e containerizada.
H1: ha diferenca (teste bilateral), alfa = 0,05.

Requer: numpy, scipy, matplotlib, pandas  (pip install ...)
"""
import os, glob, csv
import numpy as np
import pandas as pd
from scipy import stats
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ALPHA = 0.05
RESULTS = "results"
os.makedirs("data", exist_ok=True)
os.makedirs("figs", exist_ok=True)

def ci95(x):
    x = np.asarray(x, float)
    n = len(x)
    if n < 2: return (np.mean(x), 0.0, 0.0)
    m, sd = np.mean(x), np.std(x, ddof=1)
    half = stats.t.ppf(1 - ALPHA/2, n-1) * sd / np.sqrt(n)
    return m, sd, half

def load(path):
    if not os.path.exists(path): return None
    df = pd.read_csv(path)
    col = df.columns[-1]
    return pd.to_numeric(df[col], errors="coerce").dropna().values

# Descobre ambientes pelos diretorios results/native_* e results/docker_*
envs = {}
for d in glob.glob(f"{RESULTS}/native_*"):
    os_tag = d.split("native_")[1]
    envs[os_tag] = {"native": d, "docker": d.replace("native_", "docker_")}

metrics = {
    "mem_write":  "Memoria escrita (MiB/s)",
    "mem_read":   "Memoria leitura (MiB/s)",
    "fio_read":   "Leitura sequencial (MiB/s)",
    "fio_write":  "Escrita sequencial (MiB/s)",
    "fio_randread":  "Leitura aleatoria (IOPS)",
    "fio_randwrite": "Escrita aleatoria (IOPS)",
}

stat_rows, test_rows = [], []
for os_tag, paths in envs.items():
    for key, label in metrics.items():
        nat = load(os.path.join(paths["native"], f"{key}.csv"))
        doc = load(os.path.join(paths["docker"], f"{key}.csv"))
        if nat is None or doc is None: continue
        for cond, arr in (("nativo", nat), ("docker", doc)):
            m, sd, half = ci95(arr)
            stat_rows.append([os_tag, label, cond, len(arr), round(m,2),
                              round(sd,2), round(m-half,2), round(m+half,2)])
        # teste de normalidade -> escolhe t ou Wilcoxon
        normal = (stats.shapiro(nat).pvalue > ALPHA and stats.shapiro(doc).pvalue > ALPHA)
        if normal:
            stat, p = stats.ttest_ind(nat, doc, equal_var=False); teste = "t de Student (Welch)"
        else:
            stat, p = stats.mannwhitneyu(nat, doc, alternative="two-sided"); teste = "Mann-Whitney"
        test_rows.append([os_tag, label, teste, round(stat,3), round(p,4),
                          "rejeita H0" if p < ALPHA else "nao rejeita H0"])

        # grafico com barras de erro
        mn, _, hn = ci95(nat); md, _, hd = ci95(doc)
        plt.figure(figsize=(4,3.2))
        plt.bar(["Nativo","Docker"], [mn, md], yerr=[hn, hd], capsize=6,
                color=["#4477AA","#EE6677"])
        plt.title(f"{label}\n({os_tag})", fontsize=9)
        plt.ylabel(label.split("(")[-1].rstrip(")"))
        plt.tight_layout()
        plt.savefig(f"figs/{os_tag}_{key}.png", dpi=150)
        plt.close()

with open("data/estatisticas.csv","w",newline="") as f:
    w = csv.writer(f); w.writerow(["ambiente","metrica","condicao","n","media","desvio_padrao","ic95_inf","ic95_sup"])
    w.writerows(stat_rows)
with open("data/testes_hipotese.csv","w",newline="") as f:
    w = csv.writer(f); w.writerow(["ambiente","metrica","teste","estatistica","p_valor","decisao_alfa_0.05"])
    w.writerows(test_rows)

print("OK -> data/estatisticas.csv, data/testes_hipotese.csv, figs/*.png")
print(f"Condicoes analisadas: {len(stat_rows)} | Testes: {len(test_rows)}")
