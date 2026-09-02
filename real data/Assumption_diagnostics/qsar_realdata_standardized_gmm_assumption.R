CFG <- list(
  x_file = "Graph_X.xlsx",
  y_file = "Graph_Y0.xlsx",
  edge_file = "index_5.xlsx",
  x_sheet = "Sheet3",
  y_sheet = "Sheet2",
  edge_sheet = "Sheet3",
  output_dir = "qsar_realdata_standardized_gmm_assumption_checks_output",

  support_min_degree = 1L,
  moment_min_degree = 2L,


  price_transform = "auto",         
  heavy_tail_abs_skew = 2.0,
  heavy_tail_excess_kurtosis = 10.0,
  heavy_tail_max_to_median = 10.0,

  h_base = 0.16,
  h_degree_power = 0.35,
  h_bounds = c(0.02, 0.28),
  tau_base = 0.30,
  tau_degree_power = 0.30,
  tau_bounds = c(0.05, 0.60),

  lambda_bounds = c(-0.80, 0.80),
  z_bounds = c(0.10, 0.90),
  z_profile_step = 0.01,

  ces_gamma_bounds = c(-50, 50),
  ces_profile_points = 161L,
  ces_positive_margin = 0.10,
  ces_root_tolerance = 1e-10,
  ces_root_moment_tolerance = 1e-10,

  ces_qsar_z_tolerance = 0.10,

  max_profile_candidates = 8L,
  
  gmm_max_outer_iterations = 50L,
  gmm_parameter_tolerance = 1e-7,
  gmm_weight_tolerance = 1e-6,
  optim_maxit = 1500L,
  optim_factr = 10,
  optim_pgtol = 1e-12,
  finite_difference_relative_step = 1e-5,
  finite_difference_z_step = 1e-4,
  finite_difference_gamma_relative_step = 1e-4,
  matrix_eigen_floor = 1e-8,
  boundary_tolerance = 1e-4,

  
  instrument_rms_floor = 1e-8,
  standardization_equivalence_tolerance = 1e-5,

  
  diagnostic_bootstrap_B = 199L,
  diagnostic_bootstrap_seed = 20260821L,
  diagnostic_z_half_width = 0.10,
  diagnostic_z_step = 0.01,
  diagnostic_lambda_half_width = 0.10,
  diagnostic_equilibrium_tolerance = 1e-8,
  diagnostic_equilibrium_max_iterations = 1000L,
  diagnostic_cpu_fraction = 0.80,
  diagnostic_reps_per_task = 4L,
  diagnostic_kappa_z_grid = seq(0.10, 0.90, by = 0.01)
)

`%||%` <- function(x, y) if (is.null(x)) y else x
stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)
warnf <- function(fmt, ...) warning(sprintf(fmt, ...), call. = FALSE)
clip <- function(x, bounds) pmin(bounds[[2L]], pmax(bounds[[1L]], x))
symmetrize <- function(A) (A + t(A)) / 2

require_package <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stopf("Package '%s' is required. Install it with install.packages('%s').", pkg, pkg)
  }
}

safe_solve <- function(A, b = NULL, ridge = 1e-10) {
  A <- as.matrix(A)
  ans <- tryCatch(if (is.null(b)) solve(A) else solve(A, b), error = function(e) NULL)
  if (!is.null(ans) && all(is.finite(ans))) return(ans)
  scale_A <- max(1, max(abs(diag(A))))
  A <- A + diag(ridge * scale_A, nrow(A))
  ans <- if (is.null(b)) solve(A) else solve(A, b)
  if (!all(is.finite(ans))) stopf("A required linear system could not be solved.")
  ans
}

stabilize_psd <- function(A, relative_floor) {
  A <- symmetrize(A)
  ee <- eigen(A, symmetric = TRUE)
  top <- max(1, max(abs(ee$values)))
  values <- pmax(ee$values, relative_floor * top)
  stable <- ee$vectors %*% (values * t(ee$vectors))
  list(
    matrix = symmetrize(stable),
    raw_min_eigenvalue = min(ee$values),
    condition_number = max(values) / min(values)
  )
}

shape_statistics <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) < 4L) stopf("At least four observations are required.")
  mu <- mean(x)
  s <- stats::sd(x)
  centered <- x - mu
  data.frame(
    n = length(x),
    mean = mu,
    sd = s,
    median = stats::median(x),
    min = min(x),
    max = max(x),
    skewness = if (s > 0) mean(centered^3) / s^3 else 0,
    excess_kurtosis = if (s > 0) mean(centered^4) / s^4 - 3 else 0,
    max_to_median = if (stats::median(x) > 0) max(x) / stats::median(x) else NA_real_
  )
}

standardize_variable <- function(x, label, reference_index = seq_along(x)) {
  x <- as.numeric(x)
  reference <- x[reference_index]
  s <- stats::sd(reference)
  if (!is.finite(s) || s <= 0) stopf("Variable '%s' has zero variance.", label)
  center <- mean(reference)
  list(value = (x - center) / s, mean = center, sd = s)
}

# -----------------------------------------------------------------------------
# Data import, network pruning, and covariate preprocessing
# -----------------------------------------------------------------------------

read_real_data <- function(cfg) {
  require_package("readxl")
  paths <- c(X = cfg$x_file, Y = cfg$y_file, edge = cfg$edge_file)
  missing_files <- paths[!file.exists(paths)]
  if (length(missing_files)) {
    stopf(
      "Cannot find %s in the current working directory: %s",
      paste(names(missing_files), collapse = ", "),
      paste(missing_files, collapse = ", ")
    )
  }
  x_path <- paths[["X"]]
  y_path <- paths[["Y"]]
  edge_path <- paths[["edge"]]

  x_raw <- as.data.frame(readxl::read_excel(x_path, sheet = cfg$x_sheet, .name_repair = "minimal"))
  y_raw <- as.data.frame(readxl::read_excel(y_path, sheet = cfg$y_sheet, .name_repair = "minimal"))
  edge_raw <- as.data.frame(readxl::read_excel(edge_path, sheet = cfg$edge_sheet, .name_repair = "minimal"))

  required_x <- c("id", "复购用户占比", "location", "category", "客单价", "时间")
  if (length(setdiff(required_x, names(x_raw)))) stopf("Graph_X has unexpected columns.")
  if (!all(c("id", "Y") %in% names(y_raw))) stopf("Graph_Y0 must contain id and Y.")
  if (!all(c("row", "column") %in% names(edge_raw))) stopf("index_5 must contain row and column.")
  if (anyNA(x_raw) || anyNA(y_raw) || anyNA(edge_raw)) stopf("Input files contain missing values.")

  x_raw$id <- as.integer(x_raw$id)
  y_raw$id <- as.integer(y_raw$id)
  edge_raw$row <- as.integer(edge_raw$row)
  edge_raw$column <- as.integer(edge_raw$column)
  if (anyDuplicated(x_raw$id) || anyDuplicated(y_raw$id)) stopf("Node IDs must be unique.")
  if (!setequal(x_raw$id, y_raw$id)) stopf("The X and Y node-ID sets do not match.")

  y_aligned <- y_raw$Y[match(x_raw$id, y_raw$id)]
  nodes <- data.frame(
    id = x_raw$id,
    Y = as.numeric(y_aligned),
    repeat_customer_ratio = as.numeric(x_raw[["复购用户占比"]]),
    commercial_zone_diversity = as.numeric(x_raw[["location"]]),
    menu_variety = as.numeric(x_raw[["category"]]),
    average_transaction_value = as.numeric(x_raw[["客单价"]]),
    operating_hours = as.numeric(x_raw[["时间"]]),
    stringsAsFactors = FALSE
  )
  if (!all(nodes$operating_hours %in% c(0, 1))) stopf("Operating hours must be coded 0/1.")
  if (any(nodes$average_transaction_value <= 0)) stopf("Transaction values must be positive.")
  if (!all(edge_raw$row %in% nodes$id) || !all(edge_raw$column %in% nodes$id)) {
    stopf("The edge list contains unknown node IDs.")
  }

  self_loops <- sum(edge_raw$row == edge_raw$column)
  edge_raw <- edge_raw[edge_raw$row != edge_raw$column, , drop = FALSE]
  edges <- unique(data.frame(
    from = pmin(edge_raw$row, edge_raw$column),
    to = pmax(edge_raw$row, edge_raw$column)
  ))
  list(
    nodes = nodes,
    edges = edges,
    paths = c(X = x_path, Y = y_path, edge = edge_path),
    raw_edge_rows = nrow(edge_raw) + self_loops,
    self_loop_count = self_loops
  )
}

make_adjacency <- function(ids, edges) {
  n <- length(ids)
  from <- match(edges$from, ids)
  to <- match(edges$to, ids)
  ok <- !is.na(from) & !is.na(to) & from != to
  adjacency <- vector("list", n)
  for (e in which(ok)) {
    i <- from[[e]]
    j <- to[[e]]
    adjacency[[i]] <- c(adjacency[[i]], j)
    adjacency[[j]] <- c(adjacency[[j]], i)
  }
  lapply(adjacency, unique)
}

retain_nonisolated_support <- function(
  nodes, edges, support_min_degree = 1L, moment_min_degree = 2L
) {
  if (support_min_degree != 1L) stopf("support_min_degree must equal one.")
  if (moment_min_degree < 2L) stopf("moment_min_degree must be at least two.")
  adjacency <- make_adjacency(nodes$id, edges)
  degree <- lengths(adjacency)
  support_alive <- degree >= support_min_degree
  support_ids <- nodes$id[support_alive]
  support_edges <- edges[
    edges$from %in% support_ids & edges$to %in% support_ids,
    , drop = FALSE
  ]
  support_nodes <- nodes[match(support_ids, nodes$id), , drop = FALSE]
  support_neighbors <- make_adjacency(support_nodes$id, support_edges)
  support_degree <- lengths(support_neighbors)
  if (any(support_degree < support_min_degree)) {
    stopf("An isolate remained in the support graph.")
  }

  # This is deliberately a one-time role assignment in the full non-isolated
  # graph, not recursive pruning.  Support nodes remain in every neighbor list.
  moment_index <- which(support_degree >= moment_min_degree)
  moment_nodes <- support_nodes[moment_index, , drop = FALSE]
  moment_neighbors <- support_neighbors[moment_index]
  moment_degree <- support_degree[moment_index]
  if (!length(moment_index) || any(lengths(moment_neighbors) < moment_min_degree)) {
    stopf("The moment-node construction failed.")
  }
  list(
    support_nodes = support_nodes,
    support_edges = support_edges,
    support_neighbors = support_neighbors,
    support_degree = support_degree,
    moment_index = moment_index,
    moment_nodes = moment_nodes,
    moment_neighbors = moment_neighbors,
    moment_degree = moment_degree,
    initial_n = nrow(nodes),
    initial_edges = nrow(edges),
    removed_isolates = sum(!support_alive),
    degree_one_support_nodes = sum(support_degree == 1L)
  )
}

preprocess_data <- function(raw, net, cfg) {
  dat <- net$support_nodes
  estimation_index <- net$moment_index
  raw_price <- shape_statistics(dat$average_transaction_value)
  log_price <- shape_statistics(log(dat$average_transaction_value))
  heavy_tail <-
    abs(raw_price$skewness) > cfg$heavy_tail_abs_skew ||
    raw_price$excess_kurtosis > cfg$heavy_tail_excess_kurtosis ||
    raw_price$max_to_median > cfg$heavy_tail_max_to_median
  use_log <- switch(
    cfg$price_transform,
    auto = heavy_tail,
    log = TRUE,
    none = FALSE,
    stopf("price_transform must be auto, log, or none.")
  )

  price <- if (use_log) log(dat$average_transaction_value) else dat$average_transaction_value
  # Centering and scaling are estimated on the moment-node sample and then
  # applied unchanged to every support node used in peer distributions.
  s1 <- standardize_variable(
    dat$repeat_customer_ratio, "repeat customer ratio", estimation_index
  )
  s2 <- standardize_variable(
    dat$commercial_zone_diversity, "commercial zone diversity", estimation_index
  )
  s3 <- standardize_variable(dat$menu_variety, "menu variety", estimation_index)
  s4 <- standardize_variable(price, "average transaction value", estimation_index)
  X_support <- cbind(
    Intercept = 1,
    repeat_customer_ratio = s1$value,
    commercial_zone_diversity = s2$value,
    menu_variety = s3$value,
    average_transaction_value = s4$value,
    operating_hours = dat$operating_hours
  )
  if (use_log) colnames(X_support)[[5L]] <- "log_average_transaction_value"
  storage.mode(X_support) <- "double"
  X <- X_support[estimation_index, , drop = FALSE]
  intercept_columns <- which(apply(X, 2L, function(v) all(abs(v - 1) <= 1e-12)))
  if (length(intercept_columns) != 1L || intercept_columns[[1L]] != 1L) {
    stopf("The structural design matrix must contain exactly one leading intercept.")
  }
  gram_eigen <- eigen(symmetrize(crossprod(X) / nrow(X)), symmetric = TRUE, only.values = TRUE)$values
  if (min(gram_eigen) <= 1e-10) stopf("The processed X matrix is rank deficient.")

  Y_support <- as.numeric(dat$Y)
  Y <- Y_support[estimation_index]
  qsar_first_stage <- safe_solve(crossprod(X), crossprod(X, Y))
  fitted_qsar_support <- drop(X_support %*% qsar_first_stage)

  # The CES power mean requires positive outcomes.  Use the same fixed shift for
  # every retained observation, computed before network pruning.
  ces_shift <- max(0, -min(raw$nodes$Y) + cfg$ces_positive_margin)
  Y_positive_support <- Y_support + ces_shift
  Y_positive <- Y_positive_support[estimation_index]
  if (any(Y_positive_support <= 0)) {
    stopf("The CES outcome shift did not produce positive values.")
  }

  # Following the CES implementation, use the OLS fitted value based only on X
  # as the exogenous outcome predictor entering the CES instruments.  Because
  # X includes an intercept, shifting Y to Y_positive changes only the fitted
  # intercept.  Positivity is checked rather than imposed by a second nonlinear
  # transformation.
  ces_first_stage <- safe_solve(
    crossprod(X), crossprod(X, Y_positive)
  )
  fitted_ces_support <- drop(X_support %*% ces_first_stage)
  predictor_method <- paste0(
    "OLS predictor X'a estimated on degree>=2 moment nodes and applied to all ",
    "non-isolated support nodes"
  )
  if (any(!is.finite(fitted_ces_support)) || any(fitted_ces_support <= 0)) {
    stopf(
      paste0(
        "The direct OLS predictor used by the CES instruments is not strictly positive. ",
        "Do not silently exponentiate it; inspect the outcome scale or increase the ",
        "pre-specified CES positive margin before estimation."
      )
    )
  }

  transformations <- data.frame(
    variable = c(
      "Intercept",
      "repeat_customer_ratio", "commercial_zone_diversity", "menu_variety",
      if (use_log) "log_average_transaction_value" else "average_transaction_value",
      "operating_hours", "Y"
    ),
    transformation = c(
      "constant_one",
      "standardized", "standardized", "standardized", "standardized",
      "unchanged_binary", "unchanged"
    ),
    centering_mean = c(NA_real_, s1$mean, s2$mean, s3$mean, s4$mean, NA_real_, NA_real_),
    scaling_sd = c(NA_real_, s1$sd, s2$sd, s3$sd, s4$sd, NA_real_, NA_real_)
  )
  processed <- data.frame(
    id = dat$id,
    support_degree = net$support_degree,
    enters_gmm_moments = seq_len(nrow(dat)) %in% estimation_index,
    Intercept = 1,
    Y = Y_support,
    Y_positive_for_CES = Y_positive_support,
    repeat_customer_ratio_std = s1$value,
    commercial_zone_diversity_std = s2$value,
    menu_variety_std = s3$value,
    average_transaction_value_model = price,
    average_transaction_value_std = s4$value,
    operating_hours = dat$operating_hours,
    fitted_Y_for_QSAR = fitted_qsar_support,
    fitted_positive_Y_for_CES_instruments = fitted_ces_support
  )
  list(
    X = X,
    Y = Y,
    Y_positive = Y_positive,
    X_support = X_support,
    Y_support = Y_support,
    Y_positive_support = Y_positive_support,
    fitted_qsar_support = fitted_qsar_support,
    fitted_ces_support = fitted_ces_support,
    estimation_index = estimation_index,
    ces_shift = ces_shift,
    ces_predictor_method = predictor_method,
    processed = processed,
    transformations = transformations,
    use_log_price = use_log,
    heavy_tail_triggered = heavy_tail,
    raw_price_stats = raw_price,
    log_price_stats = log_price,
    gram_min_eigenvalue = min(gram_eigen),
    gram_condition_number = max(gram_eigen) / min(gram_eigen)
  )
}

# -----------------------------------------------------------------------------
# Peer norms: mean, Gaussian-smoothed quantile, and CES power mean
# -----------------------------------------------------------------------------

prepare_piecewise_quantile <- function(values) {
  values <- sort(as.numeric(values))
  m <- length(values)
  if (m < 2L) stopf("Every retained node must have at least two neighbors.")
  knots <- seq(0, 1, length.out = m)
  slopes <- diff(values) / diff(knots)
  list(
    values = values,
    knots = knots,
    slopes = slopes,
    intercepts = values[-m] - slopes * knots[-m]
  )
}

prepare_neighbor_quantiles <- function(values, neighbors) {
  lapply(neighbors, function(index) prepare_piecewise_quantile(values[index]))
}

gaussian_smooth_quantile_one <- function(prep, z, bandwidth) {
  values <- prep$values
  knots <- prep$knots
  left <- knots[-length(knots)]
  right <- knots[-1L]
  A <- (left - z) / bandwidth
  B <- (right - z) / bandwidth
  probability <- stats::pnorm(B) - stats::pnorm(A)
  level <-
    values[[1L]] * stats::pnorm(-z / bandwidth) +
    values[[length(values)]] * (1 - stats::pnorm((1 - z) / bandwidth)) +
    sum(
      (prep$intercepts + prep$slopes * z) * probability +
        prep$slopes * bandwidth * (stats::dnorm(A) - stats::dnorm(B))
    )
  derivative <- sum(prep$slopes * probability)
  c(level = level, derivative = derivative)
}

gaussian_smooth_quantiles <- function(prepared, z, bandwidths) {
  result <- lapply(seq_along(prepared), function(i) {
    gaussian_smooth_quantile_one(prepared[[i]], z, bandwidths[[i]])
  })
  matrix_result <- do.call(rbind, result)
  list(level = matrix_result[, "level"], derivative = matrix_result[, "derivative"])
}

make_bandwidths <- function(degree, cfg) {
  reference <- stats::median(degree)
  result <- list(
    h = clip(cfg$h_base * (degree / reference)^(-cfg$h_degree_power), cfg$h_bounds),
    tau = clip(cfg$tau_base * (degree / reference)^(-cfg$tau_degree_power), cfg$tau_bounds),
    degree_reference = reference
  )
  if (any(!is.finite(result$h)) || any(!is.finite(result$tau)) ||
      any(result$h <= 0) || any(result$tau <= 0)) {
    stopf("The degree-adaptive bandwidth rule produced an invalid bandwidth.")
  }
  if (any(result$tau <= result$h)) {
    stopf("The selected rule requires tau_i > h_i for every retained node.")
  }
  result
}

ces_power_mean_one <- function(log_values, gamma) {
  log_values <- as.numeric(log_values)
  if (is.infinite(gamma)) {
    level <- if (gamma > 0) exp(max(log_values)) else exp(min(log_values))
    # The CES derivative instrument vanishes in the peer-minimum/maximum
    # limits.  Keeping the limiting value zero lets the same moment vector and
    # the same final weight matrix be used in the five-point diagnostic table.
    return(c(level = level, derivative = 0))
  }
  if (abs(gamma) < 1e-6) {
    mu <- mean(log_values)
    level <- exp(mu)
    derivative <- 0.5 * level * mean((log_values - mu)^2)
    return(c(level = level, derivative = derivative))
  }
  scaled <- gamma * log_values
  maximum <- max(scaled)
  exponentials <- exp(scaled - maximum)
  log_mean_exp <- maximum + log(mean(exponentials))
  log_level <- log_mean_exp / gamma
  level <- exp(log_level)
  weights <- exponentials / sum(exponentials)
  derivative_log_level <-
    (gamma * sum(weights * log_values) - log_mean_exp) / gamma^2
  c(level = level, derivative = level * derivative_log_level)
}

ces_power_means <- function(log_values, neighbors, gamma) {
  result <- lapply(neighbors, function(index) ces_power_mean_one(log_values[index], gamma))
  matrix_result <- do.call(rbind, result)
  list(level = matrix_result[, "level"], derivative = matrix_result[, "derivative"])
}

neighbor_means <- function(values, neighbors) {
  vapply(neighbors, function(index) mean(values[index]), numeric(1))
}

# Map a CES norm to the quantile index that has the same value in a node's
# empirical peer distribution.  This is the appropriate bridge between gamma
# and z: gamma itself is a curvature parameter and is not a percentile.
ces_equivalent_quantile_one <- function(values, target, gamma) {
  values <- sort(as.numeric(values))
  if (is.infinite(gamma)) return(if (gamma > 0) 1 else 0)
  knots <- seq(0, 1, length.out = length(values))
  unique_values <- unique(values)
  if (length(unique_values) == 1L) return(0.5)
  unique_knots <- vapply(
    unique_values,
    function(value) mean(knots[abs(values - value) <= 1e-12 * max(1, abs(value))]),
    numeric(1)
  )
  as.numeric(stats::approx(
    x = unique_values,
    y = unique_knots,
    xout = target,
    method = "linear",
    rule = 2,
    ties = "ordered"
  )$y)
}

ces_equivalent_quantiles <- function(values, neighbors, ces_levels, gamma) {
  vapply(seq_along(neighbors), function(i) {
    ces_equivalent_quantile_one(values[neighbors[[i]]], ces_levels[[i]], gamma)
  }, numeric(1))
}

# -----------------------------------------------------------------------------
# CES-author-style outer-product score covariance
# -----------------------------------------------------------------------------

gmm_score_covariance <- function(scores, eigen_floor) {
  scores <- as.matrix(scores)
  n <- nrow(scores)
  # This is the H matrix used in the CES authors' compW() and GMMvarcov():
  # the average outer product of individual moment scores.  It permits
  # heteroskedasticity across observations.
  Sigma <- crossprod(scores) / n
  stable <- stabilize_psd(Sigma, eigen_floor)
  list(
    Sigma = stable$matrix,
    raw_min_eigenvalue = stable$raw_min_eigenvalue,
    condition_number = stable$condition_number
  )
}

# -----------------------------------------------------------------------------
# Indexed GMM for CES and QSAR
# -----------------------------------------------------------------------------

make_qsar_model <- function(prep, net, bandwidths, cfg) {
  model <- list(
    name = "QSAR",
    index_name = "z",
    X = prep$X,
    y = prep$Y,
    n = nrow(prep$X),
    p = ncol(prep$X),
    index_bounds = cfg$z_bounds,
    profile_grid = seq(cfg$z_bounds[[1L]], cfg$z_bounds[[2L]], by = cfg$z_profile_step),
    derivative_scaled_by_lambda = TRUE,
    prepared_observed = prepare_neighbor_quantiles(
      prep$Y_support, net$moment_neighbors
    ),
    prepared_fitted = prepare_neighbor_quantiles(
      prep$fitted_qsar_support, net$moment_neighbors
    ),
    h = bandwidths$h,
    tau = bandwidths$tau,
    cache = new.env(parent = emptyenv())
  )
  model$instrument_scale <- rep(1, model$p + 2L)
  names(model$instrument_scale) <- c(colnames(model$X), "peer_level", "peer_derivative")
  model
}

make_ces_model <- function(prep, net, cfg) {
  bound <- max(abs(cfg$ces_gamma_bounds))
  u <- seq(-1, 1, length.out = cfg$ces_profile_points)
  gamma_grid <- sort(unique(c(
    cfg$ces_gamma_bounds,
    bound * sign(u) * abs(u)^3,
    -1, 0, 1
  )))
  model <- list(
    name = "CES",
    index_name = "gamma",
    X = prep$X,
    y = prep$Y_positive,
    n = nrow(prep$X),
    p = ncol(prep$X),
    index_bounds = cfg$ces_gamma_bounds,
    profile_grid = gamma_grid,
    derivative_scaled_by_lambda = FALSE,
    log_observed = log(prep$Y_positive_support),
    log_fitted = log(prep$fitted_ces_support),
    neighbors = net$moment_neighbors,
    cache = new.env(parent = emptyenv())
  )
  model$instrument_scale <- rep(1, model$p + 2L)
  names(model$instrument_scale) <- c(colnames(model$X), "peer_level", "peer_derivative")
  model
}

instrument_scale_vector <- function(model, number_of_columns = model$p + 2L) {
  scale <- model$instrument_scale %||% rep(1, number_of_columns)
  if (length(scale) != number_of_columns || any(!is.finite(scale)) || any(scale <= 0)) {
    stopf("%s has an invalid fixed instrument-scale vector.", model$name)
  }
  as.numeric(scale)
}

evaluate_peer_terms <- function(index, model) {
  key <- sprintf("%.12f", index)
  if (exists(key, envir = model$cache, inherits = FALSE)) {
    return(get(key, envir = model$cache, inherits = FALSE))
  }
  if (model$name == "QSAR") {
    observed <- gaussian_smooth_quantiles(model$prepared_observed, index, model$h)
    fitted <- gaussian_smooth_quantiles(model$prepared_fitted, index, model$tau)
    result <- list(
      observed = observed$level,
      fitted = fitted$level,
      derivative = fitted$derivative
    )
  } else if (model$name == "CES") {
    observed <- ces_power_means(model$log_observed, model$neighbors, index)
    fitted <- ces_power_means(model$log_fitted, model$neighbors, index)
    result <- list(
      observed = observed$level,
      fitted = fitted$level,
      derivative = fitted$derivative
    )
  } else {
    stopf("Unknown indexed model '%s'.", model$name)
  }
  assign(key, result, envir = model$cache)
  result
}

indexed_moment_components <- function(theta, model) {
  beta <- theta[seq_len(model$p)]
  lambda <- theta[[model$p + 1L]]
  index <- theta[[model$p + 2L]]
  peer <- evaluate_peer_terms(index, model)
  residual <- model$y - drop(model$X %*% beta) - lambda * peer$observed
  derivative_instrument <- if (model$derivative_scaled_by_lambda) {
    lambda * peer$derivative
  } else {
    peer$derivative
  }
  raw_instruments <- cbind(model$X, peer$fitted, derivative_instrument)
  scale <- instrument_scale_vector(model, ncol(raw_instruments))
  instruments <- sweep(raw_instruments, 2L, scale, FUN = "/")
  scores <- instruments * residual
  list(
    moments = colMeans(scores),
    scores = scores,
    residual = residual,
    instruments = instruments,
    raw_instruments = raw_instruments,
    instrument_scale = scale,
    peer = peer
  )
}

indexed_objective <- function(theta, model, W, lambda_bounds) {
  if (any(!is.finite(theta))) return(.Machine$double.xmax / 100)
  lambda <- theta[[model$p + 1L]]
  index <- theta[[model$p + 2L]]
  if (lambda < lambda_bounds[[1L]] || lambda > lambda_bounds[[2L]] ||
      index < model$index_bounds[[1L]] || index > model$index_bounds[[2L]]) {
    return(.Machine$double.xmax / 100)
  }
  moments <- indexed_moment_components(theta, model)$moments
  value <- drop(crossprod(moments, W %*% moments))
  if (is.finite(value)) value else .Machine$double.xmax / 100
}

indexed_diagnostics <- function(theta, model, W) {
  parts <- indexed_moment_components(theta, model)
  objective <- drop(crossprod(parts$moments, W %*% parts$moments))
  index_moment <- tail(parts$moments, 1L)
  index_instrument <- parts$instruments[, ncol(parts$instruments)]
  index_instrument_rms <- sqrt(mean(index_instrument^2))
  list(
    objective = objective,
    index_moment = index_moment,
    index_instrument_rms = index_instrument_rms,
    max_abs_moment = max(abs(parts$moments))
  )
}

profile_start <- function(index, model, W, cfg) {
  peer <- evaluate_peer_terms(index, model)
  regressors <- cbind(model$X, peer$observed)
  first_raw_instruments <- cbind(model$X, peer$fitted)
  first_instruments <- sweep(
    first_raw_instruments,
    2L,
    instrument_scale_vector(model)[seq_len(model$p + 1L)],
    FUN = "/"
  )
  coefficients <- drop(safe_solve(
    crossprod(first_instruments, regressors),
    crossprod(first_instruments, model$y)
  ))
  lambda <- clip(coefficients[[length(coefficients)]], cfg$lambda_bounds)
  if (lambda != coefficients[[length(coefficients)]]) {
    beta <- drop(safe_solve(
      crossprod(model$X),
      crossprod(model$X, model$y - lambda * peer$observed)
    ))
    coefficients <- c(beta, lambda)
  }
  theta <- c(coefficients, index)
  metrics <- indexed_diagnostics(theta, model, W)
  c(list(theta = theta), metrics)
}

local_extrema_indices <- function(values, type = c("min", "max")) {
  type <- match.arg(type)
  if (length(values) < 3L) return(seq_along(values))
  result <- integer()
  for (i in 2:(length(values) - 1L)) {
    if (type == "min" && values[[i]] <= values[[i - 1L]] && values[[i]] <= values[[i + 1L]]) {
      result <- c(result, i)
    }
    if (type == "max" && values[[i]] >= values[[i - 1L]] && values[[i]] >= values[[i + 1L]]) {
      result <- c(result, i)
    }
  }
  result
}

profile_basins <- function(profile, candidate_indices, bounds, criterion) {
  maxima <- local_extrema_indices(profile[[criterion]], "max")
  lapply(candidate_indices, function(index) {
    left <- maxima[maxima < index]
    right <- maxima[maxima > index]
    lower <- if (length(left)) profile$index[[max(left)]] else bounds[[1L]]
    upper <- if (length(right)) profile$index[[min(right)]] else bounds[[2L]]
    if (upper - lower < 1e-6) c(lower = bounds[[1L]], upper = bounds[[2L]]) else c(lower = lower, upper = upper)
  })
}

refine_ces_profile_roots <- function(model, W, cfg, starts, profile, criterion) {
  if (model$name != "CES") {
    return(list(starts = list(), indices = integer(), basins = list(), roots = numeric()))
  }
  moment <- vapply(starts, `[[`, numeric(1), "index_moment")
  intervals <- which(
    is.finite(moment[-length(moment)]) & is.finite(moment[-1L]) &
      moment[-length(moment)] * moment[-1L] <= 0
  )
  roots <- numeric()
  for (i in intervals) {
    lower <- model$profile_grid[[i]]
    upper <- model$profile_grid[[i + 1L]]
    root <- tryCatch(
      stats::uniroot(
        function(index) profile_start(index, model, W, cfg)$index_moment,
        interval = c(lower, upper),
        tol = cfg$ces_root_tolerance,
        maxiter = 200L
      )$root,
      error = function(e) NA_real_
    )
    if (is.finite(root) &&
        root > model$index_bounds[[1L]] + cfg$boundary_tolerance &&
        root < model$index_bounds[[2L]] - cfg$boundary_tolerance) {
      roots <- c(roots, root)
    }
  }
  if (!length(roots)) {
    return(list(starts = list(), indices = integer(), basins = list(), roots = numeric()))
  }
  roots <- sort(unique(round(roots / cfg$ces_root_tolerance) * cfg$ces_root_tolerance))
  root_starts <- lapply(roots, profile_start, model = model, W = W, cfg = cfg)
  nearest <- vapply(
    roots,
    function(root) which.min(abs(model$profile_grid - root)),
    integer(1)
  )
  list(
    starts = root_starts,
    indices = nearest,
    basins = profile_basins(profile, nearest, model$index_bounds, criterion),
    roots = roots
  )
}

run_profile <- function(model, W, cfg) {
  starts <- lapply(model$profile_grid, profile_start, model = model, W = W, cfg = cfg)
  objective <- vapply(starts, `[[`, numeric(1), "objective")
  index_moment <- vapply(starts, `[[`, numeric(1), "index_moment")
  index_instrument_rms <- vapply(starts, `[[`, numeric(1), "index_instrument_rms")
  minima <- unique(c(which.min(objective), local_extrema_indices(objective, "min")))
  minima <- minima[order(objective[minima])]
  selected <- integer()
  for (index in minima) {
    if (!length(selected) || all(abs(index - selected) >= 2L)) selected <- c(selected, index)
    if (length(selected) >= cfg$max_profile_candidates) break
  }
  profile <- data.frame(
    index = model$profile_grid,
    objective = objective,
    index_moment = index_moment,
    index_instrument_rms = index_instrument_rms
  )
  grid_basins <- profile_basins(
    profile, selected, model$index_bounds, "objective"
  )
  roots <- refine_ces_profile_roots(model, W, cfg, starts, profile, "objective")
  list(
    profile = profile,
    starts = starts,
    candidate_indices = selected,
    basins = grid_basins,
    candidate_starts = c(starts[selected], roots$starts),
    candidate_basins = c(grid_basins, roots$basins),
    candidate_sources = c(
      rep("profile_local_minimum", length(selected)),
      rep("uniroot_index_moment", length(roots$starts))
    ),
    refined_roots = roots$roots
  )
}

numeric_indexed_jacobian <- function(theta, model, cfg) {
  k <- length(theta)
  G <- matrix(NA_real_, k, k)
  for (j in seq_len(k)) {
    step <- cfg$finite_difference_relative_step * max(1, abs(theta[[j]]))
    if (j == k && model$index_name == "z") step <- cfg$finite_difference_z_step
    if (j == k && model$index_name == "gamma") {
      step <- cfg$finite_difference_gamma_relative_step * max(1, abs(theta[[j]]))
    }
    step <- max(step, 1e-7)
    plus <- minus <- theta
    plus[[j]] <- plus[[j]] + step
    minus[[j]] <- minus[[j]] - step
    G[, j] <-
      (indexed_moment_components(plus, model)$moments -
         indexed_moment_components(minus, model)$moments) / (2 * step)
  }
  G
}

jacobian_diagnostics <- function(G) {
  raw <- svd(G, nu = 0L, nv = 0L)$d
  norms <- sqrt(colSums(G^2))
  norms[norms <= 1e-12] <- 1
  scaled <- svd(sweep(G, 2L, norms, FUN = "/"), nu = 0L, nv = 0L)$d
  list(
    raw_smin = min(raw),
    raw_condition = max(raw) / max(min(raw), 1e-16),
    scaled_smin = min(scaled),
    scaled_condition = max(scaled) / max(min(scaled), 1e-16)
  )
}

optimize_profile_candidate <- function(start, basin, source, model, W, cfg) {
  lower <- c(rep(-Inf, model$p), cfg$lambda_bounds[[1L]], basin[["lower"]])
  upper <- c(rep(Inf, model$p), cfg$lambda_bounds[[2L]], basin[["upper"]])
  start <- pmin(upper, pmax(lower, start))
  start_metrics <- indexed_diagnostics(start, model, W)
  exact_ces_root <-
    model$name == "CES" &&
    start_metrics$max_abs_moment <= cfg$ces_root_moment_tolerance
  index_scale <- if (model$index_name == "gamma") {
    max(1, diff(model$index_bounds) / 10)
  } else {
    0.20
  }
  parscale <- pmax(abs(start), c(rep(0.25, model$p), 0.20, index_scale))
  fit <- if (exact_ces_root) {
    NULL
  } else {
    tryCatch(
      stats::optim(
        par = start,
        fn = indexed_objective,
        model = model,
        W = W,
        lambda_bounds = cfg$lambda_bounds,
        method = "L-BFGS-B",
        lower = lower,
        upper = upper,
        control = list(
          maxit = cfg$optim_maxit,
          factr = cfg$optim_factr,
          pgtol = cfg$optim_pgtol,
          parscale = parscale
        )
      ),
      error = function(e) NULL
    )
  }
  if (exact_ces_root) {
    theta <- start
    value <- start_metrics$objective
    convergence <- 0L
    message <- "retained exact concentrated CES moment root"
  } else if (is.null(fit) || any(!is.finite(fit$par))) {
    theta <- start
    value <- indexed_objective(theta, model, W, cfg$lambda_bounds)
    convergence <- 999L
    message <- "optim failed; retained profile start"
  } else {
    theta <- fit$par
    value <- fit$value
    convergence <- fit$convergence
    message <- fit$message %||% ""
  }
  G <- numeric_indexed_jacobian(theta, model, cfg)
  metrics <- indexed_diagnostics(theta, model, W)
  list(
    theta = theta,
    objective = metrics$objective,
    index_moment = metrics$index_moment,
    index_instrument_rms = metrics$index_instrument_rms,
    convergence = convergence,
    message = message,
    basin = basin,
    source = source,
    jacobian_diagnostics = jacobian_diagnostics(G)
  )
}

select_candidate <- function(candidates) {
  objective <- vapply(candidates, `[[`, numeric(1), "objective")
  which.min(objective)
}

normalize_weight_matrix <- function(W) {
  W <- symmetrize(W)
  scale <- sum(diag(W))
  if (!is.finite(scale) || scale <= 0) stopf("A GMM weight matrix has invalid scale.")
  W / scale
}

relative_parameter_change <- function(new, old) {
  max(abs(new - old) / pmax(1, abs(old)))
}

relative_weight_change <- function(new, old) {
  new <- normalize_weight_matrix(new)
  old <- normalize_weight_matrix(old)
  sqrt(sum((new - old)^2)) / max(sqrt(sum(old^2)), 1e-14)
}

fit_indexed_gmm <- function(model, cfg, initial_weight_matrix = NULL) {
  k <- model$p + 2L
  run_label <- model$run_label %||% model$name
  W <- if (is.null(initial_weight_matrix)) diag(k) else {
    initial_weight_matrix <- as.matrix(initial_weight_matrix)
    if (!identical(dim(initial_weight_matrix), c(k, k)) ||
        any(!is.finite(initial_weight_matrix))) {
      stopf("The initial %s GMM weight matrix has invalid dimensions or values.", model$name)
    }
    eigenvalues <- eigen(symmetrize(initial_weight_matrix), symmetric = TRUE,
                         only.values = TRUE)$values
    if (min(eigenvalues) <= 0) stopf("The initial %s GMM weight must be positive definite.", model$name)
    symmetrize(initial_weight_matrix)
  }
  global <- run_profile(model, W, cfg)
  candidates <- lapply(seq_along(global$candidate_starts), function(c) {
    optimize_profile_candidate(
      global$candidate_starts[[c]]$theta,
      global$candidate_basins[[c]],
      global$candidate_sources[[c]],
      model,
      W,
      cfg
    )
  })
  selected <- select_candidate(candidates)
  selected_initially <- selected
  current <- candidates[[selected]]
  cat(sprintf(
    "[%s GMM initial] %s=%.8f; lambda=%.8f; selected candidate=%d.\n",
    run_label, model$index_name, tail(current$theta, 1L),
    current$theta[[k - 1L]], selected
  ))

  iteration_history <- vector("list", cfg$gmm_max_outer_iterations)
  converged <- FALSE
  iterations_used <- 0L
  for (iteration in seq_len(cfg$gmm_max_outer_iterations)) {
    current_parts <- indexed_moment_components(current$theta, model)
    current_covariance <- gmm_score_covariance(
      current_parts$scores, cfg$matrix_eigen_floor
    )
    W_fit <- safe_solve(current_covariance$Sigma)

    # Re-optimize every pre-selected basin under the same updated weight.  This
    # avoids silently locking the iterated estimator into the first basin when
    # the covariance weight changes the finite-sample ordering of candidates.
    updated_candidates <- lapply(candidates, function(candidate) {
      optimize_profile_candidate(
        candidate$theta, candidate$basin, candidate$source, model, W_fit, cfg
      )
    })
    selected_updated <- select_candidate(updated_candidates)
    updated <- updated_candidates[[selected_updated]]

    updated_parts <- indexed_moment_components(updated$theta, model)
    updated_covariance <- gmm_score_covariance(
      updated_parts$scores, cfg$matrix_eigen_floor
    )
    W_updated <- safe_solve(updated_covariance$Sigma)
    parameter_change <- relative_parameter_change(updated$theta, current$theta)
    weight_change <- relative_weight_change(W_updated, W_fit)

    iteration_history[[iteration]] <- data.frame(
      model = model$name,
      outer_iteration = iteration,
      selected_candidate = selected_updated,
      index_estimate = tail(updated$theta, 1L),
      lambda_estimate = updated$theta[[k - 1L]],
      parameter_change = parameter_change,
      normalized_weight_change = weight_change,
      optimizer_convergence = updated$convergence,
      objective = indexed_objective(
        updated$theta, model, W_updated, cfg$lambda_bounds
      ),
      stringsAsFactors = FALSE
    )
    cat(sprintf(
      paste0(
        "[%s GMM update %02d] parameter change=%.3e; normalized weight ",
        "change=%.3e; %s=%.8f; lambda=%.8f; candidate=%d.\n"
      ),
      run_label, iteration, parameter_change, weight_change,
      model$index_name, tail(updated$theta, 1L), updated$theta[[k - 1L]],
      selected_updated
    ))
    iterations_used <- iteration
    candidates <- updated_candidates
    selected <- selected_updated
    current <- updated
    if (updated$convergence == 0L &&
        parameter_change <= cfg$gmm_parameter_tolerance &&
        weight_change <= cfg$gmm_weight_tolerance) {
      converged <- TRUE
      break
    }
  }
  iteration_history <- do.call(rbind, iteration_history[seq_len(iterations_used)])
  if (!converged) {
    warnf(
      "%s iterated GMM did not jointly converge within %d outer updates.",
      run_label, cfg$gmm_max_outer_iterations
    )
  }

  parts <- indexed_moment_components(current$theta, model)
  score_covariance <- gmm_score_covariance(parts$scores, cfg$matrix_eigen_floor)
  final_weight_matrix <- safe_solve(score_covariance$Sigma)
  G <- numeric_indexed_jacobian(current$theta, model, cfg)
  diagnostics <- jacobian_diagnostics(G)
  G_inverse <- safe_solve(G)
  V_root_n <- symmetrize(
    G_inverse %*% score_covariance$Sigma %*% t(G_inverse)
  )
  standard_error <- sqrt(pmax(diag(V_root_n) / model$n, 0))
  index_hat <- current$theta[[k]]
  lambda_hat <- current$theta[[k - 1L]]
  index_boundary <-
    abs(index_hat - model$index_bounds[[1L]]) <= cfg$boundary_tolerance ||
    abs(index_hat - model$index_bounds[[2L]]) <= cfg$boundary_tolerance
  lambda_boundary <-
    abs(lambda_hat - cfg$lambda_bounds[[1L]]) <= cfg$boundary_tolerance ||
    abs(lambda_hat - cfg$lambda_bounds[[2L]]) <= cfg$boundary_tolerance

  candidate_table <- do.call(rbind, lapply(seq_along(candidates), function(i) {
    candidate <- candidates[[i]]
    data.frame(
      model = model$name,
      candidate = i,
      selected_initially = i == selected_initially,
      selected_finally = i == selected,
      candidate_source = candidate$source,
      objective = candidate$objective,
      index_moment = candidate$index_moment,
      index_instrument_rms = candidate$index_instrument_rms,
      lambda = candidate$theta[[k - 1L]],
      index_name = model$index_name,
      index_estimate = candidate$theta[[k]],
      basin_lower = candidate$basin[["lower"]],
      basin_upper = candidate$basin[["upper"]],
      raw_jacobian_smin = candidate$jacobian_diagnostics$raw_smin,
      scaled_jacobian_smin = candidate$jacobian_diagnostics$scaled_smin,
      optim_convergence = candidate$convergence
    )
  }))
  profile <- global$profile
  names(profile)[names(profile) == "index"] <- model$index_name
  profile$model <- model$name

  list(
    model = model$name,
    index_name = model$index_name,
    theta = current$theta,
    standard_error = standard_error,
    objective = indexed_objective(
      current$theta, model, final_weight_matrix, cfg$lambda_bounds
    ),
    final_weight_matrix = final_weight_matrix,
    residual = parts$residual,
    moments = parts$moments,
    profile = profile,
    candidates = candidate_table,
    refined_profile_roots = global$refined_roots,
    selected_candidate_source = current$source,
    selected_index_moment = current$index_moment,
    selected_index_instrument_rms = current$index_instrument_rms,
    index_boundary_hit = index_boundary,
    lambda_boundary_hit = lambda_boundary,
    basin_boundary_hit =
      abs(index_hat - current$basin[["lower"]]) <= cfg$boundary_tolerance ||
      abs(index_hat - current$basin[["upper"]]) <= cfg$boundary_tolerance,
    jacobian_diagnostics = diagnostics,
    score_covariance_raw_min_eigenvalue = score_covariance$raw_min_eigenvalue,
    score_covariance_condition = score_covariance$condition_number,
    optim_convergence = current$convergence,
    gmm_converged = converged,
    gmm_outer_iterations = iterations_used,
    gmm_parameter_rounds = iterations_used + 1L,
    gmm_iteration_history = iteration_history,
    final_parameter_change = tail(iteration_history$parameter_change, 1L),
    final_normalized_weight_change = tail(
      iteration_history$normalized_weight_change, 1L
    )
  )
}

make_fixed_rms_standardized_model <- function(raw_model, raw_fit, cfg) {
  if (raw_model$name != "QSAR") stopf("Fixed RMS comparison is implemented for QSAR only.")
  raw_parts <- indexed_moment_components(raw_fit$theta, raw_model)
  raw_rms <- sqrt(colMeans(raw_parts$raw_instruments^2))
  scale <- pmax(raw_rms, cfg$instrument_rms_floor)
  names(scale) <- c(colnames(raw_model$X), "peer_level", "peer_derivative")

  standardized_model <- raw_model
  standardized_model$instrument_scale <- scale
  standardized_model$run_label <- "QSAR standardized instruments"

  standardized_parts <- indexed_moment_components(raw_fit$theta, standardized_model)
  standardized_rms <- sqrt(colMeans(standardized_parts$instruments^2))
  scale_table <- data.frame(
    instrument = names(scale),
    fixed_divisor = as.numeric(scale),
    RMS_at_scale_freeze_point = as.numeric(raw_rms),
    standardized_RMS_at_scale_freeze_point = as.numeric(standardized_rms),
    floor_active = raw_rms < cfg$instrument_rms_floor,
    stringsAsFactors = FALSE
  )

  # If g_std = D^{-1} g_raw, W_std = D W_raw D.  Since the original first
  # round uses W_raw=I, the equivalent standardized first-round weight is D^2.
  initial_weight <- diag(scale^2, nrow = length(scale))
  transformed_moment_error <- max(abs(
    standardized_parts$moments - raw_parts$moments / scale
  ))
  raw_initial_objective <- sum(raw_parts$moments^2)
  standardized_initial_objective <- drop(crossprod(
    standardized_parts$moments,
    initial_weight %*% standardized_parts$moments
  ))

  list(
    model = standardized_model,
    scale = scale,
    scale_table = scale_table,
    initial_weight = initial_weight,
    transformed_moment_error = transformed_moment_error,
    raw_initial_objective = raw_initial_objective,
    standardized_initial_objective = standardized_initial_objective
  )
}

make_neighbor_matrix_plan <- function(neighbors) {
  degree <- lengths(neighbors)
  if (!length(degree) || min(degree) < 1L) {
    stopf("An isolate entered the Assumption 3 bootstrap plan.")
  }
  index <- matrix(1L, nrow = length(neighbors), ncol = max(degree))
  valid <- matrix(FALSE, nrow = length(neighbors), ncol = max(degree))
  for (i in seq_along(neighbors)) {
    columns <- seq_len(degree[[i]])
    index[i, columns] <- neighbors[[i]]
    valid[i, columns] <- TRUE
  }
  list(index = index, valid = valid)
}

fast_peer_quantiles <- function(values, plan, probabilities) {
  neighbor_values <- matrix(
    values[as.vector(plan$index)],
    nrow = nrow(plan$index), ncol = ncol(plan$index)
  )
  neighbor_values[!plan$valid] <- NA_real_
  result <- matrixStats::rowQuantiles(
    neighbor_values, probs = probabilities, na.rm = TRUE, type = 7
  )
  if (length(probabilities) == 1L) as.numeric(result) else result
}

simulate_qsar_equilibrium_for_assumption3 <- function(
  base, errors, neighbor_plan, lambda, z, tolerance, maximum_iterations
) {
  y <- base + errors
  for (iteration in seq_len(maximum_iterations)) {
    updated <- base + errors + lambda * fast_peer_quantiles(y, neighbor_plan, z)
    change <- max(abs(updated - y))
    y <- updated
    if (change < tolerance) return(y)
  }
  stopf(
    "An Assumption 3 bootstrap equilibrium failed within %d iterations.",
    maximum_iterations
  )
}

assumption3_bootstrap_chunk_worker <- function(replication_ids) {
  state <- assumption3_boot_state
  mu_sum <- matrix(
    0, nrow = nrow(state$moment_plan$index), ncol = length(state$z_grid)
  )
  order_sum <- lapply(state$moment_degree, numeric)
  for (unused in replication_ids) {
    errors <- sample(
      state$residual_pool, length(state$residual_pool), replace = TRUE
    )
    equilibrium_y <- simulate_qsar_equilibrium_for_assumption3(
      state$base_support, errors, state$support_plan, state$lambda, state$z0,
      state$tolerance, state$maximum_iterations
    )
    mu_sum <- mu_sum + fast_peer_quantiles(
      equilibrium_y, state$moment_plan, state$z_grid
    )
    for (i in seq_along(state$moment_neighbors)) {
      order_sum[[i]] <- order_sum[[i]] +
        sort(equilibrium_y[state$moment_neighbors[[i]]])
    }
  }
  list(mu_sum = mu_sum, order_sum = order_sum)
}

bootstrap_expected_peer_quantiles_for_assumption3 <- function(
  prep, net, theta, z_grid, cfg
) {
  p <- ncol(prep$X)
  beta <- theta[seq_len(p)]
  lambda <- theta[[p + 1L]]
  z0 <- theta[[p + 2L]]
  base_support <- drop(prep$X_support %*% beta)
  support_plan <- make_neighbor_matrix_plan(net$support_neighbors)
  moment_plan <- make_neighbor_matrix_plan(net$moment_neighbors)
  raw_peer_at_z0 <- fast_peer_quantiles(prep$Y_support, support_plan, z0)
  residual_pool <- prep$Y_support - base_support - lambda * raw_peer_at_z0
  residual_pool <- residual_pool - mean(residual_pool)

  assumption3_boot_state <- list(
    base_support = base_support,
    residual_pool = residual_pool,
    support_plan = support_plan,
    moment_plan = moment_plan,
    moment_neighbors = net$moment_neighbors,
    moment_degree = net$moment_degree,
    lambda = lambda,
    z0 = z0,
    z_grid = z_grid,
    tolerance = cfg$diagnostic_equilibrium_tolerance,
    maximum_iterations = cfg$diagnostic_equilibrium_max_iterations
  )
  repetitions <- seq_len(cfg$diagnostic_bootstrap_B)
  task_size <- max(1L, as.integer(cfg$diagnostic_reps_per_task))
  tasks <- split(repetitions, ceiling(repetitions / task_size))
  detected <- suppressWarnings(parallel::detectCores(logical = TRUE))
  if (!is.finite(detected) || detected < 1L) detected <- 1L
  workers <- max(1L, min(
    length(tasks), floor(detected * cfg$diagnostic_cpu_fraction)
  ))
  cat(sprintf(
    "Assumption 3 bootstrap: B=%d using %d of %d logical cores.\n",
    cfg$diagnostic_bootstrap_B, workers, detected
  ))

  cluster <- parallel::makePSOCKcluster(workers)
  on.exit(if (!is.null(cluster)) parallel::stopCluster(cluster), add = TRUE)
  parallel::clusterExport(
    cluster, "assumption3_boot_state", envir = environment()
  )
  parallel::clusterExport(
    cluster,
    c(
      "assumption3_bootstrap_chunk_worker",
      "simulate_qsar_equilibrium_for_assumption3",
      "fast_peer_quantiles", "stopf"
    ),
    envir = environment(bootstrap_expected_peer_quantiles_for_assumption3)
  )
  parallel::clusterSetRNGStream(cluster, cfg$diagnostic_bootstrap_seed)

  mu_sum <- matrix(0, nrow = nrow(moment_plan$index), ncol = length(z_grid))
  order_sum <- lapply(net$moment_degree, numeric)
  waves <- split(tasks, ceiling(seq_along(tasks) / workers))
  completed <- 0L
  for (wave in waves) {
    results <- parallel::parLapply(cluster, wave, assumption3_bootstrap_chunk_worker)
    for (result in results) {
      mu_sum <- mu_sum + result$mu_sum
      for (i in seq_along(order_sum)) {
        order_sum[[i]] <- order_sum[[i]] + result$order_sum[[i]]
      }
    }
    completed <- completed + sum(lengths(wave))
    cat(sprintf(
      "Assumption 3 bootstrap %03d/%03d\n",
      completed, cfg$diagnostic_bootstrap_B
    ))
  }
  parallel::stopCluster(cluster)
  cluster <- NULL
  list(
    mu = mu_sum / cfg$diagnostic_bootstrap_B,
    expected_order = lapply(
      order_sum, function(x) x / cfg$diagnostic_bootstrap_B
    )
  )
}

residualize_columns_on_X <- function(A, X) {
  A - X %*% safe_solve(crossprod(X), crossprod(X, A))
}

# =============================================================================
# Standardized finite-sample checks for Assumptions 1--5 and 7--8
# =============================================================================

empirical_psi2_norm <- function(x) {
  x <- as.numeric(x) - mean(x)
  if (max(abs(x)) <= .Machine$double.eps) return(0)
  equation <- function(scale) mean(exp(pmin((x / scale)^2, 700))) - 2
  lower <- max(.Machine$double.eps, stats::sd(x) / 100)
  upper <- max(stats::sd(x), max(abs(x)) / sqrt(log(2)))
  while (equation(upper) > 0) upper <- 2 * upper
  stats::uniroot(equation, c(lower, upper), tol = 1e-10)$root
}

build_quantile_selector <- function(values, neighbors, z) {
  n <- length(neighbors)
  row_index <- col_index <- integer(0)
  weight <- numeric(0)
  for (i in seq_len(n)) {
    nb <- neighbors[[i]]
    d <- length(nb)
    if (d < 1L) stopf("An isolate entered the quantile-propagation check.")
    ordered <- nb[order(values[nb], nb)]
    if (d == 1L) {
      lower <- upper <- 1L
      fraction <- 0
    } else {
      position <- 1 + (d - 1) * z
      lower <- floor(position)
      upper <- ceiling(position)
      fraction <- position - lower
    }
    if (lower == upper) {
      row_index <- c(row_index, i)
      col_index <- c(col_index, ordered[[lower]])
      weight <- c(weight, 1)
    } else {
      row_index <- c(row_index, i, i)
      col_index <- c(col_index, ordered[[lower]], ordered[[upper]])
      weight <- c(weight, 1 - fraction, fraction)
    }
  }
  Matrix::sparseMatrix(
    i = row_index, j = col_index, x = weight,
    dims = c(n, n), giveCsparse = TRUE
  )
}

realized_kappa_proxy <- function(values, neighbors, z, lambda_abs) {
  B <- build_quantile_selector(values, neighbors, z)
  left <- as.numeric(Matrix::colSums(B))
  Bt <- Matrix::t(B)
  column_sums <- left
  for (iteration in seq_len(1000L)) {
    updated <- left + lambda_abs * as.numeric(Bt %*% column_sums)
    if (max(abs(updated - column_sums)) < 1e-10) {
      column_sums <- updated
      break
    }
    column_sums <- updated
  }
  if (any(!is.finite(column_sums))) {
    stopf("The quantile-propagation calculation failed at z=%.2f.", z)
  }
  mean(column_sums^2)
}

numeric_standardized_jacobian <- function(theta, model, cfg) {
  k <- length(theta)
  G <- matrix(NA_real_, k, k)
  for (j in seq_len(k)) {
    step <- cfg$finite_difference_relative_step * max(1, abs(theta[[j]]))
    if (j == k) step <- cfg$finite_difference_z_step
    step <- max(step, 1e-7)
    plus <- minus <- theta
    plus[[j]] <- plus[[j]] + step
    minus[[j]] <- minus[[j]] - step
    G[, j] <- (
      indexed_moment_components(plus, model)$moments -
        indexed_moment_components(minus, model)$moments
    ) / (2 * step)
  }
  G
}

standardize_rms_columns <- function(A, floor_value) {
  divisor <- sqrt(colMeans(A^2))
  divisor <- pmax(divisor, floor_value)
  list(
    matrix = sweep(A, 2L, divisor, FUN = "/"),
    divisor = divisor
  )
}

make_standardized_local_relevance <- function(
  prep, model, fit, standardization, bootstrap, cfg
) {
  p <- model$p
  lambda_hat <- fit$theta[[p + 1L]]
  z_hat <- fit$theta[[p + 2L]]
  z_lower <- max(cfg$z_bounds[[1L]], z_hat - cfg$diagnostic_z_half_width)
  z_upper <- min(cfg$z_bounds[[2L]], z_hat + cfg$diagnostic_z_half_width)
  z_grid <- sort(unique(round(c(
    seq(z_lower, z_upper, by = cfg$diagnostic_z_step), z_hat, z_upper
  ), 12L)))
  z_grid[[which.min(abs(z_grid - z_hat))]] <- z_hat
  z_grid <- sort(unique(z_grid))
  lambda_grid <- sort(unique(clip(
    lambda_hat + c(-cfg$diagnostic_lambda_half_width, 0,
                   cfg$diagnostic_lambda_half_width),
    cfg$lambda_bounds
  )))
  z0_index <- which.min(abs(z_grid - z_hat))
  mu0 <- bootstrap$mu[, z0_index]
  # The estimating level instrument is fitted_peer, whereas Z_P in
  # Assumption 3 contains lambda*fitted_peer.  Multiplying the fixed level
  # divisor by |lambda_hat| therefore places both columns of Z_P on the same
  # fixed RMS scale at the estimated parameter.
  peer_scale <- c(
    abs(lambda_hat) * standardization$scale[[p + 1L]],
    standardization$scale[[p + 2L]]
  )
  peer_scale <- pmax(peer_scale, cfg$instrument_rms_floor)

  rows <- list()
  counter <- 0L
  for (lambda in lambda_grid) {
    for (g in seq_along(z_grid)) {
      z <- z_grid[[g]]
      if (abs(z - z_hat) <= 1e-12) next
      peer <- evaluate_peer_terms(z, model)
      Z <- cbind(lambda * peer$fitted, lambda * peer$derivative)
      Z_standardized <- sweep(Z, 2L, peer_scale, FUN = "/")
      secant <- (bootstrap$mu[, g] - mu0) / (z - z_hat)
      R <- cbind(bootstrap$mu[, g], lambda_hat * secant)
      R_partial <- residualize_columns_on_X(R, prep$X)
      R_standardization <- standardize_rms_columns(
        R_partial, cfg$instrument_rms_floor
      )
      S <- crossprod(
        Z_standardized, R_standardization$matrix
      ) / nrow(prep$X)
      singular_values <- svd(S, nu = 0L, nv = 0L)$d
      counter <- counter + 1L
      rows[[counter]] <- data.frame(
        lambda = lambda,
        z = z,
        standardized_secant_smin = min(singular_values),
        standardized_secant_smax = max(singular_values),
        standardized_secant_condition =
          max(singular_values) / max(min(singular_values), 1e-16),
        instrument_1_rms = sqrt(mean(Z_standardized[, 1L]^2)),
        instrument_2_rms = sqrt(mean(Z_standardized[, 2L]^2)),
        R_1_divisor = R_standardization$divisor[[1L]],
        R_2_divisor = R_standardization$divisor[[2L]],
        standardized_R_F2_over_n = sum(R_standardization$matrix^2) /
          nrow(prep$X),
        stringsAsFactors = FALSE
      )
    }
  }
  path <- do.call(rbind, rows)
  list(
    path = path,
    uniform_smin = min(path$standardized_secant_smin),
    maximum_condition = max(path$standardized_secant_condition),
    minimum_instrument_rms = min(path$instrument_1_rms, path$instrument_2_rms),
    minimum_R_divisor = min(path$R_1_divisor, path$R_2_divisor),
    maximum_R_divisor = max(path$R_1_divisor, path$R_2_divisor),
    maximum_standardized_R_norm = max(path$standardized_R_F2_over_n),
    z_grid = z_grid,
    lambda_grid = lambda_grid
  )
}

make_spacing_checks <- function(prep, net, expected_order, z_range) {
  rows <- vector("list", length(net$moment_index))
  for (i in seq_along(net$moment_index)) {
    d <- net$moment_degree[[i]]
    pseudo <- sort(prep$fitted_qsar_support[net$moment_neighbors[[i]]])
    pseudo_gap <- d * diff(pseudo)
    m <- expected_order[[i]]
    s <- (d - 1) * diff(m)
    k_s_all <- seq_len(d - 1L)
    k_s <- k_s_all[
      k_s_all / (d - 1) >= z_range[[1L]] &
        (k_s_all - 1) / (d - 1) <= z_range[[2L]]
    ]
    k_delta <- if (d >= 3L) {
      k <- seq_len(d - 2L)
      k[z_range[[1L]] <= k / (d - 1) &
          k / (d - 1) <= z_range[[2L]]]
    } else integer(0)
    rows[[i]] <- data.frame(
      id = net$moment_nodes$id[[i]],
      degree = d,
      max_d_times_fitted_pseudo_gap = max(pseudo_gap),
      max_abs_expected_s = max(abs(s[k_s])),
      max_d_times_expected_delta_s = if (length(k_delta)) {
        max(d * abs(diff(s)[k_delta]))
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

add_condition <- function(table, assumption, quantity, direction, value) {
  rbind(table, data.frame(
    assumption = assumption,
    quantity = quantity,
    desired_direction = direction,
    value = as.numeric(value),
    stringsAsFactors = FALSE
  ))
}

run_standardized_condition_checks <- function(
  prep, net, model, fit, standardization, cfg
) {
  theta <- fit$theta
  p <- model$p
  n <- model$n
  lambda_hat <- theta[[p + 1L]]
  z_hat <- theta[[p + 2L]]

  cat("Checking Assumption 1 on the dense z grid...\n")
  kappa_path <- data.frame(
    z = cfg$diagnostic_kappa_z_grid,
    kappa_proxy = NA_real_
  )
  for (g in seq_len(nrow(kappa_path))) {
    kappa_path$kappa_proxy[[g]] <- realized_kappa_proxy(
      prep$Y_support, net$support_neighbors, kappa_path$z[[g]],
      abs(lambda_hat)
    )
  }
  kappa_max <- max(kappa_path$kappa_proxy)

  cat(sprintf(
    "Approximating expected peer quantiles and order statistics (B=%d)...\n",
    cfg$diagnostic_bootstrap_B
  ))
  z_lower <- max(cfg$z_bounds[[1L]], z_hat - cfg$diagnostic_z_half_width)
  z_upper <- min(cfg$z_bounds[[2L]], z_hat + cfg$diagnostic_z_half_width)
  z_grid <- sort(unique(round(c(
    seq(z_lower, z_upper, by = cfg$diagnostic_z_step), z_hat, z_upper
  ), 12L)))
  z_grid[[which.min(abs(z_grid - z_hat))]] <- z_hat
  z_grid <- sort(unique(z_grid))
  bootstrap <- bootstrap_expected_peer_quantiles_for_assumption3(
    prep, net, theta, z_grid, cfg
  )

  relevance <- make_standardized_local_relevance(
    prep, model, fit, standardization, bootstrap, cfg
  )
  z_range <- c(z_lower, z_upper)
  spacing <- make_spacing_checks(
    prep, net, bootstrap$expected_order, z_range
  )

  parts <- indexed_moment_components(theta, model)
  residual <- parts$residual
  Sigma <- symmetrize(crossprod(parts$scores) / n)
  Sigma_eigen <- sort(eigen(
    Sigma, symmetric = TRUE, only.values = TRUE
  )$values)
  G <- numeric_standardized_jacobian(theta, model, cfg)
  GtG_eigen <- pmax(sort(eigen(
    symmetrize(crossprod(G)), symmetric = TRUE, only.values = TRUE
  )$values), 0)
  G_singular <- sqrt(pmax(GtG_eigen, 0))

  max_Z_norm <- 0
  assumption3_peer_scale <- c(
    abs(lambda_hat) * standardization$scale[[p + 1L]],
    standardization$scale[[p + 2L]]
  )
  assumption3_peer_scale <- pmax(
    assumption3_peer_scale, cfg$instrument_rms_floor
  )
  for (lambda in relevance$lambda_grid) {
    for (z in relevance$z_grid) {
      peer <- evaluate_peer_terms(z, model)
      Z <- cbind(lambda * peer$fitted, lambda * peer$derivative)
      Z_std <- sweep(
        Z, 2L, assumption3_peer_scale, FUN = "/"
      )
      max_Z_norm <- max(max_Z_norm, sum(Z_std^2) / n)
    }
  }

  summary <- data.frame(
    assumption = character(0), quantity = character(0),
    desired_direction = character(0), value = numeric(0),
    stringsAsFactors = FALSE
  )
  summary <- add_condition(summary, "Sample", "moment_nodes", "information", n)
  summary <- add_condition(summary, "Estimate", "lambda_hat", "information", lambda_hat)
  summary <- add_condition(summary, "Estimate", "z_hat", "information", z_hat)
  summary <- add_condition(summary, "Equilibrium", "one_minus_abs_lambda_hat",
                           "away_from_zero", 1 - abs(lambda_hat))
  summary <- add_condition(summary, "Parameter interior",
                           "lambda_distance_to_boundary", "away_from_zero",
                           min(lambda_hat - cfg$lambda_bounds[[1L]],
                               cfg$lambda_bounds[[2L]] - lambda_hat))
  summary <- add_condition(summary, "Parameter interior",
                           "lambda_distance_to_zero", "away_from_zero",
                           abs(lambda_hat))
  summary <- add_condition(summary, "Parameter interior",
                           "z_distance_to_boundary", "away_from_zero",
                           min(z_hat - cfg$z_bounds[[1L]],
                               cfg$z_bounds[[2L]] - z_hat))
  summary <- add_condition(summary, "Assumption 1", "max_X_row_norm",
                           "bounded", max(sqrt(rowSums(prep$X^2))))
  summary <- add_condition(summary, "Assumption 1", "max_kappa_proxy",
                           "bounded", kappa_max)
  summary <- add_condition(
    summary, "Assumption 1", "z_at_max_kappa_proxy", "information",
    kappa_path$z[[which.max(kappa_path$kappa_proxy)]]
  )
  summary <- add_condition(summary, "Assumption 1", "kappa_over_n",
                           "toward_zero", kappa_max / n)
  summary <- add_condition(summary, "Assumption 2", "residual_mean",
                           "toward_zero", mean(residual))
  summary <- add_condition(summary, "Assumption 2", "empirical_residual_psi2",
                           "bounded", empirical_psi2_norm(residual))
  summary <- add_condition(
    summary, "Assumption 3", "lambda_min_X_cross_X_over_n",
    "away_from_zero", min(eigen(
      crossprod(prep$X) / n, symmetric = TRUE, only.values = TRUE
    )$values)
  )
  summary <- add_condition(
    summary, "Assumption 3", "standardized_local_secant_smin",
    "away_from_zero", relevance$uniform_smin
  )
  summary <- add_condition(
    summary, "Assumption 3", "minimum_standardized_instrument_RMS",
    "away_from_zero", relevance$minimum_instrument_rms
  )
  summary <- add_condition(
    summary, "Assumption 3", "minimum_R_RMS_divisor",
    "away_from_zero", relevance$minimum_R_divisor
  )
  summary <- add_condition(
    summary, "Assumption 3", "maximum_R_RMS_divisor",
    "bounded", relevance$maximum_R_divisor
  )
  summary <- add_condition(summary, "Assumption 4", "kernel_integral",
                           "equal_to_one", 1)
  summary <- add_condition(summary, "Assumption 4", "kernel_first_moment",
                           "equal_to_zero", 0)
  summary <- add_condition(summary, "Assumption 4", "kernel_second_moment",
                           "positive_and_finite", 1)
  summary <- add_condition(summary, "Assumption 4",
                           "gaussian_nonnegative_symmetric_twice_continuously_differentiable",
                           "satisfied_by_construction", 1)
  summary <- add_condition(summary, "Assumption 4",
                           "gaussian_kernel_derivative_bounds",
                           "finite", 1)
  summary <- add_condition(
    summary, "Assumption 5(i)", "max_d_times_fitted_pseudo_gap_proxy",
    "bounded", max(spacing$max_d_times_fitted_pseudo_gap)
  )
  summary <- add_condition(
    summary, "Assumption 5(ii)", "lambda_max_X_cross_X_over_n",
    "bounded", max(eigen(
      crossprod(prep$X) / n, symmetric = TRUE, only.values = TRUE
    )$values)
  )
  summary <- add_condition(
    summary, "Assumption 5(ii)", "max_standardized_Z_F2_over_n",
    "bounded", max_Z_norm
  )
  summary <- add_condition(
    summary, "Assumption 5(ii)", "max_standardized_R_F2_over_n",
    "bounded", relevance$maximum_standardized_R_norm
  )
  summary <- add_condition(
    summary, "Assumption 7(i)", "z_neighborhood_lower",
    "information", z_lower
  )
  summary <- add_condition(
    summary, "Assumption 7(i)", "z_neighborhood_upper",
    "information", z_upper
  )
  summary <- add_condition(
    summary, "Assumption 7(i)", "max_abs_expected_s",
    "bounded", max(spacing$max_abs_expected_s, na.rm = TRUE)
  )
  summary <- add_condition(
    summary, "Assumption 7(i)", "max_d_times_expected_delta_s",
    "bounded", max(spacing$max_d_times_expected_delta_s, na.rm = TRUE)
  )
  summary <- add_condition(
    summary, "Assumption 8(i)", "standardized_Sigma_min_eigenvalue",
    "away_from_zero", min(Sigma_eigen)
  )
  summary <- add_condition(
    summary, "Assumption 8(i)", "standardized_Sigma_max_eigenvalue",
    "bounded", max(Sigma_eigen)
  )
  summary <- add_condition(
    summary, "Assumption 8(i)", "standardized_Sigma_condition_number",
    "bounded", max(Sigma_eigen) / max(min(Sigma_eigen), 1e-16)
  )
  summary <- add_condition(
    summary, "Assumption 8(ii)", "standardized_GtG_min_eigenvalue",
    "away_from_zero", min(GtG_eigen)
  )
  summary <- add_condition(
    summary, "Assumption 8(ii)", "standardized_GtG_max_eigenvalue",
    "bounded", max(GtG_eigen)
  )
  summary <- add_condition(
    summary, "Assumption 8(ii)", "standardized_Jacobian_smin",
    "away_from_zero", min(G_singular)
  )
  summary <- add_condition(
    summary, "Assumption 8(ii)", "standardized_Jacobian_condition_number",
    "bounded", max(G_singular) / max(min(G_singular), 1e-16)
  )
  summary <- add_condition(
    summary, "Estimated moments", "standardized_moment_norm",
    "toward_zero", sqrt(sum(parts$moments^2))
  )
  list(
    summary = summary,
    kappa_path = kappa_path,
    relevance_path = relevance$path,
    spacing = spacing,
    covariance_eigenvalues = data.frame(
      index = seq_along(Sigma_eigen), eigenvalue = Sigma_eigen
    ),
    jacobian_gram_eigenvalues = data.frame(
      index = seq_along(GtG_eigen), eigenvalue = GtG_eigen,
      singular_value = G_singular
    )
  )
}

write_standardized_condition_outputs <- function(
  output_dir, standardization, invariance, checks
) {
  utils::write.csv(
    standardization$scale_table,
    file.path(output_dir, "standardized_instrument_RMS_scales.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    invariance,
    file.path(output_dir, "standardized_estimate_invariance_check.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$summary,
    file.path(output_dir, "standardized_assumption_checks.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$relevance_path,
    file.path(output_dir, "standardized_assumption3_path.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$kappa_path,
    file.path(output_dir, "assumption1_kappa_path.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$spacing,
    file.path(output_dir, "local_spacing_and_response_regularity.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$covariance_eigenvalues,
    file.path(output_dir, "standardized_covariance_eigenvalues.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    checks$jacobian_gram_eigenvalues,
    file.path(output_dir, "standardized_Jacobian_Gram_eigenvalues.csv"),
    row.names = FALSE
  )
  cat("\nStandardized-estimation invariance check\n")
  print(invariance, row.names = FALSE)
  cat("\nCondition checks (bandwidth conditions omitted)\n")
  print(checks$summary, row.names = FALSE, digits = 6)
  invisible(TRUE)
}

fit_linear_iterated_gmm <- function(
  regressors, instruments, y, p, lambda_bounds, cfg, model_name
) {
  n <- length(y)
  a <- colMeans(instruments * y)
  B <- crossprod(instruments, regressors) / n

  estimate_with_weight <- function(W) {
    theta <- drop(safe_solve(crossprod(B, W %*% B), crossprod(B, W %*% a)))
    unconstrained_lambda <- tail(theta, 1L)
    theta[[p + 1L]] <- clip(unconstrained_lambda, lambda_bounds)
    if (abs(theta[[p + 1L]] - unconstrained_lambda) > 0) {
      B_x <- B[, seq_len(p), drop = FALSE]
      adjusted <- a - B[, p + 1L] * theta[[p + 1L]]
      theta[seq_len(p)] <- drop(safe_solve(
        crossprod(B_x, W %*% B_x), crossprod(B_x, W %*% adjusted)
      ))
    }
    theta
  }

  theta <- estimate_with_weight(diag(ncol(instruments)))
  cat(sprintf(
    "[%s GMM initial] lambda=%.8f.\n", model_name, tail(theta, 1L)
  ))
  iteration_history <- vector("list", cfg$gmm_max_outer_iterations)
  converged <- FALSE
  iterations_used <- 0L
  for (iteration in seq_len(cfg$gmm_max_outer_iterations)) {
    residual <- y - drop(regressors %*% theta)
    current_covariance <- gmm_score_covariance(
      instruments * residual, cfg$matrix_eigen_floor
    )
    W_fit <- safe_solve(current_covariance$Sigma)
    updated_theta <- estimate_with_weight(W_fit)

    updated_residual <- y - drop(regressors %*% updated_theta)
    updated_scores <- instruments * updated_residual
    updated_covariance <- gmm_score_covariance(
      updated_scores, cfg$matrix_eigen_floor
    )
    W_updated <- safe_solve(updated_covariance$Sigma)
    parameter_change <- relative_parameter_change(updated_theta, theta)
    weight_change <- relative_weight_change(W_updated, W_fit)
    moments <- colMeans(updated_scores)
    iteration_history[[iteration]] <- data.frame(
      model = model_name,
      outer_iteration = iteration,
      selected_candidate = NA_integer_,
      index_estimate = NA_real_,
      lambda_estimate = tail(updated_theta, 1L),
      parameter_change = parameter_change,
      normalized_weight_change = weight_change,
      optimizer_convergence = 0L,
      objective = drop(crossprod(moments, W_updated %*% moments)),
      stringsAsFactors = FALSE
    )
    cat(sprintf(
      paste0(
        "[%s GMM update %02d] parameter change=%.3e; normalized weight ",
        "change=%.3e; lambda=%.8f.\n"
      ),
      model_name, iteration, parameter_change, weight_change,
      tail(updated_theta, 1L)
    ))
    iterations_used <- iteration
    theta <- updated_theta
    if (parameter_change <= cfg$gmm_parameter_tolerance &&
        weight_change <= cfg$gmm_weight_tolerance) {
      converged <- TRUE
      break
    }
  }
  iteration_history <- do.call(rbind, iteration_history[seq_len(iterations_used)])
  if (!converged) {
    warnf(
      "%s iterated GMM did not jointly converge within %d outer updates.",
      model_name, cfg$gmm_max_outer_iterations
    )
  }

  residual <- y - drop(regressors %*% theta)
  scores <- instruments * residual
  score_covariance <- gmm_score_covariance(scores, cfg$matrix_eigen_floor)
  W_final <- safe_solve(score_covariance$Sigma)
  G <- -B
  G_inverse <- safe_solve(G)
  V_root_n <- symmetrize(
    G_inverse %*% score_covariance$Sigma %*% t(G_inverse)
  )
  moments <- colMeans(scores)
  list(
    model = model_name,
    theta = theta,
    standard_error = sqrt(pmax(diag(V_root_n) / n, 0)),
    residual = residual,
    moments = moments,
    objective = drop(crossprod(moments, W_final %*% moments)),
    lambda_boundary_hit =
      abs(theta[[length(theta)]] - lambda_bounds[[1L]]) <= cfg$boundary_tolerance ||
      abs(theta[[length(theta)]] - lambda_bounds[[2L]]) <= cfg$boundary_tolerance,
    jacobian_diagnostics = jacobian_diagnostics(G),
    score_covariance_raw_min_eigenvalue = score_covariance$raw_min_eigenvalue,
    score_covariance_condition = score_covariance$condition_number,
    gmm_converged = converged,
    gmm_outer_iterations = iterations_used,
    gmm_parameter_rounds = iterations_used + 1L,
    gmm_iteration_history = iteration_history,
    final_parameter_change = tail(iteration_history$parameter_change, 1L),
    final_normalized_weight_change = tail(
      iteration_history$normalized_weight_change, 1L
    )
  )
}

# The two CES limit cases are fitted separately from the regular finite-gamma
# model.  Their objectives have a different number of moments and therefore are
# diagnostic limit models, not candidates in the finite-gamma root selection.
fit_fixed_peer_gmm <- function(model, index, cfg) {
  peer <- evaluate_peer_terms(index, model)
  fit_linear_iterated_gmm(
    regressors = cbind(model$X, peer$observed),
    instruments = cbind(model$X, peer$fitted),
    y = model$y,
    p = model$p,
    lambda_bounds = cfg$lambda_bounds,
    cfg = cfg,
    model_name = if (index < 0) "CES_min_limit" else "CES_max_limit"
  )
}

annotate_finite_ces_fit <- function(fit) {
  fit$finite_gamma_estimate <- tail(fit$theta, 1L)
  fit$gamma_is_limit <- FALSE
  fit$ces_limit_case <- if (fit$index_boundary_hit) "finite boundary" else "finite interior"
  fit
}

fit_ces_corner_models <- function(model, cfg) {
  result <- lapply(c(-Inf, Inf), function(gamma) {
    fit <- fit_fixed_peer_gmm(model, gamma, cfg)
    fit$model <- if (gamma < 0) "CES_min_corner" else "CES_max_corner"
    fit$gamma <- gamma
    fit$peer_norm <- if (gamma < 0) "peer minimum" else "peer maximum"
    fit$residual_rmse <- sqrt(mean(fit$residual^2))
    fit
  })
  names(result) <- c("minimum", "maximum")
  result
}

# Compare the estimated finite gamma with the two finite bounds and the two CES
# limits.  At each fixed gamma, beta and lambda are re-estimated while the CES
# estimator's final weight matrix is held fixed.  The resulting objectives use
# the same raw moment vector and the same weight and are therefore comparable.
fixed_ces_components <- function(coefficients, gamma, model) {
  beta <- coefficients[seq_len(model$p)]
  lambda <- coefficients[[model$p + 1L]]
  peer <- evaluate_peer_terms(gamma, model)
  residual <- model$y - drop(model$X %*% beta) - lambda * peer$observed
  instruments <- cbind(model$X, peer$fitted, peer$derivative)
  scores <- instruments * residual
  list(
    residual = residual,
    moments = colMeans(scores),
    instruments = instruments
  )
}

fixed_ces_objective <- function(coefficients, gamma, model, W, lambda_bounds) {
  if (any(!is.finite(coefficients))) return(.Machine$double.xmax / 100)
  lambda <- coefficients[[model$p + 1L]]
  if (lambda < lambda_bounds[[1L]] || lambda > lambda_bounds[[2L]]) {
    return(.Machine$double.xmax / 100)
  }
  moments <- fixed_ces_components(coefficients, gamma, model)$moments
  value <- drop(crossprod(moments, W %*% moments))
  if (is.finite(value)) value else .Machine$double.xmax / 100
}

fit_fixed_ces_common_weight <- function(gamma, model, W, finite_fit, cfg) {
  peer <- evaluate_peer_terms(gamma, model)
  regressors <- cbind(model$X, peer$observed)
  first_instruments <- cbind(model$X, peer$fitted)
  iv_start <- drop(safe_solve(
    crossprod(first_instruments, regressors),
    crossprod(first_instruments, model$y)
  ))
  iv_start[[model$p + 1L]] <- clip(
    iv_start[[model$p + 1L]], cfg$lambda_bounds
  )
  finite_start <- finite_fit$theta[seq_len(model$p + 1L)]
  starts <- list(iv_start, finite_start)
  lower <- c(rep(-Inf, model$p), cfg$lambda_bounds[[1L]])
  upper <- c(rep(Inf, model$p), cfg$lambda_bounds[[2L]])
  candidates <- lapply(starts, function(start) {
    start <- pmin(upper, pmax(lower, start))
    fit <- tryCatch(
      stats::optim(
        par = start,
        fn = fixed_ces_objective,
        gamma = gamma,
        model = model,
        W = W,
        lambda_bounds = cfg$lambda_bounds,
        method = "L-BFGS-B",
        lower = lower,
        upper = upper,
        control = list(
          maxit = cfg$optim_maxit,
          factr = cfg$optim_factr,
          pgtol = cfg$optim_pgtol,
          parscale = pmax(abs(start), c(rep(0.25, model$p), 0.20))
        )
      ),
      error = function(e) NULL
    )
    if (is.null(fit) || any(!is.finite(fit$par))) {
      list(
        coefficients = start,
        objective = fixed_ces_objective(
          start, gamma, model, W, cfg$lambda_bounds
        ),
        convergence = 999L
      )
    } else {
      list(
        coefficients = fit$par,
        objective = fit$value,
        convergence = fit$convergence
      )
    }
  })
  selected <- which.min(vapply(candidates, `[[`, numeric(1), "objective"))
  result <- candidates[[selected]]
  parts <- fixed_ces_components(result$coefficients, gamma, model)
  data.frame(
    gamma = gamma,
    lambda = result$coefficients[[model$p + 1L]],
    residual_rmse = sqrt(mean(parts$residual^2)),
    gmm_objective = drop(crossprod(parts$moments, W %*% parts$moments)),
    derivative_instrument_rms = sqrt(mean(
      parts$instruments[, ncol(parts$instruments)]^2
    )),
    max_abs_moment = max(abs(parts$moments)),
    optimizer_convergence = result$convergence,
    stringsAsFactors = FALSE
  )
}

make_ces_gamma_diagnostics <- function(model, finite_fit, cfg) {
  gamma_hat <- tail(finite_fit$theta, 1L)
  cases <- c(
    "estimated_gamma", "lower_bound", "upper_bound",
    "negative_infinity", "positive_infinity"
  )
  fixed_gamma_values <- c(
    cfg$ces_gamma_bounds[[1L]],
    cfg$ces_gamma_bounds[[2L]],
    -Inf,
    Inf
  )
  finite_coefficients <- finite_fit$theta[seq_len(model$p + 1L)]
  finite_parts <- fixed_ces_components(
    finite_coefficients, gamma_hat, model
  )
  estimated_row <- data.frame(
    gamma = gamma_hat,
    lambda = finite_coefficients[[model$p + 1L]],
    residual_rmse = sqrt(mean(finite_parts$residual^2)),
    gmm_objective = drop(crossprod(
      finite_parts$moments,
      finite_fit$final_weight_matrix %*% finite_parts$moments
    )),
    derivative_instrument_rms = sqrt(mean(
      finite_parts$instruments[, ncol(finite_parts$instruments)]^2
    )),
    max_abs_moment = max(abs(finite_parts$moments)),
    optimizer_convergence = finite_fit$optim_convergence,
    stringsAsFactors = FALSE
  )
  fixed_rows <- lapply(fixed_gamma_values, function(gamma) {
    fit_fixed_ces_common_weight(
      gamma, model, finite_fit$final_weight_matrix, finite_fit, cfg
    )
  })
  result <- do.call(rbind, c(list(estimated_row), fixed_rows))
  result$case <- cases
  result <- result[, c(
    "case", "gamma", "lambda", "residual_rmse", "gmm_objective",
    "derivative_instrument_rms", "max_abs_moment",
    "optimizer_convergence"
  )]
  rownames(result) <- NULL
  result
}

# -----------------------------------------------------------------------------
# Reduced-form LIM, estimated on the unshifted response with an intercept
# -----------------------------------------------------------------------------

fit_lim_gmm <- function(prep, net, cfg) {
  X <- prep$X
  y <- prep$Y
  observed <- neighbor_means(prep$Y_support, net$moment_neighbors)
  fitted <- neighbor_means(prep$fitted_qsar_support, net$moment_neighbors)
  fit_linear_iterated_gmm(
    regressors = cbind(X, observed),
    instruments = cbind(X, fitted),
    y = y,
    p = ncol(X),
    lambda_bounds = cfg$lambda_bounds,
    cfg = cfg,
    model_name = "LIM"
  )
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

coefficient_table <- function(fit, term_names, social_norm_term = NULL) {
  estimate <- fit$theta
  se <- fit$standard_error
  critical <- stats::qnorm(0.975)
  p_value <- 2 * stats::pnorm(-abs(estimate / se))
  if (!is.null(social_norm_term)) p_value[term_names == social_norm_term] <- NA_real_
  data.frame(
    model = fit$model,
    term = term_names,
    estimate = estimate,
    standard_error = se,
    ci_lower = estimate - critical * se,
    ci_upper = estimate + critical * se,
    p_value = p_value,
    stringsAsFactors = FALSE
  )
}

quantile_region <- function(z) {
  if (!is.finite(z)) return(NA_character_)
  if (z < 0.40) "lower" else if (z > 0.60) "upper" else "central"
}

make_ces_qsar_alignment <- function(prep, net, ces_model, ces_fit, qsar_fit, cfg) {
  gamma <- ces_fit$theta[[length(ces_fit$theta)]]
  ces_peer <- evaluate_peer_terms(gamma, ces_model)$observed
  effective_z <- ces_equivalent_quantiles(
    prep$Y_positive_support,
    net$moment_neighbors,
    ces_peer,
    gamma
  )
  qsar_z <- qsar_fit$theta[[length(qsar_fit$theta)]]
  qsar_z_se <- qsar_fit$standard_error[[length(qsar_fit$standard_error)]]
  ces_median <- stats::median(effective_z)
  critical <- stats::qnorm(0.975)
  summary <- data.frame(
    ces_gamma = gamma,
    ces_limit_case = ces_fit$ces_limit_case,
    ces_equivalent_z_mean = mean(effective_z),
    ces_equivalent_z_median = ces_median,
    ces_equivalent_z_p10 = as.numeric(stats::quantile(effective_z, 0.10, names = FALSE)),
    ces_equivalent_z_p90 = as.numeric(stats::quantile(effective_z, 0.90, names = FALSE)),
    qsar_z = qsar_z,
    qsar_z_standard_error = qsar_z_se,
    qsar_z_ci_lower = qsar_z - critical * qsar_z_se,
    qsar_z_ci_upper = qsar_z + critical * qsar_z_se,
    absolute_z_difference = abs(ces_median - qsar_z),
    prespecified_tolerance = cfg$ces_qsar_z_tolerance,
    equivalent_z_agreement = abs(ces_median - qsar_z) <= cfg$ces_qsar_z_tolerance,
    ces_quantile_region = quantile_region(ces_median),
    qsar_quantile_region = quantile_region(qsar_z),
    quantile_region_agreement = quantile_region(ces_median) == quantile_region(qsar_z),
    stringsAsFactors = FALSE
  )
  node_level <- data.frame(
    id = net$moment_nodes$id,
    degree = net$moment_degree,
    ces_peer_norm = ces_peer,
    ces_equivalent_z = effective_z,
    stringsAsFactors = FALSE
  )
  list(summary = summary, node_level = node_level)
}

write_outputs <- function(
  raw, net, prep, bandwidths, lim_fit, ces_model, ces_fit, ces_corners,
  qsar_fit, cfg
) {
  output_dir <- cfg$output_dir
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  x_terms <- colnames(prep$X)
  estimates <- rbind(
    coefficient_table(lim_fit, c(x_terms, "lambda")),
    coefficient_table(ces_fit, c(x_terms, "lambda", "gamma"), "gamma"),
    coefficient_table(qsar_fit, c(x_terms, "lambda", "z"), "z")
  )
  estimates$regular_wald_inference <- TRUE
  estimates$regular_wald_inference[
    estimates$model == "CES" & estimates$term == "gamma" &
      (ces_fit$index_boundary_hit || ces_fit$gamma_is_limit)
  ] <- FALSE
  corner_estimates <- rbind(
    coefficient_table(
      ces_corners$minimum,
      c(x_terms, "lambda")
    ),
    coefficient_table(
      ces_corners$maximum,
      c(x_terms, "lambda")
    )
  )
  corner_estimates$gamma <- ifelse(
    corner_estimates$model == "CES_min_corner", -Inf, Inf
  )
  corner_summary <- do.call(rbind, lapply(ces_corners, function(corner) {
    data.frame(
      model = corner$model,
      gamma = corner$gamma,
      peer_norm = corner$peer_norm,
      lambda = tail(corner$theta, 1L),
      lambda_standard_error = tail(corner$standard_error, 1L),
      residual_rmse = corner$residual_rmse,
      gmm_objective = corner$objective,
      raw_jacobian_smin = corner$jacobian_diagnostics$raw_smin,
      stringsAsFactors = FALSE
    )
  }))
  ces_gamma_diagnostics <- make_ces_gamma_diagnostics(
    ces_model, ces_fit, cfg
  )

  alignment <- make_ces_qsar_alignment(prep, net, ces_model, ces_fit, qsar_fit, cfg)

  density <- 2 * nrow(net$support_edges) /
    (nrow(net$support_nodes) * (nrow(net$support_nodes) - 1))
  diagnostics <- data.frame(
    structural_intercept = TRUE,
    covariance_method = "CES-author-style observation-level outer-product sandwich",
    initial_nodes = net$initial_n,
    support_nodes = nrow(net$support_nodes),
    moment_nodes = nrow(net$moment_nodes),
    degree_one_support_nodes = net$degree_one_support_nodes,
    lim_sample_n = nrow(prep$X),
    ces_sample_n = nrow(prep$X),
    qsar_sample_n = nrow(prep$X),
    removed_isolates = net$removed_isolates,
    retained_undirected_edges = nrow(net$support_edges),
    density = density,
    support_min_degree = min(net$support_degree),
    support_median_degree = stats::median(net$support_degree),
    support_mean_degree = mean(net$support_degree),
    support_max_degree = max(net$support_degree),
    moment_min_degree = min(net$moment_degree),
    moment_median_degree = stats::median(net$moment_degree),
    moment_mean_degree = mean(net$moment_degree),
    moment_max_degree = max(net$moment_degree),
    price_logged = prep$use_log_price,
    ces_outcome_shift = prep$ces_shift,
    ces_fitted_min = min(prep$fitted_ces_support),
    h_min = min(bandwidths$h),
    h_median = stats::median(bandwidths$h),
    h_max = max(bandwidths$h),
    h_base = cfg$h_base,
    h_degree_power = cfg$h_degree_power,
    h_lower_bound_hits = sum(abs(bandwidths$h - cfg$h_bounds[[1L]]) <= 1e-12),
    h_upper_bound_hits = sum(abs(bandwidths$h - cfg$h_bounds[[2L]]) <= 1e-12),
    median_degree_times_h = stats::median(net$moment_degree * bandwidths$h),
    tau_min = min(bandwidths$tau),
    tau_median = stats::median(bandwidths$tau),
    tau_max = max(bandwidths$tau),
    tau_base = cfg$tau_base,
    tau_degree_power = cfg$tau_degree_power,
    tau_lower_bound_hits = sum(abs(bandwidths$tau - cfg$tau_bounds[[1L]]) <= 1e-12),
    tau_upper_bound_hits = sum(abs(bandwidths$tau - cfg$tau_bounds[[2L]]) <= 1e-12),
    median_degree_times_tau = stats::median(net$moment_degree * bandwidths$tau),
    minimum_tau_minus_h = min(bandwidths$tau - bandwidths$h),
    lim_lambda_boundary = lim_fit$lambda_boundary_hit,
    ces_gamma_boundary = ces_fit$index_boundary_hit,
    ces_gamma_is_limit = ces_fit$gamma_is_limit,
    ces_limit_case = ces_fit$ces_limit_case,
    ces_finite_gamma_estimate = ces_fit$finite_gamma_estimate,
    ces_refined_root_count = length(ces_fit$refined_profile_roots),
    ces_refined_roots = paste(signif(ces_fit$refined_profile_roots, 12), collapse = ";"),
    ces_selected_candidate_source = ces_fit$selected_candidate_source,
    ces_selected_gmm_objective = ces_fit$objective,
    ces_selected_index_moment = ces_fit$selected_index_moment,
    ces_selected_derivative_instrument_rms = ces_fit$selected_index_instrument_rms,
    ces_lambda_boundary = ces_fit$lambda_boundary_hit,
    ces_min_corner_lambda = tail(ces_corners$minimum$theta, 1L),
    ces_min_corner_residual_rmse = ces_corners$minimum$residual_rmse,
    ces_max_corner_lambda = tail(ces_corners$maximum$theta, 1L),
    ces_max_corner_residual_rmse = ces_corners$maximum$residual_rmse,
    qsar_z_boundary = qsar_fit$index_boundary_hit,
    qsar_lambda_boundary = qsar_fit$lambda_boundary_hit,
    ces_raw_jacobian_smin = ces_fit$jacobian_diagnostics$raw_smin,
    ces_scaled_jacobian_smin = ces_fit$jacobian_diagnostics$scaled_smin,
    qsar_standardized_jacobian_smin = qsar_fit$jacobian_diagnostics$raw_smin,
    qsar_standardized_jacobian_condition =
      qsar_fit$jacobian_diagnostics$raw_condition,
    lim_gmm_converged = lim_fit$gmm_converged,
    lim_gmm_outer_iterations = lim_fit$gmm_outer_iterations,
    lim_final_parameter_change = lim_fit$final_parameter_change,
    lim_final_weight_change = lim_fit$final_normalized_weight_change,
    ces_gmm_converged = ces_fit$gmm_converged,
    ces_gmm_outer_iterations = ces_fit$gmm_outer_iterations,
    ces_final_parameter_change = ces_fit$final_parameter_change,
    ces_final_weight_change = ces_fit$final_normalized_weight_change,
    qsar_gmm_converged = qsar_fit$gmm_converged,
    qsar_gmm_outer_iterations = qsar_fit$gmm_outer_iterations,
    qsar_final_parameter_change = qsar_fit$final_parameter_change,
    qsar_final_weight_change = qsar_fit$final_normalized_weight_change,
    ces_equivalent_z_median = alignment$summary$ces_equivalent_z_median,
    qsar_z_estimate = alignment$summary$qsar_z,
    ces_qsar_equivalent_z_agreement = alignment$summary$equivalent_z_agreement,
    stringsAsFactors = FALSE
  )
  degree_bandwidths <- data.frame(
    id = net$moment_nodes$id,
    degree = net$moment_degree,
    h = bandwidths$h,
    tau = bandwidths$tau
  )
  price_diagnostics <- rbind(
    transform(prep$raw_price_stats, scale = "raw transaction value"),
    transform(prep$log_price_stats, scale = "log transaction value")
  )

  utils::write.csv(estimates, file.path(output_dir, "model_estimates.csv"), row.names = FALSE)
  utils::write.csv(diagnostics, file.path(output_dir, "estimation_diagnostics.csv"), row.names = FALSE)
  utils::write.csv(qsar_fit$profile, file.path(output_dir, "qsar_z_profile.csv"), row.names = FALSE)
  utils::write.csv(ces_fit$profile, file.path(output_dir, "ces_gamma_profile.csv"), row.names = FALSE)
  utils::write.csv(
    rbind(ces_fit$candidates, qsar_fit$candidates),
    file.path(output_dir, "profile_candidates.csv"),
    row.names = FALSE
  )
  utils::write.csv(prep$processed, file.path(output_dir, "processed_data.csv"), row.names = FALSE)
  utils::write.csv(prep$transformations, file.path(output_dir, "transformations.csv"), row.names = FALSE)
  utils::write.csv(degree_bandwidths, file.path(output_dir, "degree_bandwidths.csv"), row.names = FALSE)
  utils::write.csv(price_diagnostics, file.path(output_dir, "price_diagnostics.csv"), row.names = FALSE)
  utils::write.csv(
    corner_estimates,
    file.path(output_dir, "ces_corner_estimates.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    corner_summary,
    file.path(output_dir, "ces_corner_summary.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    ces_gamma_diagnostics,
    file.path(output_dir, "ces_gamma_diagnostics.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    alignment$summary,
    file.path(output_dir, "ces_qsar_quantile_alignment.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    alignment$node_level,
    file.path(output_dir, "ces_equivalent_quantiles_by_node.csv"),
    row.names = FALSE
  )
  gmm_history <- rbind(
    lim_fit$gmm_iteration_history,
    ces_fit$gmm_iteration_history,
    qsar_fit$gmm_iteration_history
  )
  utils::write.csv(
    gmm_history,
    file.path(output_dir, "gmm_iteration_history.csv"),
    row.names = FALSE
  )

  cat("\nLIM, CES, and QSAR all include a structural intercept.\n")
  cat(sprintf(
    paste0(
      "Support graph: %d non-isolated nodes of %d; %d degree-one support ",
      "nodes; %d undirected edges; degree range %d--%d.\n"
    ),
    nrow(net$support_nodes), net$initial_n, net$degree_one_support_nodes,
    nrow(net$support_edges), min(net$support_degree), max(net$support_degree)
  ))
  cat(sprintf(
    paste0(
      "GMM moment sample: %d degree>=2 egos; all peer norms retain neighbors ",
      "from the full support graph.\n"
    ),
    nrow(net$moment_nodes)
  ))
  cat(sprintf(
    paste0(
      "Fixed QSAR bandwidths: h range %.4f--%.4f (median %.4f); ",
      "tau range %.4f--%.4f (median %.4f).\n"
    ),
    min(bandwidths$h), max(bandwidths$h), stats::median(bandwidths$h),
    min(bandwidths$tau), max(bandwidths$tau), stats::median(bandwidths$tau)
  ))
  cat(sprintf(
    "Bandwidth-bound hits: h lower/upper = %d/%d; tau lower/upper = %d/%d.\n",
    diagnostics$h_lower_bound_hits, diagnostics$h_upper_bound_hits,
    diagnostics$tau_lower_bound_hits, diagnostics$tau_upper_bound_hits
  ))
  cat(sprintf("CES positive-outcome shift: %.6f.\n", prep$ces_shift))
  cat(sprintf("CES instrument predictor: %s.\n", prep$ces_predictor_method))
  cat(
    paste0(
      "Standard errors: CES-author-style observation-level outer-product ",
      "GMM sandwich.\n"
    )
  )
  cat(sprintf(
    paste0(
      "Joint iterated-GMM convergence: LIM=%s (%d updates), CES=%s (%d), ",
      "QSAR=%s (%d).\n"
    ),
    if (lim_fit$gmm_converged) "YES" else "NO", lim_fit$gmm_outer_iterations,
    if (ces_fit$gmm_converged) "YES" else "NO", ces_fit$gmm_outer_iterations,
    if (qsar_fit$gmm_converged) "YES" else "NO", qsar_fit$gmm_outer_iterations
  ))
  cat(sprintf(
    "Finite CES refined roots: %s; selected source: %s.\n",
    if (length(ces_fit$refined_profile_roots)) {
      paste(sprintf("%.8f", ces_fit$refined_profile_roots), collapse = ", ")
    } else {
      "none"
    },
    ces_fit$selected_candidate_source
  ))
  cat(sprintf(
    paste0(
      "Selected finite CES diagnostics: gamma=%.8f; final GMM objective=%.3e; ",
      "derivative-instrument RMS=%.3e; raw Jacobian smin=%.3e.\n"
    ),
    tail(ces_fit$theta, 1L),
    ces_fit$objective,
    ces_fit$selected_index_instrument_rms,
    ces_fit$jacobian_diagnostics$raw_smin
  ))
  cat("\nLIM, CES, and QSAR estimates\n")
  print(estimates[, c("model", "term", "estimate", "standard_error")], row.names = FALSE)
  cat("\nSeparate CES peer-minimum/maximum limit-model diagnostics\n")
  print(corner_summary, row.names = FALSE)
  cat(
    paste0(
      "\nCES gamma comparison using raw instruments and one common final ",
      "weight matrix\n"
    )
  )
  print(ces_gamma_diagnostics, row.names = FALSE)
  cat(sprintf(
    paste0(
      "\nCES-equivalent peer percentile (median across nodes): %.4f; ",
      "QSAR z: %.4f; absolute difference: %.4f.\n"
    ),
    alignment$summary$ces_equivalent_z_median,
    alignment$summary$qsar_z,
    alignment$summary$absolute_z_difference
  ))
  cat(sprintf(
    "Pre-specified equivalent-percentile agreement (tolerance %.2f): %s.\n",
    cfg$ces_qsar_z_tolerance,
    if (alignment$summary$equivalent_z_agreement) "YES" else "NO"
  ))
  cat(sprintf("\nOutput directory: %s\n", output_dir))

  if (ces_fit$index_boundary_hit) {
    warnf(
      paste0(
        "The regular finite CES estimate hit [%.0f, %.0f]. It was retained as ",
        "a finite-boundary diagnostic rather than being relabeled as infinity. ",
        "Inspect ces_gamma_profile.csv and the separately fitted limit models."
      ),
      cfg$ces_gamma_bounds[[1L]], cfg$ces_gamma_bounds[[2L]]
    )
  }
  if (qsar_fit$index_boundary_hit) warnf("The QSAR estimate z hit its fixed search boundary.")
  if (ces_fit$lambda_boundary_hit || qsar_fit$lambda_boundary_hit || lim_fit$lambda_boundary_hit) {
    warnf("At least one network coefficient hit its fixed parameter boundary.")
  }
  if (!alignment$summary$equivalent_z_agreement) {
    warnf(
      paste0(
        "CES and QSAR do not agree after translating the CES norm into an ",
        "equivalent peer percentile. This is a substantive/model diagnostic; ",
        "do not tune h or tau after seeing it merely to force agreement."
      )
    )
  }
  invisible(list(
    estimates = estimates,
    corner_estimates = corner_estimates,
    corner_summary = corner_summary,
    ces_gamma_diagnostics = ces_gamma_diagnostics,
    diagnostics = diagnostics,
    alignment = alignment,
    gmm_iteration_history = gmm_history,
    output_dir = output_dir
  ))
}

run_internal_checks <- function(cfg = CFG) {
  toy_nodes <- data.frame(id = 1:5)
  toy_edges <- data.frame(from = c(1L, 2L, 3L), to = c(2L, 3L, 4L))
  toy_net <- retain_nonisolated_support(toy_nodes, toy_edges, 1L, 2L)
  if (nrow(toy_net$support_nodes) != 4L ||
      !identical(toy_net$moment_nodes$id, c(2L, 3L)) ||
      toy_net$degree_one_support_nodes != 2L ||
      any(lengths(toy_net$moment_neighbors) != 2L)) {
    stopf("Non-isolated support-node construction check failed.")
  }
  if (relative_weight_change(2 * diag(3), diag(3)) > 1e-14) {
    stopf("Scale-normalized GMM weight convergence check failed.")
  }
  prep <- prepare_piecewise_quantile(c(-1, 0, 1, 2))
  z <- 0.43
  h <- 0.12
  analytic <- gaussian_smooth_quantile_one(prep, z, h)
  epsilon <- 1e-6
  numeric_derivative <-
    (gaussian_smooth_quantile_one(prep, z + epsilon, h)[["level"]] -
       gaussian_smooth_quantile_one(prep, z - epsilon, h)[["level"]]) /
    (2 * epsilon)
  if (abs(analytic[["derivative"]] - numeric_derivative) > 1e-5) {
    stopf("Gaussian-smoothing derivative check failed.")
  }
  values <- c(1, 2, 4, 8)
  at_one <- ces_power_mean_one(log(values), 1)[["level"]]
  at_zero <- ces_power_mean_one(log(values), 0)[["level"]]
  at_high <- ces_power_mean_one(log(values), 300)[["level"]]
  at_low <- ces_power_mean_one(log(values), -300)[["level"]]
  at_infinity <- ces_power_mean_one(log(values), Inf)[["level"]]
  at_minus_infinity <- ces_power_mean_one(log(values), -Inf)[["level"]]
  ces_at_two <- ces_power_mean_one(log(values), 2)
  ces_numeric_derivative <-
    (ces_power_mean_one(log(values), 2 + epsilon)[["level"]] -
       ces_power_mean_one(log(values), 2 - epsilon)[["level"]]) /
    (2 * epsilon)
  if (abs(at_one - mean(values)) > 1e-10 ||
      abs(at_zero - exp(mean(log(values)))) > 1e-10 ||
      abs(at_high - max(values)) > 0.05 ||
      abs(at_low - min(values)) > 0.05 ||
      abs(at_infinity - max(values)) > 1e-12 ||
      abs(at_minus_infinity - min(values)) > 1e-12 ||
      ces_power_mean_one(log(values), Inf)[["derivative"]] != 0 ||
      ces_power_mean_one(log(values), -Inf)[["derivative"]] != 0 ||
      abs(ces_at_two[["derivative"]] - ces_numeric_derivative) > 1e-5) {
    stopf("CES power-mean limit check failed.")
  }
  if (abs(ces_equivalent_quantile_one(c(1, 2, 3), 2, 1) - 0.5) > 1e-12 ||
      ces_equivalent_quantile_one(c(1, 2, 3), 3, Inf) != 1) {
    stopf("CES-equivalent quantile check failed.")
  }
  bandwidth_test <- make_bandwidths(c(2, 5, 72), cfg)
  if (any(diff(bandwidth_test$h) >= 0) || any(diff(bandwidth_test$tau) >= 0) ||
      any(bandwidth_test$tau <= bandwidth_test$h)) {
    stopf("Degree-adaptive bandwidth monotonicity check failed.")
  }
  score_test <- matrix(c(1, 0, 0, 1, 1, 1), nrow = 3L, byrow = TRUE)
  covariance_test <- gmm_score_covariance(score_test, 1e-12)$Sigma
  if (max(abs(covariance_test - crossprod(score_test) / nrow(score_test))) > 1e-10) {
    stopf("CES-author-style outer-product covariance check failed.")
  }
  raw_candidates <- list(list(objective = 2), list(objective = 1))
  if (select_candidate(raw_candidates) != 2L) {
    stopf("Raw GMM-objective candidate-selection check failed.")
  }
  raw_moment <- c(0.4, -0.2, 0.1)
  scale <- c(2, 0.5, 4)
  standardized_moment <- raw_moment / scale
  transformed_weight <- diag(scale^2)
  if (abs(
    sum(raw_moment^2) -
      drop(crossprod(standardized_moment, transformed_weight %*% standardized_moment))
  ) > 1e-14) {
    stopf("Equivalent fixed instrument-scaling check failed.")
  }
  rms_test <- cbind(c(1, 2, 3), c(-2, 1, 4))
  rms_scaled <- standardize_rms_columns(rms_test, 1e-12)$matrix
  if (max(abs(sqrt(colMeans(rms_scaled^2)) - 1)) > 1e-12 ||
      max(abs(colMeans(rms_scaled))) < 1e-3) {
    stopf("Non-centered RMS-standardization check failed.")
  }

  invisible(TRUE)
}

main <- function(cfg = CFG) {
  run_internal_checks(cfg)
  require_package("Matrix")
  require_package("matrixStats")
  if (cfg$support_min_degree != 1L) stopf("support_min_degree must equal one.")
  if (cfg$moment_min_degree < 2L) {
    stopf("moment_min_degree must be at least two for indexed peer norms.")
  }
  if (cfg$gmm_max_outer_iterations < 1L ||
      cfg$gmm_parameter_tolerance <= 0 || cfg$gmm_weight_tolerance <= 0) {
    stopf("Invalid iterated-GMM convergence settings.")
  }
  if (cfg$h_base <= 0 || cfg$tau_base <= 0) stopf("Bandwidth constants must be positive.")
  if (length(cfg$h_bounds) != 2L || cfg$h_bounds[[1L]] <= 0 ||
      cfg$h_bounds[[1L]] >= cfg$h_bounds[[2L]]) stopf("Invalid h bounds.")
  if (length(cfg$tau_bounds) != 2L || cfg$tau_bounds[[1L]] <= 0 ||
      cfg$tau_bounds[[1L]] >= cfg$tau_bounds[[2L]]) stopf("Invalid tau bounds.")
  if (cfg$ces_gamma_bounds[[1L]] >= cfg$ces_gamma_bounds[[2L]]) stopf("Invalid CES gamma bounds.")
  if (any(!is.finite(cfg$ces_gamma_bounds))) stopf("Finite CES gamma bounds are required.")
  if (cfg$ces_root_tolerance <= 0 || cfg$ces_root_moment_tolerance <= 0) {
    stopf("CES root tolerances must be positive.")
  }
  if (cfg$ces_qsar_z_tolerance <= 0 || cfg$ces_qsar_z_tolerance >= 1) {
    stopf("ces_qsar_z_tolerance must lie strictly between zero and one.")
  }
  if (cfg$instrument_rms_floor <= 0 ||
      cfg$standardization_equivalence_tolerance <= 0 ||
      cfg$diagnostic_bootstrap_B < 1L ||
      cfg$diagnostic_z_step <= 0 ||
      cfg$diagnostic_z_half_width <= 0 ||
      cfg$diagnostic_lambda_half_width < 0 ||
      cfg$diagnostic_cpu_fraction <= 0 ||
      cfg$diagnostic_cpu_fraction > 1) {
    stopf("Invalid standardization or condition-check settings.")
  }

  cat("Reading and validating the three Excel files...\n")
  raw <- read_real_data(cfg)
  cat("Deleting isolates and retaining degree-one nodes as peer-support neighbors...\n")
  net <- retain_nonisolated_support(
    raw$nodes, raw$edges, cfg$support_min_degree, cfg$moment_min_degree
  )
  cat("Transforming covariates and adding one structural intercept...\n")
  prep <- preprocess_data(raw, net, cfg)
  bandwidths <- make_bandwidths(net$moment_degree, cfg)

  cat("Estimating reduced-form LIM...\n")
  lim_fit <- fit_lim_gmm(prep, net, cfg)
  cat("Estimating CES by the paper's fitted-norm/derivative-instrument GMM...\n")
  ces_model <- make_ces_model(prep, net, cfg)
  qsar_model <- make_qsar_model(prep, net, bandwidths, cfg)
  if (ces_model$n != nrow(prep$X) || qsar_model$n != nrow(prep$X)) {
    stopf("LIM, CES, and QSAR must use exactly the same moment-node sample.")
  }
  ces_fit <- annotate_finite_ces_fit(fit_indexed_gmm(ces_model, cfg))
  cat("Estimating the CES peer-minimum and peer-maximum limit models separately...\n")
  ces_corners <- fit_ces_corner_models(ces_model, cfg)
  cat("Obtaining the preliminary QSAR scale-freezing fit...\n")
  preliminary_qsar_fit <- fit_indexed_gmm(qsar_model, cfg)
  standardization <- make_fixed_rms_standardized_model(
    qsar_model, preliminary_qsar_fit, cfg
  )
  cat(paste0(
    "Estimating double-smoothed QSAR with fixed RMS-standardized ",
    "instruments...\n"
  ))
  qsar_fit <- fit_indexed_gmm(
    standardization$model,
    cfg,
    initial_weight_matrix = standardization$initial_weight
  )

  term_names <- c(colnames(prep$X), "lambda", "z")
  invariance <- data.frame(
    term = term_names,
    preliminary_estimate = preliminary_qsar_fit$theta,
    standardized_estimate = qsar_fit$theta,
    absolute_estimate_difference = abs(
      preliminary_qsar_fit$theta - qsar_fit$theta
    ),
    preliminary_standard_error = preliminary_qsar_fit$standard_error,
    standardized_standard_error = qsar_fit$standard_error,
    absolute_standard_error_difference = abs(
      preliminary_qsar_fit$standard_error - qsar_fit$standard_error
    ),
    stringsAsFactors = FALSE
  )
  if (max(invariance$absolute_estimate_difference) >
      cfg$standardization_equivalence_tolerance ||
      max(invariance$absolute_standard_error_difference) >
      cfg$standardization_equivalence_tolerance) {
    stopf(
      paste0(
        "The standardized fit differs from the scale-freezing fit by more ",
        "than %.1e, so the condition checks are stopped."
      ),
      cfg$standardization_equivalence_tolerance
    )
  }

  checks <- run_standardized_condition_checks(
    prep, net, standardization$model, qsar_fit, standardization, cfg
  )

  output <- write_outputs(
    raw, net, prep, bandwidths, lim_fit, ces_model, ces_fit, ces_corners,
    qsar_fit, cfg
  )
  write_standardized_condition_outputs(
    output$output_dir, standardization, invariance, checks
  )
  output$qsar_fit <- qsar_fit
  output$qsar_standardization <- standardization
  output$condition_checks <- checks
  invisible(output)
}

results <- main(CFG)
