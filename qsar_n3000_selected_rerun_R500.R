if (
  !requireNamespace("Matrix", quietly = TRUE) ||
    !requireNamespace("igraph", quietly = TRUE)
) {
  stop("Packages 'Matrix' and 'igraph' are required.")
}

options(stringsAsFactors = FALSE)
EEEEE
IDENTIFICATION_SAFETY_FACTOR <- 1.20

CFG <- list(
  N = 3000L,
  R = 500L,
  network_types = c("Dyad", "SBM", "PowerLaw"),
  # Retain the original A/X and pilot diagnostic grid.
  z_values = c(0.30, 0.50, 0.70),
  # Formal estimation is restricted to these four network/z_0 settings.
  rerun_z_values = list(Dyad = 0.70, SBM = c(0.30, 0.50), PowerLaw = 0.30),
  seed = 20261708L,

  # theta_0 = (beta_1, beta_2, lambda, z_0); there is no intercept.
  beta = c(0.90, -0.65),
  lambda = 0.28,
  z = 0.50,  # overwritten inside each z_0 scenario
  innovation_sd = 0.30,
  lambda_bounds = c(0.05, 0.55),
  z_bounds = c(0.10, 0.90),
  confidence_level = 0.95,

  # Dyad and SBM have expected mean degree
  # 64*(N/1000)^0.38.  Power-Law has exact truncated degrees with lower
  # and upper endpoints growing at rates N^0.38 and N^0.44.
  degree_base = c(Dyad = 64, SBM = 64, PowerLaw = 32),
  degree_power = c(Dyad = 0.38, SBM = 0.38, PowerLaw = 0.38),
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
  # pre-error design diagnostics.
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
  tau_base = 0.160,
  tau_exponent = 0.18,
  tau_degree_power = 0.08,
  x_condition_max = 1.60,
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
  # Fixed post-estimation numerical-admissibility rule.  The theoretical
  # standard-error bound is imposed on the root-N scale so that the same
  # constant is used at all three sample sizes.  GMM nonconvergence or either
  # failed check rejects the whole network/N/replication block, including all
  # selected z_0 outcomes in that block.
  formal_numerical_retry = TRUE,
  formal_root_n_se_max = 3.0,
  formal_jacobian_condition_max = 500.0,
  # This retry count covers A/X generation, the independent-pilot screen,
  # GMM nonconvergence and the post-estimation numerical-admissibility screen.
  max_resample_attempts = 200L,

  fixed_point_tolerance = 1e-9,
  fixed_point_max_iterations = 250L,
  z_grid_size = 81L,
  # Global profile selection with h-smoothed structural Y_-(z) and
  # tau-smoothed instruments.  Local minima at the two fixed z-boundaries are
  # included.  In each iteration, candidate minima use the same current-weight
  # criterion and are retained only when they are at least
  # profile_min_separation apart.
  profile_max_candidates = 3L,
  profile_min_separation = 0.08,
  # Candidate comparison uses n*Q_n.  Only candidates within this fixed
  # numerical tolerance of the smallest score are treated as tied.  The
  # tie-break then maximizes the normalized distance from the fixed z and
  # lambda bounds.
  profile_selection_abs_tolerance = 1e-8,
  profile_selection_rel_tolerance = 1e-7,
  profile_optimizer_tolerance = 1e-7,
  # The profile optimizer uses function values only.  This step is used for
  # numerical z-Jacobians in unsmoothed identification diagnostics, so a knot gets
  # the symmetric local slope instead of an arbitrary one-sided derivative.
  jacobian_z_step = 1e-4,
  # Stop when consecutive parameter estimates differ by at most the tolerance.
  # This limit is only a safeguard: reaching it without convergence is an error.
  gmm_max_iterations = 100L,
  gmm_parameter_tolerance = 1e-6,
  ridge = 1e-9,
  # The paper's stated iterated-GMM update uses node-level score outer
  # products.  "network" remains available as a sensitivity option.
  weighting = "iid",  # "iid" or "network"
  score_covariance = "iid_robust",  # or "homoskedastic"
  # Process-level parallelism across independent replication blocks.
  # NULL uses half the available logical cores, rounded down, minimum one.
  # Set parallel_workers to an integer to override the automatic choice.
  parallel = TRUE,
  parallel_workers = NULL,
  # PSOCK keeps a persistent worker pool and gives cross-platform dynamic
  # load balancing.  "auto" is still accepted and resolves to PSOCK.
  parallel_backend = "psock",
  # Used only if "multicore" is selected explicitly.  TRUE avoids creating a
  # fresh fork for every one of the 1500 selected blocks.
  parallel_preschedule = TRUE,
  # One scheduler task is one complete block of the selected z_0 values.
  # Single-block dynamic dispatch is intentionally used because N and network
  # mechanism produce materially different runtimes.
  parallel_block_chunk_size = 1L,
  parallel_progress = TRUE,
  # Print each completed block. PSOCK output comes from the main process.
  progress_every_block = TRUE,
  # Used when progress_every_block is FALSE.
  progress_target_updates = 20L,
  progress_bar_width = 42L,
  # Separate supplemental results and checkpoints from the original run.
  output_dir = "qsar_n3000_selected_rerun_seed20261708",
  # Save each finished block; rerunning resumes the same simulation design.
  resume = TRUE,
  # Retry cached failures while reusing successful blocks.
  retry_failed = TRUE
)

clamp <- function(x, lower, upper) {
  pmin(pmax(x, lower), upper)
}

safe_solve <- function(A, b, ridge = CFG$ridge) {
  if (any(!is.finite(A)) || any(!is.finite(b))) {
    stop("Linear system contains non-finite values.")
  }
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

make_adjacency <- function(n, i, j, directed = FALSE) {
  if (length(i) == 0L) stop("The generated graph has no edges.")
  A <- Matrix::sparseMatrix(
    i = if (directed) i else c(i, j),
    j = if (directed) j else c(j, i),
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
    stop("The Dyad design requires independent dyad sampling.")
  }
  probability <- target_degree / (n - 1)
  if (!is.finite(probability) || probability <= 0 || probability > 2 / 3) {
    stop("The directed Dyad design requires 0 < p_n <= 2/3.")
  }

  # Independent dyads: (1,1), (1,0), (0,1) each have probability p_n/2;
  # (0,0) has probability 1-3*p_n/2.  Each directed edge has marginal p_n.
  # A binomial count and a uniform subset generate the nonempty dyads exactly;
  # their three nonempty states are then equally likely, independently.
  total_dyads <- n * (n - 1) / 2
  dyad_count <- stats::rbinom(1L, size = total_dyads, prob = 1.5 * probability)
  if (dyad_count == 0L) stop("The generated Dyad graph has no edges.")
  pair_id <- sample.int(total_dyads, dyad_count, replace = FALSE)
  ij <- edge_index_to_ij(pair_id)
  state <- sample.int(3L, dyad_count, replace = TRUE)
  forward <- state %in% c(1L, 2L)
  backward <- state %in% c(1L, 3L)
  list(
    A = make_adjacency(
      n,
      c(ij$i[forward], ij$j[backward]),
      c(ij$j[forward], ij$i[backward]),
      directed = TRUE
    ),
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
        directed = identical(mechanism, "Dyad"),
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
  if (any(!is.finite(base))) {
    stop("Generated Y or its innovation contains non-finite values.")
  }

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
    if (any(!is.finite(y_new))) {
      stop("Generated Y or its innovation contains non-finite values.")
    }
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
      length(outcome$innovation) != n
  ) {
    stop("Generated Y or its innovation has the wrong length.", call. = FALSE)
  }
  if (any(!is.finite(outcome$y)) || any(!is.finite(outcome$innovation))) {
    stop("Generated Y or its innovation contains non-finite values.", call. = FALSE)
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
  # Intentional optimization stabilization: omit the two lambda factors and
  # standardize every instrument column at the current z.  Keep this convention
  # throughout the profile objective and its iterated weighting updates.
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
  if (any(!is.finite(coefficient))) stop("GMM returned non-finite parameters.")

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
  if (any(!is.finite(S))) stop("Weight matrix contains non-finite values.")
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
    y, X, outcome_smooth, fitted_smooth, estimate,
    cfg = CFG) {
  # Sandwich inference with raw M(theta).  Sigma_hat uses node-level
  # score outer products as the chosen covariance approximation.
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

  # Working covariance approximation using node-level score outer products.
  # This retains the chosen approximation and does not estimate cross-node
  # score covariances.  Xi (optimization weight) and Sigma (score covariance)
  # have distinct roles in the theorem.
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
  # Independent innovations do not make the smoothed scores independent.
  # The node-level covariance above is deliberately retained as an approximation.
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
  if (any(!is.finite(G_hat))) {
    stop("The plug-in inference Jacobian is singular or non-finite.")
  }
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

  list(
    standard_error = standard_error,
    ci_lower = ci_lower,
    ci_upper = ci_upper,
    jacobian_condition = max(jacobian_singular_values) /
      min(jacobian_singular_values)
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
  if (n_grid < 2L) stop("A profile with at least two grid points is required.")
  if (any(!is.finite(objective))) {
    stop("Profile grid contains a non-finite objective.")
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
  if (length(objective) != length(z_grid)) {
    stop("The profile and z grid have different lengths.")
  }
  if (any(!is.finite(objective))) {
    stop("Profile grid contains a non-finite objective.")
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
    !is.data.frame(candidates) || nrow(candidates) < 1L ||
      !all(c("selection_score", "boundary_margin") %in% names(candidates))
  ) {
    stop("Invalid global profile candidate table.")
  }
  if (any(!is.finite(candidates$selection_score)) ||
      any(!is.finite(candidates$boundary_margin))) {
    stop("Profile candidates contain a non-finite score or boundary margin.")
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
  list(selected_index = selected, tie_count = length(tied))
}

estimate_qsar <- function(y, X, network, cfg = CFG) {
  n <- length(y)
  first_stage <- stats::lm.fit(x = X, y = y)
  fitted <- as.numeric(X %*% first_stage$coefficients)
  outcome_groups <- make_sorted_peer_groups(y, network$neighbors)
  fitted_groups <- make_sorted_peer_groups(fitted, network$neighbors)
  z_grid <- seq(cfg$z_bounds[1L], cfg$z_bounds[2L], length.out = cfg$z_grid_size)
  mean_degree <- mean(network$degree)
  outcome_grid <- smooth_peer_quantile_grid(
    outcome_groups, z_grid, n, mean_degree, cfg, bandwidth_fun = h_value
  )
  fitted_grid <- smooth_peer_quantile_grid(
    fitted_groups, z_grid, n, mean_degree, cfg
  )

  direct_profile <- function(z, W) {
    outcome <- smooth_peer_quantile(
      outcome_groups, z, n, mean_degree, cfg, bandwidth_fun = h_value
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

  # Use the same fixed W for all candidates in one iteration.  After updating
  # W, search the full prescribed z-grid again rather than retaining an old basin.
  minimize_for_weight <- function(W) {
    grid_pass <- evaluate_profile_grid(
      y, X, outcome_grid, fitted_grid, W = W, cfg = cfg
    )
    all_local_indices <- profile_local_minimum_indices(grid_pass$objective)
    candidate_indices <- select_separated_profile_minima(
      all_local_indices, grid_pass$objective, z_grid,
      cfg$profile_max_candidates, cfg$profile_min_separation
    )
    refinements <- vector("list", length(candidate_indices))
    candidate_rows <- vector("list", length(candidate_indices))
    for (rank in seq_along(candidate_indices)) {
      grid_index <- candidate_indices[rank]
      basin <- profile_basin_bounds(
        grid_index, all_local_indices, grid_pass$objective, z_grid, cfg$z_bounds
      )
      refined <- refine_profile_basin(
        profile_function = function(z) direct_profile(z, W),
        lower = basin["lower"], upper = basin["upper"],
        center = z_grid[grid_index], cfg = cfg
      )
      refinements[[rank]] <- refined
      candidate_rows[[rank]] <- data.frame(
        candidate_rank = rank,
        selection_score = n * refined$objective,
        boundary_margin = normalized_parameter_boundary_margin(
          refined$z, unname(tail(refined$profile$coefficient, 1L)), cfg
        )
      )
    }
    candidates <- do.call(rbind, candidate_rows)
    selection <- choose_profile_candidate(candidates, cfg)
    selected <- selection$selected_index
    list(refined = refinements[[selected]])
  }

  W <- diag(ncol(X) + 2L)
  previous_estimate <- NULL
  converged <- FALSE
  parameter_change <- Inf
  for (gmm_iteration in seq_len(cfg$gmm_max_iterations)) {
    optimized <- minimize_for_weight(W)
    final_profile <- optimized$refined$profile
    estimate <- c(
      beta1 = final_profile$coefficient[1L],
      beta2 = final_profile$coefficient[2L],
      lambda = final_profile$coefficient[3L],
      z = optimized$refined$z
    )
    if (any(!is.finite(estimate))) stop("GMM returned non-finite parameters.")
    if (!is.null(previous_estimate)) {
      parameter_change <- max(abs(estimate - previous_estimate))
      if (parameter_change <= cfg$gmm_parameter_tolerance) {
        converged <- TRUE
        break
      }
    }
    if (gmm_iteration < cfg$gmm_max_iterations) {
      previous_estimate <- estimate
      W <- second_step_weight(final_profile, network$A, network$degree, cfg)
    }
  }
  if (!converged) {
    # Report nonconvergence to the caller, which redraws the complete data
    # block under the existing bounded retry procedure.
    stop(sprintf(
      "Iterated GMM did not converge after %d iterations (parameter change %.3g; tolerance %.3g).",
      cfg$gmm_max_iterations, parameter_change, cfg$gmm_parameter_tolerance
    ))
  }

  inference <- theorem_inference(
    y, X, final_profile$outcome_smooth, final_profile$fitted_smooth,
    estimate, cfg
  )
  list(
    estimate = estimate,
    inference = inference,
    gmm_iterations = gmm_iteration,
    gmm_converged = converged,
    gmm_parameter_change = parameter_change
  )
}

jacobian_matrix_diagnostic <- function(J) {
  if (
    !is.matrix(J) ||
      nrow(J) == 0L ||
      ncol(J) == 0L
  ) {
    stop("The Jacobian diagnostic received an invalid matrix.")
  }
  if (any(!is.finite(J))) {
    stop("The Jacobian diagnostic contains non-finite entries.")
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
  selected_z_values <- cfg$rerun_z_values[[mechanism]]
  scenario_results <- vector("list", length(selected_z_values))
  for (z_index in seq_along(selected_z_values)) {
    z0 <- selected_z_values[z_index]
    scenario_cfg <- cfg
    scenario_cfg$z <- z0

    outcome <- generate_outcome(
      X = X,
      network = network,
      innovation_draw = innovation_draw,
      cfg = scenario_cfg
    )
    validate_generated_outcome(
      outcome = outcome,
      X = X,
      network = network,
      cfg = scenario_cfg
    )
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
    row <- data.frame(
      network = mechanism, N = n, z0 = z0, replication = replication,
      resample_attempt = draw_attempt,
      gmm_iterations = fit$gmm_iterations,
      gmm_converged = fit$gmm_converged,
      gmm_parameter_change = fit$gmm_parameter_change,
      status = "success", error = NA_character_,
      formal_numerical_rejections_before_acceptance = NA_integer_
    )
    for (parameter in names(truth)) {
      row[[paste0(parameter, "_hat")]] <- unname(fit$estimate[parameter])
      row[[paste0(parameter, "_se")]] <- unname(fit$inference$standard_error[parameter])
      row[[paste0(parameter, "_ci_lower")]] <- unname(fit$inference$ci_lower[parameter])
      row[[paste0(parameter, "_ci_upper")]] <- unname(fit$inference$ci_upper[parameter])
      row[[paste0(parameter, "_covered")]] <- unname(
        truth[parameter] >= fit$inference$ci_lower[parameter] &
          truth[parameter] <= fit$inference$ci_upper[parameter]
      )
    }
    scenario_results[[z_index]] <- row
  }
  list(accepted = TRUE, replication = do.call(rbind, scenario_results))
}

simulation_output_dir <- function(cfg = CFG) {
  if (is.null(cfg$output_dir)) {
    sprintf("qsar_directedDyad_doubleSmooth_results_R%d", as.integer(cfg$R))
  } else cfg$output_dir
}

failed_replication_rows <- function(job, cfg, error, draw_attempt = NA_integer_) {
  out <- data.frame(
    network = as.character(job$network), N = as.integer(job$N),
    z0 = cfg$rerun_z_values[[as.character(job$network)]],
    replication = as.integer(job$replication),
    resample_attempt = draw_attempt, gmm_iterations = NA_integer_,
    gmm_converged = FALSE, gmm_parameter_change = NA_real_,
    status = "failed", error = as.character(error)
  )
  for (parameter in c("beta1", "beta2", "lambda", "z")) {
    for (suffix in c("hat", "se", "ci_lower", "ci_upper")) {
      out[[paste0(parameter, "_", suffix)]] <- NA_real_
    }
    out[[paste0(parameter, "_covered")]] <- NA
  }
  out$formal_numerical_rejections_before_acceptance <- NA_integer_
  out
}

summarize_results <- function(replications, cfg = CFG) {
  rows <- list()
  for (mechanism in cfg$network_types) {
    for (z0 in cfg$rerun_z_values[[mechanism]]) {
      for (n in cfg$N) {
        keep <- replications$network == mechanism & replications$N == n &
          abs(replications$z0 - z0) < 1e-12
        all_rows <- replications[keep, , drop = FALSE]
        one <- all_rows[all_rows$status == "success", , drop = FALSE]
        count <- nrow(one)
        for (parameter in c("beta1", "beta2", "lambda", "z")) {
          estimate <- one[[paste0(parameter, "_hat")]]
          truth <- switch(parameter, beta1 = cfg$beta[1L], beta2 = cfg$beta[2L],
                          lambda = cfg$lambda, z = z0)
          error <- estimate - truth
          rows[[length(rows) + 1L]] <- data.frame(
            network = mechanism, N = n, z0 = z0, parameter = parameter,
            R = count, R_requested = cfg$R,
            R_failed = sum(all_rows$status == "failed"),
            R_pending = cfg$R - sum(all_rows$status != "pending"),
            truth = truth,
            mean_estimate = if (count) mean(estimate) else NA_real_,
            RMSE = if (count) sqrt(mean(error^2)) else NA_real_,
            Bias = if (count) abs(mean(error)) else NA_real_,
            SE = if (count) sqrt(mean((estimate - mean(estimate))^2)) else NA_real_,
            tSE = if (count) mean(one[[paste0(parameter, "_se")]]) else NA_real_,
            CP = if (count) mean(one[[paste0(parameter, "_covered")]]) else NA_real_
          )
        }
      }
    }
  }
  do.call(rbind, rows)
}

write_outputs <- function(results, cfg = CFG) {
  assign(".qsar_last_results", results, envir = .GlobalEnv)
  assign(".qsar_last_cfg", cfg, envir = .GlobalEnv)
  output_dir <- simulation_output_dir(cfg)
  template <- failed_replication_rows(
    list(network = cfg$network_types[1L], N = 0L, replication = 0L), cfg, ""
  )[FALSE, , drop = FALSE]
  pieces <- lapply(results, function(one) {
    x <- one$replication
    if (is.null(x) || !nrow(x)) return(template)
    if (is.null(x$status)) x$status <- "success"
    if (is.null(x$error)) x$error <- NA_character_
    if (is.null(x$formal_numerical_rejections_before_acceptance)) {
      x$formal_numerical_rejections_before_acceptance <- NA_integer_
    }
    x[, names(template), drop = FALSE]
  })
  replications <- if (length(pieces)) do.call(rbind, pieces) else template
  design <- do.call(rbind, lapply(cfg$network_types, function(mechanism) {
    expand.grid(
      network = mechanism, N = cfg$N,
      z0 = cfg$rerun_z_values[[mechanism]],
      replication = seq_len(cfg$R), KEEP.OUT.ATTRS = FALSE,
      stringsAsFactors = FALSE
    )
  }))
  key <- function(x) paste(x$network, x$N, x$z0, x$replication, sep = ":")
  if (anyDuplicated(key(replications)) ||
      any(!key(replications) %in% key(design))) {
    stop("Result identifiers are duplicated or outside the requested design.")
  }
  missing <- design[!key(design) %in% key(replications), , drop = FALSE]
  if (nrow(missing)) {
    pending <- template[rep(NA_integer_, nrow(missing)), , drop = FALSE]
    pending[, names(missing)] <- missing
    pending$status <- "pending"
    pending$error <- "No completed result is available."
    replications <- rbind(replications, pending)
  }
  success <- replications$status == "success"
  valid <- !is.na(replications$gmm_converged) & replications$gmm_converged &
    is.finite(replications$gmm_parameter_change) &
    replications$gmm_parameter_change <= cfg$gmm_parameter_tolerance
  for (parameter in c("beta1", "beta2", "lambda", "z")) {
    valid <- valid & is.finite(replications[[paste0(parameter, "_hat")]]) &
      is.finite(replications[[paste0(parameter, "_se")]]) &
      replications[[paste0(parameter, "_se")]] > 0 &
      !is.na(replications[[paste0(parameter, "_covered")]])
  }
  invalid <- success & !valid
  if (any(invalid)) {
    replications$status[invalid] <- "failed"
    replications$error[invalid] <- "The returned estimate or standard error failed validation."
  }
  replications <- replications[order(replications$network, replications$N,
                                     replications$z0, replications$replication), ]
  rownames(replications) <- NULL
  summary <- summarize_results(replications, cfg)
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) {
    stop("Could not create output directory: ", output_dir)
  }
  utils::write.csv(replications, file.path(output_dir, "qsar_replications.csv"), row.names = FALSE)
  utils::write.csv(summary, file.path(output_dir, "qsar_summary.csv"), row.names = FALSE)
  print(summary, row.names = FALSE)
  message(sprintf(
    "Saved %d successful, %d failed and %d pending scenario results to: %s",
    sum(replications$status == "success"), sum(replications$status == "failed"),
    sum(replications$status == "pending"), output_dir
  ))
  invisible(list(replications = replications, summary = summary))
}

checkpoint_signature <- function(cfg) {
  ignored <- c("R", "output_dir", "resume", "retry_failed", ".checkpoint_dir",
               "parallel", "parallel_workers", "parallel_backend",
               "parallel_preschedule", "parallel_block_chunk_size",
               "parallel_progress", "progress_every_block",
               "progress_target_updates", "progress_bar_width")
  cfg[sort(setdiff(names(cfg), ignored))]
}

prepare_checkpoints <- function(cfg) {
  directory <- file.path(simulation_output_dir(cfg), "checkpoints")
  if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE)) {
    stop("Could not create checkpoint directory: ", directory)
  }
  directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  manifest <- file.path(directory, "configuration.rds")
  signature <- list(format = 1L, configuration = checkpoint_signature(cfg))
  if (file.exists(manifest)) {
    if (!identical(readRDS(manifest), signature)) {
      stop("Checkpoint settings differ from CFG. Use a different output_dir for a different design.")
    }
  } else saveRDS(signature, manifest)
  cfg$.checkpoint_dir <- directory
  cfg
}

job_checkpoint_path <- function(job, cfg) {
  file.path(cfg$.checkpoint_dir, sprintf("job_%s_N%d_rep%06d.rds",
    as.character(job$network), as.integer(job$N), as.integer(job$replication)))
}

save_job_checkpoint <- function(value, job, cfg) {
  if (is.null(cfg$.checkpoint_dir)) return(invisible(NULL))
  target <- job_checkpoint_path(job, cfg)
  temporary <- tempfile("job_", tmpdir = cfg$.checkpoint_dir, fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(value, temporary, compress = FALSE)
  if (.Platform$OS.type == "windows" && file.exists(target)) unlink(target)
  if (!file.rename(temporary, target)) stop("Could not save checkpoint: ", target)
  invisible(NULL)
}

collect_qsar_results <- function(x, cfg = CFG) {
  if (is.data.frame(x)) {
    needed <- c("network", "N", "z0", "replication", "beta1_hat")
    if (all(needed %in% names(x))) return(list(list(replication = x)))
    return(list())
  }
  if (!is.list(x)) return(list())
  if (is.data.frame(x$replication)) return(list(x))
  if (is.data.frame(x$replications)) return(list(list(replication = x$replications)))
  if (identical(x$ok, FALSE) && !is.null(x$label)) {
    parts <- regmatches(x$label, regexec(
      "network=([^,]+), N=([0-9]+), replication=([0-9]+)", x$label))[[1L]]
    if (length(parts) == 4L) {
      return(list(list(replication = failed_replication_rows(
        list(network = parts[2L], N = as.integer(parts[3L]),
             replication = as.integer(parts[4L])), cfg, x$error))))
    }
  }
  unlist(lapply(x, collect_qsar_results, cfg = cfg), recursive = FALSE)
}

# Export retained objects or saved blocks without rerunning estimation.
recover_qsar_results <- function(results = NULL, cfg = NULL) {
  if (is.null(cfg)) {
    cfg <- if (exists(".qsar_last_cfg", envir = .GlobalEnv, inherits = FALSE)) {
      get(".qsar_last_cfg", envir = .GlobalEnv)
    } else CFG
  }
  recovered <- if (is.null(results)) list() else collect_qsar_results(results, cfg)
  if (is.null(results)) {
    object_names <- c(".qsar_last_results", ".qsar_last_raw_results",
                      "raw_results", "chunk_results", "results")
    environments <- list(.GlobalEnv)
    if (exists("last.dump", envir = .GlobalEnv, inherits = FALSE)) {
      dump <- get("last.dump", envir = .GlobalEnv)
      if (is.list(dump)) environments <- c(environments, Filter(is.environment, dump))
    }
    for (environment in environments) {
      for (name in object_names) {
        if (!exists(name, envir = environment, inherits = FALSE)) next
        candidate <- collect_qsar_results(get(name, envir = environment), cfg)
        if (length(candidate) > length(recovered)) recovered <- candidate
      }
    }
    directory <- file.path(simulation_output_dir(cfg), "checkpoints")
    if (dir.exists(directory)) {
      checked_cfg <- prepare_checkpoints(cfg)
      files <- list.files(directory, pattern = "^job_.*[.]rds$", full.names = TRUE)
      cached <- lapply(files, function(path) tryCatch(readRDS(path), error = function(e) NULL))
      candidate <- collect_qsar_results(cached, checked_cfg)
      if (length(candidate) > length(recovered)) recovered <- candidate
    }
  }
  if (!length(recovered)) {
    stop(paste0("No retained result object or checkpoint was found. ",
      "The old script did not save simulation results before its final error; ",
      "the error message alone cannot reconstruct completed estimates."), call. = FALSE)
  }
  write_outputs(recovered, cfg)
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
    available %/% 2L
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
  # Selected blocks contain different numbers of z scenarios.
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
      "QSAR progress [%s] %d/%d blocks | ",
      "%5.1f%% | elapsed %s | ETA %s | %.2f blocks/min"
    ),
    bar,
    completed_blocks,
    total_blocks,
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
  tracker$print_every <- max(1L, ceiling(tracker$total_blocks / cfg$progress_target_updates))
  tracker$last_printed <- 0L

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

print_master_progress <- function(tracker, cfg) {
  if (!isTRUE(tracker$enabled)) return(invisible(FALSE))
  cat(render_progress_line(
    tracker$completed_blocks, tracker$total_blocks, length(cfg$z_values),
    cfg$progress_bar_width, tracker$start_time
  ))
  cat("\n")
  flush_visible_output()
  tracker$last_printed <- tracker$completed_blocks
  invisible(TRUE)
}

update_master_completion_tracker <- function(
  tracker,
  completed_chunk,
  cfg = CFG
) {
  if (!is.environment(tracker)) {
    stop("The main-process completion tracker is invalid.")
  }

  for (one_job in completed_chunk) {
    replication <- as.integer(one_job$replication)
    tracker$completed_blocks <- tracker$completed_blocks + 1L
    tracker$completed_by_replication[replication] <-
      tracker$completed_by_replication[replication] + 1L
    if (tracker$completed_by_replication[replication] ==
        tracker$expected_by_replication[replication]) {
      tracker$completed_replications <- tracker$completed_replications + 1L
    } else if (tracker$completed_by_replication[replication] >
               tracker$expected_by_replication[replication]) {
      stop("A replication was counted more than once.")
    }
  }
  should_print <- isTRUE(tracker$enabled) && (
    isTRUE(cfg$progress_every_block) || tracker$last_printed == 0L ||
      tracker$completed_blocks == tracker$total_blocks ||
      tracker$completed_blocks - tracker$last_printed >= tracker$print_every
  )
  if (should_print) print_master_progress(tracker, cfg)
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

is_redrawable_numerical_error <- function(err) {
  message_text <- conditionMessage(err)
  # These failures can occur in either pilot calculations or formal estimation.
  if (grepl(paste0(
    "^The DGP fixed point failed to converge|",
    "^Generated Y failed the fixed-point equation check|",
    "^Generated Y or its innovation contains non-finite values|",
    "^Degenerate instrument column|",
    "^Linear system contains non-finite values|",
    "^Weight matrix contains non-finite values|",
    "^The Jacobian diagnostic contains non-finite entries"
  ), message_text)) return(TRUE)

  # Recognize numerical failures from base linear algebra, without treating
  # dimension/type errors or memory allocation failures as reasons to redraw.
  error_call <- conditionCall(err)
  operation <- if (is.call(error_call)) {
    sub("^(base|stats)::", "", paste(deparse(error_call[[1L]]), collapse = ""))
  } else ""
  operation %in% c("solve", "solve.default", "eigen", "svd", "La.svd") &&
    grepl(paste0(
      "system is (computationally |exactly )?singular|",
      "singular matrix|\u5947\u5f02|infinite or missing values in|",
      "error code [1-9][0-9]* from (Lapack|LAPACK|DGESDD|DSYEVR)"
    ), message_text)
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
            "^The generated (Dyad )?graph has no edges|",
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
            "^Iterated GMM did not converge|",
            "^GMM returned non-finite parameters|",
            "^Profile grid contains a non-finite objective|",
            "^Profile refinement produced a non-finite objective|",
            "^Profile candidates contain a non-finite score or boundary margin|",
            "Formal numerical admissibility screen failed|",
            "The plug-in inference Jacobian is singular or non-finite|",
            "The plug-in GMM bread matrix could not be inverted|",
            "The plug-in asymptotic covariance has a non-positive diagonal"
          ),
          message_text
        )
        redrawable_numerical_error <- is_redrawable_numerical_error(err)
        if (
          !redrawable_design_error &&
            !redrawable_formal_numerical_error &&
            !redrawable_numerical_error
        ) {
          stop(
            paste0(
              "Simulation or estimation failed: ",
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
          } else if (redrawable_numerical_error) {
            "numerical"
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
      return(candidate)
    }
    if (identical(candidate$rejection_type, "formal_numerical")) {
      formal_numerical_rejections <- formal_numerical_rejections + 1L
    }
    last_rejection <- candidate$reason

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
  if (!is.null(cfg$.checkpoint_dir) && !identical(cfg$resume, FALSE)) {
    path <- job_checkpoint_path(job, cfg)
    cached <- if (file.exists(path)) {
      tryCatch(readRDS(path), error = function(e) NULL)
    } else NULL
    if (is.list(cached) && !is.null(cached$ok)) {
      complete <- isTRUE(cached$ok) &&
        all(cached$value$replication$status == "success")
      if (complete || !isTRUE(cfg$retry_failed)) {
        cached$job_index <- as.integer(job$job_index)
        return(cached)
      }
    }
  }
  value <- tryCatch(
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
          as.character(job$network), as.integer(job$N), as.integer(job$replication)
        ),
        error = conditionMessage(err)
      )
    }
  )
  tryCatch(save_job_checkpoint(value, job, cfg), error = function(err) {
    warning("Could not save this block; its result remains available in memory: ",
            conditionMessage(err), call. = FALSE)
  })
  value
}

run_jobs <- function(jobs, cfg = CFG) {
  cfg <- prepare_checkpoints(cfg)
  assign(".qsar_last_cfg", cfg, envir = .GlobalEnv)
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
      "using backend='%s' (%d available logical cores)."
    ),
    number_of_jobs,
    workers,
    backend,
    available
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
    # The main process prints periodic progress; worker stdout is not needed.
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

  assign(".qsar_last_raw_results", raw_results, envir = .GlobalEnv)
  results <- vector("list", number_of_jobs)
  for (one in raw_results) {
    if (!is.list(one) || length(one$job_index) != 1L ||
        !is.finite(one$job_index) || one$job_index < 1L ||
        one$job_index > number_of_jobs) next
    index <- as.integer(one$job_index)
    if (isTRUE(one$ok)) {
      results[[index]] <- one$value
    } else {
      results[[index]] <- list(replication = failed_replication_rows(
        job_list[[index]], cfg, one$error
      ))
    }
  }
  for (index in which(vapply(results, is.null, logical(1L)))) {
    results[[index]] <- list(replication = failed_replication_rows(
      job_list[[index]], cfg, "Worker did not return a valid result."
    ))
  }
  assign(".qsar_last_results", results, envir = .GlobalEnv)
  failed <- sum(vapply(results, function(one) {
    sum(one$replication$status == "failed")
  }, integer(1L)))
  message(sprintf(
    "Completed %d jobs with %d failed z scenarios; exporting available estimates.",
    number_of_jobs, failed
  ))
  results
}

run_simulation <- function(cfg = CFG) {
  stopifnot(
    length(cfg$R) == 1L,
    is.numeric(cfg$R),
    is.finite(cfg$R),
    cfg$R >= 1L,
    cfg$R == as.integer(cfg$R),
    cfg$R < 100000L,
    identical(as.integer(cfg$N), 3000L),
    identical(
      as.character(cfg$network_types),
      c("Dyad", "SBM", "PowerLaw")
    ),
    isTRUE(all.equal(
      as.numeric(cfg$z_values),
      c(0.30, 0.50, 0.70)
    )),
    is.list(cfg$rerun_z_values),
    identical(names(cfg$rerun_z_values), cfg$network_types),
    all(vapply(cfg$rerun_z_values, function(z) {
      is.numeric(z) && length(z) > 0L && all(is.finite(z)) &&
        !anyDuplicated(z) && all(z %in% cfg$z_values)
    }, logical(1L))),
    all(cfg$z_values > cfg$z_bounds[1L]),
    all(cfg$z_values < cfg$z_bounds[2L]),
    length(cfg$confidence_level) == 1L,
    is.numeric(cfg$confidence_level),
    is.finite(cfg$confidence_level),
    cfg$confidence_level > 0,
    cfg$confidence_level < 1,
    all(cfg$degree_power < 1 / 2),
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
    is.numeric(cfg$beta),
    all(is.finite(cfg$beta)),
    length(cfg$lambda) == 1L,
    is.finite(cfg$lambda),
    length(cfg$lambda_bounds) == 2L,
    all(is.finite(cfg$lambda_bounds)),
    cfg$lambda_bounds[1L] < cfg$lambda_bounds[2L],
    length(cfg$z_bounds) == 2L,
    all(is.finite(cfg$z_bounds)),
    0 < cfg$z_bounds[1L],
    cfg$z_bounds[1L] < cfg$z_bounds[2L],
    cfg$z_bounds[2L] < 1,
    length(cfg$ridge) == 1L,
    is.finite(cfg$ridge),
    cfg$ridge > 0,
    length(cfg$fixed_point_tolerance) == 1L,
    is.finite(cfg$fixed_point_tolerance),
    cfg$fixed_point_tolerance > 0,
    length(cfg$fixed_point_max_iterations) == 1L,
    is.finite(cfg$fixed_point_max_iterations),
    cfg$fixed_point_max_iterations >= 1L,
    cfg$fixed_point_max_iterations == as.integer(cfg$fixed_point_max_iterations),
    is.numeric(cfg$innovation_sd),
    length(cfg$innovation_sd) == 1L,
    is.finite(cfg$innovation_sd),
    cfg$innovation_sd > 0,
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
    length(cfg$jacobian_z_step) == 1L,
    is.numeric(cfg$jacobian_z_step),
    is.finite(cfg$jacobian_z_step),
    cfg$jacobian_z_step > 0,
    cfg$jacobian_z_step < min(cfg$z_bounds[1L], 1 - cfg$z_bounds[2L]),
    length(cfg$gmm_max_iterations) == 1L,
    is.finite(cfg$gmm_max_iterations),
    cfg$gmm_max_iterations >= 2L,
    cfg$gmm_max_iterations == as.integer(cfg$gmm_max_iterations),
    length(cfg$gmm_parameter_tolerance) == 1L,
    is.finite(cfg$gmm_parameter_tolerance),
    cfg$gmm_parameter_tolerance > 0,
    cfg$weighting %in% c("iid", "network"),
    cfg$score_covariance %in% c("iid_robust", "homoskedastic"),
    length(cfg$parallel) == 1L,
    is.logical(cfg$parallel),
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
  message(sprintf(
    "Running %d blocks with %d selected z scenarios in total (N=3000, seed=%d); directed Dyad, undirected SBM/PowerLaw. Existing identification and numerical retry rules are retained.",
    nrow(jobs), cfg$R * sum(lengths(cfg$rerun_z_values)), cfg$seed
  ))
  results <- run_jobs(jobs, cfg)

  write_outputs(results, cfg)
}

if (sys.nframe() == 0L) {
  run_simulation(CFG)
}
