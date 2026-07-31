# Football Birthday Paradox

Análise do paradoxo do aniversário nas escalações do Brasileirão Série A (2018–2025). O projeto compara a hipótese clássica — aniversários independentes e uniformes em 365 dias — com a distribuição observada entre jogadores profissionais.

## Estrutura

- `notebooks/01_data_collection.ipynb`: coleta, limpeza e seleção das escalações.
- `notebooks/02_birthday_analysis.ipynb`: análise combinatória, distribuição dos nascimentos, comparação estatística e visualizações.
- `data/brasileirao_serie_a_2018_2025/`: dados coletados (gerados pelo notebook 01).
- `data/analysis/`: tabelas e figuras da análise (geradas pelo notebook 02).

## Execução

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m jupyter lab
```

Execute os notebooks na ordem `01 → 02`. A análise principal considera os 22 titulares de cada partida; o grupo de 23 jogadores é apresentado separadamente para comparação direta com o enunciado clássico do paradoxo.

## Escopo

Os resultados descrevem as partidas cobertas pela base. A distribuição empírica é tratada como um modelo de referência, não como prova causal de que o efeito da idade relativa explica sozinho as coincidências observadas.
