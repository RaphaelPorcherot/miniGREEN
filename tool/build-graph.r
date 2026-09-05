#!/usr/bin/env Rscript
# ==============================================================================
# build-graph.r — run the model, then write the dependency graph the app reads
#
#   Rscript tool/build-graph.r
#
# The Shiny viewer in app/graph/ loads one file, `graph_obj.RData`, holding a
# node table and an edge table. This produces it.
#
# The edges come from `deps`, which eq() fills as the model runs: one row per
# (variable, what it reads). So the graph is not a drawing of the model kept in
# step by hand — it is what the model actually did on its last run. Running the
# model is therefore part of building it, not a prerequisite someone has to
# remember.
# ==============================================================================

message("running the model ...")
# Keep the source text of every function the model defines, so the viewer can
# show the equation as it is written rather than as R deparses it — comments,
# spacing and all. Must be set before the files are parsed.
options(keep.source = TRUE)

# run_model.r opens with rm(list = ls(all = TRUE)), so nothing defined before
# this line survives it. Paths come back with it.
suppressPackageStartupMessages({ library(here) })
invisible(capture.output(suppressMessages(source(here::here("src", "run_model.r")))))

APP <- file.path(DIR_APP, "graph")
OUT <- file.path(APP, "graph_obj.RData")

suppressPackageStartupMessages({ library(dplyr); library(RColorBrewer) })

# --- nodes and edges ----------------------------------------------------------

computed <- unique(as.character(d[!is.na(Name), Name]))

# Only "input" edges: a `parameter` role is a constant read from `dp`, which
# would treble the edge count without saying anything about the dynamics.
edges <- as.data.frame(deps[Role == "input", .(from = Dependency, to = Variable)],
                       stringsAsFactors = FALSE)

# Structural objects — dimensions, templates, the engine itself — are read by
# many equations and are not part of the economics. `keep_list()` is what the
# model protects from clean_ws(), which is exactly that set.
# `keep_list()` also holds a few model variables that the setup creates as
# globals before the loop — ST_population_csg among them. Anything the model
# computes belongs in the graph whatever else it is.
structural <- setdiff(c(keep_list(), "t", "dt", "convergence"), computed)
edges <- edges[!edges$from %in% structural & !edges$to %in% structural, ]

# A variable that is read but never computed is a lag or a level: it enters the
# model from `init` rather than from an equation. Worth showing, and worth
# showing differently.
all_vars <- unique(c(edges$from, edges$to, computed))
all_vars <- setdiff(all_vars, structural)

nodes <- data.frame(id = seq_along(all_vars), label = all_vars,
                    stringsAsFactors = FALSE)

# module, and Kind, straight from `d`
info <- unique(d[!is.na(Name), .(Name = as.character(Name), Module = as.character(Module), Kind)])
nodes$type <- info$Module[match(nodes$label, info$Name)]
nodes$kind <- info$Kind[match(nodes$label, info$Name)]
nodes$type[is.na(nodes$type)] <- "lag"
nodes$kind[is.na(nodes$kind)] <- "lag"

# Description is a list column, so it is matched row by row rather than through
# unique(), which cannot order a list.
first <- d[!is.na(Name)]
idx <- match(nodes$label, as.character(first$Name))
nodes$description <- vapply(idx, function(i) {
  if (is.na(i)) return(NA_character_)
  v <- first$Description[[i]]
  if (is.null(v) || all(is.na(v))) NA_character_ else as.character(v)[1]
}, character(1))

# which equation computes it, from the same table
eqn <- unique(deps[, .(Variable, Equation)])
nodes$equation <- eqn$Equation[match(nodes$label, eqn$Variable)]

# --- the equations themselves -------------------------------------------------
# One row per function, not per variable: a single equation often computes
# several. The node table keeps the name as the key.
eq_names <- sort(unique(na.omit(nodes$equation)))
equations <- do.call(rbind, lapply(eq_names, function(nm) {
  if (!exists(nm, envir = globalenv(), mode = "function")) {
    return(data.frame(name = nm, file = NA_character_, line = NA_integer_,
                      src = NA_character_, stringsAsFactors = FALSE))
  }
  f  <- get(nm, envir = globalenv(), mode = "function")
  sr <- attr(f, "srcref")
  if (is.null(sr)) {
    # keep.source was off, or the function was built rather than parsed
    return(data.frame(name = nm, file = NA_character_, line = NA_integer_,
                      src = paste(deparse(f), collapse = "\n"),
                      stringsAsFactors = FALSE))
  }
  path <- utils::getSrcFilename(f, full.names = TRUE)
  data.frame(
    name = nm,
    file = sub(paste0("^", PROJECT_ROOT, "/"), "", path),
    line = utils::getSrcLocation(f, "line"),
    src  = paste(as.character(sr), collapse = "\n"),
    stringsAsFactors = FALSE
  )
}))

# --- where a lag lives --------------------------------------------------------
# A lag or an init-read has no module of its own: it carries a variable that is
# computed somewhere. Without this, every edge leaving a lag would be counted as
# crossing a module boundary, which says nothing about the model's structure.
bare <- sub("_(lag2|lag|lvl)$", "", nodes$label)
nodes$home <- nodes$type
lag_rows <- which(nodes$type == "lag")
nodes$home[lag_rows] <- info$Module[match(bare[lag_rows], info$Name)]
nodes$home[is.na(nodes$home)] <- "lag"   # carrier we could not trace back

# --- appearance ---------------------------------------------------------------

types <- sort(unique(nodes$type))
pal <- if (length(types) <= 12) {
  suppressWarnings(RColorBrewer::brewer.pal(max(3, length(types)), "Set3"))[seq_along(types)]
} else {
  grDevices::hcl.colors(length(types), "Set 3")
}
names(pal) <- types
nodes$fillcolor <- pal[nodes$type]
nodes$fillcolor[nodes$type == "lag"] <- "#F0F0F0"

# Shape carries Kind, colour carries the module: the two questions one asks of
# a node are "what is it" and "where does it live", and they are orthogonal.
# Only shapes that draw the label inside, so the graph stays readable.
KIND_SHAPE <- c(state = "database", flow = "box", aux = "ellipse", lag = "text")
nodes$shape <- unname(KIND_SHAPE[nodes$kind])
nodes$shape[is.na(nodes$shape)] <- "ellipse"

# --- edges by index, and the module of each end -------------------------------

edges$from_name <- edges$from
edges$to_name   <- edges$to
edges$from <- match(edges$from_name, nodes$label)
edges$to   <- match(edges$to_name,   nodes$label)
edges <- edges[!is.na(edges$from) & !is.na(edges$to), ]
edges$from_type <- nodes$type[edges$from]
edges$to_type   <- nodes$type[edges$to]

edges$from_home <- nodes$home[edges$from]
edges$to_home   <- nodes$home[edges$to]

# An edge that leaves its module is what makes the model one model rather than
# eleven. Judged on `home`, so a lag is credited to the module it comes from.
# An untraceable carrier is not counted either way: we do not know.
edges$crosses_module <- edges$from_home != edges$to_home &
                        edges$from_home != "lag" & edges$to_home != "lag"

graph_obj <- list(nodes = nodes, edges = edges, equations = equations,
                  kind_shape = KIND_SHAPE,
                  built = Sys.time(),
                  period = get("t", envir = globalenv()))

dir.create(APP, recursive = TRUE, showWarnings = FALSE)
save(graph_obj, file = OUT)

cat(sprintf(paste0("%s\n  %d nodes (%d computed, %d entering from init)\n",
                   "  by kind: %s\n",
                   "  %d edges, %d crossing a module (%d undecidable)\n",
                   "  %d equations, %d with source (%d without)\n",
                   "  modules: %s\n"),
    sub(paste0(PROJECT_ROOT, "/"), "", OUT),
    nrow(nodes), sum(nodes$type != "lag"), sum(nodes$type == "lag"),
    paste(sprintf("%s %d", names(table(nodes$kind)), table(nodes$kind)), collapse = ", "),
    nrow(edges), sum(edges$crosses_module),
    sum(edges$from_home == "lag" | edges$to_home == "lag"),
    nrow(equations), sum(!is.na(equations$src)), sum(is.na(equations$src)),
    paste(setdiff(types, "lag"), collapse = ", ")))
