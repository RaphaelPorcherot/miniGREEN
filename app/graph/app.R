library(shiny)
library(bslib)
library(visNetwork)
library(dplyr)

# The viewer reads one file and runs nothing: tool/build-graph.r produced it.
load("graph_obj.RData")

# Fill whatever the card gives us
h <- "100%"
w <- "100%"

modules <- unique(graph_obj$nodes$type)
modules <- modules[modules != "lag"]
modules <- c("main", modules)

nodes     <- graph_obj$nodes
edges     <- graph_obj$edges
equations <- graph_obj$equations

# Kind says what an object is, the module says where it lives: two orthogonal
# questions, carried by shape and colour respectively.
KIND_ORDER <- c("state", "flow", "aux", "lag")
KIND_GLOSS <- c(state = "a stock, carries the past",
                flow  = "what moves a stock",
                aux   = "computed then forgotten",
                lag   = "enters from init")
SHAPE_GLOSS <- c(database = "cylinder", box = "box",
                 ellipse = "ellipse", text = "no border")

kinds_present <- KIND_ORDER[KIND_ORDER %in% unique(nodes$kind)]
kind_counts   <- table(nodes$kind)

EDGE_CROSS  <- "#C0392B"   # an edge that leaves its module
EDGE_WITHIN <- "#B0B0B0"

# ------------------------------------------------------------------------------------------------
                                          # Functions #
# ------------------------------------------------------------------------------------------------

# Barycentres, one band per module (main graph)
set_node_positions <- function(nodes_df) {
  set.seed(42)
  
  module_levels <- unique(nodes_df$type)
  n_modules <- length(module_levels)
  
  barycenters_y <- seq(0.1, 0.9, length.out = n_modules)
  names(barycenters_y) <- module_levels
  
  nodes_df <- nodes_df |>
    rowwise() |>
    mutate(
      x = if_else(type == "lag",
                  runif(1, 0, 0.125),
                  runif(1, 0.125, 1)),
      y = barycenters_y[type] + runif(1, -0.05, 0.05)
    ) |>
    ungroup() |>
    mutate(
      y = pmin(pmax(y, 0), 1)  # clamp
    )
  
  return(nodes_df)
}


# Focus graph: pad the zones and pin X by depth
set_focus_positions <- function(nodes_df, edges_df, focus_id, up, down) {
  set.seed(42)
  
  degrees <- data.frame(id = focus_id, deg = 0)
  
  # Upstream
  if (up > 0) {
    current_level <- focus_id
    for (i in 1:up) {
      parents <- edges_df |> filter(to %in% current_level) |> pull(from) |> unique()
      new_nodes <- setdiff(parents, degrees$id)
      if (length(new_nodes) == 0) break
      degrees <- rbind(degrees, data.frame(id = new_nodes, deg = -i))
      current_level <- new_nodes
    }
  }
  
  # Downstream
  if (down > 0) {
    current_level <- focus_id
    for (i in 1:down) {
      children <- edges_df |> filter(from %in% current_level) |> pull(to) |> unique()
      new_nodes <- setdiff(children, degrees$id)
      if (length(new_nodes) == 0) break
      degrees <- rbind(degrees, data.frame(id = new_nodes, deg = i))
      current_level <- new_nodes
    }
  }
  
  nodes_df <- nodes_df |>
    left_join(degrees, by = "id") |>
    filter(!is.na(deg)) |>
    mutate(deg = pmin(pmax(deg, -5), 5))
  
  # 11 zones, from -5 to 5
  zone_count <- 11
  total_padding <- 0.01  # padding entre zones
  effective_zone_width <- (1 - total_padding * zone_count) / zone_count
  
  # Fixed X per depth
  get_x_fixed <- function(deg) {
    idx <- deg + 6  # [-5,5] -> [1,11]
    start <- (idx - 1) * (effective_zone_width + total_padding) + total_padding / 2
    start + effective_zone_width / 2  # centre of the zone
  }
  
  nodes_df <- nodes_df |>
    mutate(
      x=NA, #x = get_x_fixed(deg),
      y = NA  # let the physics handle Y
    )

  return(nodes_df)
}


# Reading filters, one set per tab.
filter_controls <- function(p) {
  id <- function(x) paste0(p, x)
  labels <- lapply(kinds_present, function(k) {
    HTML(sprintf("<b>%s</b> <span style='color:#888'>(%d, %s &mdash; %s)</span>",
                 k, kind_counts[[k]],
                 SHAPE_GLOSS[[ graph_obj$kind_shape[[k]] ]], KIND_GLOSS[[k]]))
  })
  tagList(
    checkboxGroupInput(id("kinds"), "Kinds:",
                       choiceNames = labels, choiceValues = kinds_present,
                       selected = kinds_present),
    radioButtons(id("edge_scope"), "Edges:",
                 choiceNames  = c("All", "Cross-module only", "Within-module only"),
                 choiceValues = c("all", "cross", "intra"), selected = "all"),
    helpText(HTML(paste0(
      "Cross-module edges are drawn in <span style='color:", EDGE_CROSS,
      "'><b>red</b></span>. An edge with an untraced carrier at either end",
      " counts as neither."))),
    tags$hr()
  )
}

# Both tabs offer the same layout settings. They must carry distinct ids:
# Shiny binds only the first occurrence of an id, so the second copy of these
# controls used to be inert.
layout_controls <- function(p) {
  id <- function(x) paste0(p, x)
  tagList(
    checkboxInput(id("enable_hierarchical"), "Enable hierarchical layout", value = FALSE),
    conditionalPanel(
      condition = sprintf("input.%s == true", id("enable_hierarchical")),
      selectInput(id("hier_direction"), "Direction:", choices = c("UD", "DU", "LR", "RL"), selected = "LR"),
      helpText("Set the direction of the hierarchical layout. UD = Up-Down, DU = Down-Up, LR = Left-Right, RL = Right-Left."),
      selectInput(id("hier_sort"), "Sort method:", choices = c("hubsize", "directed"), selected = "directed"),
      helpText("Determines node sorting: 'directed' sorts by edge directions; 'hubsize' sorts by node degree."),
      numericInput(id("hier_levelsep"), "Level separation:", value = 300, min = 10, max = 1000),
      helpText("Distance between different levels in the hierarchy."),
      numericInput(id("hier_nodespacing"), "Node spacing:", value = 300, min = 10, max = 1000),
      helpText("Horizontal spacing between nodes on the same level."),
      numericInput(id("hier_treespacing"), "Tree spacing:", value = 300, min = 10, max = 1000),
      helpText("Spacing between different trees (connected components) in the layout."),
      checkboxInput(id("hier_blockshift"), "Block shifting", value = TRUE),
      helpText("Enables block shifting to avoid node overlap in hierarchical layout."),
      checkboxInput(id("hier_edgemin"), "Edge minimization", value = TRUE),
      helpText("Minimizes edge crossings for better readability."),
      checkboxInput(id("hier_parentcent"), "Parent centralization", value = TRUE),
      helpText("Centers parent nodes over their child nodes.")
    ),
    checkboxInput(id("enable_physics"), "Enable physics (BarnesHut)", value = TRUE),
    conditionalPanel(
      condition = sprintf("input.%s == true && input.%s == false", id("enable_physics"), id("enable_hierarchical")),
      numericInput(id("phys_stabilization_iter"), "Stabilization iterations:", value = 500, min = 0, max = 5000),
      helpText("Number of iterations for physics simulation stabilization."),
      numericInput(id("phys_gravity"), "Central gravity:", value = 0.05, min = 0, max = 5, step = 0.1),
      helpText("Strength of the central gravity pulling nodes towards the center."),
      numericInput(id("phys_spring_length"), "Spring length:", value = 120, min = 10, max = 500),
      helpText("Ideal distance between connected nodes."),
      numericInput(id("phys_spring_constant"), "Spring constant:", value = 0.05, min = 0, max = 1, step = 0.01),
      helpText("Stiffness of the springs between nodes."),
      numericInput(id("phys_damping"), "Damping:", value = 0.5, min = 0, max = 1, step = 0.01),
      helpText("Amount of friction to slow down node movement."),
      # vis.js wants a number between 0 and 1 here, not a boolean.
      numericInput(id("phys_avoidoverlap"), "Avoid node overlap:", value = 0, min = 0, max = 1, step = 0.1),
      helpText("0 = nodes may overlap, 1 = maximum repulsion between nodes.")
    )
  )
}

# Apply tab p's filters. `keep_ids` escapes the kind filter: it is the variable
# the focus was asked for, and dropping it would empty the screen without
# saying anything.
apply_filters <- function(nodes_sub, edges_sub, input, p, keep_ids = integer(0)) {
  g <- function(x) input[[paste0(p, x)]]

  kinds <- g("kinds")
  if (!is.null(kinds)) {
    nodes_sub <- nodes_sub[nodes_sub$kind %in% kinds | nodes_sub$id %in% keep_ids, , drop = FALSE]
    edges_sub <- edges_sub[edges_sub$from %in% nodes_sub$id &
                           edges_sub$to   %in% nodes_sub$id, , drop = FALSE]
  }

  scope <- g("edge_scope")
  if (identical(scope, "cross")) edges_sub <- edges_sub[edges_sub$crosses_module, , drop = FALSE]
  if (identical(scope, "intra")) edges_sub <- edges_sub[!edges_sub$crosses_module, , drop = FALSE]

  list(nodes = nodes_sub, edges = edges_sub)
}

# An edge that crosses a module boundary should be visible as such.
style_edges <- function(e) {
  if (nrow(e) == 0) return(data.frame(from = integer(0), to = integer(0)))
  data.frame(
    from   = e$from,
    to     = e$to,
    color  = ifelse(e$crosses_module, EDGE_CROSS, EDGE_WITHIN),
    width  = ifelse(e$crosses_module, 2.5, 1),
    title  = paste0(e$from_name, " &rarr; ", e$to_name,
                    ifelse(e$crosses_module,
                           paste0("<br><i>", e$from_home, " &rarr; ", e$to_home, "</i>"), "")),
    stringsAsFactors = FALSE
  )
}

# The tooltip answers "what is this", the modal answers "how is it computed".
node_tooltip <- function(n) {
  paste0("<b>", n$label, "</b><br>", n$kind, " &middot; ", n$type,
         ifelse(!is.na(n$equation), paste0("<br><code>", n$equation, "()</code>"), ""))
}

node_modal <- function(node_id, meta) {
  i <- match(node_id, meta$id)
  if (is.na(i)) return(invisible(NULL))
  n  <- meta[i, ]
  eq <- if (!is.na(n$equation)) equations[match(n$equation, equations$name), ] else NULL

  showModal(modalDialog(
    title = n$label, size = "l", easyClose = TRUE,
    tags$p(tags$span(class = "badge bg-secondary", n$kind), " ",
           tags$span(class = "badge bg-light text-dark", n$type),
           if (!is.na(n$home) && n$home != n$type)
             tags$small(paste0("  carries a variable from ", n$home))),
    tags$p(if (is.na(n$description)) tags$em("no description in the model")
           else n$description),
    if (!is.null(eq) && !is.na(eq$src)) tagList(
      tags$hr(),
      tags$p(tags$code(paste0(eq$name, "()")), " ",
             tags$small(style = "color:#888", paste0(eq$file, ":", eq$line))),
      tags$pre(style = paste("max-height:55vh; overflow:auto; background:#f7f7f7;",
                             "padding:12px; border-radius:4px; font-size:12px;"),
               eq$src)
    ) else tags$p(tags$hr(), tags$em(
      "no equation computes this object: it enters from init."))
  ))
}

# Apply the layout settings of the tab prefixed by p to the network.
apply_layout <- function(net, input, p) {
  g <- function(x) input[[paste0(p, x)]]
  if (isTRUE(g("enable_hierarchical"))) {
    net |>
      visHierarchicalLayout(
        direction            = g("hier_direction"),
        levelSeparation      = g("hier_levelsep"),
        nodeSpacing          = g("hier_nodespacing"),
        treeSpacing          = g("hier_treespacing"),
        blockShifting        = g("hier_blockshift"),
        edgeMinimization     = g("hier_edgemin"),
        parentCentralization = g("hier_parentcent"),
        sortMethod           = g("hier_sort")
      ) |>
      visPhysics(enabled = FALSE)
  } else if (isTRUE(g("enable_physics"))) {
    net |>
      visPhysics(
        enabled       = TRUE,
        solver        = "barnesHut",
        stabilization = list(iterations = g("phys_stabilization_iter")),
        barnesHut = list(
          centralGravity = g("phys_gravity"),
          springLength   = g("phys_spring_length"),
          springConstant = g("phys_spring_constant"),
          damping        = g("phys_damping"),
          avoidOverlap   = as.numeric(g("phys_avoidoverlap"))
        )
      )
  } else {
    net |> visPhysics(enabled = FALSE)
  }
}


# ------------------------------------------------------------------------------------------------
                                            # UI #
# ------------------------------------------------------------------------------------------------
ui <- page_navbar(
  title = "miniGREEN",
  theme = bs_theme(bootswatch = "flatly"),
  
  ### --- Tab 1 : Graphe principal ---
  nav_panel("Module focus",
            layout_sidebar(
              sidebar = sidebar(
                selectInput("select_graph", "Choose a graph among:", choices = modules),
                tags$hr(),
                tags$h4("Legend:"),
                uiOutput("legend"), 
                tags$hr(),
                filter_controls("m_"),
                layout_controls("m_")
              ),
              card(
                card_header(textOutput("module_title")),
                visNetworkOutput("graph", height = h, width = w)
              )
            )
  ),
  
  ### --- Tab 2 : Variable Focus ---
  nav_panel("Variable focus",
            layout_sidebar(
              sidebar = sidebar(
                selectInput("focus_var", "Select variable:", choices = sort(unique(nodes$label))),
                sliderInput("focus_up", "Upstream (up):", min = 0, max = 5, value = 1),
                sliderInput("focus_down", "Downstream (down):", min = 0, max = 5, value = 1),
                
                tags$hr(),
                tags$h4("Legend:"),
                uiOutput("focus_legend"),
                tags$hr(),
                filter_controls("f_"),
                layout_controls("f_")
              ),
              card(
                card_header(textOutput("focus_title")),
                visNetworkOutput("focus_graph", height = h, width = w)
              )
            )
  )
)

# ------------------------------------------------------------------------------------------------
                                            # SERVER #
# ------------------------------------------------------------------------------------------------

server <- function(input, output, session) {
  
  # ---- Graphe principal ----
  graph_reactive <- reactive({
    req(input$select_graph)
    
    if (input$select_graph == "main") {
      nodes_sub <- nodes
      edges_sub <- edges
    } else {
      edges_sub <- edges |>
        filter(from_type == input$select_graph | to_type == input$select_graph)
      
      obj_in_sub <- unique(c(edges_sub$from_name, edges_sub$to_name))
      nodes_sub <- nodes |> filter(label %in% obj_in_sub)
    }
    
    kept <- apply_filters(nodes_sub, edges_sub, input, "m_")
    nodes_sub <- kept$nodes; edges_sub <- kept$edges
    if (nrow(nodes_sub) == 0) return(NULL)

    nodes_sub <- set_node_positions(nodes_sub)

    # Shape comes from `kind` as build-graph.r decided it, colour from the
    # module. Neither is recomputed here.
    nodes_df <- data.frame(
      id = nodes_sub$id, label = nodes_sub$label,
      group = nodes_sub$type, color = nodes_sub$fillcolor,
      title = node_tooltip(nodes_sub),
      x = nodes_sub$x, y = nodes_sub$y, shape = nodes_sub$shape,
      stringsAsFactors = FALSE
    )

    list(nodes = nodes_df, edges = style_edges(edges_sub), meta = nodes_sub,
         n_cross = sum(edges_sub$crosses_module))
  })
  
  output$graph <- renderVisNetwork({
    data <- graph_reactive()
    req(!is.null(data))

    net <- visNetwork(data$nodes, data$edges, height = h, width = w) |>
      visNodes(fixed = FALSE,
               font = list(size = 20, face = "arial")) |>
      visEdges(arrows = "to") |>
      visOptions(
        highlightNearest = TRUE,
        nodesIdSelection = TRUE
      ) |>
      visInteraction(
        navigationButtons = TRUE,
        zoomView = TRUE,
        dragView = TRUE
      ) 
          
    net <- apply_layout(net, input, "m_")
      
      
      net <- net |> visEvents(
        selectNode = "function(params) {
          if(params.nodes.length > 0){
            Shiny.setInputValue('clicked_node', params.nodes[0], {priority: 'event'});
          }
        }"
      )
  })
  
  output$module_title <- renderText({
    data <- graph_reactive()
    if (is.null(data)) return("No object passes the filters.")
    n_lag <- sum(data$meta$type == "lag")
    sprintf("Module: %s | %d objects (%d computed, %d from init) | %d edges, %d of them cross-module",
            input$select_graph, nrow(data$meta), nrow(data$meta) - n_lag, n_lag,
            nrow(data$edges), data$n_cross)
  })
  
  output$legend <- renderUI({
    data <- graph_reactive()
    req(!is.null(data))
    nodes_df <- data$nodes
    groups <- sort(unique(nodes_df$group))
    
    colors <- sapply(groups, function(g) {
      col <- nodes_df$color[which(nodes_df$group == g)[1]]
      if (is.na(col) | is.null(col)) "#cccccc" else col
    })
    
    div(
      lapply(seq_along(groups), function(i) {
        tags$div(
          tags$span(
            style = paste0("display: inline-block; width: 15px; height: 15px; background-color: ", colors[i], "; margin-right: 8px; border: 1px solid #666;"),
            ""
          ),
          groups[i]
        )
      })
    )
  })
  
  # ---- Graphe focus sur variable ----
  focus_graph_reactive <- reactive({
    req(input$focus_var)
    
    current_label <- input$focus_var
    current_id <- nodes$id[match(current_label, nodes$label)]
    if (is.na(current_id)) return(NULL)
    
    up <- input$focus_up
    down <- input$focus_down
    
    ids <- c(current_id)
    visited <- c()
    
    if (up > 0) {
      ids_up <- current_id
      for (i in 1:up) {
        parents <- edges |> filter(to %in% ids_up) |> pull(from)
        ids_up <- setdiff(parents, visited)
        visited <- c(visited, ids_up)
        ids <- c(ids, ids_up)
      }
    }
    
    if (down > 0) {
      ids_down <- current_id
      for (i in 1:down) {
        children <- edges |> filter(from %in% ids_down) |> pull(to)
        ids_down <- setdiff(children, visited)
        visited <- c(visited, ids_down)
        ids <- c(ids, ids_down)
      }
    }
    
    ids <- unique(ids)
    
    nodes_sub <- nodes |> filter(id %in% ids)
    edges_sub <- edges |> filter(from %in% ids & to %in% ids)

    # The variable at the centre survives the kind filter: dropping it would
    # empty the screen without teaching anything.
    kept <- apply_filters(nodes_sub, edges_sub, input, "f_", keep_ids = current_id)
    nodes_sub <- kept$nodes; edges_sub <- kept$edges
    if (nrow(nodes_sub) == 0) return(NULL)

    nodes_sub <- set_focus_positions(nodes_sub, edges_sub, focus_id = current_id, up = up, down = down)
    # set_focus_positions walks the graph again with the filtered edges: a
    # tight filter can leave nothing behind.
    if (nrow(nodes_sub) == 0) return(NULL)

    # The focus keeps its shape, hence its kind, and is marked by its border.
    is_focus <- nodes_sub$id == current_id
    nodes_df <- data.frame(
      id = nodes_sub$id, label = nodes_sub$label,
      group = nodes_sub$type, color = nodes_sub$fillcolor,
      title = node_tooltip(nodes_sub),
      x = nodes_sub$x, y = nodes_sub$y, shape = nodes_sub$shape,
      borderWidth = ifelse(is_focus, 4, 1),
      stringsAsFactors = FALSE
    )

    list(nodes = nodes_df, edges = style_edges(edges_sub), meta = nodes_sub,
         n_cross = sum(edges_sub$crosses_module))
  })
  
    output$focus_graph <- renderVisNetwork({
      data <- focus_graph_reactive()
      req(!is.null(data))
      
      net <- visNetwork(data$nodes, data$edges, height = h, width = w) |>
        visNodes(fixed = FALSE,
                 font = list(size = 20, face = "arial")) |>
        visEdges(arrows = "to") |>
        visOptions(
          highlightNearest = TRUE,
          nodesIdSelection = TRUE
        ) |>
        visInteraction(
          navigationButtons = TRUE,
          zoomView = FALSE
        )
      
              net <- apply_layout(net, input, "f_")
    
      net |>
        visEvents(
          selectNode = "function(params) {
            if(params.nodes.length > 0){
              Shiny.setInputValue('clicked_focus_node', params.nodes[0], {priority: 'event'});
            }
          }"
        )
    })

  
  output$focus_legend <- renderUI({
    data <- focus_graph_reactive()
    req(!is.null(data))
    
    nodes_df <- data$nodes
    types <- sort(unique(nodes_df$group))
    
    colors <- sapply(types, function(t) {
      col <- nodes_df$color[which(nodes_df$group == t)[1]]
      if (is.na(col) | is.null(col)) "#cccccc" else col
    })
    
    div(
      lapply(seq_along(types), function(i) {
        tags$div(
          tags$span(
            style = paste0("display: inline-block; width: 15px; height: 15px; background-color: ", colors[i], "; margin-right: 8px; border: 1px solid #666;"),
            ""
          ),
          types[i]
        )
      })
    )
  })
  
  output$focus_title <- renderText({
    req(input$focus_var)
    data <- focus_graph_reactive()
    if (is.null(data)) return(paste0("Focus on: ", input$focus_var, " | nothing to show"))
    sprintf("Focus on: %s (up %d, down %d) | %d objects, %d edges, %d of them cross-module",
            input$focus_var, input$focus_up, input$focus_down,
            nrow(data$meta), nrow(data$edges), data$n_cross)
  })
  
  # Clicking a node shows the equation that computes it.
  # The description lives in `meta`, not in the table handed to visNetwork: the
  # old version looked for it in `nodes` after a select() had dropped it, and so
  # always showed "(No description available)".
  observeEvent(input$clicked_node, {
    data <- graph_reactive(); req(!is.null(data))
    node_modal(input$clicked_node, data$meta)
  })

  observeEvent(input$clicked_focus_node, {
    data <- focus_graph_reactive(); req(!is.null(data))
    node_modal(input$clicked_focus_node, data$meta)
  })
  # Hierarchical and physics exclude each other: ticking one unticks the other,
  # per tab.
  for (p in c("m_", "f_")) local({
    prefix <- p
    observeEvent(input[[paste0(prefix, "enable_hierarchical")]], {
      if (isTRUE(input[[paste0(prefix, "enable_hierarchical")]])) {
        updateCheckboxInput(session, paste0(prefix, "enable_physics"), value = FALSE)
      }
    })
    observeEvent(input[[paste0(prefix, "enable_physics")]], {
      if (isTRUE(input[[paste0(prefix, "enable_physics")]])) {
        updateCheckboxInput(session, paste0(prefix, "enable_hierarchical"), value = FALSE)
      }
    })
  })

}

# Run the app
shinyApp(ui = ui, server = server)
