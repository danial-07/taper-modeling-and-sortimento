# Data Challenge 05 — Taper Modeling and Product Assortment (Sortimento)

Stand 8, eucalyptus plantation. Two stages, sharing one functions file.

```
desafio-05-taper-e-sortimento/
├── data/
│   ├── cubagem.xlsx              # 36-tree rigorous cubage (Stage 1 input)
│   └── inventa_rio.xlsx          # 215-tree inventory (Stage 2 input)
├── scripts/
│   ├── 00_funcoes_desafio05.R    # shared functions (sourced by both stages)
│   ├── 01_etapa1_ajuste_taper.R  # Stage 1: fit + compare 3 taper models
│   └── 02_etapa2_sortimento.R    # Stage 2: sortimento estimation, 3 models
├── outputs/
│   ├── ajuste_taper.csv
│   ├── sortimento_por_modelo.csv
│   ├── comparacao_sortimento.csv
│   ├── comparacao_sortimento.png
│   ├── residuos_perfil_fuste.png
│   ├── residuos_por_classe_dap.png
│   ├── modelos_taper.rds
│   └── sortimento_detalhe_arvore.xlsx
├── report/
│   └── short_report_desafio05.md
└── README.md   (this file)
```

## Stage 1 — Taper model formulations 

All three models were fit with `lm()` on the pooled cubagem dataset:
**1,125 measured sections from the 36 cubed trees**, using the relative
height `Z = hi/HT` (0 at the base, 1 at the treetop).

### Kozak (1969) — 2nd-degree polynomial
```
(di/DAP)² = b0 + b1·Z + b2·Z²
```
Fit on the response `(di/DAP)²`. This is the simplest of the three models:
a single parabola describing the whole stem profile in one piece. It is
included as the "baseline" model the other two are compared against.

### Schöpfer (1966) — 5th-degree polynomial
```
di/DAP = b0 + b1·Z + b2·Z² + b3·Z³ + b4·Z⁴ + b5·Z⁵
```
Fit directly on the ratio `di/DAP` (not squared). The extra degrees of
freedom let it follow the classic neiloid-parabolic-conic shape of a real
stem (concave near the base, roughly straight in the mid-stem, convex near
the top) far more closely than Kozak's single parabola.

### Hradetzky (1976) — fractional/integer power polynomial
```
di/DAP = b1·Z^0.1 + b2·Z^0.5 + b3·Z + b4·Z² + b5·Z³ + b6·Z⁵ + b7·Z⁸
```
**Exponents adopted: 0.1, 0.5, 1, 2, 3, 5, 8** (the example set given in the
assignment sheet). Fit **without an intercept** — this is standard practice
for Hradetzky's model in the Brazilian forestry literature. Why these
exponents:
- The two fractional exponents (0.1, 0.5) let the curve bend sharply right
  at the base, capturing butt flare (the swelling seen in several of our
  cubed trees, where `di/DAP` exceeds 1.0 in the first section) without
  needing a high-degree polynomial to do it.
- The higher integer exponents (3, 5, 8) let the curve flatten out
  correctly in the upper stem, where the taper rate genuinely slows down.
- Because the exponents are fixed (not estimated), the model stays a
  simple linear regression — no nonlinear optimizer needed — while still
  being far more flexible near the base than Schöpfer's single 5th-degree
  polynomial, which has to compromise between the base and the tip with
  the same set of powers.

### Evaluation metrics and model selection

| Model | R² | R² adjusted | Syx% |
|---|---|---|---|
| Kozak | 0.9489 | 0.9488 | 14.59% |
| Schöpfer | 0.9855 | 0.9854 | 4.81% |
| **Hradetzky** | **0.9875** | **0.9874** | **4.48%** |

*(Kozak's Syx% is on the `(di/DAP)²` scale and Schöpfer/Hradetzky's on the
`di/DAP` scale — the two are not numerically comparable on the same axis,
but R²/R²adj are, and both tell the same story as Syx% here.)*

**Hradetzky (1976) was selected as the Stage-1 reference model.** It has
the lowest Syx% and highest R²/R²adj of the three, and — checked visually
via `residuos_perfil_fuste.png` and `residuos_por_classe_dap.png` — its
residuals are the most evenly scattered around zero across the full stem
profile, including the base sections where Kozak's single parabola
systematically under- or over-predicts diameter. Schöpfer is a close
second and is carried forward into Stage 2 alongside Kozak for comparison,
exactly as the assignment requires ("apply the three models, not just the
best one").

## Stage 2 — Sortimento methodology

1. **Missing heights** (106 of the 215 inventory trees) are filled with the
   Challenge 02 log-log hypsometric model, Baskerville-corrected
   (`ln(HT) = 1.404 + 0.689·ln(DAP)`, correction factor 1.0011). Edit
   `HIPSO_B0` / `HIPSO_B1` / `HIPSO_FC` at the top of
   `02_etapa2_sortimento.R` if your own Challenge 02 numbers differ.
2. **Stump height 0.10 m**: segmentation starts at 0.10 m; the 0–0.10 m
   stump itself is excluded from every tally (it is cut off and left in
   the field — neither a product log nor "residual" stem volume).
3. **Segmentation**: fixed 2.20 m logs, starting at 0.10 m, using the
   taper function (not interpolation) to get the diameter at every cut
   point.
4. **Classification**: each log is classified by the diameter at its
   **thin (top) end**, by priority — laminação (≥25 cm) > serraria (≥18,
   <25) > mourão/poste (≥8, <18) > celulose (≥6, <8). The first time a
   candidate log's top diameter falls below 6 cm, everything from that
   point to the treetop is residual (taper is monotonically decreasing, so
   this can only happen once per tree). Any leftover stem shorter than a
   full 2.20 m log is also residual.
5. **Log volume by integration**: `V = ∫[h0,h1] (π/40000)·d(h)² dh`,
   computed with R's `integrate()` on the taper-predicted diameter — **not**
   the Smalian frustum formula.
6. **Expansion to 1 ha**: `FE = 10,000 / area_amostrada_m2`. We reused the
   Challenge 01 estimate of 6 plots × 441 m² = 2,646 m² sampled
   (`FE ≈ 3.779`). Edit `AREA_AMOSTRADA_M2` if your own Challenge 01 figure
   differs.
7. Steps 2–6 are repeated for **all three** taper models fitted in Stage 1.

## How to run

1. Edit the `CONFIG` block at the top of `01_etapa1_ajuste_taper.R`
   (3 paths) and run it first — it creates `modelos_taper.rds`, which
   Stage 2 needs.
2. Edit the `CONFIG` block at the top of `02_etapa2_sortimento.R`
   (paths + your own Challenge 01/02 numbers if different) and run it.

```r
Rscript 01_etapa1_ajuste_taper.R
Rscript 02_etapa2_sortimento.R
```

## Output files (as required by the assignment)

| File | Content |
|---|---|
| `ajuste_taper.csv` | model, coefficients, R², R² adjusted, Syx%, flag for the Stage-1-selected model |
| `sortimento_por_modelo.csv` | one row per model × product (incl. "residual"): logs/ha, volume/ha |
| `comparacao_sortimento.csv` | wide comparison of logs/ha and volume/ha across the 3 models, per product, with the reference model identified |
