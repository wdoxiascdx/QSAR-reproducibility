if (
  !requireNamespace("Matrix", quietly = TRUE) ||
    !requireNamespace("igraph", quietly = TRUE)
) {
  stop("Packages 'Matrix' and 'igraph' are required.")
}

options(stringsAsFactors = FALSE)

IDENTIFICATION_SAFETY_FACTOR <- 1.20

CFG <- list(
  N = c(1000L, 2000L, 3000L),
  R = 500L,
  network_types = c("Dyad", "SBM", "PowerLaw"),
  z_values = c(0.30, 0.50, 0.70),
  seed = 20261208L,

  # theta_0 = (beta_1, beta_2, lambda, z_0); there is no intercept.
  beta = c(0.90, -0.65),
  lambda = 0.28,
  z = 0.50,  # overwritten inside each z_0 scenario
  innovation_sd = 0.30,
  lambda_bounds = c(0.05, 0.55),
  z_bounds = c(0.10, 0.90),
  confidence_level = 0.95,
  coverage_mc_band_level = 0.95,

  # Dyad and SBM have expected mean degree
  # 64*(N/1000)^0.38.  Power-Law has exact truncated degrees with lower
  # and upper endpoints growing at rates N^0.38 and N^0.44.
  degree_base = c(Dyad = 64, SBM = 64, PowerLaw = 32),
  degree_power = c(Dyad = 0.38, SBM = 0.38, PowerLaw = 0.38),
  max_degree_power =
    c(Dyad = 0.38, SBM = 0.38, PowerLaw = 0.44),
  min_degree_fraction = c(Dyad = 0.35, SBM = 0.30, PowerLaw = 0.99),
  dyad_sampling = "bernoulli",
  sbm_in_out_ratio = 4.0,
  powerlaw_exponent = 2.20,
  powerlaw_min_degree_base = 32,
  powerlaw_min_degree_exponent = 0.38,
  powerlaw_max_degree_base = 128,
  powerlaw_max_degree_exponent = 0.44,
  # igraph's Viger-Latapy generator returns a connected, simple, undirected
  # graph with the requested degree sequence and randomizes it by
  # degree-preserving edge switches.
  powerlaw_graph_method = "vl",
  network_attempts = 30L,

  # Strength of both A-dependent exposures in X.  This is frozen using
  # pre-error design diagnostics, never by inspecting MSE or coverage.
  x_network_strength = 1.50,
  # The first part of Assumption 3 requires the minimum eigenvalue of
  # Q_X=n^{-1}X^T X to stay away from zero.  Use an explicit spectral lower
  # bound rather than relying on a condition number alone.
  x_gram_eigen_min = IDENTIFICATION_SAFETY_FACTOR * 0.60,

  # Gaussian convolution uses separate bandwidths for the residual and instruments.
  #   h_i = 0.060 (n/1000)^(-0.32) (d_i/dbar_n)^(-0.08).
  #   tau_i = 0.160 (n/1000)^(-0.18) (d_i/dbar_n)^(-0.08).
  h_y_base = 0.060,
  h_y_exponent = 0.32,
  h_y_degree_power = 0.08,
  h_y_limits = c(1e-4, 0.240),
  # The exponent 0.18 < 1/4 keeps tau_i above the n^{-1/4} scale up to
  # logarithmic factors.
  tau_base = 0.160,
  tau_exponent = 0.18,
  tau_degree_power = 0.08,
  x_condition_max = 1.60,
  # The broad numerical guards are inactive at the three requested N values
  # and do not create an asymptotic positive bandwidth floor.
  tau_limits = c(1e-4, 0.240),

  # All pre-formal smallest-singular-value thresholds below use the same 20%
  # safety factor relative to the preceding design.  This rule was fixed
  # before the fresh seed above is run and is not network-, z- or N-specific.
  identification_safety_factor = IDENTIFICATION_SAFETY_FACTOR,

  # Error-free A/X instrument screen.  raw_smin is the smallest singular
  # value of [Q_i, lambda Q_i'] after partialling out X and division by
  # sqrt(N).  This screen does not attempt to approximate E{Y_-(z)}.
  design_raw_smin_min =
    IDENTIFICATION_SAFETY_FACTOR *
      c(Dyad = 0.060, SBM = 0.060, PowerLaw = 0.060),
  design_scaled_smin_min =
    IDENTIFICATION_SAFETY_FACTOR *
      c(Dyad = 0.080, SBM = 0.080, PowerLaw = 0.080),
  design_max_abs_correlation =
    c(Dyad = 0.95, SBM = 0.95, PowerLaw = 0.95),
  design_z_offsets = c(-0.08, 0, 0.08),
  design_attempts = 40L,

  # Four mutually independent auxiliary Gaussian innovation vectors are used
  # only to screen A/X before the formal innovation is drawn.  For each true
  # z_0, they estimate mu_n(z)=E{Y_-(z)|A,X}; exact local secants are formed
  # from that Monte Carlo mean at z_0 +/- {0.04,0.08}.  The oracle instruments
  # are evaluated over lambda_0 +/- 0.04 as well as lambda_0.  This is a
  # finite-grid diagnostic for the uniform condition in Assumption 3.
  pilot_B = 4L,
  pilot_secant_z_offsets = c(-0.08, -0.04, 0.04, 0.08),
  pilot_secant_lambda_offsets = c(-0.04, 0, 0.04),
  pilot_secant_raw_smin_min =
    IDENTIFICATION_SAFETY_FACTOR * 0.0025,
  pilot_secant_scaled_smin_min =
    IDENTIFICATION_SAFETY_FACTOR * 0.006,
  # The same four pilots also provide a complementary full-moment Jacobian
  # screen.  Matrices are averaged before their singular values are computed.
  pilot_jacobian_smin_min =
    IDENTIFICATION_SAFETY_FACTOR * 0.012,
  pilot_jacobian_scaled_smin_min =
    IDENTIFICATION_SAFETY_FACTOR * 0.010,
  # These truth-based post-outcome, pre-estimation diagnostics remain
  # report-only and are not used by the separate fit-based numerical rule.
  assumption3_jacobian_smin_warn = 0.012,
  assumption3_scaled_smin_warn = 0.010,
  post_outcome_screen_action = "diagnose_only",
  # Fixed post-estimation numerical-admissibility rule.  The theoretical
  # standard-error bound is imposed on the root-N scale so that the same
  # constant is used at all three sample sizes.  Either failure rejects the
  # whole network/N/replication block, including all three z_0 outcomes.
  formal_numerical_retry = TRUE,
  formal_root_n_se_max = 3.0,
  formal_jacobian_condition_max = 500.0,
  # This retry count covers A/X generation, the independent-pilot screen and
  # the fixed post-estimation numerical-admissibility screen.
  max_resample_attempts = 200L,

  fixed_point_tolerance = 1e-9,
  fixed_point_max_iterations = 250L,
  z_grid_size = 81L,
  # Global profile selection with h-smoothed structural Y_-(z) and
  # tau-smoothed instruments.  Local minima at the two fixed z-boundaries are
  # included.  Candidate minima are ranked by the same identity-weight
  # criterion and greedily retained only when they are at least
  # profile_min_separation apart.
  profile_max_candidates = 3L,
  profile_min_separation = 0.08,
  # Candidate comparison uses n*Q_n.  Only candidates within this fixed
  # numerical tolerance of the smallest score are treated as tied.  The
  # tie-break then maximizes the normalized distance from the fixed z and
  # lambda bounds; it never uses truth, MSE, coverage or a Jacobian screen.
  profile_selection_abs_tolerance = 1e-8,
  profile_selection_rel_tolerance = 1e-7,
  profile_optimizer_tolerance = 1e-7,
  profile_basin_hit_tolerance = 1e-4,
  # The profile optimizer uses function values only.  This step is used for
  # numerical z-Jacobians in unsmoothed identification diagnostics, so a knot gets
  # the symmetric local slope instead of an arbitrary one-sided derivative.
  jacobian_z_step = 1e-4,
  gmm_max_iterations = 3L,
  gmm_parameter_tolerance = 1e-6,
  ridge = 1e-9,
  # The paper's stated iterated-GMM update uses node-level score outer
  # products.  "network" remains available as a sensitivity option.
  weighting = "iid",  # "iid" or "network"
  score_covariance = "iid_robust",  # or "homoskedastic"
  run_internal_tests = TRUE,
  # Process-level parallelism across independent replication blocks.
  # NULL uses floor(parallel_fraction * available logical cores).
  # Set parallel_workers to an integer to override the automatic choice.
  parallel = TRUE,
  parallel_fraction = 0.80,
  parallel_workers = NULL,
  # PSOCK keeps a persistent worker pool and gives cross-platform dynamic
  # load balancing.  "auto" is still accepted and resolves to PSOCK.
  parallel_backend = "psock",
  # Used only if "multicore" is selected explicitly.  TRUE avoids creating a
  # fresh fork for every one of the 4500 blocks.
  parallel_preschedule = TRUE,
  # One scheduler task is one complete data block containing all three z_0.
  # Single-block dynamic dispatch is intentionally used because N and network
  # mechanism produce materially different runtimes.
  parallel_block_chunk_size = 1L,
  parallel_progress = TRUE,
  # With the default PSOCK backend, the main process prints and flushes one
  # console line immediately after each returned network/N/replication block.
  progress_every_block = TRUE,
  # Used by sequential/multicore fallback progress.  PSOCK instead prints
  # directly from the main-process dispatcher.
  progress_target_updates = 500L,
  progress_bar_width = 42L,
  # NULL makes the directory name update automatically when CFG$R changes.
  output_dir = NULL
)

clamp <- function(x, lower, upper) {
  pmin(pmax(x, lower), upper)
}

safe_solve <- function(A, b, ridge = CFG$ridge) {
  A <- (A + t(A)) / 2
  scale_A <- max(1, mean(abs(diag(A))))
  solve(A + diag(ridge * scale_A, nrow(A)), b)
}

edge_index_to_ij <- function(k) {
  # Column-wise enumeration of the strict upper triangle:
  # (1,2), (1,3), (2,3), (1,4), ...
  k <- as.numeric(k)
  j <- ceiling((1 + sqrt(1 + 8 * k)) / 2)
  i <- k - (j - 1) * (j - 2) / 2
  list(i = as.integer(i), j = as.integer(j))
}

make_adjacency <- function(n, i, j) {
  if (length(i) == 0L) stop("The generated graph has no edges.")
  A <- Matrix::sparseMatrix(
    i = c(i, j),
    j = c(j, i),
    x = 1,
    dims = c(n, n),
    giveCsparse = TRUE
  )
  A@x[] <- 1
  diag(A) <- 0
  Matrix::drop0(A)
}

sample_within_block <- function(nodes, probability) {
  m_nodes <- length(nodes)
  total <- m_nodes * (m_nodes - 1) / 2
  edge_count <- stats::rbinom(1L, size = total, prob = probability)
  if (edge_count == 0L) return(list(i = integer(), j = integer()))
  pair_id <- sample.int(total, edge_count, replace = FALSE)
  ij <- edge_index_to_ij(pair_id)
  list(i = nodes[ij$i], j = nodes[ij$j])
}

sample_between_blocks <- function(nodes_a, nodes_b, probability) {
  n_a <- length(nodes_a)
  n_b <- length(nodes_b)
  total <- n_a * n_b
  edge_count <- stats::rbinom(1L, size = total, prob = probability)
  if (edge_count == 0L) return(list(i = integer(), j = integer()))
  pair_id <- sample.int(total, edge_count, replace = FALSE)
  local_a <- ((pair_id - 1L) %% n_a) + 1L
  local_b <- ((pair_id - 1L) %/% n_a) + 1L
  list(i = nodes_a[local_a], j = nodes_b[local_b])
}

generate_dyad_independence <- function(
  n,
  target_degree,
  sampling = "bernoulli"
) {
  if (!identical(sampling, "bernoulli")) {
    stop("The classical Dyad design requires Bernoulli sampling.")
  }
  probability <- target_degree / (n - 1)
  if (probability <= 0 || probability >= 1) {
    stop("Invalid classical Dyad edge probability.")
  }

  # Drawing E~Binomial(C(n,2),p), followed by a uniformly selected E-subset,
  # is exactly equivalent to drawing all unordered dyads independently from
  # Bernoulli(p), but avoids allocating C(n,2) indicators.
  total_dyads <- n * (n - 1) / 2
  edge_count <- stats::rbinom(
    1L,
    size = total_dyads,
    prob = probability
  )
  if (edge_count == 0L) {
    stop("The generated classical Dyad graph has no edges.")
  }
  pair_id <- sample.int(total_dyads, edge_count, replace = FALSE)
  ij <- edge_index_to_ij(pair_id)
  list(
    A = make_adjacency(n, ij$i, ij$j),
    probability = probability
  )
}

generate_sbm <- function(n, target_degree, block,
                         in_out_ratio = 4.0) {
  if (max(block) != 2L) stop("The SBM must contain exactly two blocks.")
  block_size <- n / 2
  p_out <- target_degree /
    ((block_size - 1) * in_out_ratio + n - block_size)
  p_in <- in_out_ratio * p_out

  nodes_1 <- which(block == 1L)
  nodes_2 <- which(block == 2L)
  within_1 <- sample_within_block(nodes_1, p_in)
  within_2 <- sample_within_block(nodes_2, p_in)
  between <- sample_between_blocks(nodes_1, nodes_2, p_out)
  list(
    A = make_adjacency(
      n,
      c(within_1$i, within_2$i, between$i),
      c(within_1$j, within_2$j, between$j)
    ),
    p_in = p_in,
    p_out = p_out
  )
}

draw_powerlaw_degrees <- function(n, cfg = CFG) {
  minimum_degree <- as.integer(ceiling(
    cfg$powerlaw_min_degree_base *
      (n / 1000)^cfg$powerlaw_min_degree_exponent
  ))
  maximum_degree <- as.integer(floor(
    cfg$powerlaw_max_degree_base *
      (n / 1000)^cfg$powerlaw_max_degree_exponent
  ))
  maximum_degree <- min(n - 1L, maximum_degree)
  if (minimum_degree < 2L || maximum_degree <= minimum_degree) {
    stop("Invalid truncated Power-Law support.")
  }
  support <- seq.int(minimum_degree, maximum_degree)
  probability <- support^(-cfg$powerlaw_exponent)
  probability <- probability / sum(probability)
  degree <- sample(support, n, replace = TRUE, prob = probability)

  # An undirected degree sequence must have an even sum.  Change one draw by
  # one only when needed, while staying inside the declared support.
  if (sum(degree) %% 2L == 1L) {
    can_increase <- which(degree < maximum_degree)
    if (length(can_increase) > 0L) {
      selected <- sample(can_increase, 1L)
      degree[selected] <- degree[selected] + 1L
    } else {
      can_decrease <- which(degree > minimum_degree)
      if (length(can_decrease) == 0L) {
        stop("Could not make the Power-Law degree sum even.")
      }
      selected <- sample(can_decrease, 1L)
      degree[selected] <- degree[selected] - 1L
    }
  }
  as.integer(degree)
}

generate_powerlaw <- function(n, cfg = CFG) {
  last_error <- NULL
  for (degree_attempt in seq_len(cfg$network_attempts)) {
    degree <- draw_powerlaw_degrees(n, cfg)
    if (!isTRUE(igraph::is_graphical(
      degree,
      allowed.edge.types = "simple"
    ))) {
      next
    }

    graph <- tryCatch(
      igraph::sample_degseq(
        out.deg = degree,
        method = cfg$powerlaw_graph_method
      ),
      error = function(e) {
        last_error <<- conditionMessage(e)
        NULL
      }
    )
    if (is.null(graph)) next
    if (
      igraph::is_directed(graph) ||
        !igraph::is_simple(graph) ||
        igraph::vcount(graph) != n
    ) {
      last_error <- "igraph returned a graph of the wrong type."
      next
    }
    edge_list <- igraph::as_edgelist(graph, names = FALSE)
    if (nrow(edge_list) == 0L) {
      last_error <- "igraph returned a graph with no edges."
      next
    }
    A <- make_adjacency(n, edge_list[, 1L], edge_list[, 2L])
    realized_degree <- as.integer(Matrix::rowSums(A))
    if (!identical(realized_degree, degree)) {
      last_error <- "The requested Power-Law degrees were not preserved."
      next
    }
    return(list(
      A = A,
      drawn_degree = degree,
      degree_sequence_attempts = degree_attempt
    ))
  }

  stop(
    sprintf(
      paste0(
        "Power-Law graph generation failed after %d degree-sequence ",
        "attempts%s."
      ),
      cfg$network_attempts,
      if (is.null(last_error)) "" else paste0(": ", last_error)
    )
  )
}

adjacency_to_neighbors <- function(A) {
  n <- nrow(A)
  triplet <- Matrix::summary(A)
  out <- split(
    triplet$j,
    factor(triplet$i, levels = seq_len(n))
  )
  lapply(out, as.integer)
}

generate_network <- function(n, mechanism, cfg = CFG) {
  degree_base <- if (length(cfg$degree_base) == 1L) {
    cfg$degree_base
  } else {
    unname(cfg$degree_base[mechanism])
  }
  degree_power <- if (length(cfg$degree_power) == 1L) {
    cfg$degree_power
  } else {
    unname(cfg$degree_power[mechanism])
  }
  if (!is.finite(degree_base) || !is.finite(degree_power)) {
    stop("Missing degree parameter for network mechanism: ", mechanism)
  }
  min_degree_fraction <- if (length(cfg$min_degree_fraction) == 1L) {
    cfg$min_degree_fraction
  } else {
    unname(cfg$min_degree_fraction[mechanism])
  }
  if (!is.finite(min_degree_fraction) || min_degree_fraction <= 0) {
    stop("Missing minimum-degree fraction for: ", mechanism)
  }
  target_degree <- degree_base * (n / 1000)^degree_power
  block <- if (identical(mechanism, "SBM")) {
    sample(
      rep(c(1L, 2L), length.out = n),
      size = n,
      replace = FALSE
    )
  } else {
    rep(NA_integer_, n)
  }
  required_min_degree <- max(
    15L,
    floor(min_degree_fraction * target_degree)
  )

  for (attempt in seq_len(cfg$network_attempts)) {
    generated <- switch(
      mechanism,
      Dyad = generate_dyad_independence(
        n,
        target_degree,
        cfg$dyad_sampling
      ),
      SBM = generate_sbm(
        n,
        target_degree,
        block,
        cfg$sbm_in_out_ratio
      ),
      PowerLaw = generate_powerlaw(n, cfg),
      stop("Unknown network mechanism: ", mechanism)
    )
    A <- generated$A
    degree <- as.numeric(Matrix::rowSums(A))
    if (identical(mechanism, "PowerLaw")) {
      required_min_degree <- min(generated$drawn_degree)
      target_degree <- mean(generated$drawn_degree)
    }
    if (min(degree) >= required_min_degree) {
      neighbors <- adjacency_to_neighbors(A)
      return(list(
        A = A,
        neighbors = neighbors,
        degree = degree,
        target_degree = target_degree,
        block = block,
        mechanism = mechanism,
        attempts = attempt,
        directed = FALSE,
        p_in = if (identical(mechanism, "SBM")) {
          generated$p_in
        } else {
          NA_real_
        },
        p_out = if (identical(mechanism, "SBM")) {
          generated$p_out
        } else {
          NA_real_
        },
        dyad_probability = if (identical(mechanism, "Dyad")) {
          generated$probability
        } else {
          NA_real_
        },
        drawn_degree_min = if (identical(mechanism, "PowerLaw")) {
          min(generated$drawn_degree)
        } else {
          NA_real_
        },
        drawn_degree_max = if (identical(mechanism, "PowerLaw")) {
          max(generated$drawn_degree)
        } else {
          NA_real_
        },
        drawn_degree = if (identical(mechanism, "PowerLaw")) {
          generated$drawn_degree
        } else {
          NULL
        },
        degree_sequence_attempts = if (
          identical(mechanism, "PowerLaw")
        ) {
          generated$degree_sequence_attempts
        } else {
          NA_integer_
        }
      ))
    }
  }

  stop(
    sprintf(
      "%s network failed the minimum-degree check after %d attempts.",
      mechanism, cfg$network_attempts
    )
  )
}

linear_quantile_slope_jumps <- function(value_matrix, degree) {
  # For knots t_k=(k-1)/(d-1), the constantly extended linearly interpolated
  # quantile can be represented as
  #
  #   Q(t) = Y_(1) + sum_r a_r (t-t_r)_+,
  #
  # where a_r are jumps in the piecewise-linear slope, including the jumps
  # from zero slope at 0 and back to zero at 1.
  if (degree == 1L) {
    return(list(
      intercept = value_matrix[, 1L],
      jumps = matrix(0, nrow = nrow(value_matrix), ncol = 1L),
      breaks = 0
    ))
  }

  slopes <- (degree - 1) * (
    value_matrix[, 2:degree, drop = FALSE] -
      value_matrix[, seq_len(degree - 1L), drop = FALSE]
  )
  interior_jumps <- if (degree > 2L) {
    slopes[, 2:(degree - 1L), drop = FALSE] -
      slopes[, seq_len(degree - 2L), drop = FALSE]
  } else {
    matrix(numeric(), nrow = nrow(value_matrix), ncol = 0L)
  }
  jumps <- cbind(
    slopes[, 1L],
    interior_jumps,
    -slopes[, degree - 1L]
  )
  list(
    intercept = value_matrix[, 1L],
    jumps = jumps,
    breaks = seq(0, 1, length.out = degree)
  )
}

gaussian_linear_hinge <- function(breaks, z, tau) {
  # If T ~ N(z,tau^2), then
  # E[(T-b)_+] = (z-b) Phi((z-b)/tau) + tau phi((z-b)/tau).
  # Its first two z-derivatives are Phi((z-b)/tau) and
  # phi((z-b)/tau)/tau.  Combining these hinge bases with the slope jumps gives
  # the exact Gaussian convolution of the constantly extended interpolated
  # quantile and its first two derivatives.
  delta <- z - breaks
  standardized <- delta / tau
  list(
    value = delta * stats::pnorm(standardized) +
      tau * stats::dnorm(standardized),
    derivative = stats::pnorm(standardized),
    second_derivative = stats::dnorm(standardized) / tau
  )
}

gaussian_linear_hinge_grid <- function(breaks, z_grid, tau) {
  delta <- outer(breaks, z_grid, function(b, z) z - b)
  standardized <- delta / tau
  list(
    value = delta * stats::pnorm(standardized) +
      tau * stats::dnorm(standardized),
    derivative = stats::pnorm(standardized),
    second_derivative = stats::dnorm(standardized) / tau
  )
}

tau_value <- function(n, degree, mean_degree, cfg = CFG) {
  tau <- cfg$tau_base *
    (n / 1000)^(-cfg$tau_exponent) *
    (degree / mean_degree)^(-cfg$tau_degree_power)
  clamp(tau, cfg$tau_limits[1L], cfg$tau_limits[2L])
}

h_value <- function(n, degree, mean_degree, cfg = CFG) {
  h <- cfg$h_y_base *
    (n / 1000)^(-cfg$h_y_exponent) *
    (degree / mean_degree)^(-cfg$h_y_degree_power)
  clamp(h, cfg$h_y_limits[1L], cfg$h_y_limits[2L])
}

make_sorted_peer_groups <- function(values, neighbors) {
  degree <- lengths(neighbors)
  node_groups <- split(seq_along(neighbors), degree)
  lapply(node_groups, function(nodes) {
    d <- degree[nodes[1L]]
    sorted_values <- vapply(
      nodes,
      function(i) sort.int(values[neighbors[[i]]], method = "quick"),
      numeric(d)
    )
    if (length(nodes) == 1L) {
      sorted_values <- matrix(sorted_values, nrow = d, ncol = 1L)
    }
    list(
      nodes = nodes,
      degree = d,
      values = t(sorted_values)
    )
  })
}

smooth_peer_quantile <- function(
    sorted_groups, z, n, mean_degree, cfg = CFG, bandwidth_fun = tau_value) {
  q <- numeric(n)
  dq <- numeric(n)
  ddq <- numeric(n)

  for (one_group in sorted_groups) {
    tau <- bandwidth_fun(n, one_group$degree, mean_degree, cfg)
    representation <- linear_quantile_slope_jumps(
      one_group$values,
      one_group$degree
    )
    basis <- gaussian_linear_hinge(representation$breaks, z, tau)
    q[one_group$nodes] <- representation$intercept +
      as.numeric(representation$jumps %*% basis$value)
    dq[one_group$nodes] <- as.numeric(
      representation$jumps %*% basis$derivative
    )
    ddq[one_group$nodes] <- as.numeric(
      representation$jumps %*% basis$second_derivative
    )
  }
  list(q = q, dq = dq, ddq = ddq)
}

smooth_peer_quantile_grid <- function(
    sorted_groups, z_grid, n, mean_degree, cfg = CFG, bandwidth_fun = tau_value) {
  q <- matrix(NA_real_, nrow = n, ncol = length(z_grid))
  dq <- matrix(NA_real_, nrow = n, ncol = length(z_grid))
  ddq <- matrix(NA_real_, nrow = n, ncol = length(z_grid))

  for (one_group in sorted_groups) {
    tau <- bandwidth_fun(n, one_group$degree, mean_degree, cfg)
    representation <- linear_quantile_slope_jumps(
      one_group$values,
      one_group$degree
    )
    basis <- gaussian_linear_hinge_grid(
      representation$breaks,
      z_grid,
      tau
    )
    q_one <- representation$jumps %*% basis$value
    q_one <- sweep(q_one, 1L, representation$intercept, "+")
    q[one_group$nodes, ] <- q_one
    dq[one_group$nodes, ] <-
      representation$jumps %*% basis$derivative
    ddq[one_group$nodes, ] <-
      representation$jumps %*% basis$second_derivative
  }
  list(q = q, dq = dq, ddq = ddq)
}

interpolated_peer_quantile_grid <- function(
    sorted_groups, z_grid, n) {
  q <- matrix(NA_real_, nrow = n, ncol = length(z_grid))
  dq <- matrix(0, nrow = n, ncol = length(z_grid))

  for (one_group in sorted_groups) {
    degree <- one_group$degree
    if (degree == 1L) {
      q[one_group$nodes, ] <- one_group$values[, 1L]
      next
    }

    ell <- 1 + (degree - 1) * z_grid
    lower <- pmin(degree - 1L, pmax(1L, floor(ell)))
    alpha <- ell - lower
    for (k in seq_along(z_grid)) {
      q[one_group$nodes, k] <-
        (1 - alpha[k]) * one_group$values[, lower[k]] +
        alpha[k] * one_group$values[, lower[k] + 1L]
      dq[one_group$nodes, k] <- (degree - 1) * (
        one_group$values[, lower[k] + 1L] -
          one_group$values[, lower[k]]
      )
    }
  }
  list(q = q, dq = dq)
}

interpolated_peer_quantile <- function(sorted_groups, z, n) {
  one <- interpolated_peer_quantile_grid(sorted_groups, z, n)
  list(
    q = as.numeric(one$q[, 1L]),
    dq = as.numeric(one$dq[, 1L])
  )
}

design_diagnostic <- function(X, network, z0 = NULL, cfg = CFG) {
  if (is.null(z0)) z0 <- cfg$z
  n <- nrow(X)
  mean_signal <- as.numeric(X %*% cfg$beta)
  sorted_signal <- make_sorted_peer_groups(mean_signal, network$neighbors)
  smoothed <- smooth_peer_quantile(
    sorted_signal,
    z0,
    n,
    mean(network$degree),
    cfg
  )

  B <- cbind(smoothed$q, cfg$lambda * smoothed$dq)
  projection_coef <- safe_solve(crossprod(X), crossprod(X, B))
  residual_B <- B - X %*% projection_coef
  raw_singular_values <- svd(residual_B / sqrt(n), nu = 0, nv = 0)$d

  rms <- sqrt(colMeans(residual_B^2))
  scaled_B <- sweep(residual_B, 2L, pmax(rms, 1e-12), "/")
  scaled_singular_values <- svd(
    scaled_B / sqrt(n), nu = 0, nv = 0
  )$d
  correlation <- suppressWarnings(
    stats::cor(residual_B[, 1L], residual_B[, 2L])
  )
  if (!is.finite(correlation)) correlation <- Inf

  list(
    raw_smin = min(raw_singular_values),
    scaled_smin = min(scaled_singular_values),
    correlation = correlation,
    q_rms = rms[1L],
    lambda_dq_rms = rms[2L]
  )
}

make_X_candidate <- function(network, cfg = CFG) {
  n <- length(network$degree)
  u <- stats::rnorm(n)
  v <- stats::rnorm(n)
  rho <- cfg$x_network_strength
  sqrt_degree <- sqrt(network$degree)

  # A-dependent, population-normalized, no-intercept design.  Conditional on
  # A, M_i and H_i both have mean zero and variance one:
  #
  # M_i = sum_j A_ij U_j/sqrt(d_i),
  # H_i = sum_j A_ij(V_j^2-1)/sqrt(2d_i).
  #
  # Since A_ii=0, U_i is independent of M_i and V_i is independent of H_i.
  # Thus each X column has conditional mean zero and unit second moment.
  network_location <- as.numeric(network$A %*% u) / sqrt_degree
  network_shape <- as.numeric(
    network$A %*% (v^2 - 1)
  ) / sqrt(2 * network$degree)
  X <- cbind(
    x1 = (u + rho * network_location) / sqrt(1 + rho^2),
    x2 = (v + rho * network_shape) / sqrt(1 + rho^2)
  )
  if (any(!is.finite(X))) stop("X contains a non-finite value.")
  X
}

generate_identified_X <- function(network, cfg = CFG) {
  best <- NULL
  best_score <- -Inf
  best_gram_condition <- Inf
  best_gram_eigen_min <- -Inf
  gram_rejections <- 0L
  z_values <- sort(unique(cfg$z_values))
  screen_z_values <- sort(unique(as.numeric(outer(
    z_values,
    cfg$design_z_offsets,
    "+"
  ))))
  screen_z_values <- screen_z_values[
    screen_z_values > cfg$z_bounds[1L] &
      screen_z_values < cfg$z_bounds[2L]
  ]
  mechanism <- network$mechanism
  threshold_for <- function(value) {
    if (length(value) == 1L) value else unname(value[mechanism])
  }
  raw_threshold <- threshold_for(cfg$design_raw_smin_min)
  scaled_threshold <- threshold_for(cfg$design_scaled_smin_min)
  correlation_threshold <- threshold_for(
    cfg$design_max_abs_correlation
  )
  if (
    any(!is.finite(c(
      raw_threshold,
      scaled_threshold,
      correlation_threshold
    )))
  ) {
    stop("Missing identification threshold for: ", mechanism)
  }
  report_index <- vapply(z_values, function(z0) {
    which.min(abs(screen_z_values - z0))
  }, integer(1L))
  if (any(abs(screen_z_values[report_index] - z_values) > 1e-12)) {
    stop("The design screen omitted a requested z_0 value.")
  }

  for (attempt in seq_len(cfg$design_attempts)) {
    X <- make_X_candidate(network, cfg)
    gram_eigenvalues <- eigen(
      crossprod(X) / nrow(X),
      symmetric = TRUE,
      only.values = TRUE
    )$values
    gram_eigen_min <- min(gram_eigenvalues)
    gram_condition <- max(gram_eigenvalues) /
      max(gram_eigen_min, .Machine$double.eps)
    if (is.finite(gram_condition) && is.finite(gram_eigen_min)) {
      best_gram_condition <- min(best_gram_condition, gram_condition)
      best_gram_eigen_min <- max(
        best_gram_eigen_min,
        gram_eigen_min
      )
    }
    if (
      !is.finite(gram_condition) ||
        !is.finite(gram_eigen_min) ||
        gram_condition > cfg$x_condition_max ||
        gram_eigen_min < cfg$x_gram_eigen_min
    ) {
      gram_rejections <- gram_rejections + 1L
      next
    }

    screen_diagnostics <- lapply(
      screen_z_values,
      function(z0) design_diagnostic(X, network, z0, cfg)
    )
    instrument_score_by_z <- vapply(
      screen_diagnostics,
      function(one) one$raw_smin * one$scaled_smin,
      numeric(1L)
    )
    score <- min(instrument_score_by_z)
    if (score > best_score) {
      best <- list(
        X = X,
        diagnostics = screen_diagnostics,
        gram_condition = gram_condition,
        gram_eigen_min = gram_eigen_min,
        attempts = attempt
      )
      best_score <- score
    }

    pass_by_z <- vapply(
      screen_diagnostics,
      function(one) {
        one$raw_smin >= raw_threshold &&
          one$scaled_smin >= scaled_threshold &&
          abs(one$correlation) <= correlation_threshold
      },
      logical(1L)
    )
    if (all(pass_by_z)) {
      requested_diagnostics <- screen_diagnostics[report_index]
      return(list(
        X = X,
        diagnostics = requested_diagnostics,
        screen_diagnostics = screen_diagnostics,
        z_values = z_values,
        screen_z_values = screen_z_values,
        gram_condition = gram_condition,
        gram_eigen_min = gram_eigen_min,
        gram_rejections = gram_rejections,
        attempts = attempt
      ))
    }
  }

  if (is.null(best)) {
    stop(sprintf(
      paste0(
        "No X design passed the Q_X eigenvalue/condition screen after %d ",
        "candidate draws. Best minimum eigenvalue=%.4g (required >= %.4g); ",
        "best condition number=%.4g (required <= %.4g)."
      ),
      cfg$design_attempts,
      best_gram_eigen_min,
      cfg$x_gram_eigen_min,
      best_gram_condition,
      cfg$x_condition_max
    ))
  }

  best_raw <- min(vapply(
    best$diagnostics, `[[`, numeric(1L), "raw_smin"
  ))
  best_scaled <- min(vapply(
    best$diagnostics, `[[`, numeric(1L), "scaled_smin"
  ))
  best_correlation <- max(abs(vapply(
    best$diagnostics, `[[`, numeric(1L), "correlation"
  )))
  stop(sprintf(
    paste0(
      "No X design passed all z_0 instrument screens. ",
      "Best worst-case raw smin=%.4g, scaled smin=%.4g, ",
      "maximum absolute correlation=%.4f."
    ),
    best_raw,
    best_scaled,
    best_correlation
  ))
}

peer_interpolated_quantile <- function(values, neighbors, z) {
  vapply(
    neighbors,
    function(index) {
      d <- length(index)
      ordered <- sort.int(values[index], method = "quick")
      if (d == 1L) return(ordered[1L])
      ell <- 1 + (d - 1) * z
      lower <- max(1L, min(d - 1L, floor(ell)))
      alpha <- ell - lower
      (1 - alpha) * ordered[lower] + alpha * ordered[lower + 1L]
    },
    numeric(1L)
  )
}

partial_secant_matrix_diagnostic <- function(
    X, Z_peer, R_peer, cfg = CFG) {
  # Raw version of the exact matrix in Assumption 3:
  # n^{-1} Z_P^T P_X^perp R_n.  The scaled version removes the RMS units of
  # the two residualized column blocks and is reported only as a geometric
  # collinearity diagnostic; the raw singular value is the theorem-relevant
  # finite-sample analogue.
  n <- nrow(X)
  projection_Z <- safe_solve(
    crossprod(X),
    crossprod(X, Z_peer),
    ridge = 0
  )
  projection_R <- safe_solve(
    crossprod(X),
    crossprod(X, R_peer),
    ridge = 0
  )
  residual_Z <- Z_peer - X %*% projection_Z
  residual_R <- R_peer - X %*% projection_R
  # This is written in the theorem's exact orientation Z_P^T P_X^perp R.
  secant_matrix <- crossprod(Z_peer, residual_R) / n
  singular_values <- svd(secant_matrix, nu = 0, nv = 0)$d

  Z_rms <- sqrt(colMeans(residual_Z^2))
  R_rms <- sqrt(colMeans(residual_R^2))
  scaled_matrix <- crossprod(
    sweep(residual_Z, 2L, pmax(Z_rms, 1e-12), "/"),
    sweep(residual_R, 2L, pmax(R_rms, 1e-12), "/")
  ) / n
  scaled_singular_values <- svd(
    scaled_matrix,
    nu = 0,
    nv = 0
  )$d

  list(
    raw_smin = min(singular_values),
    scaled_smin = min(scaled_singular_values),
    condition_number = max(singular_values) /
      max(min(singular_values), .Machine$double.eps),
    Z_rms_min = min(Z_rms),
    R_rms_min = min(R_rms)
  )
}

maximum_local_spacing_proxy <- function(
    pseudo_groups, z_bounds = CFG$z_bounds) {
  # Finite-sample proxy for Assumption 5(i), evaluated on the compact
  # quantile-index set rather than at the constantly extended tails.
  max(vapply(
    pseudo_groups,
    function(one_group) {
      degree <- one_group$degree
      if (degree <= 1L) return(0)
      interval_left <- (seq_len(degree - 1L) - 1) / (degree - 1)
      interval_right <- seq_len(degree - 1L) / (degree - 1)
      local_interval <- interval_right >= z_bounds[1L] &
        interval_left <= z_bounds[2L]
      gaps <- one_group$values[, 2:degree, drop = FALSE] -
        one_group$values[
          , seq_len(degree - 1L), drop = FALSE
        ]
      max(degree * gaps[, local_interval, drop = FALSE])
    },
    numeric(1L)
  ))
}

generate_innovation <- function(network, cfg = CFG) {
  n <- length(network$degree)
  error_scale <- rep(cfg$innovation_sd, n)
  innovation <- stats::rnorm(
    n = n,
    mean = 0,
    sd = cfg$innovation_sd
  )
  list(innovation = innovation, error_scale = error_scale)
}

generate_outcome <- function(
    X, network, innovation_draw = NULL, cfg = CFG) {
  if (is.null(innovation_draw)) {
    innovation_draw <- generate_innovation(network, cfg)
  }
  innovation <- innovation_draw$innovation
  error_scale <- innovation_draw$error_scale
  base <- as.numeric(X %*% cfg$beta) + innovation

  y <- base + cfg$lambda * as.numeric(
    stats::quantile(base, probs = cfg$z, type = 7)
  )
  converged <- FALSE
  distance <- Inf

  for (iteration in seq_len(cfg$fixed_point_max_iterations)) {
    peer_q <- peer_interpolated_quantile(
      y,
      network$neighbors,
      cfg$z
    )
    y_new <- base + cfg$lambda * peer_q
    distance <- max(abs(y_new - y))
    y <- y_new
    if (distance <= cfg$fixed_point_tolerance) {
      converged <- TRUE
      break
    }
  }
  if (!converged) {
    stop(sprintf("The DGP fixed point failed to converge; gap=%.4g.", distance))
  }

  list(
    y = y,
    innovation = innovation,
    error_scale = error_scale,
    iterations = iteration,
    final_gap = distance
  )
}

validate_generated_outcome <- function(
    outcome, X, network, cfg = CFG) {
  n <- nrow(X)
  if (
    length(outcome$y) != n ||
      length(outcome$innovation) != n ||
      any(!is.finite(outcome$y)) ||
      any(!is.finite(outcome$innovation))
  ) {
    stop(
      "Generated Y or its innovation is non-finite or has the wrong length.",
      call. = FALSE
    )
  }

  peer_q <- peer_interpolated_quantile(
    outcome$y,
    network$neighbors,
    cfg$z
  )
  fixed_point_rhs <- as.numeric(
    X %*% cfg$beta
  ) + outcome$innovation + cfg$lambda * peer_q
  equation_gap <- max(abs(outcome$y - fixed_point_rhs))
  numerical_tolerance <- max(
    10 * cfg$fixed_point_tolerance,
    100 * .Machine$double.eps *
      max(1, max(abs(outcome$y)), max(abs(fixed_point_rhs)))
  )
  if (!is.finite(equation_gap) || equation_gap > numerical_tolerance) {
    stop(sprintf(
      paste0(
        "Generated Y failed the fixed-point equation check: ",
        "gap=%.4g, tolerance=%.4g."
      ),
      equation_gap,
      numerical_tolerance
    ), call. = FALSE)
  }

  list(
    fixed_point_equation_gap = equation_gap,
    fixed_point_equation_tolerance = numerical_tolerance
  )
}

instrument_matrix <- function(X, fitted_q, fitted_dq) {
  Z <- cbind(X, fitted_q = fitted_q, fitted_dq = fitted_dq)
  rms <- sqrt(colMeans(Z^2))
  if (any(!is.finite(rms)) || any(rms < 1e-10)) {
    stop("Degenerate instrument column.")
  }
  list(Z = sweep(Z, 2L, rms, "/"), scale = rms)
}

profile_linear_parameters <- function(
    y, X, outcome_q, fitted_q, fitted_dq, W = NULL, cfg = CFG) {
  n <- length(y)
  instruments <- instrument_matrix(X, fitted_q, fitted_dq)
  Z <- instruments$Z
  D <- cbind(X, peer_q = outcome_q)
  A <- crossprod(Z, D) / n
  b <- as.numeric(crossprod(Z, y) / n)
  if (is.null(W)) W <- diag(ncol(Z))

  normal_matrix <- crossprod(A, W %*% A)
  normal_rhs <- crossprod(A, W %*% b)
  coefficient <- as.numeric(safe_solve(normal_matrix, normal_rhs))

  # Enforce a fixed, truth-independent compact parameter space for lambda.
  lambda_hat <- clamp(
    coefficient[ncol(D)],
    cfg$lambda_bounds[1L],
    cfg$lambda_bounds[2L]
  )
  if (abs(lambda_hat - coefficient[ncol(D)]) > 0) {
    A_beta <- A[, seq_len(ncol(X)), drop = FALSE]
    rhs_beta <- b - A[, ncol(D)] * lambda_hat
    beta_hat <- as.numeric(safe_solve(
      crossprod(A_beta, W %*% A_beta),
      crossprod(A_beta, W %*% rhs_beta)
    ))
    coefficient <- c(beta_hat, lambda_hat)
  }

  residual <- y - as.numeric(D %*% coefficient)
  moment <- colMeans(Z * residual)
  objective <- as.numeric(crossprod(moment, W %*% moment))

  list(
    coefficient = coefficient,
    residual = residual,
    moment = moment,
    objective = objective,
    Z = Z,
    instrument_scale = instruments$scale
  )
}

positive_definite_inverse <- function(S, ridge = CFG$ridge) {
  # Matrix products involving a sparse adjacency matrix may return an S4
  # Matrix object.  Base t() and eigen() below should receive a dense matrix.
  S <- as.matrix(S)
  S <- (S + t(S)) / 2
  decomposition <- eigen(S, symmetric = TRUE)
  largest <- max(decomposition$values, 1e-8)
  floor_value <- max(ridge, 1e-6 * largest)
  values <- pmax(decomposition$values, floor_value)
  decomposition$vectors %*% diag(1 / values) %*% t(decomposition$vectors)
}

second_step_weight <- function(profile, A, degree, cfg = CFG) {
  psi <- profile$Z * profile$residual
  S <- crossprod(psi) / nrow(psi)

  if (identical(cfg$weighting, "network")) {
    inv_sqrt_degree <- 1 / sqrt(pmax(degree, 1))
    normalized_A <- Matrix::Diagonal(x = inv_sqrt_degree) %*%
      A %*%
      Matrix::Diagonal(x = inv_sqrt_degree)
    neighbor_psi <- as.matrix(normalized_A %*% psi)
    neighbor_term <- as.matrix(
      crossprod(psi, neighbor_psi) / nrow(psi)
    )
    S <- S + (neighbor_term + t(neighbor_term)) / 2
  } else if (!identical(cfg$weighting, "iid")) {
    stop("CFG$weighting must be 'network' or 'iid'.")
  }

  positive_definite_inverse(S, cfg$ridge)
}

theorem_inference <- function(
    y, X, outcome_smooth, fitted_smooth, estimate, network,
    cfg = CFG) {
  # Plug-in implementation of Theorem (Asymptotic normality):
  #
  #   sqrt(n) (theta_hat - theta_0) -> N(0, V),
  #
  # where V has the GMM sandwich form.  The paper's observation-specific
  # moment is
  #
  #   g_i(theta) = M_i(theta) e_i(theta),
  #   M(theta) = [X, lambda * fitted_q, lambda * fitted_dq].
  #
  # There are p + 2 moments and p + 2 parameters in this simulation.  The
  # general sandwich is therefore algebraically equal to
  # G^{-1} Sigma G^{-T}; the general expression is retained below so that the
  # code mirrors the theorem and remains transparent.  The estimation profile
  # normalizes moment columns for numerical stability, whereas inference uses
  # the paper's unnormalized M(theta); nonsingular moment rescaling does not
  # change just-identified sandwich inference.
  n <- length(y)
  p <- ncol(X)
  parameter_names <- c(paste0("beta", seq_len(p)), "lambda", "z")
  if (length(estimate) != p + 2L) {
    stop("The estimate dimension does not match p + 2.")
  }
  estimate <- stats::setNames(as.numeric(estimate), parameter_names)
  beta_hat <- estimate[seq_len(p)]
  lambda_hat <- unname(estimate["lambda"])

  M <- cbind(
    X,
    fitted_q = lambda_hat * fitted_smooth$q,
    fitted_dq = lambda_hat * fitted_smooth$dq
  )
  residual <- y -
    as.numeric(X %*% beta_hat) -
    lambda_hat * outcome_smooth$q
  psi <- M * residual
  moment <- colMeans(psi)

  # Xi and Sigma play distinct conceptual roles.  For the efficient iid
  # implementation they have the same probability limit, but Sigma_hat below
  # is explicitly constructed as an estimator of the score variance.
  psi_centered <- sweep(psi, 2L, colMeans(psi), "-")
  if (identical(cfg$score_covariance, "iid_robust")) {
    Sigma_hat <- as.matrix(crossprod(psi_centered) / n)
  } else if (identical(cfg$score_covariance, "homoskedastic")) {
    degrees_of_freedom <- max(1, n - length(estimate))
    sigma2_hat <- sum((residual - mean(residual))^2) /
      degrees_of_freedom
    Sigma_hat <- sigma2_hat * as.matrix(crossprod(M) / n)
  } else {
    stop(
      "CFG$score_covariance must be 'iid_robust' or 'homoskedastic'."
    )
  }
  Sigma_hat <- (Sigma_hat + t(Sigma_hat)) / 2
  # The model uses iid innovations.  A graph-HAC estimator would require a
  # separate bandwidth theory and is therefore not inserted ad hoc here.
  if (missing(network) || is.null(network$A)) {
    stop("Network information is required for inference diagnostics.")
  }
  Xi_inverse_hat <- positive_definite_inverse(Sigma_hat, cfg$ridge)

  # Analytic sample Jacobian of the feasible smoothed moment.  The two terms
  # in each peer-effect column respectively account for the derivative of the
  # instrument and the derivative of the structural residual.
  G_beta <- -crossprod(M, X) / n

  dM_dlambda <- matrix(0, nrow = n, ncol = p + 2L)
  dM_dlambda[, p + 1L] <- fitted_smooth$q
  dM_dlambda[, p + 2L] <- fitted_smooth$dq
  G_lambda <- colMeans(
    sweep(dM_dlambda, 1L, residual, "*") -
      sweep(M, 1L, outcome_smooth$q, "*")
  )

  dM_dz <- matrix(0, nrow = n, ncol = p + 2L)
  dM_dz[, p + 1L] <- lambda_hat * fitted_smooth$dq
  dM_dz[, p + 2L] <- lambda_hat * fitted_smooth$ddq
  G_z <- colMeans(
    sweep(dM_dz, 1L, residual, "*") -
      sweep(M, 1L, lambda_hat * outcome_smooth$dq, "*")
  )

  G_hat <- cbind(G_beta, G_lambda, G_z)
  rownames(G_hat) <- colnames(M)
  colnames(G_hat) <- parameter_names
  jacobian_singular_values <- svd(G_hat, nu = 0, nv = 0)$d
  if (
    any(!is.finite(jacobian_singular_values)) ||
      min(jacobian_singular_values) <= 0
  ) {
    stop("The plug-in inference Jacobian is singular or non-finite.")
  }

  bread <- crossprod(G_hat, Xi_inverse_hat %*% G_hat)
  bread_inverse <- tryCatch(
    solve(bread),
    error = function(err) {
      stop(
        "The plug-in GMM bread matrix could not be inverted: ",
        conditionMessage(err)
      )
    }
  )
  V_hat <- bread_inverse %*%
    crossprod(
      G_hat,
      Xi_inverse_hat %*% Sigma_hat %*% Xi_inverse_hat %*% G_hat
    ) %*%
    bread_inverse
  V_hat <- (V_hat + t(V_hat)) / 2

  # Exact-identification identity used only as a numerical diagnostic.
  G_inverse <- tryCatch(
    solve(G_hat),
    error = function(err) {
      stop(
        "The exactly identified inference Jacobian could not be inverted: ",
        conditionMessage(err)
      )
    }
  )
  V_exact <- G_inverse %*% Sigma_hat %*% t(G_inverse)
  V_exact <- (V_exact + t(V_exact)) / 2
  sandwich_identity_gap <- max(abs(V_hat - V_exact)) /
    max(1, max(abs(V_exact)))

  covariance_hat <- V_hat / n
  diagonal <- diag(covariance_hat)
  if (any(!is.finite(diagonal)) || any(diagonal <= 0)) {
    stop("The plug-in asymptotic covariance has a non-positive diagonal.")
  }
  standard_error <- sqrt(diagonal)
  names(standard_error) <- parameter_names

  alpha <- 1 - cfg$confidence_level
  critical_value <- stats::qnorm(1 - alpha / 2)
  ci_lower <- estimate - critical_value * standard_error
  ci_upper <- estimate + critical_value * standard_error

  score_singular_values <- svd(Sigma_hat, nu = 0, nv = 0)$d
  list(
    standard_error = standard_error,
    ci_lower = ci_lower,
    ci_upper = ci_upper,
    critical_value = critical_value,
    covariance = covariance_hat,
    asymptotic_V = V_hat,
    moment = moment,
    jacobian = G_hat,
    jacobian_smin = min(jacobian_singular_values),
    jacobian_condition = max(jacobian_singular_values) /
      min(jacobian_singular_values),
    score_cov_smin = min(score_singular_values),
    score_cov_condition = max(score_singular_values) /
      max(min(score_singular_values), .Machine$double.eps),
    sandwich_identity_gap = sandwich_identity_gap
  )
}

formal_numerical_admissibility <- function(fit, n, cfg = CFG) {
  if (
    !is.list(fit) ||
      is.null(fit$inference) ||
      length(n) != 1L ||
      !is.finite(n) ||
      n <= 0
  ) {
    stop("Invalid input to the formal numerical-admissibility check.")
  }

  theoretical_se <- fit$inference$standard_error
  jacobian_condition <- fit$inference$jacobian_condition
  root_n_se <- sqrt(n) * theoretical_se
  se_pass <-
    length(root_n_se) > 0L &&
      all(is.finite(root_n_se)) &&
      all(root_n_se > 0) &&
      max(root_n_se) <= cfg$formal_root_n_se_max
  jacobian_pass <-
    length(jacobian_condition) == 1L &&
      is.finite(jacobian_condition) &&
      jacobian_condition > 0 &&
      jacobian_condition <= cfg$formal_jacobian_condition_max

  largest_index <- if (length(root_n_se) > 0L) {
    which.max(replace(root_n_se, !is.finite(root_n_se), Inf))[1L]
  } else {
    NA_integer_
  }
  largest_parameter <- if (
    is.finite(largest_index) &&
      length(names(root_n_se)) == length(root_n_se) &&
      !is.na(names(root_n_se)[largest_index]) &&
      nzchar(names(root_n_se)[largest_index])
  ) {
    names(root_n_se)[largest_index]
  } else if (is.finite(largest_index)) {
    paste0("parameter_", largest_index)
  } else {
    NA_character_
  }

  list(
    passed = isTRUE(se_pass) && isTRUE(jacobian_pass),
    se_pass = isTRUE(se_pass),
    jacobian_pass = isTRUE(jacobian_pass),
    root_n_se = root_n_se,
    max_root_n_se = if (length(root_n_se) > 0L) {
      max(replace(root_n_se, !is.finite(root_n_se), Inf))
    } else {
      Inf
    },
    max_root_n_se_parameter = largest_parameter,
    jacobian_condition = as.numeric(jacobian_condition),
    root_n_se_threshold = cfg$formal_root_n_se_max,
    jacobian_condition_threshold =
      cfg$formal_jacobian_condition_max
  )
}

evaluate_profile_grid <- function(
    y, X, outcome_grid, fitted_grid, W = NULL, cfg = CFG) {
  grid_size <- ncol(outcome_grid$q)
  profiles <- vector("list", grid_size)
  objective <- numeric(grid_size)
  for (k in seq_len(grid_size)) {
    profiles[[k]] <- profile_linear_parameters(
      y = y,
      X = X,
      outcome_q = outcome_grid$q[, k],
      fitted_q = fitted_grid$q[, k],
      fitted_dq = fitted_grid$dq[, k],
      W = W,
      cfg = cfg
    )
    objective[k] <- profiles[[k]]$objective
  }
  list(profiles = profiles, objective = objective)
}

profile_local_minimum_indices <- function(objective) {
  objective <- as.numeric(objective)
  n_grid <- length(objective)
  if (n_grid < 2L || any(!is.finite(objective))) {
    stop("A finite profile with at least two grid points is required.")
  }

  left <- c(Inf, objective[-n_grid])
  right <- c(objective[-1L], Inf)
  raw_indices <- which(objective <= left & objective <= right)
  if (length(raw_indices) == 0L) {
    raw_indices <- which.min(objective)
  }

  # A flat stretch is one valley, not many starts.  Keep the point closest
  # to the middle of each contiguous stretch among points attaining its
  # smallest objective up to machine-level tolerance.
  run_id <- cumsum(c(TRUE, diff(raw_indices) > 1L))
  runs <- split(raw_indices, run_id)
  scale_objective <- max(1, max(abs(objective)))
  plateau_tolerance <- 32 * .Machine$double.eps * scale_objective
  representatives <- vapply(runs, function(one_run) {
    run_minimum <- min(objective[one_run])
    eligible <- one_run[
      objective[one_run] <= run_minimum + plateau_tolerance
    ]
    eligible[which.min(abs(eligible - mean(one_run)))]
  }, integer(1L))

  sort(unique(as.integer(representatives)))
}

select_separated_profile_minima <- function(
    local_indices,
    objective,
    z_grid,
    max_candidates,
    min_separation
) {
  local_indices <- as.integer(local_indices)
  if (
    length(local_indices) == 0L ||
      max_candidates < 1L ||
      min_separation < 0
  ) {
    stop("Invalid inputs for profile candidate selection.")
  }
  ordered <- local_indices[order(
    objective[local_indices],
    z_grid[local_indices],
    local_indices
  )]
  selected <- integer()
  for (one_index in ordered) {
    sufficiently_separated <- length(selected) == 0L ||
      all(
        abs(z_grid[one_index] - z_grid[selected]) >=
          min_separation - 1e-12
      )
    if (sufficiently_separated) {
      selected <- c(selected, one_index)
    }
    if (length(selected) >= max_candidates) break
  }
  if (length(selected) == 0L) selected <- ordered[1L]
  as.integer(selected)
}

profile_basin_bounds <- function(
    local_index,
    all_local_indices,
    objective,
    z_grid,
    z_bounds
) {
  if (
    length(objective) != length(z_grid) ||
      any(!is.finite(objective))
  ) {
    stop("The basin boundaries require a finite full profile.")
  }
  all_local_indices <- all_local_indices[
    order(z_grid[all_local_indices])
  ]
  position <- match(local_index, all_local_indices)
  if (is.na(position)) {
    stop("The requested candidate is not a profile local minimum.")
  }

  separating_peak <- function(left_minimum, right_minimum) {
    between <- seq.int(left_minimum, right_minimum)
    peak_value <- max(objective[between])
    scale_objective <- max(1, max(abs(objective[between])))
    peak_tolerance <- 32 * .Machine$double.eps * scale_objective
    peak_indices <- between[
      objective[between] >= peak_value - peak_tolerance
    ]
    target <- mean(z_grid[c(left_minimum, right_minimum)])
    peak_indices[which.min(abs(z_grid[peak_indices] - target))]
  }

  lower <- if (position == 1L) {
    z_bounds[1L]
  } else {
    left_peak <- separating_peak(
      all_local_indices[position - 1L],
      all_local_indices[position]
    )
    z_grid[left_peak]
  }
  upper <- if (position == length(all_local_indices)) {
    z_bounds[2L]
  } else {
    right_peak <- separating_peak(
      all_local_indices[position],
      all_local_indices[position + 1L]
    )
    z_grid[right_peak]
  }
  center <- z_grid[local_index]
  if (
    !is.finite(lower) ||
      !is.finite(upper) ||
      lower > center ||
      center > upper ||
      upper <= lower
  ) {
    stop("A profile basin has invalid bounds.")
  }
  c(lower = lower, upper = upper)
}

normalized_parameter_boundary_margin <- function(
    z,
    lambda,
    cfg = CFG
) {
  z_margin <- min(
    (z - cfg$z_bounds[1L]) / diff(cfg$z_bounds),
    (cfg$z_bounds[2L] - z) / diff(cfg$z_bounds)
  )
  lambda_margin <- min(
    (lambda - cfg$lambda_bounds[1L]) / diff(cfg$lambda_bounds),
    (cfg$lambda_bounds[2L] - lambda) / diff(cfg$lambda_bounds)
  )
  max(0, min(z_margin, lambda_margin))
}

refine_profile_basin <- function(
    profile_function,
    lower,
    upper,
    center,
    cfg = CFG
) {
  if (
    !is.finite(lower) ||
      !is.finite(upper) ||
      !is.finite(center) ||
      lower > center ||
      center > upper ||
      upper <= lower
  ) {
    stop("Invalid interval supplied to profile refinement.")
  }

  optimized_z <- NA_real_
  if (upper - lower > 1e-10) {
    # stats::optimize is a bounded derivative-free one-dimensional search.
    # It evaluates the doubly smoothed objective without requiring derivatives.
    optimized <- tryCatch(
      stats::optimize(
        function(z) profile_function(z)$objective,
        interval = c(lower, upper),
        tol = cfg$profile_optimizer_tolerance
      ),
      error = function(error) NULL
    )
    if (!is.null(optimized)) optimized_z <- optimized$minimum
  }

  evaluation_z <- unique(clamp(
    c(optimized_z, center, lower, upper),
    lower,
    upper
  ))
  evaluation_z <- evaluation_z[is.finite(evaluation_z)]
  evaluated <- lapply(evaluation_z, profile_function)
  objective <- vapply(
    evaluated,
    function(one) as.numeric(one$objective),
    numeric(1L)
  )
  if (length(objective) == 0L || any(!is.finite(objective))) {
    stop("Profile refinement produced a non-finite objective.")
  }
  best <- which.min(objective)
  list(
    z = evaluation_z[best],
    profile = evaluated[[best]],
    objective = objective[best]
  )
}

choose_profile_candidate <- function(candidates, cfg = CFG) {
  if (
    !is.data.frame(candidates) ||
      nrow(candidates) < 1L ||
      any(!is.finite(candidates$selection_score)) ||
      any(!is.finite(candidates$boundary_margin))
  ) {
    stop("Invalid global profile candidate table.")
  }
  best_score <- min(candidates$selection_score)
  tolerance <- cfg$profile_selection_abs_tolerance +
    cfg$profile_selection_rel_tolerance *
      max(abs(best_score), .Machine$double.eps)
  tied <- which(
    candidates$selection_score <= best_score + tolerance
  )
  largest_margin <- max(candidates$boundary_margin[tied])
  margin_tolerance <- 64 * .Machine$double.eps
  tied_by_margin <- tied[
    candidates$boundary_margin[tied] >=
      largest_margin - margin_tolerance
  ]
  selected <- tied_by_margin[
    which.min(candidates$candidate_rank[tied_by_margin])
  ]
  ordered_score <- sort(candidates$selection_score)
  second_best_score <- if (length(ordered_score) >= 2L) {
    ordered_score[2L]
  } else {
    NA_real_
  }
  alternative_score <- if (nrow(candidates) >= 2L) {
    min(candidates$selection_score[-selected])
  } else {
    NA_real_
  }

  list(
    selected_index = selected,
    best_score = best_score,
    second_best_score = second_best_score,
    alternative_score = alternative_score,
    score_gap = if (is.finite(second_best_score)) {
      second_best_score - best_score
    } else {
      NA_real_
    },
    selected_score_excess =
      candidates$selection_score[selected] - best_score,
    tolerance = tolerance,
    tie_count = length(tied),
    tied_indices = tied
  )
}

estimate_qsar <- function(y, X, network, cfg = CFG) {
  n <- length(y)
  # lm.fit has no intercept because X contains no constant column.
  first_stage <- stats::lm.fit(x = X, y = y)
  fitted <- as.numeric(X %*% first_stage$coefficients)

  outcome_groups <- make_sorted_peer_groups(y, network$neighbors)
  fitted_groups <- make_sorted_peer_groups(fitted, network$neighbors)
  z_grid <- seq(
    cfg$z_bounds[1L],
    cfg$z_bounds[2L],
    length.out = cfg$z_grid_size
  )
  mean_degree <- mean(network$degree)

  # The residual and instruments use Gaussian smoothing with h_i and tau_i.
  outcome_grid <- smooth_peer_quantile_grid(
    outcome_groups, z_grid, n, mean_degree, cfg,
    bandwidth_fun = h_value
  )
  fitted_grid <- smooth_peer_quantile_grid(
    fitted_groups, z_grid, n, mean_degree, cfg
  )

  # A single pre-specified identity weight is used for every candidate, so
  # candidate objectives are on exactly the same scale.  Multiplication by n
  # below gives the usual n*Q_n selection score without changing its ranking.
  selection_W <- diag(ncol(X) + 2L)
  selection_pass <- evaluate_profile_grid(
    y,
    X,
    outcome_grid,
    fitted_grid,
    W = selection_W,
    cfg = cfg
  )
  all_local_indices <- profile_local_minimum_indices(
    selection_pass$objective
  )
  candidate_grid_indices <- select_separated_profile_minima(
    local_indices = all_local_indices,
    objective = selection_pass$objective,
    z_grid = z_grid,
    max_candidates = cfg$profile_max_candidates,
    min_separation = cfg$profile_min_separation
  )

  subset_grid <- function(one_grid, index) {
    list(
      q = one_grid$q[, index, drop = FALSE],
      dq = one_grid$dq[, index, drop = FALSE],
      ddq = if (!is.null(one_grid$ddq)) {
        one_grid$ddq[, index, drop = FALSE]
      } else {
        matrix(0, nrow = nrow(one_grid$q), ncol = length(index))
      }
    )
  }

  direct_profile <- function(z, W) {
    outcome <- smooth_peer_quantile(
      outcome_groups, z, n, mean_degree, cfg,
      bandwidth_fun = h_value
    )
    fitted_one <- smooth_peer_quantile(
      fitted_groups, z, n, mean_degree, cfg
    )
    profile <- profile_linear_parameters(
      y, X, outcome$q, fitted_one$q, fitted_one$dq, W, cfg
    )
    profile$outcome_smooth <- outcome
    profile$fitted_smooth <- fitted_one
    profile
  }

  candidate_refinements <- vector(
    "list",
    length(candidate_grid_indices)
  )
  candidate_rows <- vector("list", length(candidate_grid_indices))
  for (candidate_rank in seq_along(candidate_grid_indices)) {
    grid_index <- candidate_grid_indices[candidate_rank]
    basin <- profile_basin_bounds(
      local_index = grid_index,
      all_local_indices = all_local_indices,
      objective = selection_pass$objective,
      z_grid = z_grid,
      z_bounds = cfg$z_bounds
    )
    refined <- refine_profile_basin(
      profile_function = function(z) direct_profile(z, selection_W),
      lower = basin["lower"],
      upper = basin["upper"],
      center = z_grid[grid_index],
      cfg = cfg
    )
    candidate_refinements[[candidate_rank]] <- refined
    lambda_candidate <- unname(tail(
      refined$profile$coefficient,
      1L
    ))
    candidate_rows[[candidate_rank]] <- data.frame(
      candidate_rank = candidate_rank,
      local_minimum_grid_index = grid_index,
      local_minimum_grid_z = z_grid[grid_index],
      local_minimum_grid_objective =
        selection_pass$objective[grid_index],
      basin_lower = unname(basin["lower"]),
      basin_upper = unname(basin["upper"]),
      refined_z = refined$z,
      refined_lambda = lambda_candidate,
      selection_objective = refined$objective,
      selection_score = n * refined$objective,
      boundary_margin = normalized_parameter_boundary_margin(
        z = refined$z,
        lambda = lambda_candidate,
        cfg = cfg
      )
    )
  }
  candidates <- do.call(rbind, candidate_rows)
  selection <- choose_profile_candidate(candidates, cfg)
  candidates$within_selection_tolerance <- seq_len(nrow(candidates)) %in%
    selection$tied_indices
  candidates$selected <- FALSE
  candidates$selected[selection$selected_index] <- TRUE

  selected_candidate <- candidates[selection$selected_index, ]
  selected_basin_lower <- selected_candidate$basin_lower
  selected_basin_upper <- selected_candidate$basin_upper
  selected_basin_index <- which(
    z_grid >= selected_basin_lower - 1e-12 &
      z_grid <= selected_basin_upper + 1e-12
  )
  if (length(selected_basin_index) == 0L) {
    stop("The selected profile basin contains no grid point.")
  }
  outcome_basin_grid <- subset_grid(
    outcome_grid,
    selected_basin_index
  )
  fitted_basin_grid <- subset_grid(
    fitted_grid,
    selected_basin_index
  )

  # Iterated GMM begins only after the common global criterion has selected a
  # basin.  Changing W can refine the selected root but cannot retrospectively
  # change which global-profile candidate was chosen.  The selected
  # candidate is already the complete identity-weight first iteration, so it
  # is reused rather than recomputed.
  selected_refinement <- candidate_refinements[[
    selection$selected_index
  ]]
  W <- selection_W
  final_profile <- selected_refinement$profile
  estimate <- c(
    beta1 = final_profile$coefficient[1L],
    beta2 = final_profile$coefficient[2L],
    lambda = final_profile$coefficient[3L],
    z = selected_refinement$z
  )
  previous_estimate <- estimate
  best_index <- selected_candidate$local_minimum_grid_index
  gmm_iterations <- 1L

  if (cfg$gmm_max_iterations > 1L) {
    W <- second_step_weight(
      final_profile,
      network$A,
      network$degree,
      cfg
    )
    for (gmm_iteration in seq.int(2L, cfg$gmm_max_iterations)) {
      gmm_iterations <- gmm_iteration
      basin_pass <- evaluate_profile_grid(
        y,
        X,
        outcome_basin_grid,
        fitted_basin_grid,
        W = W,
        cfg = cfg
      )
      basin_best_position <- which.min(basin_pass$objective)
      best_index <- selected_basin_index[basin_best_position]

      refinement_lower <- if (basin_best_position == 1L) {
        selected_basin_lower
      } else {
        z_grid[selected_basin_index[basin_best_position - 1L]]
      }
      refinement_upper <- if (
        basin_best_position == length(selected_basin_index)
      ) {
        selected_basin_upper
      } else {
        z_grid[selected_basin_index[basin_best_position + 1L]]
      }

      refined <- refine_profile_basin(
        profile_function = function(z) direct_profile(z, W),
        lower = refinement_lower,
        upper = refinement_upper,
        center = z_grid[best_index],
        cfg = cfg
      )
      refined_z <- refined$z
      final_profile <- refined$profile
      estimate <- c(
        beta1 = final_profile$coefficient[1L],
        beta2 = final_profile$coefficient[2L],
        lambda = final_profile$coefficient[3L],
        z = refined_z
      )

      if (
        max(abs(estimate - previous_estimate)) <=
          cfg$gmm_parameter_tolerance
      ) {
        break
      }
      previous_estimate <- estimate
      if (gmm_iteration < cfg$gmm_max_iterations) {
        W <- second_step_weight(
          final_profile,
          network$A,
          network$degree,
          cfg
        )
      }
    }
  }

  inference <- theorem_inference(
    y = y,
    X = X,
    outcome_smooth = final_profile$outcome_smooth,
    fitted_smooth = final_profile$fitted_smooth,
    estimate = estimate,
    network = network,
    cfg = cfg
  )

  list(
    estimate = estimate,
    inference = inference,
    objective = final_profile$objective,
    selected_grid_z = z_grid[best_index],
    global_profile_grid_z = z_grid[
      which.min(selection_pass$objective)
    ],
    profile_local_minimum_count = length(all_local_indices),
    profile_candidate_count = nrow(candidates),
    selected_candidate_rank = selected_candidate$candidate_rank,
    selected_candidate_grid_z =
      selected_candidate$local_minimum_grid_z,
    selected_candidate_refined_z = selected_candidate$refined_z,
    selected_basin_lower = selected_basin_lower,
    selected_basin_upper = selected_basin_upper,
    selected_basin_hit = (
      abs(estimate["z"] - selected_basin_lower) <
        cfg$profile_basin_hit_tolerance ||
        abs(estimate["z"] - selected_basin_upper) <
          cfg$profile_basin_hit_tolerance
    ),
    selection_objective = selected_candidate$selection_objective,
    selection_score = selected_candidate$selection_score,
    selection_best_score = selection$best_score,
    selection_second_best_score = selection$second_best_score,
    selection_alternative_score = selection$alternative_score,
    selection_score_gap = selection$score_gap,
    selection_selected_score_excess =
      selection$selected_score_excess,
    selection_tolerance = selection$tolerance,
    selection_tie_count = selection$tie_count,
    gmm_iterations = gmm_iterations,
    boundary_hit = (
      abs(estimate["z"] - cfg$z_bounds[1L]) < 1e-5 ||
        abs(estimate["z"] - cfg$z_bounds[2L]) < 1e-5 ||
        abs(estimate["lambda"] - cfg$lambda_bounds[1L]) < 1e-8 ||
        abs(estimate["lambda"] - cfg$lambda_bounds[2L]) < 1e-8
    ),
    profile_z = z_grid,
    profile_objective = selection_pass$objective,
    profile_score = n * selection_pass$objective,
    profile_is_local_minimum =
      seq_along(z_grid) %in% all_local_indices,
    profile_is_candidate_minimum =
      seq_along(z_grid) %in% candidate_grid_indices,
    profile_in_selected_basin = (
      z_grid >= selected_basin_lower - 1e-12 &
        z_grid <= selected_basin_upper + 1e-12
    ),
    profile_candidates = candidates,
    first_stage_r2 = 1 - sum((y - fitted)^2) / sum(y^2),
    outcome_groups = outcome_groups,
    fitted_groups = fitted_groups,
    W = W
  )
}

jacobian_matrix_diagnostic <- function(J) {
  if (
    !is.matrix(J) ||
      any(!is.finite(J)) ||
      nrow(J) == 0L ||
      ncol(J) == 0L
  ) {
    stop("The Jacobian diagnostic received an invalid matrix.")
  }
  singular_values <- svd(J, nu = 0, nv = 0)$d
  column_norm <- sqrt(colSums(J^2))
  J_scaled <- sweep(J, 2L, pmax(column_norm, 1e-12), "/")
  scaled_singular_values <- svd(J_scaled, nu = 0, nv = 0)$d

  list(
    smin = min(singular_values),
    scaled_smin = min(scaled_singular_values),
    condition_number = max(singular_values) /
      max(min(singular_values), .Machine$double.eps)
  )
}

sample_jacobian_diagnostic <- function(
    y, X, network, cfg = CFG, return_matrix = FALSE,
    outcome_groups = NULL) {
  n <- length(y)
  fitted <- as.numeric(X %*% stats::lm.fit(x = X, y = y)$coefficients)
  if (is.null(outcome_groups)) {
    outcome_groups <- make_sorted_peer_groups(y, network$neighbors)
  }
  fitted_groups <- make_sorted_peer_groups(fitted, network$neighbors)
  mean_degree <- mean(network$degree)

  moment_at <- function(beta, lambda, z) {
    outcome <- interpolated_peer_quantile(
      outcome_groups, z, n
    )
    fitted_one <- smooth_peer_quantile(
      fitted_groups, z, n, mean_degree, cfg
    )
    Z <- instrument_matrix(X, fitted_one$q, fitted_one$dq)$Z
    residual <- y - as.numeric(X %*% beta) - lambda * outcome$q
    colMeans(Z * residual)
  }

  z_step <- cfg$jacobian_z_step
  base_outcome <- interpolated_peer_quantile(
    outcome_groups, cfg$z, n
  )
  base_fitted <- smooth_peer_quantile(
    fitted_groups, cfg$z, n, mean_degree, cfg
  )
  Z0 <- instrument_matrix(X, base_fitted$q, base_fitted$dq)$Z
  J_beta <- -crossprod(Z0, X) / n
  J_lambda <- -as.numeric(crossprod(Z0, base_outcome$q) / n)
  J_z <- (
    moment_at(cfg$beta, cfg$lambda, cfg$z + z_step) -
      moment_at(cfg$beta, cfg$lambda, cfg$z - z_step)
  ) / (2 * z_step)
  J <- cbind(J_beta, J_lambda, J_z)
  diagnostic <- jacobian_matrix_diagnostic(J)
  if (isTRUE(return_matrix)) diagnostic$jacobian <- J
  diagnostic
}

independent_pilot_identification_screen <- function(
    X, network, z_values, cfg = CFG) {
  B <- as.integer(cfg$pilot_B)
  z_values <- as.numeric(z_values)
  n <- nrow(X)
  parameter_count <- ncol(X) + 2L
  secant_z_offsets <- sort(unique(as.numeric(
    cfg$pilot_secant_z_offsets
  )))
  secant_z_offsets <- secant_z_offsets[
    abs(secant_z_offsets) > 1e-12
  ]
  candidate_z_by_truth <- lapply(z_values, function(z0) {
    candidate_z <- z0 + secant_z_offsets
    candidate_z[
      candidate_z > cfg$z_bounds[1L] &
        candidate_z < cfg$z_bounds[2L]
    ]
  })
  if (any(lengths(candidate_z_by_truth) < 2L)) {
    stop(
      paste0(
        "Each z_0 requires at least two nonzero in-bounds pilot ",
        "secant offsets."
      )
    )
  }
  candidate_lambda <- sort(unique(
    cfg$lambda + as.numeric(cfg$pilot_secant_lambda_offsets)
  ))
  candidate_lambda <- candidate_lambda[
    candidate_lambda > cfg$lambda_bounds[1L] &
      candidate_lambda < cfg$lambda_bounds[2L]
  ]
  if (length(candidate_lambda) < 2L) {
    stop(
      "At least two in-bounds pilot lambda values are required."
    )
  }

  jacobian_sums <- lapply(
    z_values,
    function(z0) matrix(
      0,
      nrow = parameter_count,
      ncol = parameter_count
    )
  )
  # For each true z_0, column 1 is Y_-(z_0) and the remaining columns are
  # Y_-(z) for the local candidate levels.  The nonlinear peer-quantile map
  # is applied to every pilot equilibrium before averaging across pilots:
  #
  #   mu_hat_B(z) = B^{-1} sum_b Y_-^{(b)}(z).
  #
  # Conditional on the fixed A and X, this is a direct Monte Carlo estimator
  # of mu_n(z)=E{Y_-(z)|A,X}; it is not Y_- evaluated at E(epsilon)=0.
  mu_sums <- lapply(seq_along(z_values), function(z_index) {
    matrix(
      0,
      nrow = n,
      ncol = 1L + length(candidate_z_by_truth[[z_index]])
    )
  })
  mu_square_sums <- lapply(mu_sums, function(one) one)
  fixed_point_iterations <- numeric(B * length(z_values))
  fixed_point_equation_gaps <- numeric(B * length(z_values))
  diagnostic_index <- 0L

  # Each pilot innovation is iid N(0, sigma^2 I_n).  Within one pilot draw,
  # the same innovation is reused across z_0, matching the formal block.
  # None of these innovations is reused for the formal Monte Carlo sample.
  for (pilot_index in seq_len(B)) {
    pilot_innovation <- generate_innovation(network, cfg)
    for (z_index in seq_along(z_values)) {
      scenario_cfg <- cfg
      scenario_cfg$z <- z_values[z_index]
      pilot_outcome <- generate_outcome(
        X = X,
        network = network,
        innovation_draw = pilot_innovation,
        cfg = scenario_cfg
      )
      pilot_validation <- validate_generated_outcome(
        outcome = pilot_outcome,
        X = X,
        network = network,
        cfg = scenario_cfg
      )
      pilot_groups <- make_sorted_peer_groups(
        pilot_outcome$y,
        network$neighbors
      )
      evaluation_z <- c(
        z_values[z_index],
        candidate_z_by_truth[[z_index]]
      )
      pilot_peer_quantiles <- interpolated_peer_quantile_grid(
        pilot_groups,
        evaluation_z,
        n
      )$q
      mu_sums[[z_index]] <- mu_sums[[z_index]] +
        pilot_peer_quantiles
      mu_square_sums[[z_index]] <- mu_square_sums[[z_index]] +
        pilot_peer_quantiles^2

      pilot_jacobian <- sample_jacobian_diagnostic(
        y = pilot_outcome$y,
        X = X,
        network = network,
        cfg = scenario_cfg,
        return_matrix = TRUE,
        outcome_groups = pilot_groups
      )
      jacobian_sums[[z_index]] <- jacobian_sums[[z_index]] +
        pilot_jacobian$jacobian
      diagnostic_index <- diagnostic_index + 1L
      fixed_point_iterations[diagnostic_index] <-
        pilot_outcome$iterations
      fixed_point_equation_gaps[diagnostic_index] <-
        pilot_validation$fixed_point_equation_gap
    }
  }

  averaged_jacobians <- lapply(jacobian_sums, function(J) J / B)
  jacobian_diagnostics <- lapply(
    averaged_jacobians,
    jacobian_matrix_diagnostic
  )
  secant_diagnostics <- lapply(
    seq_along(z_values),
    function(z_index) {
      z0 <- z_values[z_index]
      candidate_z <- candidate_z_by_truth[[z_index]]
      mu_hat <- mu_sums[[z_index]] / B
      mu_at_truth <- mu_hat[, 1L]

      # beta^* = beta_0 + lambda_0 Q_X^{-1} n^{-1}X^T mu_n(z_0).
      # The factors n^{-1} cancel in the solve below.
      beta_star_hat <- cfg$beta + cfg$lambda * as.numeric(
        safe_solve(
          crossprod(X),
          crossprod(X, mu_at_truth),
          ridge = 0
        )
      )
      oracle_pseudo_response <- as.numeric(X %*% beta_star_hat)
      oracle_pseudo_groups <- make_sorted_peer_groups(
        oracle_pseudo_response,
        network$neighbors
      )
      mean_degree <- mean(network$degree)

      local_diagnostics <- list()
      local_index <- 0L
      for (candidate_index in seq_along(candidate_z)) {
        z <- candidate_z[candidate_index]
        mu_at_z <- mu_hat[, candidate_index + 1L]
        exact_secant <- (mu_at_z - mu_at_truth) / (z - z0)
        fitted_smooth <- smooth_peer_quantile(
          oracle_pseudo_groups,
          z,
          n,
          mean_degree,
          cfg
        )
        R_peer <- cbind(
          mu_at_z,
          cfg$lambda * exact_secant
        )

        for (lambda in candidate_lambda) {
          local_index <- local_index + 1L
          Z_peer <- cbind(
            lambda * fitted_smooth$q,
            lambda * fitted_smooth$dq
          )
          one <- partial_secant_matrix_diagnostic(
            X = X,
            Z_peer = Z_peer,
            R_peer = R_peer,
            cfg = cfg
          )
          local_diagnostics[[local_index]] <- c(
            list(lambda = lambda, z = z),
            one
          )
        }
      }

      mu_variance <- pmax(
        (
          mu_square_sums[[z_index]] -
            mu_sums[[z_index]]^2 / B
        ) / (B - 1L),
        0
      )
      mu_mean_mc_se <- sqrt(mu_variance / B)
      list(
        secant_raw_smin = min(vapply(
          local_diagnostics,
          `[[`,
          numeric(1L),
          "raw_smin"
        )),
        secant_scaled_smin = min(vapply(
          local_diagnostics,
          `[[`,
          numeric(1L),
          "scaled_smin"
        )),
        secant_condition_max = max(vapply(
          local_diagnostics,
          `[[`,
          numeric(1L),
          "condition_number"
        )),
        secant_Z_rms_min = min(vapply(
          local_diagnostics,
          `[[`,
          numeric(1L),
          "Z_rms_min"
        )),
        secant_R_rms_min = min(vapply(
          local_diagnostics,
          `[[`,
          numeric(1L),
          "R_rms_min"
        )),
        beta_star_hat = beta_star_hat,
        mu_z0_rms = sqrt(mean(mu_at_truth^2)),
        mu_z0_mc_se_rms = sqrt(mean(mu_mean_mc_se[, 1L]^2)),
        mu_grid_mc_se_rms_max = max(sqrt(colMeans(
          mu_mean_mc_se^2
        ))),
        local_spacing_proxy_max = maximum_local_spacing_proxy(
          oracle_pseudo_groups,
          cfg$z_bounds
        ),
        candidate_z_min = min(candidate_z),
        candidate_z_max = max(candidate_z),
        candidate_lambda_min = min(candidate_lambda),
        candidate_lambda_max = max(candidate_lambda)
      )
    }
  )
  diagnostics <- lapply(seq_along(z_values), function(z_index) {
    c(
      list(z = z_values[z_index]),
      jacobian_diagnostics[[z_index]],
      secant_diagnostics[[z_index]]
    )
  })

  jacobian_raw_smin <- vapply(
    jacobian_diagnostics,
    `[[`,
    numeric(1L),
    "smin"
  )
  jacobian_scaled_smin <- vapply(
    jacobian_diagnostics,
    `[[`,
    numeric(1L),
    "scaled_smin"
  )
  jacobian_condition_number <- vapply(
    jacobian_diagnostics,
    `[[`,
    numeric(1L),
    "condition_number"
  )
  secant_raw_smin <- vapply(
    secant_diagnostics,
    `[[`,
    numeric(1L),
    "secant_raw_smin"
  )
  secant_scaled_smin <- vapply(
    secant_diagnostics,
    `[[`,
    numeric(1L),
    "secant_scaled_smin"
  )
  secant_condition_number <- vapply(
    secant_diagnostics,
    `[[`,
    numeric(1L),
    "secant_condition_max"
  )
  jacobian_passed_by_z <- (
    jacobian_raw_smin >= cfg$pilot_jacobian_smin_min &
      jacobian_scaled_smin >= cfg$pilot_jacobian_scaled_smin_min
  )
  secant_passed_by_z <- (
    secant_raw_smin >= cfg$pilot_secant_raw_smin_min &
      secant_scaled_smin >= cfg$pilot_secant_scaled_smin_min
  )
  passed_by_z <- jacobian_passed_by_z & secant_passed_by_z

  list(
    passed = all(passed_by_z),
    passed_by_z = passed_by_z,
    jacobian_passed_by_z = jacobian_passed_by_z,
    secant_passed_by_z = secant_passed_by_z,
    diagnostics = diagnostics,
    z_values = z_values,
    B = B,
    mu_hat_by_z = lapply(mu_sums, function(one) one / B),
    candidate_z_by_truth = candidate_z_by_truth,
    candidate_lambda = candidate_lambda,
    raw_smin_min = min(jacobian_raw_smin),
    scaled_smin_min = min(jacobian_scaled_smin),
    condition_number_max = max(jacobian_condition_number),
    secant_raw_smin_min = min(secant_raw_smin),
    secant_scaled_smin_min = min(secant_scaled_smin),
    secant_condition_number_max = max(secant_condition_number),
    mean_fixed_point_iterations = mean(fixed_point_iterations),
    max_fixed_point_iterations = max(fixed_point_iterations),
    max_fixed_point_equation_gap =
      max(fixed_point_equation_gaps)
  )
}

validate_tau_bandwidth <- function(network, n, cfg = CFG) {
  degree <- network$degree
  mean_degree <- mean(degree)
  tau <- vapply(degree, function(d) {
    tau_value(
      n = n,
      degree = d,
      mean_degree = mean_degree,
      cfg = cfg
    )
  }, numeric(1L))

  h_y <- vapply(degree, function(d) {
    h_value(n, d, mean_degree, cfg)
  }, numeric(1L))
  knots_tau <- 2 * tau * degree
  list(
    h_y_min = min(h_y),
    h_y_mean = mean(h_y),
    h_y_max = max(h_y),
    knots_y_min = min(2 * h_y * degree),
    degree_h_y_min = min(degree * h_y),
    sqrt_n_h_y_sq = sqrt(n) * max(h_y)^2,
    tau_min = min(tau),
    tau_mean = mean(tau),
    tau_max = max(tau),
    knots_tau_min = min(knots_tau),
    degree_tau_min = min(degree * tau),
    n_quarter_tau = n^(1 / 4) * max(tau),
    max_degree_n045 = max(degree) / n^0.45
  )
}

set_simulation_seed <- function(cfg, mechanism_id, n, replication, draw_attempt) {
  n_id <- match(n, cfg$N)
  if (is.na(n_id)) stop("N is not listed in CFG$N.")
  # Mixed-radix job IDs avoid the collision in the old formula, for example
  # (replication=1,N=2000) and (replication=2,N=1000) previously received the
  # same seed.  Double arithmetic is exact over this integer range.
  job_id <- (
    (
      (mechanism_id - 1) * length(cfg$N) +
        (n_id - 1)
    ) * 100000 +
      (replication - 1)
  ) * 1000 + (draw_attempt - 1)
  seed_modulus <- as.double(.Machine$integer.max) - 1
  seed <- as.integer(
    (as.double(cfg$seed) + job_id) %% seed_modulus + 1
  )
  set.seed(seed)
  invisible(seed)
}

simulate_block <- function(
  n,
  mechanism,
  replication,
  draw_attempt = 1L,
  cfg = CFG
) {
  mechanism_id <- match(mechanism, cfg$network_types)
  set_simulation_seed(cfg, mechanism_id, n, replication, draw_attempt)

  network <- generate_network(n, mechanism, cfg)
  x_design <- generate_identified_X(network, cfg)
  X <- x_design$X
  pilot_screen <- independent_pilot_identification_screen(
    X = X,
    network = network,
    z_values = x_design$z_values,
    cfg = cfg
  )
  if (!isTRUE(pilot_screen$passed)) {
    failed_z <- paste(
      format(
        pilot_screen$z_values[!pilot_screen$passed_by_z],
        nsmall = 2L
      ),
      collapse = ","
    )
    stop(sprintf(
      paste0(
        "Independent B=%d pilot identification screen failed for ",
        "%s, N=%d at z_0={%s}: averaged-Jacobian raw smin ",
        "minimum=%.5f (required %.5f), scaled minimum=%.5f ",
        "(required %.5f); Assumption-3 oracle-partial-secant raw ",
        "minimum=%.5f (required %.5f), scaled minimum=%.5f ",
        "(required %.5f)."
      ),
      pilot_screen$B,
      mechanism,
      n,
      failed_z,
      pilot_screen$raw_smin_min,
      cfg$pilot_jacobian_smin_min,
      pilot_screen$scaled_smin_min,
      cfg$pilot_jacobian_scaled_smin_min,
      pilot_screen$secant_raw_smin_min,
      cfg$pilot_secant_raw_smin_min,
      pilot_screen$secant_scaled_smin_min,
      cfg$pilot_secant_scaled_smin_min
    ), call. = FALSE)
  }
  # This is the first formal innovation draw.  It occurs only after the
  # auxiliary screen has passed and is independent of all B pilot draws.
  innovation_draw <- generate_innovation(network, cfg)
  bandwidth <- validate_tau_bandwidth(network, n, cfg)
  qx_eigenvalues <- eigen(
    crossprod(X) / n,
    symmetric = TRUE,
    only.values = TRUE
  )$values
  in_degree <- as.numeric(Matrix::colSums(network$A))

  scenario_results <- vector("list", length(x_design$z_values))
  for (z_index in seq_along(x_design$z_values)) {
    z0 <- x_design$z_values[z_index]
    scenario_cfg <- cfg
    scenario_cfg$z <- z0
    design_one <- x_design$diagnostics[[z_index]]
    pilot_one <- pilot_screen$diagnostics[[z_index]]

    outcome <- generate_outcome(
      X = X,
      network = network,
      innovation_draw = innovation_draw,
      cfg = scenario_cfg
    )
    outcome_validation <- validate_generated_outcome(
      outcome = outcome,
      X = X,
      network = network,
      cfg = scenario_cfg
    )
    # This diagnostic uses the known simulation truth and the generated Y,
    # and is intentionally computed before estimate_qsar().  It is recorded
    # for every draw but never used as an acceptance rule: Assumption 3 is a
    # population/oracle condition, whereas this is a noisy sample analogue.
    jacobian <- sample_jacobian_diagnostic(
      outcome$y, X, network, scenario_cfg
    )
    assumption3_raw_pass <-
      is.finite(jacobian$smin) &&
      jacobian$smin >= scenario_cfg$assumption3_jacobian_smin_warn
    scaled_smin_warning <-
      !is.finite(jacobian$scaled_smin) ||
      jacobian$scaled_smin < scenario_cfg$assumption3_scaled_smin_warn
    # The truth-based sample-Jacobian quantities above remain report-only.
    # The separate fit-based rule below is the fixed numerical-admissibility
    # screen requested for this conditional Monte Carlo experiment.
    fit <- estimate_qsar(outcome$y, X, network, scenario_cfg)
    formal_screen <- formal_numerical_admissibility(
      fit = fit,
      n = n,
      cfg = scenario_cfg
    )
    if (
      isTRUE(scenario_cfg$formal_numerical_retry) &&
        !isTRUE(formal_screen$passed)
    ) {
      stop(sprintf(
        paste0(
          "Formal numerical admissibility screen failed for %s, N=%d, ",
          "z_0=%.2f: max sqrt(N)*SE=%.6f for %s (required <= %.6f); ",
          "inference Jacobian condition number=%.6f ",
          "(required <= %.6f)."
        ),
        mechanism,
        n,
        z0,
        formal_screen$max_root_n_se,
        formal_screen$max_root_n_se_parameter,
        formal_screen$root_n_se_threshold,
        formal_screen$jacobian_condition,
        formal_screen$jacobian_condition_threshold
      ), call. = FALSE)
    }

    truth <- c(
      beta1 = scenario_cfg$beta[1L],
      beta2 = scenario_cfg$beta[2L],
      lambda = scenario_cfg$lambda,
      z = z0
    )
    error <- fit$estimate - truth
    theoretical_se <- fit$inference$standard_error
    ci_lower <- fit$inference$ci_lower
    ci_upper <- fit$inference$ci_upper
    covered <- truth >= ci_lower & truth <= ci_upper
    studentized_error <- error / theoretical_se

    replication_row <- data.frame(
      network = mechanism,
      N = n,
      z0 = z0,
      replication = replication,
      resample_attempt = draw_attempt,
      beta1_hat = unname(fit$estimate["beta1"]),
      beta2_hat = unname(fit$estimate["beta2"]),
      lambda_hat = unname(fit$estimate["lambda"]),
      z_hat = unname(fit$estimate["z"]),
      beta1_error = unname(error["beta1"]),
      beta2_error = unname(error["beta2"]),
      lambda_error = unname(error["lambda"]),
      z_error = unname(error["z"]),
      confidence_level = scenario_cfg$confidence_level,
      beta1_se = unname(theoretical_se["beta1"]),
      beta1_ci_lower = unname(ci_lower["beta1"]),
      beta1_ci_upper = unname(ci_upper["beta1"]),
      beta1_covered = unname(covered["beta1"]),
      beta1_studentized_error = unname(studentized_error["beta1"]),
      beta2_se = unname(theoretical_se["beta2"]),
      beta2_ci_lower = unname(ci_lower["beta2"]),
      beta2_ci_upper = unname(ci_upper["beta2"]),
      beta2_covered = unname(covered["beta2"]),
      beta2_studentized_error = unname(studentized_error["beta2"]),
      lambda_se = unname(theoretical_se["lambda"]),
      lambda_ci_lower = unname(ci_lower["lambda"]),
      lambda_ci_upper = unname(ci_upper["lambda"]),
      lambda_covered = unname(covered["lambda"]),
      lambda_studentized_error = unname(studentized_error["lambda"]),
      z_se = unname(theoretical_se["z"]),
      z_ci_lower = unname(ci_lower["z"]),
      z_ci_upper = unname(ci_upper["z"]),
      z_covered = unname(covered["z"]),
      z_studentized_error = unname(studentized_error["z"]),
      objective = fit$objective,
      selected_grid_z = fit$selected_grid_z,
      global_profile_grid_z = fit$global_profile_grid_z,
      profile_local_minimum_count =
        fit$profile_local_minimum_count,
      profile_candidate_count = fit$profile_candidate_count,
      selected_candidate_rank = fit$selected_candidate_rank,
      selected_candidate_grid_z =
        fit$selected_candidate_grid_z,
      selected_candidate_refined_z =
        fit$selected_candidate_refined_z,
      selected_basin_lower = fit$selected_basin_lower,
      selected_basin_upper = fit$selected_basin_upper,
      selected_basin_hit = fit$selected_basin_hit,
      selection_objective = fit$selection_objective,
      selection_score = fit$selection_score,
      selection_best_score = fit$selection_best_score,
      selection_second_best_score =
        fit$selection_second_best_score,
      selection_alternative_score =
        fit$selection_alternative_score,
      selection_score_gap = fit$selection_score_gap,
      selection_selected_score_excess =
        fit$selection_selected_score_excess,
      selection_tolerance = fit$selection_tolerance,
      selection_tie_count = fit$selection_tie_count,
      gmm_iterations = fit$gmm_iterations,
      boundary_hit = fit$boundary_hit,
      first_stage_r2 = fit$first_stage_r2,
      formal_max_root_n_se = formal_screen$max_root_n_se,
      formal_max_root_n_se_parameter =
        formal_screen$max_root_n_se_parameter,
      formal_inference_jacobian_condition =
        formal_screen$jacobian_condition,
      formal_numerical_pass = formal_screen$passed
    )

    diagnostic_row <- data.frame(
      network = mechanism,
      N = n,
      z0 = z0,
      replication = replication,
      resample_attempt = draw_attempt,
      min_degree = min(network$degree),
      mean_degree = mean(network$degree),
      max_degree = max(network$degree),
      min_in_degree = min(in_degree),
      mean_in_degree = mean(in_degree),
      max_in_degree = max(in_degree),
      target_degree = network$target_degree,
      directed_network = network$directed,
      arc_count = Matrix::nnzero(network$A),
      undirected_edge_count = Matrix::nnzero(network$A) / 2,
      network_density = Matrix::nnzero(network$A) / (n * (n - 1)),
      dyad_edge_probability = network$dyad_probability,
      sbm_p_in = network$p_in,
      sbm_p_out = network$p_out,
      powerlaw_drawn_degree_min = network$drawn_degree_min,
      powerlaw_drawn_degree_max = network$drawn_degree_max,
      powerlaw_degree_sequence_attempts =
        network$degree_sequence_attempts,
      network_attempts = network$attempts,
      x_attempts = x_design$attempts,
      x_gram_rejections = x_design$gram_rejections,
      qx_eigen_min = min(qx_eigenvalues),
      qx_eigen_max = max(qx_eigenvalues),
      qx_condition = max(qx_eigenvalues) / min(qx_eigenvalues),
      qx_eigen_min_threshold = scenario_cfg$x_gram_eigen_min,
      qx_condition_threshold = scenario_cfg$x_condition_max,
      x1_mean = mean(X[, 1L]),
      x2_mean = mean(X[, 2L]),
      x1_second_moment = mean(X[, 1L]^2),
      x2_second_moment = mean(X[, 2L]^2),
      x12_correlation = stats::cor(X[, 1L], X[, 2L]),
      x_max_abs_entry = max(abs(X)),
      x_max_row_norm = max(sqrt(rowSums(X^2))),
      design_raw_smin = design_one$raw_smin,
      design_scaled_smin = design_one$scaled_smin,
      design_correlation = design_one$correlation,
      design_q_rms = design_one$q_rms,
      design_lambda_dq_rms = design_one$lambda_dq_rms,
      identification_safety_factor =
        scenario_cfg$identification_safety_factor,
      pilot_B = pilot_screen$B,
      pilot_jacobian_smin = pilot_one$smin,
      pilot_jacobian_scaled_smin = pilot_one$scaled_smin,
      pilot_jacobian_condition = pilot_one$condition_number,
      pilot_jacobian_pass =
        pilot_screen$jacobian_passed_by_z[z_index],
      pilot_jacobian_raw_threshold =
        scenario_cfg$pilot_jacobian_smin_min,
      pilot_jacobian_scaled_threshold =
        scenario_cfg$pilot_jacobian_scaled_smin_min,
      pilot_secant_raw_smin = pilot_one$secant_raw_smin,
      pilot_secant_scaled_smin =
        pilot_one$secant_scaled_smin,
      pilot_secant_condition_max =
        pilot_one$secant_condition_max,
      pilot_secant_Z_rms_min = pilot_one$secant_Z_rms_min,
      pilot_secant_R_rms_min = pilot_one$secant_R_rms_min,
      pilot_secant_pass =
        pilot_screen$secant_passed_by_z[z_index],
      pilot_secant_raw_threshold =
        scenario_cfg$pilot_secant_raw_smin_min,
      pilot_secant_scaled_threshold =
        scenario_cfg$pilot_secant_scaled_smin_min,
      pilot_beta_star1 = pilot_one$beta_star_hat[1L],
      pilot_beta_star2 = pilot_one$beta_star_hat[2L],
      pilot_mu_z0_rms = pilot_one$mu_z0_rms,
      pilot_mu_z0_mc_se_rms = pilot_one$mu_z0_mc_se_rms,
      pilot_mu_grid_mc_se_rms_max =
        pilot_one$mu_grid_mc_se_rms_max,
      pilot_local_spacing_proxy_max =
        pilot_one$local_spacing_proxy_max,
      pilot_candidate_z_min = pilot_one$candidate_z_min,
      pilot_candidate_z_max = pilot_one$candidate_z_max,
      pilot_candidate_lambda_min =
        pilot_one$candidate_lambda_min,
      pilot_candidate_lambda_max =
        pilot_one$candidate_lambda_max,
      pilot_mean_fixed_point_iterations =
        pilot_screen$mean_fixed_point_iterations,
      pilot_max_fixed_point_iterations =
        pilot_screen$max_fixed_point_iterations,
      pilot_max_fixed_point_equation_gap =
        pilot_screen$max_fixed_point_equation_gap,
      sample_jacobian_smin = jacobian$smin,
      sample_jacobian_scaled_smin = jacobian$scaled_smin,
      sample_jacobian_condition = jacobian$condition_number,
      inference_jacobian_smin = fit$inference$jacobian_smin,
      inference_jacobian_condition = fit$inference$jacobian_condition,
      inference_score_cov_smin = fit$inference$score_cov_smin,
      inference_score_cov_condition = fit$inference$score_cov_condition,
      inference_sandwich_identity_gap =
        fit$inference$sandwich_identity_gap,
      formal_max_root_n_se = formal_screen$max_root_n_se,
      formal_max_root_n_se_parameter =
        formal_screen$max_root_n_se_parameter,
      formal_root_n_se_threshold =
        formal_screen$root_n_se_threshold,
      formal_inference_jacobian_condition =
        formal_screen$jacobian_condition,
      formal_jacobian_condition_threshold =
        formal_screen$jacobian_condition_threshold,
      formal_numerical_pass = formal_screen$passed,
      assumption3_raw_pass = assumption3_raw_pass,
      scaled_smin_warning = scaled_smin_warning,
      fixed_point_iterations = outcome$iterations,
      fixed_point_gap = outcome$final_gap,
      fixed_point_equation_gap =
        outcome_validation$fixed_point_equation_gap,
      fixed_point_equation_tolerance =
        outcome_validation$fixed_point_equation_tolerance,
      residual_smoothing = TRUE,
      h_y_base_rule = scenario_cfg$h_y_base,
      h_y_exponent_rule = scenario_cfg$h_y_exponent,
      h_y_degree_power_rule = scenario_cfg$h_y_degree_power,
      h_y_min = bandwidth$h_y_min,
      h_y_mean = bandwidth$h_y_mean,
      h_y_max = bandwidth$h_y_max,
      knots_y_min = bandwidth$knots_y_min,
      degree_h_y_min = bandwidth$degree_h_y_min,
      sqrt_n_h_y_sq = bandwidth$sqrt_n_h_y_sq,
      tau_base_rule = scenario_cfg$tau_base,
      tau_exponent_rule = scenario_cfg$tau_exponent,
      tau_degree_power_rule = scenario_cfg$tau_degree_power,
      tau_min = bandwidth$tau_min,
      tau_mean = bandwidth$tau_mean,
      tau_max = bandwidth$tau_max,
      knots_tau_min = bandwidth$knots_tau_min,
      degree_tau_min = bandwidth$degree_tau_min,
      n_quarter_tau = bandwidth$n_quarter_tau,
      max_degree_n045 = bandwidth$max_degree_n045
    )

    profile_row <- data.frame(
      network = mechanism,
      N = n,
      z0 = z0,
      replication = replication,
      resample_attempt = draw_attempt,
      z = fit$profile_z,
      objective = fit$profile_objective,
      selection_score = fit$profile_score,
      is_local_minimum = fit$profile_is_local_minimum,
      is_candidate_minimum = fit$profile_is_candidate_minimum,
      in_selected_basin = fit$profile_in_selected_basin
    )

    candidate_row <- cbind(
      data.frame(
        network = mechanism,
        N = n,
        z0 = z0,
        replication = replication,
        resample_attempt = draw_attempt
      ),
      fit$profile_candidates
    )

    scenario_results[[z_index]] <- list(
      replication = replication_row,
      diagnostic = diagnostic_row,
      profile = profile_row,
      candidate = candidate_row
    )
  }

  list(
    accepted = TRUE,
    replication = do.call(rbind, lapply(
      scenario_results, `[[`, "replication"
    )),
    diagnostic = do.call(rbind, lapply(
      scenario_results, `[[`, "diagnostic"
    )),
    profile = do.call(rbind, lapply(
      scenario_results, `[[`, "profile"
    )),
    candidate = do.call(rbind, lapply(
      scenario_results, `[[`, "candidate"
    ))
  )
}

summarize_results <- function(replications, cfg = CFG) {
  parameters <- c("beta1", "beta2", "lambda", "z")
  rows <- list()
  counter <- 0L

  for (mechanism in cfg$network_types) {
    for (z0 in cfg$z_values) {
      for (n in cfg$N) {
        keep <- replications$network == mechanism &
          replications$N == n &
          abs(replications$z0 - z0) < 1e-12
        one_group <- replications[keep, , drop = FALSE]
        if (nrow(one_group) != cfg$R) {
          stop(sprintf(
            "Expected R=%d rows for %s, N=%d, z_0=%.2f; found %d.",
            cfg$R, mechanism, n, z0, nrow(one_group)
          ))
        }
        for (parameter in parameters) {
          counter <- counter + 1L
          estimate <- one_group[[paste0(parameter, "_hat")]]
          error <- one_group[[paste0(parameter, "_error")]]
          theoretical_se <- one_group[[paste0(parameter, "_se")]]
          ci_lower <- one_group[[paste0(parameter, "_ci_lower")]]
          ci_upper <- one_group[[paste0(parameter, "_ci_upper")]]
          covered <- one_group[[paste0(parameter, "_covered")]]
          studentized_error <- one_group[[
            paste0(parameter, "_studentized_error")
          ]]
          empirical_sd <- sqrt(mean((estimate - mean(estimate))^2))
          signed_bias <- mean(error)
          mean_theoretical_se <- mean(theoretical_se)
          median_theoretical_se <- stats::median(theoretical_se)
          p95_theoretical_se <- unname(stats::quantile(
            theoretical_se,
            probs = 0.95,
            names = FALSE
          ))
          max_theoretical_se <- max(theoretical_se)
          coverage_count <- sum(covered)
          coverage_probability <- mean(covered)
          mc_alpha <- 1 - cfg$coverage_mc_band_level
          coverage_reference_lower <- stats::qbinom(
            mc_alpha / 2,
            size = nrow(one_group),
            prob = cfg$confidence_level
          ) / nrow(one_group)
          coverage_reference_upper <- stats::qbinom(
            1 - mc_alpha / 2,
            size = nrow(one_group),
            prob = cfg$confidence_level
          ) / nrow(one_group)
          rows[[counter]] <- data.frame(
            network = mechanism,
            N = n,
            z0 = z0,
            parameter = parameter,
            R = nrow(one_group),
            truth = switch(
              parameter,
              beta1 = cfg$beta[1L],
              beta2 = cfg$beta[2L],
              lambda = cfg$lambda,
              z = z0
            ),
            mean_estimate = mean(estimate),
            bias = abs(signed_bias),
            signed_bias = signed_bias,
            empirical_sd = empirical_sd,
            mse = mean(error^2),
            rmse = sqrt(mean(error^2)),
            mean_theoretical_se = mean_theoretical_se,
            median_theoretical_se = median_theoretical_se,
            p95_theoretical_se = p95_theoretical_se,
            max_theoretical_se = max_theoretical_se,
            theoretical_se_mean_to_median = if (
              is.finite(median_theoretical_se) &&
                median_theoretical_se > 0
            ) {
              mean_theoretical_se / median_theoretical_se
            } else {
              NA_real_
            },
            theoretical_to_empirical_se = if (
              is.finite(empirical_sd) && empirical_sd > 0
            ) {
              mean_theoretical_se / empirical_sd
            } else {
              NA_real_
            },
            nominal_coverage = cfg$confidence_level,
            coverage_count = coverage_count,
            noncoverage_count = nrow(one_group) - coverage_count,
            coverage_probability = coverage_probability,
            coverage_mc_se = sqrt(
              coverage_probability *
                (1 - coverage_probability) /
                nrow(one_group)
            ),
            coverage_reference_lower = coverage_reference_lower,
            coverage_reference_upper = coverage_reference_upper,
            coverage_within_mc_band = (
              coverage_probability >= coverage_reference_lower &&
                coverage_probability <= coverage_reference_upper
            ),
            mean_ci_length = mean(ci_upper - ci_lower),
            mean_studentized_error = mean(studentized_error),
            sd_studentized_error = stats::sd(studentized_error)
          )
        }
      }
    }
  }
  do.call(rbind, rows)
}

write_outputs <- function(results, cfg = CFG) {
  output_dir <- if (is.null(cfg$output_dir)) {
    sprintf(
      paste0(
        "qsar_classic_networks_AdependentX_B4secant_",
        "doubleSmooth_numericalRetry_results_",
        "R%d_z030507_cp%d"
      ),
      as.integer(cfg$R),
      as.integer(round(100 * cfg$confidence_level))
    )
  } else {
    cfg$output_dir
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  replications <- do.call(rbind, lapply(results, `[[`, "replication"))
  diagnostics <- do.call(rbind, lapply(results, `[[`, "diagnostic"))
  profiles <- do.call(rbind, lapply(results, `[[`, "profile"))
  candidates <- do.call(rbind, lapply(results, `[[`, "candidate"))
  expected_scenarios <- length(cfg$network_types) *
    length(cfg$N) *
    length(cfg$z_values) *
    cfg$R
  if (
    nrow(replications) != expected_scenarios ||
      nrow(diagnostics) != expected_scenarios ||
      nrow(profiles) != expected_scenarios * cfg$z_grid_size ||
      nrow(candidates) < expected_scenarios ||
      nrow(candidates) >
        expected_scenarios * cfg$profile_max_candidates
  ) {
    stop("Output row counts do not match the requested simulation design.")
  }
  candidate_scenario_key <- interaction(
    candidates$network,
    candidates$N,
    candidates$z0,
    candidates$replication,
    drop = TRUE
  )
  selected_per_scenario <- tapply(
    candidates$selected,
    candidate_scenario_key,
    sum
  )
  candidates_per_scenario <- table(candidate_scenario_key)
  if (
    length(selected_per_scenario) != expected_scenarios ||
      any(selected_per_scenario != 1L) ||
      any(candidates_per_scenario < 1L) ||
      any(candidates_per_scenario > cfg$profile_max_candidates)
  ) {
    stop(
      "Every scenario must have one selected profile candidate."
    )
  }
  for (parameter in c("beta1", "beta2", "lambda", "z")) {
    standard_error <- replications[[paste0(parameter, "_se")]]
    ci_lower <- replications[[paste0(parameter, "_ci_lower")]]
    ci_upper <- replications[[paste0(parameter, "_ci_upper")]]
    covered <- replications[[paste0(parameter, "_covered")]]
    if (
      any(!is.finite(standard_error)) ||
        any(standard_error <= 0) ||
        any(!is.finite(ci_lower)) ||
        any(!is.finite(ci_upper)) ||
        any(ci_lower >= ci_upper) ||
        any(is.na(covered))
    ) {
      stop(sprintf(
        "Invalid plug-in confidence-interval output for %s.",
        parameter
      ))
    }
  }
  if (
    any(!replications$formal_numerical_pass) ||
      any(!is.finite(replications$formal_max_root_n_se)) ||
      any(
        replications$formal_max_root_n_se >
          cfg$formal_root_n_se_max
      ) ||
      any(!is.finite(
        replications$formal_inference_jacobian_condition
      )) ||
      any(
        replications$formal_inference_jacobian_condition >
          cfg$formal_jacobian_condition_max
      )
  ) {
    stop(
      "An accepted result violates the formal numerical-admissibility rule."
    )
  }
  summary <- summarize_results(replications, cfg)
  z_summary <- summary[summary$parameter == "z", ]
  trend_rows <- list()
  trend_counter <- 0L
  for (mechanism in cfg$network_types) {
    for (z0 in cfg$z_values) {
      trend_counter <- trend_counter + 1L
      one <- z_summary[
        z_summary$network == mechanism &
          abs(z_summary$z0 - z0) < 1e-12,
      ]
      one <- one[order(one$N), ]
      trend_rows[[trend_counter]] <- data.frame(
        network = mechanism,
        z0 = z0,
        mse_N1000 = one$mse[one$N == 1000L],
        mse_N2000 = one$mse[one$N == 2000L],
        mse_N3000 = one$mse[one$N == 3000L],
        strictly_decreasing = all(diff(one$mse) < 0)
      )
    }
  }
  trend <- do.call(rbind, trend_rows)
  coverage_trend_rows <- list()
  coverage_trend_counter <- 0L
  for (mechanism in cfg$network_types) {
    for (z0 in cfg$z_values) {
      coverage_trend_counter <- coverage_trend_counter + 1L
      one <- z_summary[
        z_summary$network == mechanism &
          abs(z_summary$z0 - z0) < 1e-12,
      ]
      one <- one[order(one$N), ]
      coverage_probability <- one$coverage_probability
      absolute_gap <- abs(
        coverage_probability - cfg$confidence_level
      )
      coverage_trend_rows[[coverage_trend_counter]] <- data.frame(
        network = mechanism,
        z0 = z0,
        cp_N1000 = coverage_probability[one$N == 1000L],
        cp_N2000 = coverage_probability[one$N == 2000L],
        cp_N3000 = coverage_probability[one$N == 3000L],
        abs_gap_N1000 = absolute_gap[one$N == 1000L],
        abs_gap_N2000 = absolute_gap[one$N == 2000L],
        abs_gap_N3000 = absolute_gap[one$N == 3000L],
        closer_at_every_step = all(diff(absolute_gap) < 0),
        N3000_closer_than_N1000 =
          absolute_gap[one$N == 3000L] <
            absolute_gap[one$N == 1000L],
        N3000_within_mc_band =
          one$coverage_within_mc_band[one$N == 3000L]
      )
    }
  }
  coverage_trend <- do.call(rbind, coverage_trend_rows)
  coverage <- summary[, c(
    "network",
    "N",
    "z0",
    "parameter",
    "R",
    "truth",
    "empirical_sd",
    "mean_theoretical_se",
    "median_theoretical_se",
    "p95_theoretical_se",
    "max_theoretical_se",
    "theoretical_se_mean_to_median",
    "theoretical_to_empirical_se",
    "nominal_coverage",
    "coverage_count",
    "noncoverage_count",
    "coverage_probability",
    "coverage_mc_se",
    "coverage_reference_lower",
    "coverage_reference_upper",
    "coverage_within_mc_band",
    "mean_ci_length",
    "mean_studentized_error",
    "sd_studentized_error"
  ), drop = FALSE]
  numerical_retry_summary <- unique(diagnostics[, c(
    "network",
    "N",
    "replication",
    "resample_attempt",
    "formal_numerical_rejections_before_acceptance",
    "formal_numerical_rejection_history"
  ), drop = FALSE])

  utils::write.csv(
    replications,
    file.path(output_dir, "qsar_replications.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    diagnostics,
    file.path(output_dir, "qsar_diagnostics.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    profiles,
    file.path(output_dir, "qsar_z_profiles.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    candidates,
    file.path(output_dir, "qsar_profile_candidates.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    summary,
    file.path(output_dir, "qsar_summary.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    trend,
    file.path(output_dir, "qsar_z_mse_trend.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    coverage,
    file.path(output_dir, "qsar_coverage.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    coverage_trend,
    file.path(output_dir, "qsar_z_coverage_trend.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    numerical_retry_summary,
    file.path(output_dir, "qsar_numerical_retry_summary.csv"),
    row.names = FALSE
  )

  print(z_summary[, c(
    "network", "z0", "N", "R", "mean_estimate", "bias", "mse", "rmse"
  )], row.names = FALSE)
  print(trend, row.names = FALSE)
  print(coverage[, c(
    "network",
    "z0",
    "N",
    "parameter",
    "empirical_sd",
    "mean_theoretical_se",
    "median_theoretical_se",
    "max_theoretical_se",
    "coverage_count",
    "coverage_probability",
    "coverage_within_mc_band"
  )], row.names = FALSE)
  print(coverage_trend, row.names = FALSE)
  if (any(!trend$strictly_decreasing)) {
    warning(sprintf(
      paste0(
        "At least one R=%d network/z_0 MSE path is not strictly decreasing. ",
        "Inspect qsar_profile_candidates.csv, qsar_z_profiles.csv and ",
        "qsar_diagnostics.csv; ",
        "do not tune the DGP after seeing Monte Carlo estimation errors."
      ),
      cfg$R
    ))
  }
  if (any(!coverage$coverage_within_mc_band)) {
    warning(sprintf(
      paste0(
        "%d of %d parameter/scenario coverage probabilities fall outside ",
        "the %.1f%% Monte Carlo reference band around nominal %.1f%% ",
        "coverage.  Treat this as an asymptotic-approximation diagnostic; ",
        "do not tune the DGP after seeing coverage errors."
      ),
      sum(!coverage$coverage_within_mc_band),
      nrow(coverage),
      100 * cfg$coverage_mc_band_level,
      100 * cfg$confidence_level
    ))
  }
  message(sprintf(
    paste0(
      "%d of %d z-coverage paths move strictly closer to nominal at both ",
      "finite-N steps; %d of %d are closer at N=3000 than at N=1000.  ",
      "These path counts are descriptive and are not an asymptotic test."
    ),
    sum(coverage_trend$closer_at_every_step),
    nrow(coverage_trend),
    sum(coverage_trend$N3000_closer_than_N1000),
    nrow(coverage_trend)
  ))
  pilot_jacobian_pass <- (
    is.finite(diagnostics$pilot_jacobian_smin) &
      diagnostics$pilot_jacobian_smin >=
        diagnostics$pilot_jacobian_raw_threshold &
      is.finite(diagnostics$pilot_jacobian_scaled_smin) &
      diagnostics$pilot_jacobian_scaled_smin >=
        diagnostics$pilot_jacobian_scaled_threshold
  )
  pilot_secant_pass <- (
    is.finite(diagnostics$pilot_secant_raw_smin) &
      diagnostics$pilot_secant_raw_smin >=
        diagnostics$pilot_secant_raw_threshold &
      is.finite(diagnostics$pilot_secant_scaled_smin) &
      diagnostics$pilot_secant_scaled_smin >=
        diagnostics$pilot_secant_scaled_threshold
  )
  if (any(!pilot_jacobian_pass | !pilot_secant_pass)) {
    stop(
      paste0(
        "An accepted block violates the independent-pilot Jacobian or ",
        "Assumption-3 partial-secant screen."
      ),
      call. = FALSE
    )
  }
  accepted_block_attempts <- numerical_retry_summary
  message(sprintf(
    paste0(
      "Independent B=%d expectation/Jacobian/secant screen verified for ",
      "all %d accepted blocks; ",
      "%d block(s) required at least one retry ",
      "(maximum accepted attempt=%d).  The fixed formal numerical screen ",
      "rejected %d proposal(s) across %d block(s)."
    ),
    cfg$pilot_B,
    nrow(accepted_block_attempts),
    sum(accepted_block_attempts$resample_attempt > 1L),
    max(accepted_block_attempts$resample_attempt),
    sum(
      accepted_block_attempts[[
        "formal_numerical_rejections_before_acceptance"
      ]]
    ),
    sum(
      accepted_block_attempts[[
        "formal_numerical_rejections_before_acceptance"
      ]] > 0L
    )
  ))
  sample_raw_warnings <- sum(!diagnostics$assumption3_raw_pass)
  sample_scaled_warnings <- sum(diagnostics$scaled_smin_warning)
  if (sample_raw_warnings + sample_scaled_warnings > 0L) {
    warning(sprintf(
      paste0(
        "Post-outcome Jacobian diagnostics recorded %d/%d (%.2f%%) raw ",
        "and %d/%d (%.2f%%) scaled warnings.  These truth-based ",
        "diagnostics were not used by the fit-based numerical screen."
      ),
      sample_raw_warnings,
      nrow(diagnostics),
      100 * sample_raw_warnings / nrow(diagnostics),
      sample_scaled_warnings,
      nrow(diagnostics),
      100 * sample_scaled_warnings / nrow(diagnostics)
    ))
  }
  if (any(replications$boundary_hit)) {
    warning(sprintf(
      paste0(
        "%d estimates hit a fixed parameter boundary; inspect ",
        "qsar_profile_candidates.csv and qsar_z_profiles.csv."
      ),
      sum(replications$boundary_hit)
    ))
  }
  if (any(replications$selected_basin_hit)) {
    warning(sprintf(
      paste0(
        "%d iterated-GMM estimates hit a selected profile basin ",
        "boundary; inspect qsar_profile_candidates.csv and ",
        "qsar_z_profiles.csv before interpreting Wald inference."
      ),
      sum(replications$selected_basin_hit)
    ))
  }
  tied_candidate_scenarios <- sum(
    replications$selection_tie_count > 1L
  )
  message(sprintf(
    paste0(
      "Global doubly smoothed profile selection retained %d candidate ",
      "basin(s) across %d scenarios; %d scenario(s) used the fixed ",
      "interior-margin rule for a numerical objective tie."
    ),
    nrow(candidates),
    nrow(replications),
    tied_candidate_scenarios
  ))
  invisible(list(
    replications = replications,
    diagnostics = diagnostics,
    profiles = profiles,
    candidates = candidates,
    summary = summary,
    trend = trend,
    coverage = coverage,
    coverage_trend = coverage_trend,
    numerical_retry_summary = numerical_retry_summary
  ))
}

set_single_thread_math <- function() {
  # Each Monte Carlo job is already a separate process.  Prevent BLAS/OpenMP
  # from starting additional threads inside every worker.
  Sys.setenv(
    OMP_NUM_THREADS = "1",
    OPENBLAS_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    BLIS_NUM_THREADS = "1"
  )
  invisible(TRUE)
}

detect_available_cores <- function() {
  # Prefer an explicit override or a scheduler allocation over the physical
  # host count.  This avoids using CPUs that were not assigned to the job.
  environment_limits <- c(
    "QSAR_N_CORES",
    "SLURM_CPUS_PER_TASK",
    "PBS_NP",
    "NSLOTS"
  )
  for (variable in environment_limits) {
    value <- suppressWarnings(as.integer(Sys.getenv(variable, "")))
    if (length(value) == 1L && is.finite(value) && value >= 1L) {
      return(value)
    }
  }
  detected <- suppressWarnings(parallel::detectCores(logical = TRUE))
  if (
    length(detected) != 1L ||
      !is.finite(detected) ||
      detected < 1L
  ) {
    detected <- 1L
  }
  as.integer(detected)
}

choose_parallel_workers <- function(cfg, number_of_jobs) {
  if (
    !isTRUE(cfg$parallel) ||
      identical(cfg$parallel_backend, "sequential") ||
      number_of_jobs <= 1L
  ) {
    return(1L)
  }

  available <- detect_available_cores()
  requested <- if (is.null(cfg$parallel_workers)) {
    floor(cfg$parallel_fraction * available)
  } else {
    as.integer(cfg$parallel_workers)
  }
  as.integer(max(1L, min(number_of_jobs, available, requested)))
}

choose_block_chunk_size <- function(cfg, number_of_jobs) {
  as.integer(max(
    1L,
    min(number_of_jobs, cfg$parallel_block_chunk_size)
  ))
}

make_job_chunks <- function(job_list, chunk_size) {
  if (length(job_list) == 0L) return(list())
  chunk_id <- ceiling(seq_along(job_list) / as.integer(chunk_size))
  unname(split(job_list, chunk_id))
}

format_elapsed_time <- function(seconds) {
  seconds <- max(0, as.integer(round(seconds)))
  hours <- seconds %/% 3600L
  minutes <- (seconds %% 3600L) %/% 60L
  seconds <- seconds %% 60L
  sprintf("%02d:%02d:%02d", hours, minutes, seconds)
}

flush_visible_output <- function() {
  flush.console()
  try(flush(stdout()), silent = TRUE)
  invisible(TRUE)
}

render_progress_line <- function(
  completed_blocks,
  total_blocks,
  z_count,
  width,
  start_time
) {
  fraction <- clamp(completed_blocks / total_blocks, 0, 1)
  filled <- as.integer(floor(width * fraction))
  bar <- paste0(
    strrep("=", filled),
    strrep(" ", width - filled)
  )
  completed_scenarios <- completed_blocks * z_count
  total_scenarios <- total_blocks * z_count
  elapsed <- as.numeric(Sys.time()) - start_time
  eta_text <- if (
    completed_blocks > 0L &&
      completed_blocks < total_blocks
  ) {
    format_elapsed_time(
      elapsed * (total_blocks - completed_blocks) / completed_blocks
    )
  } else if (completed_blocks >= total_blocks) {
    "00:00:00"
  } else {
    "--:--:--"
  }
  blocks_per_minute <- if (elapsed > 0 && completed_blocks > 0L) {
    60 * completed_blocks / elapsed
  } else {
    0
  }
  sprintf(
    paste0(
      "QSAR progress [%s] %d/%d blocks | %d/%d z-scenarios | ",
      "%5.1f%% | elapsed %s | ETA %s | %.2f blocks/min"
    ),
    bar,
    completed_blocks,
    total_blocks,
    completed_scenarios,
    total_scenarios,
    100 * fraction,
    format_elapsed_time(elapsed),
    eta_text,
    blocks_per_minute
  )
}

initialize_progress_state <- function(
  total_blocks,
  z_count,
  width,
  target_updates,
  enabled
) {
  if (!isTRUE(enabled)) return(list(enabled = FALSE))
  progress_directory <- tempfile("qsar_parallel_progress_")
  if (!dir.create(progress_directory, recursive = TRUE)) {
    stop("Could not initialize the parallel progress state.")
  }
  state_file <- file.path(progress_directory, "state.rds")
  state <- list(
    completed_blocks = 0L,
    total_blocks = as.integer(total_blocks),
    z_count = as.integer(z_count),
    width = as.integer(width),
    start_time = as.numeric(Sys.time()),
    print_every = as.integer(max(
      1L,
      ceiling(total_blocks / target_updates)
    )),
    last_printed = 0L
  )
  saveRDS(state, state_file)
  specification <- list(
    enabled = TRUE,
    directory = progress_directory,
    state_file = state_file,
    lock_directory = file.path(progress_directory, "update.lock")
  )
  cat(
    render_progress_line(
      completed_blocks = 0L,
      total_blocks = state$total_blocks,
      z_count = state$z_count,
      width = state$width,
      start_time = state$start_time
    ),
    "\n"
  )
  cat(sprintf(
    "Progress snapshots will be printed after every %d completed block(s).\n",
    state$print_every
  ))
  flush_visible_output()
  specification
}

update_progress_state <- function(specification, increment) {
  if (!isTRUE(specification$enabled)) return(invisible(FALSE))
  acquired <- FALSE
  started <- proc.time()[["elapsed"]]
  while (!acquired) {
    acquired <- dir.create(
      specification$lock_directory,
      showWarnings = FALSE
    )
    if (!acquired) {
      if (proc.time()[["elapsed"]] - started > 120) {
        warning("Progress update timed out; simulation continues.")
        return(invisible(FALSE))
      }
      Sys.sleep(0.02)
    }
  }
  on.exit(
    unlink(
      specification$lock_directory,
      recursive = TRUE,
      force = TRUE
    ),
    add = TRUE
  )

  state <- readRDS(specification$state_file)
  state$completed_blocks <- min(
    state$total_blocks,
    state$completed_blocks + as.integer(increment)
  )
  should_print <- (
    state$completed_blocks >= state$total_blocks ||
      state$completed_blocks - state$last_printed >= state$print_every
  )
  if (should_print) {
    state$last_printed <- state$completed_blocks
  }
  saveRDS(state, specification$state_file)
  if (should_print) {
    cat(
      render_progress_line(
        completed_blocks = state$completed_blocks,
        total_blocks = state$total_blocks,
        z_count = state$z_count,
        width = state$width,
        start_time = state$start_time
      ),
      "\n"
    )
    flush_visible_output()
  }
  invisible(TRUE)
}

remove_progress_state <- function(specification) {
  if (
    isTRUE(specification$enabled) &&
      dir.exists(specification$directory)
  ) {
    unlink(specification$directory, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

initialize_master_completion_tracker <- function(
  job_chunks,
  cfg = CFG
) {
  tracker <- new.env(parent = emptyenv())
  tracker$enabled <- isTRUE(cfg$parallel_progress)
  tracker$total_blocks <- sum(lengths(job_chunks))
  tracker$completed_blocks <- 0L
  tracker$total_replications <- as.integer(cfg$R)
  tracker$completed_replications <- 0L
  tracker$completed_by_replication <- integer(cfg$R)
  tracker$expected_by_replication <- integer(cfg$R)
  tracker$start_time <- as.numeric(Sys.time())

  for (one_chunk in job_chunks) {
    for (one_job in one_chunk) {
      replication <- as.integer(one_job$replication)
      tracker$expected_by_replication[replication] <-
        tracker$expected_by_replication[replication] + 1L
    }
  }
  expected_blocks <- length(cfg$N) * length(cfg$network_types)
  tracker$blocks_per_replication <- expected_blocks
  if (
    length(tracker$expected_by_replication) != cfg$R ||
      any(tracker$expected_by_replication != expected_blocks)
  ) {
    stop(
      "The parallel job list is not balanced across replications.",
      call. = FALSE
    )
  }

  if (tracker$enabled) {
    replication_width <- nchar(as.character(cfg$R))
    block_width <- nchar(as.character(tracker$total_blocks))
    cat(sprintf(
      paste0(
        "[%0*d/%d blocks] returned | ",
        "[%0*d/%d replications] complete | ",
        "waiting for the first completed block.\n"
      ),
      block_width,
      0L,
      tracker$total_blocks,
      replication_width,
      0L,
      cfg$R
    ))
    flush_visible_output()
  }
  tracker
}

update_master_completion_tracker <- function(
  tracker,
  completed_chunk,
  cfg = CFG
) {
  if (!is.environment(tracker)) {
    stop("The main-process completion tracker is invalid.")
  }

  newly_completed_replications <- integer()
  completed_replication_counts <- integer()
  for (one_job in completed_chunk) {
    replication <- as.integer(one_job$replication)
    tracker$completed_blocks <- tracker$completed_blocks + 1L
    tracker$completed_by_replication[replication] <-
      tracker$completed_by_replication[replication] + 1L

    elapsed <- as.numeric(Sys.time()) - tracker$start_time
    eta <- if (
      tracker$completed_blocks > 0L &&
        tracker$completed_blocks < tracker$total_blocks
    ) {
      elapsed *
        (tracker$total_blocks - tracker$completed_blocks) /
        tracker$completed_blocks
    } else {
      0
    }
    if (
      isTRUE(tracker$enabled) &&
        isTRUE(cfg$progress_every_block)
    ) {
      block_width <- nchar(as.character(tracker$total_blocks))
      replication_width <- nchar(as.character(cfg$R))
      network_label <- if (!is.null(one_job$network)) {
        as.character(one_job$network)
      } else {
        "unknown"
      }
      n_label <- if (!is.null(one_job$N)) {
        as.integer(one_job$N)
      } else {
        NA_integer_
      }
      cat(sprintf(
        paste0(
          "[%0*d/%d blocks] returned | network=%s | N=%s | ",
          "replication=%0*d/%d | elapsed %s | ETA %s\n"
        ),
        block_width,
        tracker$completed_blocks,
        tracker$total_blocks,
        network_label,
        if (is.na(n_label)) "unknown" else as.character(n_label),
        replication_width,
        replication,
        cfg$R,
        format_elapsed_time(elapsed),
        format_elapsed_time(eta)
      ))
      # This flush is executed by the main R process, immediately after
      # recvOneResult() returns.  It does not depend on worker stdout.
      flush_visible_output()
    }

    if (
      tracker$completed_by_replication[replication] ==
        tracker$expected_by_replication[replication]
    ) {
      tracker$completed_replications <-
        tracker$completed_replications + 1L
      newly_completed_replications <- c(
        newly_completed_replications,
        replication
      )
      completed_replication_counts <- c(
        completed_replication_counts,
        tracker$completed_replications
      )
    } else if (
      tracker$completed_by_replication[replication] >
        tracker$expected_by_replication[replication]
    ) {
      stop("A replication was counted more than once.")
    }
  }

  if (
    isTRUE(tracker$enabled) &&
      length(newly_completed_replications) > 0L
  ) {
    elapsed <- as.numeric(Sys.time()) - tracker$start_time
    eta <- if (
      tracker$completed_blocks > 0L &&
        tracker$completed_blocks < tracker$total_blocks
    ) {
      elapsed *
        (tracker$total_blocks - tracker$completed_blocks) /
        tracker$completed_blocks
    } else {
      0
    }
    replication_width <- nchar(as.character(cfg$R))
    block_width <- nchar(as.character(tracker$total_blocks))
    for (completion_index in seq_along(newly_completed_replications)) {
      replication <- newly_completed_replications[completion_index]
      cat(sprintf(
        paste0(
          "[%0*d/%d replications] latest r=%0*d | ",
          "%0*d/%d blocks | elapsed %s | ETA %s\n"
        ),
        replication_width,
        completed_replication_counts[completion_index],
        cfg$R,
        replication_width,
        replication,
        block_width,
        tracker$completed_blocks,
        tracker$total_blocks,
        format_elapsed_time(elapsed),
        format_elapsed_time(eta)
      ))
    }
    flush_visible_output()
  } else if (
    isTRUE(tracker$enabled) &&
      !isTRUE(cfg$progress_every_block) &&
      tracker$completed_blocks %% tracker$blocks_per_replication == 0L
  ) {
    elapsed <- as.numeric(Sys.time()) - tracker$start_time
    eta <- if (tracker$completed_blocks < tracker$total_blocks) {
      elapsed *
        (tracker$total_blocks - tracker$completed_blocks) /
        tracker$completed_blocks
    } else {
      0
    }
    replication_width <- nchar(as.character(cfg$R))
    block_width <- nchar(as.character(tracker$total_blocks))
    cat(sprintf(
      paste0(
        "[%0*d/%d replications] %0*d/%d blocks returned | ",
        "waiting for a complete replication | elapsed %s | ETA %s\n"
      ),
      replication_width,
      tracker$completed_replications,
      cfg$R,
      block_width,
      tracker$completed_blocks,
      tracker$total_blocks,
      format_elapsed_time(elapsed),
      format_elapsed_time(eta)
    ))
    flush_visible_output()
  }
  invisible(tracker)
}

psock_dynamic_apply_with_master_progress <- function(
  cluster,
  job_chunks,
  cfg = CFG
) {
  number_of_chunks <- length(job_chunks)
  if (number_of_chunks == 0L) return(list())
  number_of_workers <- min(length(cluster), number_of_chunks)
  results <- vector("list", number_of_chunks)
  tracker <- initialize_master_completion_tracker(job_chunks, cfg)

  parallel_namespace <- asNamespace("parallel")
  send_call <- get0(
    "sendCall",
    envir = parallel_namespace,
    mode = "function",
    inherits = FALSE
  )
  receive_one_result <- get0(
    "recvOneResult",
    envir = parallel_namespace,
    mode = "function",
    inherits = FALSE
  )
  if (is.null(send_call) || is.null(receive_one_result)) {
    stop(
      paste0(
        "This R installation does not expose the low-level PSOCK ",
        "dispatcher needed for main-process progress reporting."
      ),
      call. = FALSE
    )
  }

  submit_chunk <- function(worker_index, chunk_index) {
    send_call(
      cluster[[worker_index]],
      run_simulation_chunk_safely,
      list(
        job_chunk = job_chunks[[chunk_index]],
        cfg = cfg,
        progress_specification = list(enabled = FALSE)
      ),
      tag = chunk_index
    )
    invisible(TRUE)
  }

  next_chunk <- 1L
  for (worker_index in seq_len(number_of_workers)) {
    submit_chunk(worker_index, next_chunk)
    next_chunk <- next_chunk + 1L
  }

  for (completed_index in seq_len(number_of_chunks)) {
    received <- receive_one_result(cluster)
    chunk_index <- as.integer(received$tag)
    worker_index <- as.integer(received$node)
    if (
      length(chunk_index) != 1L ||
        !is.finite(chunk_index) ||
        chunk_index < 1L ||
        chunk_index > number_of_chunks ||
        !is.null(results[[chunk_index]])
    ) {
      stop("The PSOCK dispatcher returned an invalid task tag.")
    }
    results[[chunk_index]] <- received$value
    update_master_completion_tracker(
      tracker,
      job_chunks[[chunk_index]],
      cfg
    )

    if (next_chunk <= number_of_chunks) {
      submit_chunk(worker_index, next_chunk)
      next_chunk <- next_chunk + 1L
    }
  }

  if (
    tracker$completed_blocks != tracker$total_blocks ||
      tracker$completed_replications != tracker$total_replications
  ) {
    stop("The main-process progress totals are internally inconsistent.")
  }
  results
}

run_simulation_chunk_safely <- function(
  job_chunk,
  cfg = CFG,
  progress_specification = list(enabled = FALSE)
) {
  values <- lapply(
    job_chunk,
    run_simulation_job_safely,
    cfg = cfg
  )
  tryCatch(
    update_progress_state(
      progress_specification,
      length(job_chunk)
    ),
    error = function(err) {
      warning(
        paste0(
          "A progress-bar update failed, but simulation continues: ",
          conditionMessage(err)
        ),
        call. = FALSE
      )
      invisible(FALSE)
    }
  )
  values
}

resolve_parallel_backend <- function(cfg, workers) {
  if (workers <= 1L) return("sequential")
  backend <- cfg$parallel_backend
  if (identical(backend, "auto")) {
    backend <- "psock"
  }
  if (
    identical(backend, "multicore") &&
      .Platform$OS.type == "windows"
  ) {
    warning(
      "The multicore backend is unavailable on Windows; using PSOCK.",
      call. = FALSE
    )
    backend <- "psock"
  }
  backend
}

run_simulation_job <- function(job, cfg = CFG) {
  # Some low-level defaults refer to the global CFG.  This assignment occurs
  # only inside the worker process and makes an explicitly supplied cfg fully
  # effective without creating shared mutable state.
  assign("CFG", cfg, envir = .GlobalEnv)
  set_single_thread_math()

  mechanism <- as.character(job$network)
  n <- as.integer(job$N)
  replication <- as.integer(job$replication)

  accepted <- FALSE
  last_rejection <- NULL
  formal_numerical_rejections <- 0L
  formal_numerical_rejection_history <- character()
  for (draw_attempt in seq_len(cfg$max_resample_attempts)) {
    candidate <- tryCatch(
      simulate_block(
        n = n,
        mechanism = mechanism,
        replication = replication,
        draw_attempt = draw_attempt,
        cfg = cfg
      ),
      error = function(err) {
        message_text <- conditionMessage(err)
        redrawable_design_error <- grepl(
          paste0(
            "network failed the minimum-degree check|",
            "Power-Law graph generation failed|",
            "Could not make the Power-Law degree sum even|",
            "No X design passed|",
            "X is poorly conditioned|",
            "X contains a non-finite value|",
            "pilot identification screen failed"
          ),
          message_text
        )
        redrawable_formal_numerical_error <- grepl(
          paste0(
            "Formal numerical admissibility screen failed|",
            "The plug-in inference Jacobian is singular or non-finite|",
            "The plug-in GMM bread matrix could not be inverted|",
            "The exactly identified inference Jacobian could not be inverted|",
            "The plug-in asymptotic covariance has a non-positive diagonal"
          ),
          message_text
        )
        if (
          !redrawable_design_error &&
            !redrawable_formal_numerical_error
        ) {
          stop(
            paste0(
              "Formal-outcome simulation or estimation failure. ",
              "The draw is not silently replaced because doing so can ",
              "distort coverage: ",
              message_text
            ),
            call. = FALSE
          )
        }
        list(
          accepted = FALSE,
          reason = message_text,
          rejection_type = if (redrawable_formal_numerical_error) {
            "formal_numerical"
          } else {
            "preformal_design_or_pilot"
          }
        )
      }
    )
    if (isTRUE(candidate$accepted)) {
      accepted <- TRUE
      candidate$replication[[
        "formal_numerical_rejections_before_acceptance"
      ]] <- formal_numerical_rejections
      candidate$diagnostic[[
        "formal_numerical_rejections_before_acceptance"
      ]] <- formal_numerical_rejections
      candidate$replication[[
        "formal_numerical_rejection_history"
      ]] <- paste(formal_numerical_rejection_history, collapse = " || ")
      candidate$diagnostic[[
        "formal_numerical_rejection_history"
      ]] <- paste(formal_numerical_rejection_history, collapse = " || ")
      if (draw_attempt > 1L) {
        message(sprintf(
          paste0(
            "Block accepted after %d attempts (%d formal numerical ",
            "rejection(s)): ",
            "network=%s, N=%d, ",
            "replication=%d."
          ),
          draw_attempt,
          formal_numerical_rejections,
          mechanism,
          n,
          replication
        ))
      }
      return(candidate)
    }
    if (identical(candidate$rejection_type, "formal_numerical")) {
      formal_numerical_rejections <- formal_numerical_rejections + 1L
      formal_numerical_rejection_history <- c(
        formal_numerical_rejection_history,
        candidate$reason
      )
    }
    last_rejection <- candidate$reason
    message(sprintf(
      paste0(
        "Discarded proposal %d/%d [%s]: ",
        "network=%s, N=%d, ",
        "replication=%d. Reason: %s."
      ),
      draw_attempt,
      cfg$max_resample_attempts,
      candidate$rejection_type,
      mechanism,
      n,
      replication,
      last_rejection
    ))
  }

  if (!accepted) {
    stop(sprintf(
      paste0(
        "No admissible draw after %d attempts for network=%s, N=%d, ",
        "replication=%d. Last rejection: %s."
      ),
      cfg$max_resample_attempts,
      mechanism,
      n,
      replication,
      last_rejection
    ))
  }
}

run_simulation_job_safely <- function(job, cfg = CFG) {
  tryCatch(
    list(
      ok = TRUE,
      job_index = as.integer(job$job_index),
      value = run_simulation_job(job, cfg)
    ),
    error = function(err) {
      list(
        ok = FALSE,
        job_index = as.integer(job$job_index),
        label = sprintf(
          "network=%s, N=%d, replication=%d",
          as.character(job$network),
          as.integer(job$N),
          as.integer(job$replication)
        ),
        error = conditionMessage(err)
      )
    }
  )
}

run_jobs <- function(jobs, cfg = CFG) {
  number_of_jobs <- nrow(jobs)
  job_list <- lapply(seq_len(number_of_jobs), function(index) {
    list(
      job_index = index,
      total_jobs = number_of_jobs,
      network = as.character(jobs$network[index]),
      N = as.integer(jobs$N[index]),
      replication = as.integer(jobs$replication[index])
    )
  })
  workers <- choose_parallel_workers(cfg, number_of_jobs)
  backend <- resolve_parallel_backend(cfg, workers)
  available <- detect_available_cores()
  message(sprintf(
    paste0(
      "Starting %d independent jobs with %d worker process(es) ",
      "using backend='%s' (%d available logical cores; target %.0f%%)."
    ),
    number_of_jobs,
    workers,
    backend,
    available,
    100 * cfg$parallel_fraction
  ))

  set_single_thread_math()
  chunk_size <- choose_block_chunk_size(cfg, number_of_jobs)
  if (
    identical(backend, "psock") &&
      isTRUE(cfg$parallel_progress) &&
      isTRUE(cfg$progress_every_block)
  ) {
    # A one-block scheduler chunk is required for genuinely immediate
    # block-level completion output.
    chunk_size <- 1L
  }
  job_chunks <- make_job_chunks(job_list, chunk_size)
  message(sprintf(
    paste0(
      "Scheduler uses %d chunk(s), up to %d block(s) per chunk; ",
      "each block contains %d z-scenarios.  The default one-block ",
      "chunks give fine-grained progress and load balancing."
    ),
    length(job_chunks),
    chunk_size,
    length(cfg$z_values)
  ))

  progress_specification <- list(enabled = FALSE)
  on.exit(remove_progress_state(progress_specification), add = TRUE)
  chunk_results <- if (identical(backend, "sequential")) {
    progress_specification <- initialize_progress_state(
      total_blocks = number_of_jobs,
      z_count = length(cfg$z_values),
      width = cfg$progress_bar_width,
      target_updates = if (isTRUE(cfg$progress_every_block)) {
        number_of_jobs
      } else {
        cfg$progress_target_updates
      },
      enabled = cfg$parallel_progress
    )
    lapply(
      job_chunks,
      run_simulation_chunk_safely,
      cfg = cfg,
      progress_specification = progress_specification
    )
  } else if (identical(backend, "multicore")) {
    progress_specification <- initialize_progress_state(
      total_blocks = number_of_jobs,
      z_count = length(cfg$z_values),
      width = cfg$progress_bar_width,
      target_updates = if (isTRUE(cfg$progress_every_block)) {
        number_of_jobs
      } else {
        cfg$progress_target_updates
      },
      enabled = cfg$parallel_progress
    )
    parallel::mclapply(
      job_chunks,
      run_simulation_chunk_safely,
      cfg = cfg,
      progress_specification = progress_specification,
      mc.cores = workers,
      mc.preschedule = cfg$parallel_preschedule,
      mc.set.seed = FALSE,
      mc.silent = !cfg$parallel_progress,
      mc.cleanup = TRUE,
      mc.allow.recursive = FALSE
    )
  } else if (identical(backend, "psock")) {
    # Worker stdout is deliberately not used for progress.  RStudio and
    # Windows PSOCK can buffer it indefinitely.  The main process receives
    # each completed task, prints one line immediately for that block, and
    # prints an additional line whenever all nine blocks for a replication
    # have completed.
    cluster <- parallel::makeCluster(workers, type = "PSOCK")
    on.exit(parallel::stopCluster(cluster), add = TRUE)

    global_names <- ls(envir = .GlobalEnv, all.names = TRUE)
    function_names <- global_names[vapply(
      global_names,
      function(name) is.function(get(name, envir = .GlobalEnv)),
      logical(1L)
    )]
    parallel::clusterExport(
      cluster,
      varlist = function_names,
      envir = .GlobalEnv
    )
    worker_pids <- unlist(parallel::clusterCall(
      cluster,
      function(runtime_cfg) {
        assign("CFG", runtime_cfg, envir = .GlobalEnv)
        options(stringsAsFactors = FALSE)
        Sys.setenv(
          OMP_NUM_THREADS = "1",
          OPENBLAS_NUM_THREADS = "1",
          MKL_NUM_THREADS = "1",
          VECLIB_MAXIMUM_THREADS = "1",
          BLIS_NUM_THREADS = "1"
        )
        if (!requireNamespace("Matrix", quietly = TRUE)) {
          stop("Package 'Matrix' is required on every PSOCK worker.")
        }
        if (!requireNamespace("igraph", quietly = TRUE)) {
          stop("Package 'igraph' is required on every PSOCK worker.")
        }
        Sys.getpid()
      },
      cfg
    ))
    message(sprintf(
      "All %d PSOCK workers are ready (distinct worker PIDs: %d).",
      length(worker_pids),
      length(unique(worker_pids))
    ))

    message(
      paste0(
        "Main-process PSOCK dispatcher is active at block resolution; ",
        "completion output does not depend on worker-console flushing."
      )
    )
    psock_dynamic_apply_with_master_progress(
      cluster = cluster,
      job_chunks = job_chunks,
      cfg = cfg
    )
  } else {
    stop("Unknown parallel backend: ", backend)
  }
  raw_results <- unlist(
    chunk_results,
    recursive = FALSE,
    use.names = FALSE
  )

  malformed <- vapply(raw_results, function(one) {
    !is.list(one) ||
      is.null(one$ok) ||
      is.null(one$job_index)
  }, logical(1L))
  if (any(malformed)) {
    stop(
      "At least one worker terminated without returning a valid result.",
      call. = FALSE
    )
  }
  failed <- !vapply(raw_results, function(one) {
    isTRUE(one$ok)
  }, logical(1L))
  if (any(failed)) {
    failures <- raw_results[failed]
    details <- vapply(
      failures[seq_len(min(5L, length(failures)))],
      function(one) paste0(one$label, ": ", one$error),
      character(1L)
    )
    stop(
      paste0(
        sum(failed),
        " simulation job(s) failed. First failure(s):\n",
        paste(details, collapse = "\n")
      ),
      call. = FALSE
    )
  }

  results <- vector("list", number_of_jobs)
  for (one in raw_results) {
    results[[one$job_index]] <- one$value
  }
  message(sprintf(
    "Completed all %d jobs; assembling Monte Carlo outputs.",
    number_of_jobs
  ))
  results
}

run_internal_unit_tests <- function(cfg = CFG) {
  values <- matrix(c(-1.0, 0.2, 1.4, 2.0), nrow = 1L)
  representation <- linear_quantile_slope_jumps(values, 4L)

  evaluate_one <- function(z, tau) {
    basis <- gaussian_linear_hinge(
      representation$breaks,
      z,
      tau
    )
    c(
      q = representation$intercept +
        as.numeric(representation$jumps %*% basis$value),
      dq = as.numeric(
        representation$jumps %*% basis$derivative
      ),
      ddq = as.numeric(
        representation$jumps %*% basis$second_derivative
      )
    )
  }

  z_test <- 0.43
  tau_test <- 0.08
  epsilon <- 1e-5
  center <- evaluate_one(z_test, tau_test)
  plus <- evaluate_one(z_test + epsilon, tau_test)
  minus <- evaluate_one(z_test - epsilon, tau_test)
  numerical_dq <- (plus["q"] - minus["q"]) / (2 * epsilon)
  numerical_ddq <- (plus["dq"] - minus["dq"]) / (2 * epsilon)
  stopifnot(
    abs(center["dq"] - numerical_dq) < 2e-5,
    abs(center["ddq"] - numerical_ddq) < 2e-4
  )

  ell <- 1 + 3 * z_test
  lower <- floor(ell)
  alpha <- ell - lower
  unsmoothed <- (1 - alpha) * values[1L, lower] +
    alpha * values[1L, lower + 1L]
  unsmoothed_group <- list(list(
    nodes = 1L,
    degree = 4L,
    values = values
  ))
  unsmoothed_direct <- interpolated_peer_quantile(
    unsmoothed_group, z_test, 1L
  )$q
  stopifnot(
    abs(evaluate_one(z_test, 1e-5)["q"] - unsmoothed) < 1e-7,
    abs(unsmoothed_direct - unsmoothed) < 1e-12
  )

  constant_values <- matrix(rep(2.5, 5L), nrow = 1L)
  constant_representation <- linear_quantile_slope_jumps(
    constant_values,
    5L
  )
  constant_basis <- gaussian_linear_hinge(
    constant_representation$breaks,
    0.37,
    0.09
  )
  stopifnot(
    abs(
      constant_representation$intercept +
        as.numeric(
          constant_representation$jumps %*%
            constant_basis$value
        ) -
        2.5
    ) < 1e-12,
    abs(as.numeric(
      constant_representation$jumps %*%
        constant_basis$derivative
    )) < 1e-12,
    abs(as.numeric(
      constant_representation$jumps %*%
        constant_basis$second_derivative
    )) < 1e-12
  )

  peer_test <- peer_interpolated_quantile(
    c(1, 3, 7, 9),
    list(1:4),
    0.5
  )
  stopifnot(abs(peer_test - 5) < 1e-12)

  profile_test_grid <- seq(0.1, 0.9, by = 0.1)
  profile_test_objective <- c(4, 1, 3, 0.5, 3, 0.8, 3, 2, 4)
  profile_test_local <- profile_local_minimum_indices(
    profile_test_objective
  )
  profile_test_candidates <- select_separated_profile_minima(
    local_indices = profile_test_local,
    objective = profile_test_objective,
    z_grid = profile_test_grid,
    max_candidates = 3L,
    min_separation = 0.08
  )
  profile_test_basin <- profile_basin_bounds(
    local_index = 4L,
    all_local_indices = profile_test_local,
    objective = profile_test_objective,
    z_grid = profile_test_grid,
    z_bounds = c(0.1, 0.9)
  )
  profile_test_refined <- refine_profile_basin(
    profile_function = function(z) {
      list(objective = (z - 0.41)^2)
    },
    lower = profile_test_basin["lower"],
    upper = profile_test_basin["upper"],
    center = profile_test_grid[4L],
    cfg = cfg
  )
  profile_test_tie_cfg <- cfg
  profile_test_tie_cfg$profile_selection_rel_tolerance <- 0
  profile_test_tie <- choose_profile_candidate(
    data.frame(
      candidate_rank = 1:2,
      selection_score = c(1e-4 + 5e-9, 1e-4),
      boundary_margin = c(0.20, 0.10)
    ),
    profile_test_tie_cfg
  )
  profile_test_no_tie <- choose_profile_candidate(
    data.frame(
      candidate_rank = 1:2,
      selection_score = c(1e-4 + 2e-8, 1e-4),
      boundary_margin = c(0.20, 0.10)
    ),
    profile_test_tie_cfg
  )
  stopifnot(
    identical(profile_test_local, c(2L, 4L, 6L, 8L)),
    identical(profile_test_candidates, c(4L, 6L, 2L)),
    isTRUE(all.equal(
      unname(profile_test_basin),
      c(0.3, 0.5),
      tolerance = 1e-12
    )),
    abs(profile_test_refined$z - 0.41) <
      5 * cfg$profile_optimizer_tolerance,
    identical(
      profile_local_minimum_indices(c(4, 1, 1, 1, 4)),
      3L
    ),
    profile_test_tie$selected_index == 1L,
    profile_test_tie$tie_count == 2L,
    profile_test_no_tie$selected_index == 2L,
    profile_test_no_tie$tie_count == 1L
  )

  for (mechanism in cfg$network_types) {
    degree_base <- unname(cfg$degree_base[mechanism])
    degree_power <- unname(cfg$degree_power[mechanism])
    target_degree <- degree_base * (cfg$N / 1000)^degree_power
    tau <- vapply(seq_along(cfg$N), function(k) {
      tau_value(
        cfg$N[k],
        target_degree[k],
        target_degree[k],
        cfg
      )
    }, numeric(1L))
    effective_instrument_knots <- 2 * tau * target_degree
    instrument_lower_rate <- cfg$N^(1 / 4) * tau
    stopifnot(
      all(diff(effective_instrument_knots) > -1e-10),
      all(diff(instrument_lower_rate) > -1e-10)
    )
  }

  set.seed(7301)
  n_graph_test <- 200L
  dyad_test <- generate_network(n_graph_test, "Dyad", cfg)
  stopifnot(
    isTRUE(all.equal(
      dyad_test$A,
      Matrix::t(dyad_test$A),
      check.attributes = FALSE
    )),
    min(dyad_test$degree) > 0,
    abs(
      dyad_test$dyad_probability -
        dyad_test$target_degree / (n_graph_test - 1)
    ) < 1e-10,
    !dyad_test$directed,
    all(is.na(dyad_test$block))
  )

  sbm_test <- generate_network(n_graph_test, "SBM", cfg)
  stopifnot(
    isTRUE(all.equal(
      sbm_test$A,
      Matrix::t(sbm_test$A),
      check.attributes = FALSE
    )),
    sbm_test$p_in > sbm_test$p_out,
    abs(sbm_test$p_in / sbm_test$p_out -
      cfg$sbm_in_out_ratio) < 1e-10,
    !sbm_test$directed,
    identical(as.integer(sort(table(sbm_test$block))), c(100L, 100L))
  )

  powerlaw_test <- generate_network(n_graph_test, "PowerLaw", cfg)
  minimum_powerlaw_degree <- ceiling(
    cfg$powerlaw_min_degree_base *
      (n_graph_test / 1000)^cfg$powerlaw_min_degree_exponent
  )
  maximum_powerlaw_degree <- floor(
    cfg$powerlaw_max_degree_base *
      (n_graph_test / 1000)^cfg$powerlaw_max_degree_exponent
  )
  stopifnot(
    isTRUE(all.equal(
      powerlaw_test$A,
      Matrix::t(powerlaw_test$A),
      check.attributes = FALSE
    )),
    !powerlaw_test$directed,
    min(powerlaw_test$degree) >= minimum_powerlaw_degree,
    max(powerlaw_test$degree) <= maximum_powerlaw_degree,
    identical(
      as.integer(powerlaw_test$degree),
      as.integer(powerlaw_test$drawn_degree)
    ),
    all(is.na(powerlaw_test$block))
  )

  x_test <- NULL
  x_test_condition <- Inf
  x_test_eigen_min <- -Inf
  for (attempt in seq_len(cfg$design_attempts)) {
    candidate_X <- make_X_candidate(dyad_test, cfg)
    candidate_eigenvalues <- eigen(
      crossprod(candidate_X) / nrow(candidate_X),
      symmetric = TRUE,
      only.values = TRUE
    )$values
    candidate_eigen_min <- min(candidate_eigenvalues)
    candidate_condition <- max(candidate_eigenvalues) /
      max(candidate_eigen_min, .Machine$double.eps)
    if (
      is.finite(candidate_condition) &&
        candidate_condition <= cfg$x_condition_max &&
        is.finite(candidate_eigen_min) &&
        candidate_eigen_min >= cfg$x_gram_eigen_min
    ) {
      x_test <- candidate_X
      x_test_condition <- candidate_condition
      x_test_eigen_min <- candidate_eigen_min
      break
    }
  }
  if (is.null(x_test)) {
    stop(
      paste0(
        "The internal A-dependent X test found no ",
        "well-conditioned candidate."
      )
    )
  }
  x_gram <- crossprod(x_test) / nrow(x_test)
  stopifnot(
    ncol(x_test) == 2L,
    max(abs(colMeans(x_test))) < 0.25,
    max(abs(diag(x_gram) - 1)) < 0.50,
    is.finite(x_test_condition),
    x_test_condition <= cfg$x_condition_max,
    is.finite(x_test_eigen_min),
    x_test_eigen_min >= cfg$x_gram_eigen_min
  )

  outcome_test_cfg <- cfg
  outcome_test_cfg$z <- 0.5
  set.seed(7302)
  outcome_test <- generate_outcome(
    X = x_test,
    network = dyad_test,
    cfg = outcome_test_cfg
  )
  outcome_validation_test <- validate_generated_outcome(
    outcome = outcome_test,
    X = x_test,
    network = dyad_test,
    cfg = outcome_test_cfg
  )
  stopifnot(
    is.finite(outcome_validation_test$fixed_point_equation_gap),
    outcome_validation_test$fixed_point_equation_gap <=
      outcome_validation_test$fixed_point_equation_tolerance
  )
  set.seed(7303)
  pilot_test <- independent_pilot_identification_screen(
    X = x_test,
    network = dyad_test,
    z_values = cfg$z_values,
    cfg = cfg
  )
  # Reproduce the same four pilot innovation draws and independently verify
  # that the returned mu_hat applies Y_-(z) before averaging.  This guards
  # against accidentally reverting to Y_-{E(epsilon)}.
  set.seed(7303)
  pilot_test_manual_mu <- lapply(
    pilot_test$mu_hat_by_z,
    function(one) matrix(0, nrow(one), ncol(one))
  )
  for (pilot_index in seq_len(cfg$pilot_B)) {
    pilot_test_innovation <- generate_innovation(dyad_test, cfg)
    for (z_index in seq_along(cfg$z_values)) {
      pilot_test_cfg <- cfg
      pilot_test_cfg$z <- cfg$z_values[z_index]
      pilot_test_outcome <- generate_outcome(
        X = x_test,
        network = dyad_test,
        innovation_draw = pilot_test_innovation,
        cfg = pilot_test_cfg
      )
      pilot_test_groups <- make_sorted_peer_groups(
        pilot_test_outcome$y,
        dyad_test$neighbors
      )
      pilot_test_evaluation_z <- c(
        cfg$z_values[z_index],
        pilot_test$candidate_z_by_truth[[z_index]]
      )
      pilot_test_manual_mu[[z_index]] <-
        pilot_test_manual_mu[[z_index]] +
        interpolated_peer_quantile_grid(
          pilot_test_groups,
          pilot_test_evaluation_z,
          nrow(x_test)
        )$q / cfg$pilot_B
    }
  }
  pilot_test_mu0 <- pilot_test$mu_hat_by_z[[1L]][, 1L]
  pilot_test_beta_star <- cfg$beta + cfg$lambda * as.numeric(
    safe_solve(
      crossprod(x_test),
      crossprod(x_test, pilot_test_mu0)
    )
  )
  stopifnot(
    pilot_test$B == 4L,
    length(pilot_test$diagnostics) == length(cfg$z_values),
    length(pilot_test$passed_by_z) == length(cfg$z_values),
    length(pilot_test$jacobian_passed_by_z) ==
      length(cfg$z_values),
    length(pilot_test$secant_passed_by_z) ==
      length(cfg$z_values),
    length(pilot_test$mu_hat_by_z) == length(cfg$z_values),
    all(vapply(seq_along(cfg$z_values), function(z_index) {
      isTRUE(all.equal(
        pilot_test$mu_hat_by_z[[z_index]],
        pilot_test_manual_mu[[z_index]],
        tolerance = 1e-12
      ))
    }, logical(1L))),
    all(vapply(
      pilot_test$mu_hat_by_z,
      function(one) {
        is.matrix(one) &&
          nrow(one) == nrow(x_test) &&
          ncol(one) >= 3L &&
          all(is.finite(one))
      },
      logical(1L)
    )),
    isTRUE(all.equal(
      as.numeric(
        pilot_test$diagnostics[[1L]]$beta_star_hat
      ),
      pilot_test_beta_star,
      tolerance = 1e-10
    )),
    all(is.finite(vapply(
      pilot_test$diagnostics,
      `[[`,
      numeric(1L),
      "smin"
    ))),
    all(is.finite(vapply(
      pilot_test$diagnostics,
      `[[`,
      numeric(1L),
      "scaled_smin"
    ))),
    all(is.finite(vapply(
      pilot_test$diagnostics,
      `[[`,
      numeric(1L),
      "secant_raw_smin"
    ))),
    all(is.finite(vapply(
      pilot_test$diagnostics,
      `[[`,
      numeric(1L),
      "secant_scaled_smin"
    )))
  )

  worker_test_cfg <- cfg
  worker_test_cfg$parallel <- FALSE
  stopifnot(choose_parallel_workers(worker_test_cfg, 10L) == 1L)
  worker_test_cfg$parallel <- TRUE
  worker_test_cfg$parallel_workers <- 2L
  worker_count <- choose_parallel_workers(worker_test_cfg, 10L)
  stopifnot(worker_count >= 1L, worker_count <= 2L)
  stopifnot(
    choose_block_chunk_size(cfg, 4500L) ==
      cfg$parallel_block_chunk_size
  )
  chunk_test <- make_job_chunks(as.list(seq_len(10L)), 3L)
  stopifnot(
    identical(vapply(chunk_test, length, integer(1L)), c(3L, 3L, 3L, 1L)),
    grepl(
      "5/10 blocks",
      render_progress_line(5L, 10L, 3L, 10L, as.numeric(Sys.time()))
    ),
    grepl(
      "15/30 z-scenarios",
      render_progress_line(5L, 10L, 3L, 10L, as.numeric(Sys.time()))
    )
  )
  tracker_test_cfg <- cfg
  tracker_test_cfg$R <- 2L
  tracker_test_cfg$parallel_progress <- FALSE
  tracker_test_jobs <- expand.grid(
    N = tracker_test_cfg$N,
    network = tracker_test_cfg$network_types,
    replication = seq_len(tracker_test_cfg$R),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  tracker_test_list <- lapply(
    seq_len(nrow(tracker_test_jobs)),
    function(index) {
      list(
        replication = as.integer(
          tracker_test_jobs$replication[index]
        )
      )
    }
  )
  tracker_test_chunks <- make_job_chunks(tracker_test_list, 1L)
  tracker_test <- initialize_master_completion_tracker(
    tracker_test_chunks,
    tracker_test_cfg
  )
  for (index in rev(seq_along(tracker_test_chunks))) {
    update_master_completion_tracker(
      tracker_test,
      tracker_test_chunks[[index]],
      tracker_test_cfg
    )
  }
  parallel_namespace <- asNamespace("parallel")
  stopifnot(
    tracker_test$completed_blocks == nrow(tracker_test_jobs),
    tracker_test$completed_replications == tracker_test_cfg$R,
    is.function(get0(
      "sendCall",
      envir = parallel_namespace,
      inherits = FALSE
    )),
    is.function(get0(
      "recvOneResult",
      envir = parallel_namespace,
      inherits = FALSE
    ))
  )

  seed_values <- numeric()
  for (mechanism_id in seq_along(cfg$network_types)) {
    for (n in cfg$N) {
      for (replication in 1:3) {
        for (draw_attempt in 1:2) {
          seed_values <- c(
            seed_values,
            set_simulation_seed(
              cfg,
              mechanism_id,
              n,
              replication,
              draw_attempt
            )
          )
        }
      }
    }
  }
  stopifnot(length(unique(seed_values)) == length(seed_values))

  numerical_test_n <- 1000L
  numerical_test_fit_pass <- list(inference = list(
    standard_error = stats::setNames(
      rep(0.5 * cfg$formal_root_n_se_max / sqrt(numerical_test_n), 4L),
      c("beta1", "beta2", "lambda", "z")
    ),
    jacobian_condition = 0.5 * cfg$formal_jacobian_condition_max
  ))
  numerical_test_fit_se_fail <- numerical_test_fit_pass
  numerical_test_fit_se_fail$inference$standard_error["z"] <-
    1.01 * cfg$formal_root_n_se_max / sqrt(numerical_test_n)
  numerical_test_fit_condition_fail <- numerical_test_fit_pass
  numerical_test_fit_condition_fail$inference$jacobian_condition <-
    1.01 * cfg$formal_jacobian_condition_max
  numerical_test_pass <- formal_numerical_admissibility(
    numerical_test_fit_pass,
    numerical_test_n,
    cfg
  )
  numerical_test_se_fail <- formal_numerical_admissibility(
    numerical_test_fit_se_fail,
    numerical_test_n,
    cfg
  )
  numerical_test_condition_fail <- formal_numerical_admissibility(
    numerical_test_fit_condition_fail,
    numerical_test_n,
    cfg
  )
  stopifnot(
    isTRUE(numerical_test_pass$passed),
    !isTRUE(numerical_test_se_fail$passed),
    !isTRUE(numerical_test_condition_fail$passed),
    identical(
      numerical_test_se_fail$max_root_n_se_parameter,
      "z"
    )
  )

  message(
    paste0(
      "Internal interpolation, derivative, tau-rate, A-dependent X, ",
      "generated-outcome, B=4 expectation/secant/Jacobian pilot, ",
      "doubly smoothed profile multistart, classical-network, progress, ",
      "parallel-worker, seed and formal numerical-screen tests passed."
    )
  )
  invisible(TRUE)
}

run_simulation <- function(cfg = CFG) {
  stopifnot(
    length(cfg$R) == 1L,
    is.numeric(cfg$R),
    is.finite(cfg$R),
    cfg$R >= 1L,
    cfg$R == as.integer(cfg$R),
    cfg$R < 100000L,
    identical(as.integer(cfg$N), c(1000L, 2000L, 3000L)),
    identical(
      as.character(cfg$network_types),
      c("Dyad", "SBM", "PowerLaw")
    ),
    isTRUE(all.equal(
      as.numeric(cfg$z_values),
      c(0.30, 0.50, 0.70)
    )),
    all(cfg$z_values > cfg$z_bounds[1L]),
    all(cfg$z_values < cfg$z_bounds[2L]),
    length(cfg$confidence_level) == 1L,
    is.numeric(cfg$confidence_level),
    is.finite(cfg$confidence_level),
    cfg$confidence_level > 0,
    cfg$confidence_level < 1,
    length(cfg$coverage_mc_band_level) == 1L,
    is.numeric(cfg$coverage_mc_band_level),
    is.finite(cfg$coverage_mc_band_level),
    cfg$coverage_mc_band_level > 0,
    cfg$coverage_mc_band_level < 1,
    all(cfg$degree_power < 1 / 2),
    all(cfg$max_degree_power < 1 / 2),
    all(cfg$max_degree_power >= cfg$degree_power),
    length(cfg$h_y_base) == 1L,
    is.numeric(cfg$h_y_base),
    is.finite(cfg$h_y_base),
    cfg$h_y_base > 0,
    is.finite(cfg$h_y_exponent),
    cfg$h_y_exponent > 1 / 4,
    all(cfg$degree_power > cfg$h_y_exponent),
    is.finite(cfg$h_y_degree_power),
    cfg$h_y_degree_power >= 0,
    length(cfg$h_y_limits) == 2L,
    all(is.finite(cfg$h_y_limits)),
    cfg$h_y_limits[1L] > 0,
    cfg$h_y_limits[2L] > cfg$h_y_limits[1L],
    length(cfg$tau_base) == 1L,
    is.numeric(cfg$tau_base),
    is.finite(cfg$tau_base),
    cfg$tau_base > 0,
    cfg$tau_exponent > 0,
    cfg$tau_exponent < 1 / 4,
    cfg$tau_degree_power >= 0,
    length(cfg$tau_limits) == 2L,
    all(is.finite(cfg$tau_limits)),
    cfg$tau_limits[1L] > 0,
    cfg$tau_limits[2L] > cfg$tau_limits[1L],
    length(cfg$x_network_strength) == 1L,
    is.numeric(cfg$x_network_strength),
    is.finite(cfg$x_network_strength),
    cfg$x_network_strength > 0,
    length(cfg$x_gram_eigen_min) == 1L,
    is.numeric(cfg$x_gram_eigen_min),
    is.finite(cfg$x_gram_eigen_min),
    cfg$x_gram_eigen_min > 0,
    length(cfg$x_condition_max) == 1L,
    is.numeric(cfg$x_condition_max),
    is.finite(cfg$x_condition_max),
    cfg$x_condition_max > 1,
    all(cfg$min_degree_fraction > 0),
    all(cfg$min_degree_fraction < 1),
    identical(cfg$dyad_sampling, "bernoulli"),
    is.finite(cfg$sbm_in_out_ratio),
    cfg$sbm_in_out_ratio > 1,
    is.finite(cfg$powerlaw_exponent),
    cfg$powerlaw_exponent > 1,
    is.finite(cfg$powerlaw_min_degree_base),
    cfg$powerlaw_min_degree_base >= 2,
    is.finite(cfg$powerlaw_min_degree_exponent),
    cfg$powerlaw_min_degree_exponent > 0,
    cfg$powerlaw_min_degree_exponent < 1 / 2,
    is.finite(cfg$powerlaw_max_degree_base),
    cfg$powerlaw_max_degree_base > cfg$powerlaw_min_degree_base,
    is.finite(cfg$powerlaw_max_degree_exponent),
    cfg$powerlaw_max_degree_exponent >=
      cfg$powerlaw_min_degree_exponent,
    cfg$powerlaw_max_degree_exponent < 1 / 2,
    identical(cfg$powerlaw_graph_method, "vl"),
    length(cfg$network_attempts) == 1L,
    is.numeric(cfg$network_attempts),
    is.finite(cfg$network_attempts),
    cfg$network_attempts >= 1L,
    cfg$network_attempts == as.integer(cfg$network_attempts),
    length(cfg$identification_safety_factor) == 1L,
    is.numeric(cfg$identification_safety_factor),
    is.finite(cfg$identification_safety_factor),
    cfg$identification_safety_factor >= 1,
    all(cfg$design_raw_smin_min > 0),
    all(cfg$design_scaled_smin_min > 0),
    all(cfg$design_max_abs_correlation > 0),
    all(cfg$design_max_abs_correlation < 1),
    all(is.finite(cfg$design_z_offsets)),
    any(abs(cfg$design_z_offsets) < 1e-12),
    all(is.finite(cfg$pilot_secant_z_offsets)),
    length(cfg$pilot_secant_z_offsets) >= 2L,
    all(abs(cfg$pilot_secant_z_offsets) > 1e-12),
    any(cfg$pilot_secant_z_offsets < 0),
    any(cfg$pilot_secant_z_offsets > 0),
    all(is.finite(cfg$pilot_secant_lambda_offsets)),
    length(cfg$pilot_secant_lambda_offsets) >= 2L,
    any(abs(cfg$pilot_secant_lambda_offsets) < 1e-12),
    any(cfg$pilot_secant_lambda_offsets < 0),
    any(cfg$pilot_secant_lambda_offsets > 0),
    length(cfg$pilot_secant_raw_smin_min) == 1L,
    is.numeric(cfg$pilot_secant_raw_smin_min),
    is.finite(cfg$pilot_secant_raw_smin_min),
    cfg$pilot_secant_raw_smin_min > 0,
    length(cfg$pilot_secant_scaled_smin_min) == 1L,
    is.numeric(cfg$pilot_secant_scaled_smin_min),
    is.finite(cfg$pilot_secant_scaled_smin_min),
    cfg$pilot_secant_scaled_smin_min > 0,
    length(cfg$pilot_B) == 1L,
    is.numeric(cfg$pilot_B),
    is.finite(cfg$pilot_B),
    identical(as.integer(cfg$pilot_B), 4L),
    cfg$pilot_B > 1L,
    cfg$pilot_B == as.integer(cfg$pilot_B),
    length(cfg$pilot_jacobian_smin_min) == 1L,
    is.numeric(cfg$pilot_jacobian_smin_min),
    is.finite(cfg$pilot_jacobian_smin_min),
    cfg$pilot_jacobian_smin_min > 0,
    length(cfg$pilot_jacobian_scaled_smin_min) == 1L,
    is.numeric(cfg$pilot_jacobian_scaled_smin_min),
    is.finite(cfg$pilot_jacobian_scaled_smin_min),
    cfg$pilot_jacobian_scaled_smin_min > 0,
    length(cfg$beta) == 2L,
    is.numeric(cfg$innovation_sd),
    length(cfg$innovation_sd) == 1L,
    is.finite(cfg$innovation_sd),
    cfg$innovation_sd > 0,
    length(cfg$post_outcome_screen_action) == 1L,
    identical(cfg$post_outcome_screen_action, "diagnose_only"),
    length(cfg$formal_numerical_retry) == 1L,
    is.logical(cfg$formal_numerical_retry),
    isTRUE(cfg$formal_numerical_retry),
    length(cfg$formal_root_n_se_max) == 1L,
    is.numeric(cfg$formal_root_n_se_max),
    is.finite(cfg$formal_root_n_se_max),
    cfg$formal_root_n_se_max > 0,
    length(cfg$formal_jacobian_condition_max) == 1L,
    is.numeric(cfg$formal_jacobian_condition_max),
    is.finite(cfg$formal_jacobian_condition_max),
    cfg$formal_jacobian_condition_max > 1,
    length(cfg$max_resample_attempts) == 1L,
    is.numeric(cfg$max_resample_attempts),
    is.finite(cfg$max_resample_attempts),
    cfg$max_resample_attempts >= 1L,
    cfg$max_resample_attempts == as.integer(cfg$max_resample_attempts),
    cfg$max_resample_attempts < 1000L,
    length(cfg$z_grid_size) == 1L,
    is.numeric(cfg$z_grid_size),
    is.finite(cfg$z_grid_size),
    cfg$z_grid_size >= 11L,
    cfg$z_grid_size == as.integer(cfg$z_grid_size),
    length(cfg$profile_max_candidates) == 1L,
    is.numeric(cfg$profile_max_candidates),
    is.finite(cfg$profile_max_candidates),
    cfg$profile_max_candidates >= 1L,
    cfg$profile_max_candidates <= cfg$z_grid_size,
    cfg$profile_max_candidates ==
      as.integer(cfg$profile_max_candidates),
    length(cfg$profile_min_separation) == 1L,
    is.numeric(cfg$profile_min_separation),
    is.finite(cfg$profile_min_separation),
    cfg$profile_min_separation > 0,
    cfg$profile_min_separation < diff(cfg$z_bounds),
    length(cfg$profile_selection_abs_tolerance) == 1L,
    is.numeric(cfg$profile_selection_abs_tolerance),
    is.finite(cfg$profile_selection_abs_tolerance),
    cfg$profile_selection_abs_tolerance >= 0,
    length(cfg$profile_selection_rel_tolerance) == 1L,
    is.numeric(cfg$profile_selection_rel_tolerance),
    is.finite(cfg$profile_selection_rel_tolerance),
    cfg$profile_selection_rel_tolerance >= 0,
    length(cfg$profile_optimizer_tolerance) == 1L,
    is.numeric(cfg$profile_optimizer_tolerance),
    is.finite(cfg$profile_optimizer_tolerance),
    cfg$profile_optimizer_tolerance > 0,
    length(cfg$profile_basin_hit_tolerance) == 1L,
    is.numeric(cfg$profile_basin_hit_tolerance),
    is.finite(cfg$profile_basin_hit_tolerance),
    cfg$profile_basin_hit_tolerance > 0,
    length(cfg$jacobian_z_step) == 1L,
    is.numeric(cfg$jacobian_z_step),
    is.finite(cfg$jacobian_z_step),
    cfg$jacobian_z_step > 0,
    cfg$jacobian_z_step < min(cfg$z_bounds[1L], 1 - cfg$z_bounds[2L]),
    cfg$gmm_max_iterations >= 1L,
    cfg$gmm_max_iterations == as.integer(cfg$gmm_max_iterations),
    cfg$gmm_parameter_tolerance > 0,
    cfg$weighting %in% c("iid", "network"),
    cfg$score_covariance %in% c("iid_robust", "homoskedastic"),
    length(cfg$run_internal_tests) == 1L,
    is.logical(cfg$run_internal_tests),
    length(cfg$parallel) == 1L,
    is.logical(cfg$parallel),
    length(cfg$parallel_fraction) == 1L,
    is.numeric(cfg$parallel_fraction),
    is.finite(cfg$parallel_fraction),
    cfg$parallel_fraction > 0,
    cfg$parallel_fraction <= 1,
    is.null(cfg$parallel_workers) || (
      length(cfg$parallel_workers) == 1L &&
        is.numeric(cfg$parallel_workers) &&
        is.finite(cfg$parallel_workers) &&
        cfg$parallel_workers >= 1L &&
        cfg$parallel_workers == as.integer(cfg$parallel_workers)
    ),
    length(cfg$parallel_backend) == 1L,
    cfg$parallel_backend %in%
      c("auto", "multicore", "psock", "sequential"),
    length(cfg$parallel_preschedule) == 1L,
    is.logical(cfg$parallel_preschedule),
    length(cfg$parallel_block_chunk_size) == 1L,
    is.numeric(cfg$parallel_block_chunk_size),
    is.finite(cfg$parallel_block_chunk_size),
    cfg$parallel_block_chunk_size >= 1L,
    cfg$parallel_block_chunk_size ==
      as.integer(cfg$parallel_block_chunk_size),
    length(cfg$parallel_progress) == 1L,
    is.logical(cfg$parallel_progress),
    length(cfg$progress_every_block) == 1L,
    is.logical(cfg$progress_every_block),
    length(cfg$progress_target_updates) == 1L,
    is.numeric(cfg$progress_target_updates),
    is.finite(cfg$progress_target_updates),
    cfg$progress_target_updates >= 1L,
    cfg$progress_target_updates ==
      as.integer(cfg$progress_target_updates),
    length(cfg$progress_bar_width) == 1L,
    is.numeric(cfg$progress_bar_width),
    is.finite(cfg$progress_bar_width),
    cfg$progress_bar_width >= 10L,
    cfg$progress_bar_width <= 100L,
    cfg$progress_bar_width == as.integer(cfg$progress_bar_width),
    cfg$lambda > 0,
    cfg$lambda < 1
  )

  jobs <- expand.grid(
    N = cfg$N,
    network = cfg$network_types,
    replication = seq_len(cfg$R),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  message(
    paste0(
      "Truth-based post-outcome Jacobian checks remain diagnostic only.  ",
      "A/X proposals that fail the deterministic instrument screen or the ",
      "independent B=", cfg$pilot_B,
      " expectation/Jacobian/Assumption-3 secant screen are redrawn.  ",
      "After estimation, the fixed numerical-admissibility rule redraws ",
      "the whole three-z_0 block when max_j sqrt(N)*SE_j > ",
      format(cfg$formal_root_n_se_max),
      " or the inference Jacobian condition number > ",
      format(cfg$formal_jacobian_condition_max),
      ".  Reported coverage is conditional on passing this rule."
    )
  )
  message(sprintf(
    paste0(
      "Pre-formal identification thresholds use safety factor %.2f: ",
      "Q_X minimum eigenvalue %.4f; design raw/scaled minima ",
      "%.4f/%.4f; pilot Jacobian raw/scaled minima %.4f/%.4f; pilot ",
      "Assumption-3 secant raw/scaled minima %.4f/%.4f.  Truth-based ",
      "formal-sample warning cutoffs remain %.4f/%.4f and do not trigger ",
      "redraws."
    ),
    cfg$identification_safety_factor,
    cfg$x_gram_eigen_min,
    min(cfg$design_raw_smin_min),
    min(cfg$design_scaled_smin_min),
    cfg$pilot_jacobian_smin_min,
    cfg$pilot_jacobian_scaled_smin_min,
    cfg$pilot_secant_raw_smin_min,
    cfg$pilot_secant_scaled_smin_min,
    cfg$assumption3_jacobian_smin_warn,
    cfg$assumption3_scaled_smin_warn
  ))
  message(sprintf(
    paste0(
      "Each block computes %d auxiliary pilot equilibria (%d draws x %d ",
      "z_0 values) before its three formal outcomes.  With PSOCK, the main ",
      "process prints immediately after each whole block returns."
    ),
    cfg$pilot_B * length(cfg$z_values),
    cfg$pilot_B,
    length(cfg$z_values)
  ))
  message(sprintf(
    paste0(
      "Estimator root selection uses h-smoothed structural Y_-(z) and ",
      "tau-smoothed instruments on all %d z-grid points, refines at most ",
      "%d local minima separated by %.3f, ",
      "and compares every candidate with the same identity-weight n*Q_n ",
      "criterion (absolute/relative tie tolerances %.1e/%.1e).  No ",
      "pilot_z is computed or written."
    ),
    cfg$z_grid_size,
    cfg$profile_max_candidates,
    cfg$profile_min_separation,
    cfg$profile_selection_abs_tolerance,
    cfg$profile_selection_rel_tolerance
  ))
  results <- run_jobs(jobs, cfg)

  write_outputs(results, cfg)
}

if (sys.nframe() == 0L) {
  if (isTRUE(CFG$run_internal_tests)) {
    run_internal_unit_tests(CFG)
  }
  run_simulation(CFG)
}
