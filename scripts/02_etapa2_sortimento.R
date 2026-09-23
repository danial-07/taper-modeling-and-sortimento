# =============================================================================
# 02_etapa2_sortimento.R
#
# DATA CHALLENGE 05 -- STAGE 2
# Apply the 3 taper models fitted in Stage 1 to the 215-tree inventory
# (inventa_rio.xlsx), segment each stem into 2.20 m logs, classify each log
# into a product (laminacao / serraria / mourao_poste / celulose / residual),
# compute log volume by INTEGRATION of the taper function, and expand the
# results to 1 hectare.
#
# HOW TO USE:
#   1. Edit INVENTARIO_FILE, OUT_DIR, FUNCOES_FILE and MODELOS_RDS below.
#   2. Edit the hypsometric-model and sampled-area constants in the CONFIG
#      block to match YOUR OWN results from Challenges 01 and 02.
#   3. Run: Rscript 02_etapa2_sortimento.R
#
# Requires: readxl, writexl (install.packages(c("readxl","writexl")))
# =============================================================================

# =============================================================================
# CONFIG -- edit these to match your computer AND your own prior results
# =============================================================================
INVENTARIO_FILE <- "C:/path/to/your/inventa_rio.xlsx"               # <-- change this
OUT_DIR         <- "C:/path/to/your/outputs"                        # <-- change this
FUNCOES_FILE    <- "C:/path/to/your/00_funcoes_desafio05.R"          # <-- change this
MODELOS_RDS     <- "C:/path/to/your/outputs/modelos_taper.rds"       # <-- from Stage 1

# --- Hypsometric model (Challenge 02) --------------------------------------
# Log-log model: ln(HT) = B0 + B1 * ln(DAP), back-transformed with the
# Baskerville correction factor FC. REPLACE these three numbers with your
# own Challenge 02 coefficients if they differ.
HIPSO_B0 <- 1.404
HIPSO_B1 <- 0.689
HIPSO_FC <- 1.0011

# --- Sampled area (Challenge 01) --------------------------------------------
# Total area actually sampled by the 6 plots of Stand 8 (m^2). REPLACE this
# with your own Challenge 01 figure if it differs (e.g. a different plot
# area or a different number of plots).
AREA_AMOSTRADA_M2 <- 6 * 441   # 6 plots x 441 m^2/plot (7x7 trees, 3x3 m spacing)
# =============================================================================

if (!requireNamespace("readxl", quietly = TRUE)) install.packages("readxl")
if (!requireNamespace("writexl", quietly = TRUE)) install.packages("writexl")
library(readxl)
library(writexl)

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
if (!file.exists(INVENTARIO_FILE)) stop(paste0("File not found:\n", INVENTARIO_FILE))
if (!file.exists(FUNCOES_FILE)) stop(paste0("File not found:\n", FUNCOES_FILE))
if (!file.exists(MODELOS_RDS)) stop(paste0(
  "File not found:\n", MODELOS_RDS,
  "\n-> Run 01_etapa1_ajuste_taper.R first, it creates modelos_taper.rds."))

source(FUNCOES_FILE)
modelos <- readRDS(MODELOS_RDS)

cat("Loading inventory file:", INVENTARIO_FILE, "\n")
inventario <- read_excel(INVENTARIO_FILE)
names(inventario) <- trimws(names(inventario))
# Standardize the DAP / HT column names regardless of accents used in the file
names(inventario)[names(inventario) %in% c("DAP")] <- "DAP"
names(inventario)[names(inventario) %in% c("HT")]  <- "HT"

cat("Trees loaded:", nrow(inventario), "\n\n")

# -----------------------------------------------------------------------
# 1) Fill missing heights with the Challenge-02 hypsometric model
# -----------------------------------------------------------------------
n_faltando <- sum(is.na(inventario$HT) | inventario$HT <= 0)
cat("Trees with missing height (to be estimated):", n_faltando,
    "of", nrow(inventario), "\n")

estimar_altura <- function(DAP) HIPSO_FC * exp(HIPSO_B0 + HIPSO_B1 * log(DAP))

inventario$HT_final <- ifelse(
  is.na(inventario$HT) | inventario$HT <= 0,
  estimar_altura(inventario$DAP),
  inventario$HT
)
inventario$ht_source <- ifelse(
  is.na(inventario$HT) | inventario$HT <= 0, "estimated", "measured"
)

cat("Height summary after filling:\n")
print(summary(inventario$HT_final))
cat("\n")

# -----------------------------------------------------------------------
# 2) Expansion factor: 10,000 m^2 / sampled area
# -----------------------------------------------------------------------
FE <- 10000 / AREA_AMOSTRADA_M2
cat("Sampled area:", AREA_AMOSTRADA_M2, "m^2  ->  expansion factor FE =",
    round(FE, 4), "\n\n")

# -----------------------------------------------------------------------
# 3) Apply segmentation + classification + integration to every tree,
#    for each of the 3 taper models
# -----------------------------------------------------------------------
nomes_modelos <- c("kozak", "schopfer", "hradetzky")

# accumulator: one row per (tree x log) and one row per (tree x residual)
todas_toras <- data.frame(
  modelo = character(0), arvore = integer(0), product = character(0),
  comprimento = numeric(0), volume_m3 = numeric(0)
)

for (mname in nomes_modelos) {
  cat("Processing model:", mname, "...\n")
  coefs <- modelos[[mname]]$coefs

  for (i in seq_len(nrow(inventario))) {
    DAP <- inventario$DAP[i]
    HT  <- inventario$HT_final[i]
    if (is.na(DAP) || is.na(HT) || HT <= 0.10) next

    res <- segmentar_arvore(DAP, HT, mname, coefs)

    if (nrow(res$toras) > 0) {
      todas_toras <- rbind(todas_toras, data.frame(
        modelo = mname,
        arvore = i,
        product = res$toras$product,
        comprimento = res$toras$comprimento,
        volume_m3 = res$toras$volume_m3
      ))
    }
    if (res$residual_m3 > 0) {
      todas_toras <- rbind(todas_toras, data.frame(
        modelo = mname, arvore = i, product = "residual",
        comprimento = NA, volume_m3 = res$residual_m3
      ))
    }
  }
}

cat("\nSegmentation finished. Total (tree x log/residual) rows:",
    nrow(todas_toras), "\n\n")

# -----------------------------------------------------------------------
# 4) Consolidate: number of logs/ha and volume/ha, by model x product
# -----------------------------------------------------------------------
produtos_ordem <- c("laminacao", "serraria", "mourao_poste", "celulose", "residual")

# Full modelo x product grid, so a product with ZERO logs in a given model
# (e.g. this stand's DAP distribution may never reach the 25 cm "laminacao"
# threshold) still gets an explicit row with volume/count = 0, instead of
# silently disappearing from the output.
grade <- expand.grid(modelo = nomes_modelos, product = produtos_ordem,
                      stringsAsFactors = FALSE)

vol_tab <- aggregate(volume_m3 ~ modelo + product, data = todas_toras, FUN = sum)
n_toras_tab <- aggregate(
  comprimento ~ modelo + product,
  data = todas_toras[todas_toras$product != "residual", ],
  FUN = length
)
names(n_toras_tab)[names(n_toras_tab) == "comprimento"] <- "n_toras"

sortimento <- merge(grade, vol_tab, by = c("modelo", "product"), all.x = TRUE)
sortimento <- merge(sortimento, n_toras_tab, by = c("modelo", "product"), all.x = TRUE)
sortimento$volume_m3[is.na(sortimento$volume_m3)] <- 0
sortimento$n_toras[is.na(sortimento$n_toras)] <- 0   # residual has no "log count"

sortimento$product <- factor(sortimento$product, levels = produtos_ordem)
sortimento <- sortimento[order(sortimento$modelo, sortimento$product), ]

sortimento$n_toras_ha <- sortimento$n_toras * FE
sortimento$volume_m3_ha <- sortimento$volume_m3 * FE

cat("=== Sortimento by model x product (sample totals and per-hectare) ===\n")
print(sortimento)

out_path1 <- file.path(OUT_DIR, "sortimento_por_modelo.csv")
write.csv(sortimento[, c("modelo", "product", "n_toras", "n_toras_ha",
                          "volume_m3", "volume_m3_ha")],
          out_path1, row.names = FALSE)
cat("\nOutput saved to:", out_path1, "\n")

# -----------------------------------------------------------------------
# 5) Comparison across the 3 models, referenced to the Stage-1 best model
# -----------------------------------------------------------------------
melhor_modelo <- modelos$melhor_modelo
cat("\nStage-1-selected reference model:", melhor_modelo, "\n")

# Built by merging one two-column slice per model (avoids reshape() pitfalls) --
comparacao <- data.frame(product = factor(produtos_ordem, levels = produtos_ordem))
for (mname in nomes_modelos) {
  slice <- sortimento[sortimento$modelo == mname,
                       c("product", "n_toras_ha", "volume_m3_ha")]
  names(slice)[2] <- paste0("n_toras_ha_", mname)
  names(slice)[3] <- paste0("volume_m3_ha_", mname)
  comparacao <- merge(comparacao, slice, by = "product", all.x = TRUE)
}
comparacao <- comparacao[match(produtos_ordem, comparacao$product), ]
num_cols <- setdiff(names(comparacao), "product")
for (cn in num_cols) comparacao[[cn]][is.na(comparacao[[cn]])] <- 0
comparacao$modelo_referencia <- melhor_modelo

cat("\n=== Comparison table (wide format, one row per product) ===\n")
print(comparacao)

out_path2 <- file.path(OUT_DIR, "comparacao_sortimento.csv")
write.csv(comparacao, out_path2, row.names = FALSE)
cat("\nOutput saved to:", out_path2, "\n")

# Comparison chart: volume/ha by product, grouped by model, reference
# model highlighted
vol_wide <- tapply(sortimento$volume_m3_ha,
                    list(sortimento$product, sortimento$modelo), sum)
vol_wide <- vol_wide[produtos_ordem, nomes_modelos]

cores <- ifelse(nomes_modelos == melhor_modelo, "darkgreen", "grey70")

png(file.path(OUT_DIR, "comparacao_sortimento.png"), width = 1200, height = 800, res = 130)
bp <- barplot(t(vol_wide), beside = TRUE, col = cores,
              legend.text = nomes_modelos,
              args.legend = list(x = "topright", bty = "n"),
              main = paste0("Volume/ha by product and taper model\n",
                             "(reference model: ", melhor_modelo, ", highlighted in green)"),
              ylab = "m3 / ha", las = 1)
dev.off()
cat("Comparison chart saved to:",
    file.path(OUT_DIR, "comparacao_sortimento.png"), "\n")

# -----------------------------------------------------------------------
# 6) Save the tree-level detail too (useful for the report / QA)
# -----------------------------------------------------------------------
write_xlsx(
  list(
    inventario_com_altura = inventario[, c("DAP", "HT", "HT_final", "ht_source")],
    toras_detalhe = todas_toras
  ),
  file.path(OUT_DIR, "sortimento_detalhe_arvore.xlsx")
)
cat("Tree-level detail saved to:",
    file.path(OUT_DIR, "sortimento_detalhe_arvore.xlsx"), "\n")

cat("\nSTAGE 2 FINISHED.\n")
