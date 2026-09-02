CFG <- list(
  x_file = "Graph_X.xlsx",
  y_file = "Graph_Y0.xlsx",
  edge_file = "index_5.xlsx",
  x_sheet = "Sheet3",
  y_sheet = "Sheet2",
  edge_sheet = "Sheet3",
  output_dir = "qsar_peer_effect_test_output",

  price_transform = "auto",       # "auto", "log", or "none"
  heavy_tail_abs_skew = 2.0,
  heavy_tail_excess_kurtosis = 10.0,
  heavy_tail_max_to_median = 10.0,

  h_base = 0.16,
  h_degree_power = 0.35,
  h_bounds = c(0.02, 0.28),
  tau_base = 0.30,
  tau_degree_power = 0.30,
  tau_bounds = c(0.05, 0.60),

  z_grid = seq(0.10, 0.90, by = 0.10),
  B = 499L,
  seed = 20260812L,
  progress_every = 25L,
  matrix_tolerance = 1e-10
)

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)
clip <- function(x, bounds) pmin(bounds[[2L]], pmax(bounds[[1L]], x))

require_package <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stopf("Package '%s' is required. Install it with install.packages('%s').", pkg, pkg)
  }
}

solve_checked <- function(A, b = NULL, tolerance = 1e-10) {
  A <- as.matrix(A)
  singular_values <- svd(A, nu = 0L, nv = 0L)$d
  if (!length(singular_values) || min(singular_values) <=
      tolerance * max(1, max(singular_values))) {
    stopf("A fixed-z moment Jacobian is numerically rank deficient.")
  }
  if (is.null(b)) solve(A) else solve(A, b)
}

shape_statistics <- function(x) {
  x <- as.numeric(x)
  mu <- mean(x)
  s <- stats::sd(x)
  centered <- x - mu
  c(
    skewness = if (s > 0) mean(centered^3) / s^3 else 0,
    excess_kurtosis = if (s > 0) mean(centered^4) / s^4 - 3 else 0,
    max_to_median = if (stats::median(x) > 0) max(x) / stats::median(x) else Inf
  )
}

standardize_on <- function(x, reference_index) {
  center <- mean(x[reference_index])
  scale <- stats::sd(x[reference_index])
  if (!is.finite(scale) || scale <= 0) stopf("A continuous covariate has zero variance.")
  list(value = (x - center) / scale, center = center, scale = scale)
}

make_adjacency <- function(ids, edges) {
  from <- match(edges$from, ids)
  to <- match(edges$to, ids)
  ok <- !is.na(from) & !is.na(to) & from != to
  adjacency <- vector("list", length(ids))
  for (e in which(ok)) {
    i <- from[[e]]
    j <- to[[e]]
    adjacency[[i]] <- c(adjacency[[i]], j)
    adjacency[[j]] <- c(adjacency[[j]], i)
  }
  lapply(adjacency, unique)
}

read_and_prepare_data <- function(cfg) {
  require_package("readxl")
  paths <- c(X = cfg$x_file, Y = cfg$y_file, edge = cfg$edge_file)
  missing <- paths[!file.exists(paths)]
  if (length(missing)) {
    stopf("Place the following file(s) in the working directory: %s",
          paste(missing, collapse = ", "))
  }

  x_raw <- as.data.frame(readxl::read_excel(
    paths[["X"]], sheet = cfg$x_sheet, .name_repair = "minimal"
  ))
  y_raw <- as.data.frame(readxl::read_excel(
    paths[["Y"]], sheet = cfg$y_sheet, .name_repair = "minimal"
  ))
  edge_raw <- as.data.frame(readxl::read_excel(
    paths[["edge"]], sheet = cfg$edge_sheet, .name_repair = "minimal"
  ))

  required_x <- c("id", "复购用户占比", "location", "category", "客单价", "时间")
  if (length(setdiff(required_x, names(x_raw)))) stopf("Graph_X has unexpected columns.")
  if (!all(c("id", "Y") %in% names(y_raw))) stopf("Graph_Y0 must contain id and Y.")
  if (!all(c("row", "column") %in% names(edge_raw))) {
    stopf("index_5 must contain row and column.")
  }
  if (anyNA(x_raw) || anyNA(y_raw) || anyNA(edge_raw)) {
    stopf("The input files contain missing values.")
  }

  x_raw$id <- as.integer(x_raw$id)
  y_raw$id <- as.integer(y_raw$id)
  if (anyDuplicated(x_raw$id) || anyDuplicated(y_raw$id) ||
      !setequal(x_raw$id, y_raw$id)) {
    stopf("X and Y must have the same unique node IDs.")
  }
  y <- as.numeric(y_raw$Y[match(x_raw$id, y_raw$id)])
  nodes <- data.frame(
    id = x_raw$id,
    Y = y,
    repeat_customer_ratio = as.numeric(x_raw[["复购用户占比"]]),
    commercial_zone_diversity = as.numeric(x_raw[["location"]]),
    menu_variety = as.numeric(x_raw[["category"]]),
    average_transaction_value = as.numeric(x_raw[["客单价"]]),
    operating_hours = as.numeric(x_raw[["时间"]])
  )
  if (any(nodes$average_transaction_value <= 0)) {
    stopf("Average transaction values must be positive.")
  }
  if (!all(nodes$operating_hours %in% c(0, 1))) {
    stopf("Operating hours must be coded 0/1.")
  }

  edge_raw$row <- as.integer(edge_raw$row)
  edge_raw$column <- as.integer(edge_raw$column)
  if (!all(edge_raw$row %in% nodes$id) || !all(edge_raw$column %in% nodes$id)) {
    stopf("The edge list contains unknown node IDs.")
  }
  edge_raw <- edge_raw[edge_raw$row != edge_raw$column, , drop = FALSE]
  edges <- unique(data.frame(
    from = pmin(edge_raw$row, edge_raw$column),
    to = pmax(edge_raw$row, edge_raw$column)
  ))

  adjacency_all <- make_adjacency(nodes$id, edges)
  nonisolated <- lengths(adjacency_all) >= 1L
  ids <- nodes$id[nonisolated]
  dat <- nodes[nonisolated, , drop = FALSE]
  edges <- edges[edges$from %in% ids & edges$to %in% ids, , drop = FALSE]
  neighbors <- make_adjacency(ids, edges)
  degree <- lengths(neighbors)
  if (any(degree < 1L)) stopf("An isolated node remained after preprocessing.")

  # Use the same degree>=2 reference set as the main QSAR transformation, then
  # apply the transformation unchanged to every non-isolated test observation.
  reference_index <- which(degree >= 2L)
  price_stats <- shape_statistics(dat$average_transaction_value)
  heavy_tail <-
    abs(price_stats[["skewness"]]) > cfg$heavy_tail_abs_skew ||
    price_stats[["excess_kurtosis"]] > cfg$heavy_tail_excess_kurtosis ||
    price_stats[["max_to_median"]] > cfg$heavy_tail_max_to_median
  use_log <- switch(
    cfg$price_transform,
    auto = heavy_tail,
    log = TRUE,
    none = FALSE,
    stopf("price_transform must be 'auto', 'log', or 'none'.")
  )
  price <- if (use_log) log(dat$average_transaction_value) else dat$average_transaction_value
  s1 <- standardize_on(dat$repeat_customer_ratio, reference_index)
  s2 <- standardize_on(dat$commercial_zone_diversity, reference_index)
  s3 <- standardize_on(dat$menu_variety, reference_index)
  s4 <- standardize_on(price, reference_index)
  X <- cbind(
    Intercept = 1,
    repeat_customer_ratio = s1$value,
    commercial_zone_diversity = s2$value,
    menu_variety = s3$value,
    average_transaction_value = s4$value,
    operating_hours = dat$operating_hours
  )
  if (use_log) colnames(X)[[5L]] <- "log_average_transaction_value"
  storage.mode(X) <- "double"

  degree_reference <- stats::median(degree[degree >= 2L])
  h <- clip(
    cfg$h_base * (degree / degree_reference)^(-cfg$h_degree_power),
    cfg$h_bounds
  )
  tau <- clip(
    cfg$tau_base * (degree / degree_reference)^(-cfg$tau_degree_power),
    cfg$tau_bounds
  )

  list(
    ids = ids,
    y = dat$Y,
    X = X,
    edges = edges,
    neighbors = neighbors,
    degree = degree,
    h = h,
    tau = tau,
    degree_reference = degree_reference,
    use_log_price = use_log,
    removed_isolates = sum(!nonisolated)
  )
}

gaussian_smoothed_quantile <- function(sorted_values, z, bandwidth) {
  m <- length(sorted_values)
  if (m == 1L) return(sorted_values[[1L]])
  knots <- seq(0, 1, length.out = m)
  left <- knots[-m]
  right <- knots[-1L]
  slopes <- diff(sorted_values) / diff(knots)
  intercepts <- sorted_values[-m] - slopes * left
  A <- (left - z) / bandwidth
  B <- (right - z) / bandwidth
  probability <- stats::pnorm(B) - stats::pnorm(A)
  sorted_values[[1L]] * stats::pnorm(-z / bandwidth) +
    sorted_values[[m]] * (1 - stats::pnorm((1 - z) / bandwidth)) +
    sum(
      (intercepts + slopes * z) * probability +
        slopes * bandwidth * (stats::dnorm(A) - stats::dnorm(B))
    )
}

prepare_peer_smoother <- function(neighbors, z_grid, bandwidths) {
  lapply(seq_along(neighbors), function(i) {
    m <- length(neighbors[[i]])
    if (m == 1L) return(matrix(1, nrow = length(z_grid), ncol = 1L))
    weights <- matrix(0, nrow = length(z_grid), ncol = m)
    for (j in seq_len(m)) {
      basis <- numeric(m)
      basis[[j]] <- 1
      weights[, j] <- vapply(
        z_grid,
        function(z) gaussian_smoothed_quantile(basis, z, bandwidths[[i]]),
        numeric(1)
      )
    }
    if (max(abs(rowSums(weights) - 1)) > 1e-10) {
      stopf("A precomputed Gaussian smoothing operator failed its unit-sum check.")
    }
    weights
  })
}

peer_quantile_matrix <- function(values, neighbors, smoother, z_grid) {
  result <- matrix(NA_real_, nrow = length(neighbors), ncol = length(z_grid))
  for (i in seq_along(neighbors)) {
    result[i, ] <- drop(smoother[[i]] %*% sort(values[neighbors[[i]]]))
  }
  colnames(result) <- sprintf("z_%.2f", z_grid)
  result
}

fixed_z_statistics <- function(
  y, X, neighbors, observed_smoother, instrument_smoother, z_grid, tolerance
) {
  n <- length(y)
  p <- ncol(X)
  beta_restricted <- drop(solve_checked(
    crossprod(X) / n, crossprod(X, y) / n, tolerance
  ))
  fitted <- drop(X %*% beta_restricted)
  observed_peer <- peer_quantile_matrix(
    y, neighbors, observed_smoother, z_grid
  )
  fitted_peer <- peer_quantile_matrix(
    fitted, neighbors, instrument_smoother, z_grid
  )

  rows <- lapply(seq_along(z_grid), function(r) {
    regressors <- cbind(X, observed_peer[, r])
    instruments <- cbind(X, fitted_peer[, r])
    B <- crossprod(instruments, regressors) / n
    a <- crossprod(instruments, y) / n

    # There are p+1 moments for p+1 parameters.  Hence the fixed-z GMM
    # estimate solves g_n(phi)=0 and does not depend on the positive-definite
    # GMM weight matrix.
    theta <- drop(solve_checked(B, a, tolerance))
    residual <- y - drop(regressors %*% theta)
    scores <- instruments * residual
    Sigma <- crossprod(scores) / n
    G_inverse <- solve_checked(-B, tolerance = tolerance)
    V_root_n <- G_inverse %*% Sigma %*% t(G_inverse)
    se <- sqrt(pmax(diag(V_root_n) / n, 0))
    lambda_hat <- theta[[p + 1L]]
    lambda_se <- se[[p + 1L]]
    if (!is.finite(lambda_se) || lambda_se <= 0) {
      stopf("A fixed-z lambda standard error is not positive.")
    }
    singular_values <- svd(B, nu = 0L, nv = 0L)$d
    moments <- colMeans(scores)
    data.frame(
      z = z_grid[[r]],
      lambda = lambda_hat,
      lambda_se = lambda_se,
      t_statistic = lambda_hat / lambda_se,
      t_squared = (lambda_hat / lambda_se)^2,
      raw_jacobian_smin = min(singular_values),
      jacobian_condition = max(singular_values) / min(singular_values),
      max_abs_moment = max(abs(moments))
    )
  })
  table <- do.call(rbind, rows)
  list(table = table, T = sum(table$t_squared))
}

run_test <- function(cfg = CFG) {
  if (cfg$B < 1L || length(cfg$z_grid) < 2L ||
      any(cfg$z_grid <= 0 | cfg$z_grid >= 1)) {
    stopf("B and z_grid are invalid.")
  }
  cat("Reading data, deleting isolates, and preparing the fixed-z test...\n")
  dat <- read_and_prepare_data(cfg)
  cat("Precomputing the two Gaussian smoothing operators...\n")
  observed_smoother <- prepare_peer_smoother(
    dat$neighbors, cfg$z_grid, dat$h
  )
  instrument_smoother <- prepare_peer_smoother(
    dat$neighbors, cfg$z_grid, dat$tau
  )
  observed <- fixed_z_statistics(
    dat$y, dat$X, dat$neighbors, observed_smoother, instrument_smoother,
    cfg$z_grid, cfg$matrix_tolerance
  )

  n <- length(dat$y)
  beta_null <- drop(solve_checked(
    crossprod(dat$X) / n, crossprod(dat$X, dat$y) / n,
    cfg$matrix_tolerance
  ))
  fitted_null <- drop(dat$X %*% beta_null)
  centered_residual <- dat$y - fitted_null
  centered_residual <- centered_residual - mean(centered_residual)

  set.seed(cfg$seed)
  bootstrap_T <- rep(NA_real_, cfg$B)
  cat(sprintf(
    "Observed T=%.6f. Starting %d residual-bootstrap replications...\n",
    observed$T, cfg$B
  ))
  for (b in seq_len(cfg$B)) {
    y_b <- fitted_null + sample(centered_residual, n, replace = TRUE)
    bootstrap_T[[b]] <- tryCatch(
      fixed_z_statistics(
        y_b, dat$X, dat$neighbors, observed_smoother, instrument_smoother,
        cfg$z_grid, cfg$matrix_tolerance
      )$T,
      error = function(e) NA_real_
    )
    if (b %% cfg$progress_every == 0L || b == cfg$B) {
      cat(sprintf("[%03d/%03d] bootstrap samples completed.\n", b, cfg$B))
    }
  }

  valid <- is.finite(bootstrap_T)
  failed <- sum(!valid)
  if (failed > max(5L, ceiling(0.01 * cfg$B))) {
    stopf("%d bootstrap replications failed numerically; inspect fixed-z rank.", failed)
  }
  if (failed > 0L) {
    warning(sprintf("%d bootstrap replications failed numerically and were omitted.", failed),
            call. = FALSE)
  }
  bootstrap_T <- bootstrap_T[valid]
  B_valid <- length(bootstrap_T)

  # The plus-one correction prevents a reported p-value of zero and is the
  # recommended finite-bootstrap version of the appendix formula.
  p_value <- (1 + sum(bootstrap_T >= observed$T)) / (B_valid + 1)
  critical <- stats::quantile(
    bootstrap_T, probs = c(0.90, 0.95, 0.99), names = FALSE, type = 1
  )
  summary <- data.frame(
    n_nonisolated = n,
    undirected_edges = nrow(dat$edges),
    degree_one_nodes = sum(dat$degree == 1L),
    removed_isolates = dat$removed_isolates,
    z_grid = paste(sprintf("%.2f", cfg$z_grid), collapse = ","),
    B_requested = cfg$B,
    B_valid = B_valid,
    observed_T = observed$T,
    critical_90 = critical[[1L]],
    critical_95 = critical[[2L]],
    critical_99 = critical[[3L]],
    bootstrap_p_value = p_value,
    reject_10_percent = p_value < 0.10,
    reject_5_percent = p_value < 0.05,
    reject_1_percent = p_value < 0.01,
    h_min = min(dat$h),
    h_median = stats::median(dat$h),
    h_max = max(dat$h),
    tau_min = min(dat$tau),
    tau_median = stats::median(dat$tau),
    tau_max = max(dat$tau),
    log_price_used = dat$use_log_price
  )
  bootstrap_table <- data.frame(
    bootstrap_replication = seq_along(bootstrap_T),
    T = bootstrap_T
  )

  dir.create(cfg$output_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(
    observed$table,
    file.path(cfg$output_dir, "peer_effect_fixed_z_statistics.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    bootstrap_table,
    file.path(cfg$output_dir, "peer_effect_bootstrap_statistics.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    summary,
    file.path(cfg$output_dir, "peer_effect_test_summary.csv"),
    row.names = FALSE
  )

  cat("\nFixed-z statistics\n")
  print(observed$table, row.names = FALSE)
  cat("\nAggregate peer-effect test\n")
  print(summary, row.names = FALSE)
  cat(sprintf("\nOutputs written to: %s\n", cfg$output_dir))

  invisible(list(
    data = dat,
    fixed_z = observed$table,
    bootstrap = bootstrap_table,
    summary = summary
  ))
}

results <- run_test(CFG)
