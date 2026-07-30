# Football Birthday Paradox

Aplica o clássico [paradoxo do aniversário](https://en.wikipedia.org/wiki/Birthday_problem) às escalações do Brasileirão Série A entre 2020 e 2025: em quantas partidas, entre os 23 jogadores relacionados (22 titulares + 1 reserva sorteado), pelo menos dois compartilham o mesmo dia e mês de nascimento?

## Resultado

Em **2.268** partidas analisadas, **1.314** (57,9%) tiveram ao menos um par de aniversariantes — acima da probabilidade teórica de 50,7% para grupos de 23 pessoas.

| Temporada | Partidas | Com aniversário compartilhado | Probabilidade observada |
|---|---|---|---|
| 2020 | 380 | 197 | 51,8% |
| 2021 | 376 | 213 | 56,6% |
| 2022 | 377 | 215 | 57,0% |
| 2023 | 376 | 230 | 61,2% |
| 2024 | 379 | 231 | 60,9% |
| 2025 | 380 | 228 | 60,0% |

Detalhes completos em [data/analysis/](data/analysis/).

## Estrutura

```
notebooks/
  01_data_collection.ipynb   # coleta as escalações e datas de nascimento
  02_birthday_analysis.ipynb # aplica o paradoxo do aniversário e exporta a análise
data/
  raw/                       # cache de HTML raspado do Transfermarkt (gerado localmente, não versionado)
  brasileirao_2020_2025/     # partidas, escalações e jogadores extraídos
  analysis/                  # resultado do paradoxo do aniversário, por partida e por temporada
```

## Fonte dos dados

As escalações combinam o dataset público [transfermarkt-datasets](https://github.com/dcaribou/transfermarkt-datasets) (temporada 2025) com súmulas raspadas diretamente do [Transfermarkt](https://www.transfermarkt.com) para 2020–2024. O uso é apenas para fins de análise/pesquisa; os dados brutos permanecem sujeitos aos termos do próprio Transfermarkt.

## Como rodar

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

jupyter lab notebooks/01_data_collection.ipynb   # coleta os dados (grava em data/raw/ e data/brasileirao_2020_2025/)
jupyter lab notebooks/02_birthday_analysis.ipynb # gera a análise em data/analysis/
```

O notebook `01` faz cache do HTML raspado em `data/raw/` — reexecutar não repete downloads já feitos, a menos que `REFRESH_HTML` seja habilitado.
