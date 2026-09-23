# =============================================================================
# 01_etapa1_ajuste_taper.R
#
# DATA CHALLENGE 05 -- STAGE 1
# Fit and compare 3 non-segmented taper models (Kozak 1969, Schopfer 1966,
# Hradetzky 1976) using the 36-tree rigorous cubagem data (cubagem.xlsx).
#
# HOW TO USE:
#   1. Edit CUBAGEM_FILE, OUT_DIR and FUNCOES_FILE below.
#   2. Run: Rscript 01_etapa1_ajuste_taper.R
#
# Requires: readxl (install.packages("readxl"))
# =============================================================================

# =============================================================================
# CONFIG -- edit these three lines to match your computer
# =============================================================================
CUBAGEM_FILE  <- "C:/path/to/your/cubagem.xlsx"                # <-- change this
OUT_DIR       <- "C:/path/to/your/outputs"                     # <-- change this
FUNCOES_FILE  <- "C:/path/to/your/00_funcoes_desafio05.R"       # <-- change this
# =============================================================================

if (!requireNamespace("readxl", quietly = TRUE)) install.packages("readxl")
library(readxl)

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
if (!file.exists(CUBAGEM_FILE)) stop(paste0("File not found:\n", CUBAGEM_FILE))
if (!file.exists(FUNCOES_FILE)) stop(paste0("File not found:\n", FUNCOES_FILE))

source(FUNCOES_FILE)

cat("Loading cubagem file:", CUBAGEM_FILE, "\n")
cubagem <- read_excel(CUBAGEM_FILE)
names(cubagem)[names(cubagem) == "Talhão"] <- "Talhao"

cat("Sections loaded:", nrow(cubagem), " | trees:", length(unique(cubagem$Arv)), "\n\n")

# -----------------------------------------------------------------------
# 1) Prepare the data: Z = hi/HT, di/DAP, (di/DAP)^2
# -----------------------------------------------------------------------
dados <- preparar_dados_taper(cubagem)

cat("Preview of prepared data:\n")
print(head(dados[, c("Arv", "hi", "di", "DAP", "HT", "Z", "di_DAP", "di_DAP2")]))
cat("\n")

# -----------------------------------------------------------------------
# 2) Fit the three models on the pooled 36-tree / 1125-section dataset
# -----------------------------------------------------------------------
cat("Fitting Kozak (1969)...\n")
mod_kozak <- ajustar_kozak(dados)

cat("Fitting Schopfer (1966)...\n")
mod_schopfer <- ajustar_schopfer(dados)

cat("Fitting Hradetzky (1976), exponents =",
    paste(HRADETZKY_EXPOENTES, collapse = ", "), "...\n\n")
mod_hradetzky <- ajustar_hradetzky(dados)

cat("=== KOZAK coefficients (b0, b1, b2) ===\n")
print(coef(mod_kozak))
cat("\n=== SCHOPFER coefficients (b0..b5) ===\n")
print(coef(mod_schopfer))
cat("\n=== HRADETZKY coefficients (b1..b7, no intercept) ===\n")
print(coef(mod_hradetzky))

# -----------------------------------------------------------------------
# 3) Evaluation metrics: R2, adjusted R2, Syx%
# -----------------------------------------------------------------------
# NOTE: Kozak and (Schopfer/Hradetzky) are fit on DIFFERENT response
# variables ((di/DAP)^2 vs di/DAP), so Syx% for Kozak is on a different
# scale than for the other two. All three Syx% values are still valid,
# comparable "error relative to the mean of what was actually fit" metrics
# -- exactly what the assignment asks for -- but note this scale difference
# explicitly when interpreting/reporting it (documented in the README).
metricas <- rbind(
  avaliar_modelo_taper(mod_kozak,     "kozak",     dados$di_DAP2),
  avaliar_modelo_taper(mod_schopfer,  "schopfer",  dados$di_DAP),
  avaliar_modelo_taper(mod_hradetzky, "hradetzky", dados$di_DAP)
)

cat("\n=== EVALUATION METRICS ===\n")
print(metricas)

# -----------------------------------------------------------------------
# 4) Residual analysis (graphical), by relative height class and DAP class
# -----------------------------------------------------------------------
dados$resid_kozak     <- resid(mod_kozak)
dados$resid_schopfer  <- resid(mod_schopfer)
dados$resid_hradetzky <- resid(mod_hradetzky)

dados$classe_Z   <- cut(dados$Z, breaks = seq(0, 1, by = 0.1), include.lowest = TRUE)
dados$classe_DAP <- cut(dados$DAP, breaks = pretty(dados$DAP, n = 6))

png(file.path(OUT_DIR, "residuos_perfil_fuste.png"), width = 1200, height = 900, res = 130)
par(mfrow = c(3, 1), mar = c(4, 4, 2, 1))
plot(dados$Z, dados$resid_kozak, pch = 16, cex = 0.5, col = "steelblue",
     main = "Kozak -- residuals vs relative height (Z)", xlab = "Z = hi/HT", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
plot(dados$Z, dados$resid_schopfer, pch = 16, cex = 0.5, col = "forestgreen",
     main = "Schopfer -- residuals vs relative height (Z)", xlab = "Z = hi/HT", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
plot(dados$Z, dados$resid_hradetzky, pch = 16, cex = 0.5, col = "darkorange",
     main = "Hradetzky -- residuals vs relative height (Z)", xlab = "Z = hi/HT", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
dev.off()

png(file.path(OUT_DIR, "residuos_por_classe_dap.png"), width = 1200, height = 900, res = 130)
par(mfrow = c(3, 1), mar = c(4, 8, 2, 1))
boxplot(resid_kozak ~ classe_DAP, data = dados, las = 2,
        main = "Kozak -- residuals by DAP class", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
boxplot(resid_schopfer ~ classe_DAP, data = dados, las = 2,
        main = "Schopfer -- residuals by DAP class", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
boxplot(resid_hradetzky ~ classe_DAP, data = dados, las = 2,
        main = "Hradetzky -- residuals by DAP class", ylab = "residual")
abline(h = 0, col = "red", lty = 2)
dev.off()

cat("\nResidual plots saved to:\n  ", file.path(OUT_DIR, "residuos_perfil_fuste.png"),
    "\n  ", file.path(OUT_DIR, "residuos_por_classe_dap.png"), "\n")

# -----------------------------------------------------------------------
# 5) Select the best model (justification printed + saved)
# -----------------------------------------------------------------------
# Selection rule: lowest Syx% wins (R2/R2adj tell essentially the same
# story here since all 3 models are fit on the same 1125 observations).
melhor <- metricas$modelo[which.min(metricas$syx_pct)]
cat("\n=== MODEL SELECTED AS STAGE-1 REFERENCE ===\n")
cat("Best model (lowest Syx%):", melhor, "\n")
print(metricas[metricas$modelo == melhor, ])

# -----------------------------------------------------------------------
# 6) Save required output: ajuste_taper.csv
# -----------------------------------------------------------------------
# One row per model with its coefficients (as a single semicolon-separated
# string, since the three models have different numbers of coefficients)
# plus the evaluation metrics and a flag marking the Stage-1-selected model.
coefs_txt <- c(
  paste(round(coef(mod_kozak), 6), collapse = "; "),
  paste(round(coef(mod_schopfer), 6), collapse = "; "),
  paste(round(coef(mod_hradetzky), 6), collapse = "; ")
)
metricas$coeficientes <- coefs_txt
metricas$selecionado_etapa1 <- metricas$modelo == melhor

out_path <- file.path(OUT_DIR, "ajuste_taper.csv")
write.csv(metricas, out_path, row.names = FALSE)
cat("\nOutput saved to:", out_path, "\n")

# Save the fitted models themselves (coefficients + exponents) so Stage 2
# can load them without re-fitting.
saveRDS(
  list(
    kozak     = list(coefs = coef(mod_kozak)),
    schopfer  = list(coefs = coef(mod_schopfer)),
    hradetzky = list(coefs = coef(mod_hradetzky), expoentes = HRADETZKY_EXPOENTES),
    melhor_modelo = melhor
  ),
  file.path(OUT_DIR, "modelos_taper.rds")
)
cat("Fitted models saved to:", file.path(OUT_DIR, "modelos_taper.rds"),
    "(read by Stage 2)\n")

cat("\nSTAGE 1 FINISHED.\n")
