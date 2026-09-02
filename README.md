# QSAR-reproducibility

Replication materials for the paper *Quantile Social Autoregressive Model*.


## Repository structure

- `simu/`: R code for the simulation experiments.

- `real data/`: R code and input data for the empirical analyses.

  - `estimate/`: Full-sample estimation of the LIM, CES, and QSAR models.

  - `Hypothesis Test/`: Residual-bootstrap test for the presence of peer effects over a prespecified grid of quantile levels.

  - `group/`: QSAR estimation for the Predicted-Low and Predicted-High groups.
    
  - `Assumption_diagnostics/`: Empirical diagnostics for the regularity conditions.

Each folder under `real data/` contains one R script and the three Excel files required to run that analysis.

## Reproducibility

1. Install R and the packages required by the script to be run.
2. For each real-data analysis, keep the R script and the three Excel input files in the same folder.
3. Set the R working directory to the folder containing the script.
4. Run the R script.
5. The output files will be written to the output directory specified in that script.

The simulation script can be run independently from the `simu/` directory. The real-data scripts should be run separately from their corresponding folders under `real data/`: `estimate/`, `Hypothesis Test/`, `group/`, and `Assumption_diagnostics/`.


## Data availability

The data and code used to produce the simulation and empirical results are publicly available in this repository.

