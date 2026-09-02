options(stringsAsFactors = FALSE, scipen = 999)

CFG <- list(
  x_files = c("Graph_X.xlsx"),
  y_files = c("Graph_Y0.xlsx"),
  edge_files = c("index_5.xlsx"),
  x_sheet = "Sheet3",
  y_sheet = "Sheet2",
  edge_sheet = "Sheet3",
  output_dir = "qsar_realdata_predicted_low_high_full_neighbors_output",

  support_min_degree = 1L,
  moment_min_degree = 2L,

  price_transform = "auto",    
  heavy_tail_abs_skew = 2.0,
  heavy_tail_excess_kurtosis = 10.0,
  heavy_tail_max_to_median = 10.0,

  crossfit_folds = 5L,
  crossfit_seed = 20260811L,
  grouping_quantile = 0.50,

  h_base = 0.16,
  h_degree_power = 0.35,
  h_bounds = c(0.02, 0.28),
  tau_base = 0.30,
  tau_degree_power = 0.30,
  tau_bounds = c(0.05, 0.60),

  lambda_bounds = c(-0.80, 0.80),
  z_bounds = c(0.10, 0.90),
  z_profile_step = 0.01,
  
  full_sample_z_reference = 0.45,
  max_profile_candidates = 8L,
  
  gmm_max_outer_iterations = 50L,
  gmm_parameter_tolerance = 1e-7,
  gmm_weight_tolerance = 1e-6,
  optim_maxit = 1500L,
  optim_factr = 10,
  optim_pgtol = 1e-12,
  finite_difference_relative_step = 1e-5,
  finite_difference_z_step = 1e-4,
  matrix_eigen_floor = 1e-8,
  boundary_tolerance = 1e-4,

  weak_lambda_warning = 0.05,
  raw_smin_warning = 1e-3
)

`%||%` <- function(x, y) if (is.null(x)) y else x
stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)
warnf <- function(fmt, ...) warning(sprintf(fmt, ...), call. = FALSE)
clip <- function(x, bounds) pmin(bounds[[2L]], pmax(bounds[[1L]], x))
symmetrize <- function(A) (A + t(A)) / 2

require_package <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stopf("Package '%s' is required. Install it before running this file.", package)
  }
}

script_directory <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) {
    return(dirname(normalizePath(sub("^--file=", "", hit), mustWork = FALSE)))
  }
  normalizePath(getwd(), mustWork = FALSE)
}

resolve_input_file <- function(candidates, search_dirs) {
  paths <- unique(unlist(lapply(search_dirs, function(path) file.path(path, candidates))))
  hit <- paths[file.exists(paths)]
  if (!length(hit)) stopf("Cannot find any of: %s", paste(candidates, collapse = ", "))
  normalizePath(hit[[1L]], mustWork = TRUE)
}

safe_solve <- function(A, b = NULL, ridge = 1e-10) {
  A <- as.matrix(A)
  answer <- tryCatch(if (is.null(b)) solve(A) else solve(A, b), error = function(e) NULL)
  if (!is.null(answer) && all(is.finite(answer))) return(answer)
  scale_A <- max(1, max(abs(diag(A))))
  regularized <- A + diag(ridge * scale_A, nrow(A))
  answer <- if (is.null(b)) solve(regularized) else solve(regularized, b)
  if (!all(is.finite(answer))) stopf("A required linear system could not be solved.")
  answer
}

stabilize_psd <- function(A, relative_floor) {
  A <- symmetrize(A)
  decomposition <- eigen(A, symmetric = TRUE)
  top <- max(1, max(abs(decomposition$values)))
  values <- pmax(decomposition$values, relative_floor * top)
  stable <- decomposition$vectors %*% (values * t(decomposition$vectors))
  list(
    matrix = symmetrize(stable),
    raw_min_eigenvalue = min(decomposition$values),
    condition_number = max(values) / min(values)
  )
}

shape_statistics <- function(x) {
  x <- as.numeric(x)
  mu <- mean(x)
  s <- stats::sd(x)
  centered <- x - mu
  list(
    skewness = if (s > 0) mean(centered^3) / s^3 else 0,
    excess_kurtosis = if (s > 0) mean(centered^4) / s^4 - 3 else 0,
    max_to_median = if (stats::median(x) > 0) max(x) / stats::median(x) else Inf
  )
}

# -----------------------------------------------------------------------------
# Import and network construction
# -----------------------------------------------------------------------------

read_real_data <- function(cfg) {
  require_package("readxl")
  root <- script_directory()
  search_dirs <- unique(c(root, getwd(), file.path(root, "upload"), file.path(getwd(), "upload")))
  x_path <- resolve_input_file(cfg$x_files, search_dirs)
  y_path <- resolve_input_file(cfg$y_files, search_dirs)
  edge_path <- resolve_input_file(cfg$edge_files, search_dirs)

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

  nodes <- data.frame(
    id = x_raw$id,
    Y = as.numeric(y_raw$Y[match(x_raw$id, y_raw$id)]),
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

  edge_raw <- edge_raw[edge_raw$row != edge_raw$column, , drop = FALSE]
  edges <- unique(data.frame(
    from = pmin(edge_raw$row, edge_raw$column),
    to = pmax(edge_raw$row, edge_raw$column)
  ))
  list(nodes = nodes, edges = edges, paths = c(X = x_path, Y = y_path, edge = edge_path))
}

make_adjacency <- function(ids, edges) {
  from <- match(edges$from, ids)
  to <- match(edges$to, ids)
  ok <- !is.na(from) & !is.na(to) & from != to
  adjacency <- vector("list", length(ids))
  for (edge in which(ok)) {
    i <- from[[edge]]
    j <- to[[edge]]
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
  support_nodes <- nodes[support_alive, , drop = FALSE]
  support_edges <- edges[
    edges$from %in% support_ids & edges$to %in% support_ids,
    , drop = FALSE
  ]
  support_neighbors <- make_adjacency(support_nodes$id, support_edges)
  support_degree <- lengths(support_neighbors)
  if (!nrow(support_nodes) || any(support_degree < support_min_degree)) {
    stopf("Non-isolated support-graph construction failed.")
  }
  moment_index <- which(support_degree >= moment_min_degree)
  if (!length(moment_index)) stopf("No degree>=2 ego remains for estimation.")
  list(
    support_nodes = support_nodes,
    support_edges = support_edges,
    support_neighbors = support_neighbors,
    support_degree = support_degree,
    moment_index = moment_index,
    moment_nodes = support_nodes[moment_index, , drop = FALSE],
    moment_neighbors = support_neighbors[moment_index],
    moment_degree = support_degree[moment_index],
    initial_n = nrow(nodes),
    initial_edges = nrow(edges),
    removed_isolates = sum(!support_alive),
    degree_one_support_nodes = sum(support_degree == 1L)
  )
}



make_transform_reference <- function(nodes, cfg) {
  raw_shape <- shape_statistics(nodes$average_transaction_value)
  heavy_tail <-
    abs(raw_shape$skewness) > cfg$heavy_tail_abs_skew ||
    raw_shape$excess_kurtosis > cfg$heavy_tail_excess_kurtosis ||
    raw_shape$max_to_median > cfg$heavy_tail_max_to_median
  use_log <- switch(
    cfg$price_transform,
    auto = heavy_tail,
    log = TRUE,
    none = FALSE,
    stopf("price_transform must be auto, log, or none.")
  )
  price <- if (use_log) log(nodes$average_transaction_value) else nodes$average_transaction_value
  variables <- list(
    repeat_customer_ratio = nodes$repeat_customer_ratio,
    commercial_zone_diversity = nodes$commercial_zone_diversity,
    menu_variety = nodes$menu_variety,
    average_transaction_value = price
  )
  means <- vapply(variables, mean, numeric(1))
  sds <- vapply(variables, stats::sd, numeric(1))
  if (any(!is.finite(sds)) || any(sds <= 0)) stopf("A full-sample covariate has zero variance.")
  list(use_log_price = use_log, means = means, sds = sds)
}

make_support_design <- function(net, reference) {
  dat <- net$support_nodes
  price <- if (reference$use_log_price) {
    log(dat$average_transaction_value)
  } else {
    dat$average_transaction_value
  }
  standardized <- function(value, name) {
    (as.numeric(value) - reference$means[[name]]) / reference$sds[[name]]
  }
  X_support <- cbind(
    Intercept = 1,
    repeat_customer_ratio = standardized(dat$repeat_customer_ratio, "repeat_customer_ratio"),
    commercial_zone_diversity = standardized(dat$commercial_zone_diversity, "commercial_zone_diversity"),
    menu_variety = standardized(dat$menu_variety, "menu_variety"),
    average_transaction_value = standardized(price, "average_transaction_value"),
    operating_hours = dat$operating_hours
  )
  if (reference$use_log_price) colnames(X_support)[[5L]] <- "log_average_transaction_value"
  storage.mode(X_support) <- "double"
  list(X_support = X_support, Y_support = as.numeric(dat$Y))
}

make_cross_fitted_grouping <- function(net, common, cfg) {
  eligible_index <- net$moment_index
  support_n <- nrow(common$X_support)
  eligible_n <- length(eligible_index)
  folds <- as.integer(cfg$crossfit_folds)
  if (!is.finite(folds) || folds < 2L || folds > eligible_n - ncol(common$X_support)) {
    stopf("crossfit_folds must be at least two and leave enough training observations.")
  }
  if (!is.finite(cfg$grouping_quantile) || cfg$grouping_quantile <= 0 ||
      cfg$grouping_quantile >= 1) {
    stopf("grouping_quantile must lie strictly between zero and one.")
  }

  # Preserve the caller's random-number state.  The fixed seed makes the fold
  # assignment reproducible without affecting any later stochastic operation.
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(cfg$crossfit_seed))

  fold_id <- integer(support_n)
  eligible_fold_labels <- rep(seq_len(folds), length.out = eligible_n)
  fold_id[eligible_index] <- sample(eligible_fold_labels, eligible_n, replace = FALSE)
  support_only_index <- setdiff(seq_len(support_n), eligible_index)
  if (length(support_only_index)) {
    support_fold_labels <- rep(seq_len(folds), length.out = length(support_only_index))
    fold_id[support_only_index] <- sample(
      support_fold_labels, length(support_only_index), replace = FALSE
    )
  }
  if (any(fold_id < 1L) || any(fold_id > folds)) stopf("Cross-fit fold assignment failed.")

  prediction <- rep(NA_real_, support_n)
  coefficient_rows <- vector("list", folds)
  for (fold in seq_len(folds)) {
    training_index <- eligible_index[fold_id[eligible_index] != fold]
    prediction_index <- which(fold_id == fold)
    X_train <- common$X_support[training_index, , drop = FALSE]
    y_train <- common$Y_support[training_index]
    gram_values <- eigen(
      symmetrize(crossprod(X_train) / nrow(X_train)),
      symmetric = TRUE,
      only.values = TRUE
    )$values
    if (min(gram_values) <= 1e-10) {
      stopf("The OLS training design is rank deficient in cross-fit fold %d.", fold)
    }
    coefficient <- drop(safe_solve(crossprod(X_train), crossprod(X_train, y_train)))
    prediction[prediction_index] <- drop(
      common$X_support[prediction_index, , drop = FALSE] %*% coefficient
    )
    coefficient_rows[[fold]] <- data.frame(
      fold = fold,
      term = colnames(common$X_support),
      coefficient = coefficient,
      training_eligible_n = length(training_index),
      held_out_eligible_n = sum(fold_id[eligible_index] == fold),
      predicted_support_n = length(prediction_index),
      gram_min_eigenvalue = min(gram_values),
      gram_condition_number = max(gram_values) / min(gram_values),
      stringsAsFactors = FALSE
    )
  }
  if (any(!is.finite(prediction))) stopf("Cross-fitted OLS produced invalid predictions.")

  eligible_prediction <- prediction[eligible_index]
  eligible_y <- common$Y_support[eligible_index]
  cutoff <- as.numeric(stats::quantile(
    eligible_prediction, probs = cfg$grouping_quantile,
    names = FALSE, type = 2
  ))
  low_index <- eligible_index[eligible_prediction <= cutoff]
  high_index <- eligible_index[eligible_prediction > cutoff]
  minimum_group_n <- ncol(common$X_support) + 3L
  if (min(length(low_index), length(high_index)) < minimum_group_n) {
    stopf("The cross-fitted grouping rule produced an estimation group that is too small.")
  }

  residual <- eligible_y - eligible_prediction
  total_sum_squares <- sum((eligible_y - mean(eligible_y))^2)
  crossfit_summary <- data.frame(
    folds = folds,
    seed = as.integer(cfg$crossfit_seed),
    eligible_egos = eligible_n,
    grouping_quantile = cfg$grouping_quantile,
    predicted_outcome_cutoff = cutoff,
    predicted_low_n = length(low_index),
    predicted_high_n = length(high_index),
    crossfit_rmse = sqrt(mean(residual^2)),
    crossfit_mae = mean(abs(residual)),
    crossfit_r_squared = 1 - sum(residual^2) / total_sum_squares,
    correlation_actual_predicted = stats::cor(eligible_y, eligible_prediction),
    own_outcome_excluded_from_own_prediction = TRUE,
    stringsAsFactors = FALSE
  )
  list(
    prediction = prediction,
    fold_id = fold_id,
    cutoff = cutoff,
    group_index = list(
      Predicted_Low = low_index,
      Predicted_High = high_index
    ),
    coefficients = do.call(rbind, coefficient_rows),
    summary = crossfit_summary
  )
}

preprocess_group <- function(net, ego_index, common) {
  ego_index <- as.integer(ego_index)
  if (!length(ego_index) || any(!ego_index %in% net$moment_index)) {
    stopf("Every estimation ego must have full-network degree at least two.")
  }
  X_support <- common$X_support
  Y_support <- common$Y_support
  X <- X_support[ego_index, , drop = FALSE]
  gram <- crossprod(X) / nrow(X)
  gram_values <- eigen(symmetrize(gram), symmetric = TRUE, only.values = TRUE)$values
  if (min(gram_values) <= 1e-10) stopf("A group-specific design matrix is rank deficient.")
  Y <- Y_support[ego_index]
  first_stage <- safe_solve(crossprod(X), crossprod(X, Y))
  fitted_support <- drop(X_support %*% first_stage)
  if (any(!is.finite(fitted_support))) stopf("The group-specific OLS predictor is invalid.")
  list(
    X = X,
    Y = Y,
    X_support = X_support,
    Y_support = Y_support,
    fitted_qsar_support = fitted_support,
    ego_index = ego_index,
    gram_min_eigenvalue = min(gram_values),
    gram_condition_number = max(gram_values) / min(gram_values)
  )
}

make_bandwidths <- function(degree, cfg, reference_degree = NULL) {
  reference <- if (is.null(reference_degree)) stats::median(degree) else reference_degree
  if (!is.finite(reference) || reference <= 0) stopf("Invalid bandwidth reference degree.")
  h <- clip(cfg$h_base * (degree / reference)^(-cfg$h_degree_power), cfg$h_bounds)
  tau <- clip(cfg$tau_base * (degree / reference)^(-cfg$tau_degree_power), cfg$tau_bounds)
  if (any(!is.finite(h)) || any(!is.finite(tau)) || any(h <= 0) || any(tau <= 0)) {
    stopf("The bandwidth rule produced invalid values.")
  }
  if (any(tau <= h)) stopf("The fixed rule requires tau_i > h_i for every retained node.")
  list(h = h, tau = tau, degree_reference = reference)
}

# -----------------------------------------------------------------------------
# Gaussian-smoothed neighbor quantiles
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

gaussian_smooth_quantile_one <- function(prepared, z, bandwidth) {
  values <- prepared$values
  knots <- prepared$knots
  left <- knots[-length(knots)]
  right <- knots[-1L]
  A <- (left - z) / bandwidth
  B <- (right - z) / bandwidth
  probability <- stats::pnorm(B) - stats::pnorm(A)
  level <-
    values[[1L]] * stats::pnorm(-z / bandwidth) +
    values[[length(values)]] * (1 - stats::pnorm((1 - z) / bandwidth)) +
    sum(
      (prepared$intercepts + prepared$slopes * z) * probability +
        prepared$slopes * bandwidth * (stats::dnorm(A) - stats::dnorm(B))
    )
  derivative <- sum(prepared$slopes * probability)
  c(level = level, derivative = derivative)
}

gaussian_smooth_quantiles <- function(prepared, z, bandwidths) {
  result <- lapply(seq_along(prepared), function(i) {
    gaussian_smooth_quantile_one(prepared[[i]], z, bandwidths[[i]])
  })
  result <- do.call(rbind, result)
  list(level = result[, "level"], derivative = result[, "derivative"])
}

# -----------------------------------------------------------------------------
# Double-smoothed QSAR GMM
# -----------------------------------------------------------------------------

make_qsar_model <- function(group, prep, ego_neighbors, bandwidths, cfg) {
  list(
    name = paste0("QSAR_", group),
    X = prep$X,
    y = prep$Y,
    n = nrow(prep$X),
    p = ncol(prep$X),
    z_bounds = cfg$z_bounds,
    profile_grid = seq(cfg$z_bounds[[1L]], cfg$z_bounds[[2L]], by = cfg$z_profile_step),
    prepared_observed = prepare_neighbor_quantiles(prep$Y_support, ego_neighbors),
    prepared_fitted = prepare_neighbor_quantiles(prep$fitted_qsar_support, ego_neighbors),
    h = bandwidths$h,
    tau = bandwidths$tau,
    cache = new.env(parent = emptyenv())
  )
}

evaluate_peer_terms <- function(z, model) {
  key <- sprintf("%.12f", z)
  if (exists(key, envir = model$cache, inherits = FALSE)) {
    return(get(key, envir = model$cache, inherits = FALSE))
  }
  observed <- gaussian_smooth_quantiles(model$prepared_observed, z, model$h)
  fitted <- gaussian_smooth_quantiles(model$prepared_fitted, z, model$tau)
  answer <- list(
    observed = observed$level,
    fitted = fitted$level,
    derivative = fitted$derivative
  )
  assign(key, answer, envir = model$cache)
  answer
}

moment_components <- function(theta, model) {
  beta <- theta[seq_len(model$p)]
  lambda <- theta[[model$p + 1L]]
  z <- theta[[model$p + 2L]]
  peer <- evaluate_peer_terms(z, model)
  residual <- model$y - drop(model$X %*% beta) - lambda * peer$observed
  instruments <- cbind(model$X, peer$fitted, lambda * peer$derivative)
  scores <- instruments * residual
  list(
    moments = colMeans(scores),
    scores = scores,
    residual = residual,
    instruments = instruments,
    peer = peer
  )
}

gmm_objective <- function(theta, model, W, cfg) {
  if (any(!is.finite(theta))) return(.Machine$double.xmax / 100)
  lambda <- theta[[model$p + 1L]]
  z <- theta[[model$p + 2L]]
  if (lambda < cfg$lambda_bounds[[1L]] || lambda > cfg$lambda_bounds[[2L]] ||
      z < model$z_bounds[[1L]] || z > model$z_bounds[[2L]]) {
    return(.Machine$double.xmax / 100)
  }
  moments <- moment_components(theta, model)$moments
  value <- drop(crossprod(moments, W %*% moments))
  if (is.finite(value)) value else .Machine$double.xmax / 100
}

profile_start <- function(z, model, W, cfg) {
  peer <- evaluate_peer_terms(z, model)
  regressors <- cbind(model$X, peer$observed)
  instruments <- cbind(model$X, peer$fitted)
  coefficients <- drop(safe_solve(
    crossprod(instruments, regressors),
    crossprod(instruments, model$y)
  ))
  lambda <- clip(coefficients[[length(coefficients)]], cfg$lambda_bounds)
  if (lambda != coefficients[[length(coefficients)]]) {
    beta <- drop(safe_solve(
      crossprod(model$X),
      crossprod(model$X, model$y - lambda * peer$observed)
    ))
    coefficients <- c(beta, lambda)
  }
  theta <- c(coefficients, z)
  list(theta = theta, objective = gmm_objective(theta, model, W, cfg))
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

profile_basins <- function(profile, candidate_indices, bounds) {
  maxima <- local_extrema_indices(profile$objective, "max")
  lapply(candidate_indices, function(index) {
    left <- maxima[maxima < index]
    right <- maxima[maxima > index]
    lower <- if (length(left)) profile$z[[max(left)]] else bounds[[1L]]
    upper <- if (length(right)) profile$z[[min(right)]] else bounds[[2L]]
    if (upper - lower < 1e-6) c(lower = bounds[[1L]], upper = bounds[[2L]]) else c(lower = lower, upper = upper)
  })
}

run_profile <- function(model, W, cfg) {
  starts <- lapply(model$profile_grid, profile_start, model = model, W = W, cfg = cfg)
  objective <- vapply(starts, `[[`, numeric(1), "objective")
  minima <- unique(c(which.min(objective), local_extrema_indices(objective, "min")))
  minima <- minima[order(objective[minima])]
  selected <- integer()
  for (index in minima) {
    if (!length(selected) || all(abs(index - selected) >= 2L)) selected <- c(selected, index)
    if (length(selected) >= cfg$max_profile_candidates) break
  }
  profile <- data.frame(z = model$profile_grid, objective = objective)
  list(
    profile = profile,
    starts = starts[selected],
    basins = profile_basins(profile, selected, model$z_bounds)
  )
}

numeric_jacobian <- function(theta, model, cfg) {
  k <- length(theta)
  G <- matrix(NA_real_, k, k)
  for (j in seq_len(k)) {
    step <- cfg$finite_difference_relative_step * max(1, abs(theta[[j]]))
    if (j == k) step <- cfg$finite_difference_z_step
    step <- max(step, 1e-7)
    plus <- minus <- theta
    plus[[j]] <- plus[[j]] + step
    minus[[j]] <- minus[[j]] - step
    if (j == k) {
      plus[[j]] <- min(model$z_bounds[[2L]], plus[[j]])
      minus[[j]] <- max(model$z_bounds[[1L]], minus[[j]])
    }
    denominator <- plus[[j]] - minus[[j]]
    G[, j] <-
      (moment_components(plus, model)$moments - moment_components(minus, model)$moments) /
      denominator
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

optimize_candidate <- function(start, basin, model, W, cfg) {
  lower <- c(rep(-Inf, model$p), cfg$lambda_bounds[[1L]], basin[["lower"]])
  upper <- c(rep(Inf, model$p), cfg$lambda_bounds[[2L]], basin[["upper"]])
  start <- pmin(upper, pmax(lower, start))
  parscale <- pmax(abs(start), c(rep(0.25, model$p), 0.20, 0.20))
  fit <- tryCatch(
    stats::optim(
      par = start,
      fn = gmm_objective,
      model = model,
      W = W,
      cfg = cfg,
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
  if (is.null(fit) || any(!is.finite(fit$par))) {
    theta <- start
    convergence <- 999L
    message <- "optim failed; retained profile start"
  } else {
    theta <- fit$par
    convergence <- fit$convergence
    message <- fit$message %||% ""
  }
  G <- numeric_jacobian(theta, model, cfg)
  list(
    theta = theta,
    objective = gmm_objective(theta, model, W, cfg),
    convergence = convergence,
    message = message,
    basin = basin,
    jacobian_diagnostics = jacobian_diagnostics(G)
  )
}

select_candidate <- function(candidates) {
  objective <- vapply(candidates, `[[`, numeric(1), "objective")
  which.min(objective)
}

gmm_score_covariance <- function(scores, eigen_floor) {
  raw <- crossprod(scores) / nrow(scores)
  stable <- stabilize_psd(raw, eigen_floor)
  list(
    Sigma = stable$matrix,
    raw_min_eigenvalue = stable$raw_min_eigenvalue,
    condition_number = stable$condition_number
  )
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

fit_qsar_gmm <- function(model, cfg) {
  k <- model$p + 2L
  W <- diag(k)
  global <- run_profile(model, W, cfg)
  candidates <- lapply(seq_along(global$starts), function(i) {
    optimize_candidate(global$starts[[i]]$theta, global$basins[[i]], model, W, cfg)
  })
  selected <- select_candidate(candidates)
  selected_initially <- selected
  current <- candidates[[selected]]
  cat(sprintf(
    "[%s GMM initial] z=%.8f; lambda=%.8f; selected candidate=%d.\n",
    model$name, tail(current$theta, 1L), current$theta[[k - 1L]], selected
  ))

  iteration_history <- vector("list", cfg$gmm_max_outer_iterations)
  converged <- FALSE
  iterations_used <- 0L
  for (iteration in seq_len(cfg$gmm_max_outer_iterations)) {
    current_parts <- moment_components(current$theta, model)
    current_covariance <- gmm_score_covariance(
      current_parts$scores, cfg$matrix_eigen_floor
    )
    W_fit <- safe_solve(current_covariance$Sigma)

    # Every pre-selected basin is re-optimized after each weight update.
    updated_candidates <- lapply(candidates, function(candidate) {
      optimize_candidate(candidate$theta, candidate$basin, model, W_fit, cfg)
    })
    selected_updated <- select_candidate(updated_candidates)
    updated <- updated_candidates[[selected_updated]]

    updated_parts <- moment_components(updated$theta, model)
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
      z_estimate = tail(updated$theta, 1L),
      lambda_estimate = updated$theta[[k - 1L]],
      parameter_change = parameter_change,
      normalized_weight_change = weight_change,
      optimizer_convergence = updated$convergence,
      objective = gmm_objective(updated$theta, model, W_updated, cfg),
      stringsAsFactors = FALSE
    )
    cat(sprintf(
      paste0(
        "[%s GMM update %02d] parameter change=%.3e; normalized weight ",
        "change=%.3e; z=%.8f; lambda=%.8f; candidate=%d.\n"
      ),
      model$name, iteration, parameter_change, weight_change,
      tail(updated$theta, 1L), updated$theta[[k - 1L]], selected_updated
    ))
    iterations_used <- iteration
    candidates <- updated_candidates
    selected <- selected_updated
    current <- updated
    # Outer GMM convergence concerns the parameter vector and the updated
    # covariance weight matrix.  The optimizer status is retained separately;
    # it must not force 50 identical outer updates after the fixed point has
    # already been reached.
    if (updated$convergence != 999L &&
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
      model$name, cfg$gmm_max_outer_iterations
    )
  }

  parts <- moment_components(current$theta, model)
  covariance <- gmm_score_covariance(parts$scores, cfg$matrix_eigen_floor)
  final_W <- safe_solve(covariance$Sigma)
  G <- numeric_jacobian(current$theta, model, cfg)
  diagnostics <- jacobian_diagnostics(G)
  G_inverse <- safe_solve(G)
  V_root_n <- symmetrize(G_inverse %*% covariance$Sigma %*% t(G_inverse))
  standard_error <- sqrt(pmax(diag(V_root_n) / model$n, 0))
  z_hat <- tail(current$theta, 1L)
  lambda_hat <- current$theta[[k - 1L]]

  candidate_table <- do.call(rbind, lapply(seq_along(candidates), function(i) {
    candidate <- candidates[[i]]
    data.frame(
      candidate = i,
      selected_initially = i == selected_initially,
      selected_finally = i == selected,
      objective = candidate$objective,
      lambda = candidate$theta[[k - 1L]],
      z = candidate$theta[[k]],
      basin_lower = candidate$basin[["lower"]],
      basin_upper = candidate$basin[["upper"]],
      raw_jacobian_smin = candidate$jacobian_diagnostics$raw_smin,
      scaled_jacobian_smin = candidate$jacobian_diagnostics$scaled_smin,
      optim_convergence = candidate$convergence
    )
  }))

  list(
    theta = current$theta,
    standard_error = standard_error,
    objective = gmm_objective(current$theta, model, final_W, cfg),
    residual = parts$residual,
    moments = parts$moments,
    profile = global$profile,
    candidates = candidate_table,
    jacobian_diagnostics = diagnostics,
    score_covariance_raw_min_eigenvalue = covariance$raw_min_eigenvalue,
    score_covariance_condition = covariance$condition_number,
    optim_convergence = current$convergence,
    gmm_converged = converged,
    gmm_outer_iterations = iterations_used,
    gmm_parameter_rounds = iterations_used + 1L,
    gmm_iteration_history = iteration_history,
    final_parameter_change = tail(iteration_history$parameter_change, 1L),
    final_normalized_weight_change = tail(
      iteration_history$normalized_weight_change, 1L
    ),
    z_boundary_hit =
      abs(z_hat - cfg$z_bounds[[1L]]) <= cfg$boundary_tolerance ||
      abs(z_hat - cfg$z_bounds[[2L]]) <= cfg$boundary_tolerance,
    lambda_boundary_hit =
      abs(lambda_hat - cfg$lambda_bounds[[1L]]) <= cfg$boundary_tolerance ||
      abs(lambda_hat - cfg$lambda_bounds[[2L]]) <= cfg$boundary_tolerance,
    basin_boundary_hit =
      abs(z_hat - current$basin[["lower"]]) <= cfg$boundary_tolerance ||
      abs(z_hat - current$basin[["upper"]]) <= cfg$boundary_tolerance
  )
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

make_estimate_table <- function(group, prep, fit) {
  terms <- c(colnames(prep$X), "lambda", "z")
  statistic <- fit$theta / fit$standard_error
  p_value <- 2 * stats::pnorm(-abs(statistic))
  p_value[terms == "z"] <- NA_real_  # z=0 is outside the maintained parameter space.
  data.frame(
    group = group,
    term = terms,
    estimate = fit$theta,
    standard_error = fit$standard_error,
    statistic = statistic,
    p_value = p_value,
    ci95_lower = fit$theta - stats::qnorm(0.975) * fit$standard_error,
    ci95_upper = fit$theta + stats::qnorm(0.975) * fit$standard_error,
    stringsAsFactors = FALSE
  )
}

make_diagnostic_row <- function(
  group, net, ego_index, prep, bandwidths, fit, cutoff, grouping_prediction,
  neighbor_appearances, opposite_group_neighbor_appearances, cfg
) {
  lambda_hat <- fit$theta[[ncol(prep$X) + 1L]]
  weak <-
    abs(lambda_hat) < cfg$weak_lambda_warning ||
    fit$jacobian_diagnostics$raw_smin < cfg$raw_smin_warning
  data.frame(
    group = group,
    grouping_method = "K-fold cross-fitted OLS prediction based on X only",
    qsar_instrument_first_stage = "OLS re-estimated within predicted group",
    cross_fitted_prediction_cutoff = cutoff,
    group_mean_cross_fitted_prediction = mean(grouping_prediction[ego_index]),
    group_sd_cross_fitted_prediction = stats::sd(grouping_prediction[ego_index]),
    group_mean_actual_Y = mean(net$support_nodes$Y[ego_index]),
    group_sd_actual_Y = stats::sd(net$support_nodes$Y[ego_index]),
    support_nodes = nrow(net$support_nodes),
    degree_one_support_nodes = net$degree_one_support_nodes,
    group_ego_n = length(ego_index),
    removed_after_group_definition = 0L,
    full_support_edges = nrow(net$support_edges),
    neighbor_appearances_used_in_peer_norms = neighbor_appearances,
    opposite_group_neighbor_appearances = opposite_group_neighbor_appearances,
    opposite_group_neighbor_share =
      opposite_group_neighbor_appearances / neighbor_appearances,
    min_full_network_degree = min(net$support_degree[ego_index]),
    median_full_network_degree = stats::median(net$support_degree[ego_index]),
    mean_full_network_degree = mean(net$support_degree[ego_index]),
    max_full_network_degree = max(net$support_degree[ego_index]),
    bandwidth_reference_degree = bandwidths$degree_reference,
    h_min = min(bandwidths$h),
    h_median = stats::median(bandwidths$h),
    h_max = max(bandwidths$h),
    h_lower_bound_hits = sum(abs(bandwidths$h - cfg$h_bounds[[1L]]) <= 1e-12),
    h_upper_bound_hits = sum(abs(bandwidths$h - cfg$h_bounds[[2L]]) <= 1e-12),
    tau_min = min(bandwidths$tau),
    tau_median = stats::median(bandwidths$tau),
    tau_max = max(bandwidths$tau),
    tau_lower_bound_hits = sum(abs(bandwidths$tau - cfg$tau_bounds[[1L]]) <= 1e-12),
    tau_upper_bound_hits = sum(abs(bandwidths$tau - cfg$tau_bounds[[2L]]) <= 1e-12),
    lambda_estimate = lambda_hat,
    z_estimate = tail(fit$theta, 1L),
    gmm_objective = fit$objective,
    residual_rmse = sqrt(mean(fit$residual^2)),
    raw_jacobian_smin = fit$jacobian_diagnostics$raw_smin,
    scaled_jacobian_smin = fit$jacobian_diagnostics$scaled_smin,
    raw_jacobian_condition = fit$jacobian_diagnostics$raw_condition,
    scaled_jacobian_condition = fit$jacobian_diagnostics$scaled_condition,
    gmm_converged = fit$gmm_converged,
    gmm_outer_iterations = fit$gmm_outer_iterations,
    final_parameter_change = fit$final_parameter_change,
    final_normalized_weight_change = fit$final_normalized_weight_change,
    z_boundary_hit = fit$z_boundary_hit,
    lambda_boundary_hit = fit$lambda_boundary_hit,
    basin_boundary_hit = fit$basin_boundary_hit,
    weak_z_identification_warning = weak,
    z_inference_reliable = !weak && !fit$z_boundary_hit && !fit$basin_boundary_hit,
    stringsAsFactors = FALSE
  )
}

run_internal_checks <- function(cfg) {
  prepared <- prepare_piecewise_quantile(c(-1, 0, 1, 2))
  z <- 0.43
  h <- 0.18
  analytic <- gaussian_smooth_quantile_one(prepared, z, h)
  step <- 1e-6
  numeric_derivative <-
    (gaussian_smooth_quantile_one(prepared, z + step, h)[["level"]] -
       gaussian_smooth_quantile_one(prepared, z - step, h)[["level"]]) /
    (2 * step)
  if (abs(analytic[["derivative"]] - numeric_derivative) > 1e-6) {
    stopf("Gaussian quantile derivative check failed.")
  }
  test_degree <- c(2, 5, 20, 72)
  bandwidths <- make_bandwidths(test_degree, cfg)
  if (any(diff(bandwidths$h) > 0) || any(diff(bandwidths$tau) > 0) ||
      any(bandwidths$tau <= bandwidths$h)) {
    stopf("Bandwidth monotonicity check failed.")
  }
  invisible(TRUE)
}

main <- function(cfg = CFG) {
  run_internal_checks(cfg)
  if (cfg$support_min_degree != 1L) stopf("support_min_degree must equal one.")
  if (cfg$moment_min_degree < 2L) stopf("moment_min_degree must be at least two.")
  if (cfg$z_bounds[[1L]] <= 0 || cfg$z_bounds[[2L]] >= 1 ||
      cfg$z_bounds[[1L]] >= cfg$z_bounds[[2L]]) stopf("Invalid z bounds.")
  if (!is.finite(cfg$full_sample_z_reference) ||
      cfg$full_sample_z_reference <= cfg$z_bounds[[1L]] ||
      cfg$full_sample_z_reference >= cfg$z_bounds[[2L]]) {
    stopf("full_sample_z_reference must lie strictly inside z_bounds.")
  }

  cat("Reading and validating the three Excel files...\n")
  raw <- read_real_data(cfg)
  cat("Deleting isolates and retaining the full non-isolated support graph...\n")
  net <- retain_nonisolated_support(
    raw$nodes, raw$edges, cfg$support_min_degree, cfg$moment_min_degree
  )
  eligible_index <- net$moment_index
  reference <- make_transform_reference(net$moment_nodes, cfg)
  common <- make_support_design(net, reference)
  cat(sprintf(
    "Constructing %d-fold cross-fitted OLS grouping scores using X only...\n",
    cfg$crossfit_folds
  ))
  grouping <- make_cross_fitted_grouping(net, common, cfg)
  cutoff <- grouping$cutoff
  group_index <- grouping$group_index
  cat(sprintf(
    paste0(
      "Support graph: %d non-isolated nodes of %d; %d degree-one support ",
      "nodes; %d degree>=2 eligible egos; %d edges.\n"
    ),
    nrow(net$support_nodes), net$initial_n, net$degree_one_support_nodes,
    length(net$moment_index), nrow(net$support_edges)
  ))
  cat(sprintf(
    paste0(
      "Cross-fitted grouping: cutoff=%.8f; Predicted-Low n=%d; ",
      "Predicted-High n=%d; out-of-fold R-squared=%.4f; correlation(Y,prediction)=%.4f.\n"
    ),
    cutoff,
    grouping$summary$predicted_low_n,
    grouping$summary$predicted_high_n,
    grouping$summary$crossfit_r_squared,
    grouping$summary$correlation_actual_predicted
  ))

  estimate_tables <- list()
  diagnostic_rows <- list()
  profiles <- list()
  candidates <- list()
  histories <- list()
  degree_bandwidths <- list()

  group_names <- names(group_index)
  for (g in seq_along(group_names)) {
    group <- group_names[[g]]
    ego_index <- group_index[[group]]
    ego_neighbors <- net$support_neighbors[ego_index]
    ego_degree <- net$support_degree[ego_index]
    ego_is_high <- group == "Predicted_High"
    support_is_high <- grouping$prediction > cutoff
    neighbor_appearances <- sum(lengths(ego_neighbors))
    opposite_group_neighbor_appearances <- sum(vapply(
      ego_neighbors,
      function(index) sum(support_is_high[index] != ego_is_high),
      integer(1)
    ))
    cat(sprintf(
      "[%d/%d] %s group: preparing %d egos...\n",
      g, length(group_names), group, length(ego_index)
    ))
    prep <- preprocess_group(net, ego_index, common)
    bandwidths <- make_bandwidths(
      ego_degree, cfg, reference_degree = stats::median(net$moment_degree)
    )
    model <- make_qsar_model(group, prep, ego_neighbors, bandwidths, cfg)
    cat(sprintf(
      "[%d/%d] %s group: estimating double-smoothed QSAR on %d restaurants...\n",
      g, length(group_names), group, length(ego_index)
    ))
    fit <- fit_qsar_gmm(model, cfg)

    estimate_tables[[group]] <- make_estimate_table(group, prep, fit)
    diagnostic_rows[[group]] <- make_diagnostic_row(
      group, net, ego_index, prep, bandwidths, fit, cutoff,
      grouping$prediction,
      neighbor_appearances, opposite_group_neighbor_appearances, cfg
    )
    profiles[[group]] <- transform(fit$profile, group = group)
    candidates[[group]] <- transform(fit$candidates, group = group)
    histories[[group]] <- transform(fit$gmm_iteration_history, group = group)
    degree_bandwidths[[group]] <- data.frame(
      group = group,
      id = net$support_nodes$id[ego_index],
      full_network_degree = ego_degree,
      h = bandwidths$h,
      tau = bandwidths$tau,
      stringsAsFactors = FALSE
    )

    lambda_hat <- fit$theta[[ncol(prep$X) + 1L]]
    z_hat <- tail(fit$theta, 1L)
    z_se <- tail(fit$standard_error, 1L)
    cat(sprintf(
      paste0(
        "[%d/%d] %s completed: egos=%d, original degree=%d--%d, ",
        "lambda=%.6f, z=%.6f (SE %.6f), raw smin=%.3e, GMM converged=%s.\n"
      ),
      g, length(group_names), group, length(ego_index),
      min(ego_degree), max(ego_degree), lambda_hat, z_hat, z_se,
      fit$jacobian_diagnostics$raw_smin,
      if (fit$gmm_converged) "YES" else "NO"
    ))
    if (abs(lambda_hat) < cfg$weak_lambda_warning ||
        fit$jacobian_diagnostics$raw_smin < cfg$raw_smin_warning) {
      warnf(
        paste0(
          "%s group has weak z identification (lambda=%.6f, raw smin=%.3e). ",
          "Report z as descriptive and do not tune the bandwidth after seeing this result."
        ),
        group, lambda_hat, fit$jacobian_diagnostics$raw_smin
      )
    }
  }

  membership <- data.frame(
    id = net$support_nodes$id,
    Y = net$support_nodes$Y,
    cross_fitted_predicted_Y = grouping$prediction,
    crossfit_fold = grouping$fold_id,
    full_network_degree = net$support_degree,
    predicted_Y_cutoff = cutoff,
    role = ifelse(net$support_degree >= cfg$moment_min_degree, "GMM_ego", "support_only"),
    ego_group = ifelse(
      net$support_degree < cfg$moment_min_degree,
      NA_character_,
      ifelse(
        grouping$prediction <= cutoff,
        "Predicted_Low",
        "Predicted_High"
      )
    ),
    stringsAsFactors = FALSE
  )
  transformations <- data.frame(
    variable = c(
      "repeat_customer_ratio", "commercial_zone_diversity", "menu_variety",
      if (reference$use_log_price) "log_average_transaction_value" else "average_transaction_value"
    ),
    full_sample_mean = unname(reference$means),
    full_sample_sd = unname(reference$sds),
    stringsAsFactors = FALSE
  )

  output_dir <- file.path(script_directory(), cfg$output_dir)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  estimates <- do.call(rbind, estimate_tables)
  diagnostics <- do.call(rbind, diagnostic_rows)
  z_table <- estimates[estimates$term == "z", c("group", "estimate", "standard_error")]
  z_comparison <- transform(
    z_table,
    full_sample_z_reference = cfg$full_sample_z_reference,
    difference_from_full_sample = estimate - cfg$full_sample_z_reference,
    position_relative_to_full_sample = ifelse(
      estimate < cfg$full_sample_z_reference, "below",
      ifelse(estimate > cfg$full_sample_z_reference, "above", "equal")
    )
  )
  utils::write.csv(estimates, file.path(output_dir, "qsar_predicted_low_high_estimates.csv"), row.names = FALSE)
  utils::write.csv(diagnostics, file.path(output_dir, "qsar_predicted_low_high_diagnostics.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, profiles), file.path(output_dir, "qsar_predicted_low_high_z_profiles.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, candidates), file.path(output_dir, "qsar_predicted_low_high_profile_candidates.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, histories), file.path(output_dir, "qsar_predicted_low_high_gmm_iteration_history.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, degree_bandwidths), file.path(output_dir, "qsar_predicted_low_high_degree_bandwidths.csv"), row.names = FALSE)
  utils::write.csv(z_comparison, file.path(output_dir, "qsar_predicted_low_high_z_comparison.csv"), row.names = FALSE)
  utils::write.csv(membership, file.path(output_dir, "qsar_predicted_low_high_membership.csv"), row.names = FALSE)
  utils::write.csv(transformations, file.path(output_dir, "qsar_predicted_low_high_transformations.csv"), row.names = FALSE)
  utils::write.csv(grouping$summary, file.path(output_dir, "ols_crossfit_summary.csv"), row.names = FALSE)
  utils::write.csv(grouping$coefficients, file.path(output_dir, "ols_crossfit_coefficients.csv"), row.names = FALSE)

  cat("\nPredicted-Low/Predicted-High QSAR estimates\n")
  print(estimates[, c("group", "term", "estimate", "standard_error")], row.names = FALSE)
  if (nrow(z_table) == 2L) {
    cat(sprintf(
      "\nEstimated z ordering: %s (%.6f) %s %s (%.6f).\n",
      z_table$group[[1L]], z_table$estimate[[1L]],
      if (z_table$estimate[[1L]] < z_table$estimate[[2L]]) "<" else ">=",
      z_table$group[[2L]], z_table$estimate[[2L]]
    ))
    below <- any(z_table$estimate < cfg$full_sample_z_reference)
    above <- any(z_table$estimate > cfg$full_sample_z_reference)
    cat(sprintf(
      "Pre-recorded full-sample z reference: %.6f; predicted-group estimates straddle it: %s.\n",
      cfg$full_sample_z_reference, if (below && above) "YES" else "NO"
    ))
    if (!(below && above)) {
      warnf(
        paste0(
          "The two predicted-group z estimates do not straddle the pre-recorded full-sample ",
          "estimate. This is a result, not a bandwidth-selection criterion; do not ",
          "retune h or tau after seeing it."
        )
      )
    }
  }
  cat("The full-sample QSAR is not re-estimated in this file.\n")
  cat(sprintf("\nAll outputs were written to: %s\n", output_dir))
  invisible(list(estimates = estimates, diagnostics = diagnostics))
}

if (sys.nframe() == 0L) main(CFG)
