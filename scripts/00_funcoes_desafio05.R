# =============================================================================
# 00_funcoes_desafio05.R
#
# DATA CHALLENGE 05 -- SHARED FUNCTIONS
# Taper modeling (Kozak / Schopfer / Hradetzky) and product-assortment
# (sortimento) estimation.
#
# This file defines every function used by both stage scripts:
#   01_etapa1_ajuste_taper.R      (Stage 1: fit and compare the 3 taper models)
#   02_etapa2_sortimento.R        (Stage 2: apply the models to the inventory)
#
# It is sourced (not run directly) by both stage scripts. Nothing in this
# file reads or writes any file -- it only defines functions and constants.
# =============================================================================

# -----------------------------------------------------------------------
# HRADETZKY EXPONENTS
# -----------------------------------------------------------------------
# The assignment explicitly asks the group to choose and document the
# exponents used in Hradetzky's (1976) fractional/integer power polynomial.
# We adopt the example set suggested in the assignment sheet itself:
#     p = 0.1, 0.5, 1, 2, 3, 5, 8
# fitted WITHOUT an intercept (b0), i.e.:
#     di/DAP = b1*Z^0.1 + b2*Z^0.5 + b3*Z^1 + b4*Z^2 + b5*Z^3 + b6*Z^5 + b7*Z^8
# This is the standard way Hradetzky's model is fit in the Brazilian forestry
# literature: the low fractional exponents (0.1, 0.5) capture the sharp
# curvature near the base (butt flare), while the higher integer exponents
# (3, 5, 8) capture the flattening taper in the upper stem.
HRADETZKY_EXPOENTES <- c(0.1, 0.5, 1, 2, 3, 5, 8)

# -----------------------------------------------------------------------
# STAGE 1 -- prepare the cubagem data for fitting
# -----------------------------------------------------------------------
# Given the raw section-level cubagem data (one row per measured point:
# Arv, hi, di, DAP, HT), add the two columns every taper model needs:
#   Z        = hi / HT           (relative height, 0 = base, 1 = treetop)
#   di_DAP   = di / DAP          (taper ratio used by Schopfer and Hradetzky)
#   di_DAP2  = (di / DAP)^2      (taper ratio used by Kozak)
preparar_dados_taper <- function(cubagem) {
  cubagem$Z       <- cubagem$hi / cubagem$HT
  cubagem$di_DAP  <- cubagem$di / cubagem$DAP
  cubagem$di_DAP2 <- cubagem$di_DAP^2
  cubagem
}

# -----------------------------------------------------------------------
# STAGE 1 -- fit the three taper models
# -----------------------------------------------------------------------
# Each ajustar_*() function fits one model by OLS (lm) on the prepared
# cubagem data (output of preparar_dados_taper()) and returns the fitted
# lm object itself -- coefficients and evaluation metrics are extracted
# from it afterwards by avaliar_modelo_taper().

ajustar_kozak <- function(dados) {
  # (di/DAP)^2 = b0 + b1*Z + b2*Z^2
  lm(di_DAP2 ~ Z + I(Z^2), data = dados)
}

ajustar_schopfer <- function(dados) {
  # di/DAP = b0 + b1*Z + b2*Z^2 + b3*Z^3 + b4*Z^4 + b5*Z^5
  lm(di_DAP ~ Z + I(Z^2) + I(Z^3) + I(Z^4) + I(Z^5), data = dados)
}

ajustar_hradetzky <- function(dados, expoentes = HRADETZKY_EXPOENTES) {
  # di/DAP = sum_k bk * Z^pk   (no intercept)
  termos <- paste0("I(Z^", expoentes, ")", collapse = " + ")
  formula_txt <- paste0("di_DAP ~ 0 + ", termos)
  lm(as.formula(formula_txt), data = dados)
}

# -----------------------------------------------------------------------
# STAGE 1 -- evaluation metrics (R2, adjusted R2, Syx%)
# -----------------------------------------------------------------------
# Returns a one-row data.frame with the metrics the assignment asks for.
# Syx% is the residual standard error of the model (in the units of the
# response variable the model was actually fit on) expressed as a percentage
# of the mean of that response variable.
avaliar_modelo_taper <- function(modelo, nome_modelo, dados_resposta) {
  s <- summary(modelo)
  syx <- s$sigma
  syx_pct <- syx / mean(dados_resposta) * 100
  data.frame(
    modelo       = nome_modelo,
    r2           = s$r.squared,
    r2_ajustado  = s$adj.r.squared,
    syx          = syx,
    syx_pct      = syx_pct,
    n_obs        = length(s$residuals)
  )
}

# -----------------------------------------------------------------------
# STAGE 2 -- diameter at any height, for each fitted model
# -----------------------------------------------------------------------
# Given a fitted taper model's coefficients, a tree's DAP and total height
# HT, and a height h (m), returns the taper-estimated diameter (cm) at h.
# Z is clipped to [0, 1] and the predicted ratio is floored at 0 so that
# numerical noise near the treetop can never return a negative diameter.

diametro_kozak <- function(h, DAP, HT, coefs) {
  Z <- pmin(pmax(h / HT, 0), 1)
  ratio2 <- coefs[1] + coefs[2] * Z + coefs[3] * Z^2
  ratio2 <- pmax(ratio2, 0)
  DAP * sqrt(ratio2)
}

diametro_schopfer <- function(h, DAP, HT, coefs) {
  Z <- pmin(pmax(h / HT, 0), 1)
  ratio <- coefs[1] + coefs[2]*Z + coefs[3]*Z^2 + coefs[4]*Z^3 +
           coefs[5]*Z^4 + coefs[6]*Z^5
  DAP * pmax(ratio, 0)
}

diametro_hradetzky <- function(h, DAP, HT, coefs, expoentes = HRADETZKY_EXPOENTES) {
  Z <- pmin(pmax(h / HT, 0), 1)
  ratio <- rep(0, length(Z))
  for (k in seq_along(expoentes)) {
    ratio <- ratio + coefs[k] * Z^expoentes[k]
  }
  DAP * pmax(ratio, 0)
}

# Generic dispatcher used by Stage 2 so the segmentation/classification
# functions below don't need to know which of the 3 models they're using.
# `modelo` is one of "kozak", "schopfer", "hradetzky".
diametro_taper <- function(h, DAP, HT, modelo, coefs) {
  if (modelo == "kozak")      return(diametro_kozak(h, DAP, HT, coefs))
  if (modelo == "schopfer")   return(diametro_schopfer(h, DAP, HT, coefs))
  if (modelo == "hradetzky")  return(diametro_hradetzky(h, DAP, HT, coefs))
  stop("Unknown taper model: ", modelo)
}

# -----------------------------------------------------------------------
# STAGE 2 -- log volume by integration of the taper function
# -----------------------------------------------------------------------
# Cross-sectional area (m^2) at height h, from taper-estimated diameter (cm):
#   A(h) = (pi/4) * (d(h)/100)^2 = (pi/40000) * d(h)^2
#
# Log volume between h0 and h1 = integral of A(h) dh, evaluated with R's
# built-in integrate() -- this is the "integration of the taper function"
# the assignment requires, NOT the Smalian frustum formula.
volume_tora_integracao <- function(DAP, HT, modelo, coefs, h0, h1) {
  area_fn <- function(h) {
    d <- diametro_taper(h, DAP, HT, modelo, coefs)
    (pi / 40000) * d^2
  }
  resultado <- integrate(area_fn, lower = h0, upper = h1, subdivisions = 200)
  resultado$value
}

# -----------------------------------------------------------------------
# STAGE 2 -- product classification (by top diameter of the log)
# -----------------------------------------------------------------------
# Diameter thresholds (min. diameter at the log's THIN end, per the
# assignment's reference table):
#   laminacao      >= 25 cm
#   serraria       >= 18 cm  (and < 25)
#   mourao_poste   >=  8 cm  (and < 18)
#   celulose       >=  6 cm  (and < 8)
#   (below 6 cm -> not a product log; becomes residual)
# Classification is by PRIORITY (highest-value product the log qualifies
# for), exactly as specified: laminacao > serraria > mourao_poste > celulose.
classificar_produto <- function(d_topo) {
  if (d_topo >= 25) return("laminacao")
  if (d_topo >= 18) return("serraria")
  if (d_topo >= 8)  return("mourao_poste")
  if (d_topo >= 6)  return("celulose")
  return(NA_character_)   # < 6 cm: not a product log
}

# -----------------------------------------------------------------------
# STAGE 2 -- segment one tree's stem into 2.20 m logs and classify each
# -----------------------------------------------------------------------
# Starting at the stump height (0.10 m by default), walk up the stem in
# fixed 2.20 m logs. For each candidate log:
#   - the taper function gives the diameter at its thin (top) end
#   - if that diameter is still >= 6 cm, the log is a valid product log:
#       classify it (by top diameter) and compute its volume by integration
#   - if that diameter has dropped below 6 cm, taper is monotonically
#     decreasing going up the stem, so EVERYTHING from here to the treetop
#     is residual -- stop segmenting.
# If the stem runs out before a full 2.20 m log can be completed, whatever
# length remains (shorter than one log) is also residual.
#
# Returns a list with:
#   $toras     data.frame: product, h0, h1, comprimento, volume_m3 (one row/log)
#   $residual_m3  volume (m3) of the un-classified remainder of the stem
segmentar_arvore <- function(DAP, HT, modelo, coefs,
                              altura_toco = 0.10, comprimento_tora = 2.20) {
  toras <- data.frame(
    product = character(0), h0 = numeric(0), h1 = numeric(0),
    comprimento = numeric(0), volume_m3 = numeric(0)
  )

  h0 <- altura_toco
  eps <- 1e-9

  while (h0 + comprimento_tora <= HT + eps) {
    h1 <- h0 + comprimento_tora
    d_topo <- diametro_taper(h1, DAP, HT, modelo, coefs)
    produto <- classificar_produto(d_topo)

    if (is.na(produto)) {
      # top diameter of this candidate log already below 6 cm -> stop here;
      # everything from h0 up is residual (handled after the loop)
      break
    }

    vol <- volume_tora_integracao(DAP, HT, modelo, coefs, h0, h1)
    toras <- rbind(toras, data.frame(
      product = produto, h0 = h0, h1 = h1,
      comprimento = comprimento_tora, volume_m3 = vol
    ))
    h0 <- h1
  }

  residual_m3 <- 0
  if (h0 < HT - eps) {
    residual_m3 <- volume_tora_integracao(DAP, HT, modelo, coefs, h0, HT)
  }

  list(toras = toras, residual_m3 = residual_m3)
}
