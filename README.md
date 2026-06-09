# Overhead de Containerização Docker: Windows/WSL2 vs macOS

Scripts de benchmark e dados brutos do artigo *"Overhead de Containerização Docker em
Ambientes de Desenvolvimento: Uma Análise Comparativa entre Windows/WSL2 e macOS"*
(Maria Augusta da Fonte, CESAR School).

O trabalho mede o overhead introduzido pelo Docker em relação à execução nativa, em duas
plataformas de desenvolvimento, usando três benchmarks de código aberto: **sysbench**
(memória), **fio** (I/O de disco) e **hyperfine** (tempo de startup de container).

## Ambientes avaliados

| | Ambiente A | Ambiente B |
|---|---|---|
| SO | Windows 11 + WSL2 (kernel 6.6.87.2) | macOS 15.7.4 |
| CPU | AMD Ryzen 5 8640HS (x86_64, 6C/12T) | Apple M4 (ARM, 4P+6E) |
| RAM | 8 GB (3,5 GB no WSL2) | 16 GB (Unified Memory) |
| Disco | 1007 GB | 256 GB SSD NVMe |
| Docker | 29.1.3 | Desktop 4.62.0 (Engine 29.2.1) |

> A métrica de CPU não é comparada entre plataformas devido à incompatibilidade
> arquitetural x86_64 vs ARM.

## Pré-requisitos

```bash
# Linux / WSL2
sudo apt install sysbench fio
cargo install hyperfine   # ou: sudo apt install hyperfine

# macOS
brew install sysbench fio hyperfine

# Docker em ambas as plataformas
docker --version
```

## Como reproduzir

Em cada ambiente, rode a suíte de forma nativa e dentro de um container:

```bash
# Execução nativa (no host)
./scripts/run_benchmarks.sh native

# Execução containerizada
docker run --rm -v "$PWD":/work -w /work \
  alpine sh -c "apk add --no-cache sysbench fio && ./scripts/run_benchmarks.sh docker"
```

Cada benchmark roda **9 vezes** (1 warm-up descartado); média e desvio padrão são
calculados a partir das saídas em `results/`.

Comandos individuais usados no artigo:

```bash
# Memória
sysbench memory --memory-block-size=1K --memory-total-size=10G --memory-oper=write run
sysbench memory --memory-block-size=1K --memory-total-size=10G --memory-oper=read  run

# I/O de disco
fio --rw=read      --bs=1M --size=512M --runtime=30
fio --rw=write     --bs=1M --size=512M --runtime=30
fio --rw=randread  --bs=4K --size=512M --runtime=30
fio --rw=randwrite --bs=4K --size=512M --runtime=30

# Startup de container
hyperfine --warmup 1 --runs 9 'docker run --rm alpine echo ok'
```

## Estrutura

```
.
├── README.md
├── LICENSE
├── artigo.pdf               # versão final do artigo
├── scripts/
│   └── run_benchmarks.sh    # executa as três suítes e salva em results/
├── data/                    # dados consolidados das tabelas (CSV)
│   ├── memoria.csv
│   ├── io_disco.csv
│   └── startup.csv
└── results/                 # saídas brutas das execuções (sysbench/fio/hyperfine)
```

## Principais resultados

- **WSL2:** overhead próximo de zero em memória e disco sequencial; escrita aleatória
  containerizada acima da nativa (atribuída ao OverlayFS).
- **macOS:** overhead modesto em memória/I-O aleatório; I/O sequencial muito acima do
  nativo (caching agressivo do FS virtualizado); startup de container **4,7x** mais
  rápido que no WSL2 (156 ms vs 733 ms).

> Valores em que o container supera o nativo refletem caching/variação entre execuções,
> não aceleração real de hardware.

## Dados brutos

Os valores reportados nas tabelas do artigo estão em `data/` (formato CSV):

| Arquivo | Conteúdo | Tabela no artigo |
|---|---|---|
| `data/memoria.csv` | Bandwidth de memória (sysbench) | Tabela 1 |
| `data/io_disco.csv` | I/O de disco sequencial e aleatório (fio) | Tabela 2 |
| `data/startup.csv` | Tempo de startup de container (hyperfine) | Tabela 3 |

As saídas brutas das execuções individuais (9 runs por benchmark) devem ser
salvas em `results/` ao rodar `scripts/run_benchmarks.sh`.

## Licença

MIT.
