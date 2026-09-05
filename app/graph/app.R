library(shiny)
library(bslib)
library(visNetwork)
library(dplyr)

# Charger le graphe
load("graph_obj.RData")

# Largeur et hauteur dynamiques
h <- "100%"
w <- "100%"

modules <- unique(graph_obj$nodes$type)
modules <- modules[modules != "lag"]
modules <- c("main", modules)

nodes <- graph_obj$nodes
edges <- graph_obj$edges

# ------------------------------------------------------------------------------------------------
                                            # Fonctions #
# ------------------------------------------------------------------------------------------------

# Fonction pour barycentres (graph principal)
set_node_positions <- function(nodes_df) {
  set.seed(42)
  
  module_levels <- unique(nodes_df$type)
  n_modules <- length(module_levels)
  
  barycenters_y <- seq(0.1, 0.9, length.out = n_modules)
  names(barycenters_y) <- module_levels
  
  nodes_df <- nodes_df %>%
    rowwise() %>%
    mutate(
      x = if_else(type == "lag",
                  runif(1, 0, 0.125),
                  runif(1, 0.125, 1)),
      y = barycenters_y[type] + runif(1, -0.05, 0.05)
    ) %>%
    ungroup() %>%
    mutate(
      y = pmin(pmax(y, 0), 1)  # clamp
    )
  
  return(nodes_df)
}


# Fonction pour focus graph avec padding et X fixe
set_focus_positions <- function(nodes_df, edges_df, focus_id, up, down) {
  set.seed(42)
  
  degrees <- data.frame(id = focus_id, deg = 0)
  
  # Upstream
  if (up > 0) {
    current_level <- focus_id
    for (i in 1:up) {
      parents <- edges_df %>% filter(to %in% current_level) %>% pull(from) %>% unique()
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
      children <- edges_df %>% filter(from %in% current_level) %>% pull(to) %>% unique()
      new_nodes <- setdiff(children, degrees$id)
      if (length(new_nodes) == 0) break
      degrees <- rbind(degrees, data.frame(id = new_nodes, deg = i))
      current_level <- new_nodes
    }
  }
  
  nodes_df <- nodes_df %>%
    left_join(degrees, by = "id") %>%
    filter(!is.na(deg)) %>%
    mutate(deg = pmin(pmax(deg, -5), 5))
  
  # Nombre de zones = 11 (de -5 à 5)
  zone_count <- 11
  total_padding <- 0.01  # padding entre zones
  effective_zone_width <- (1 - total_padding * zone_count) / zone_count
  
  # Fonction pour X fixe par deg
  get_x_fixed <- function(deg) {
    idx <- deg + 6  # de [-5,5] à [1,11]
    start <- (idx - 1) * (effective_zone_width + total_padding) + total_padding / 2
    start + effective_zone_width / 2  # centre de la zone
  }
  
  nodes_df <- nodes_df %>%
    mutate(
      x=NA, #x = get_x_fixed(deg),
      y = NA  # laisse à la physique gérer Y
    )

  return(nodes_df)
}


# Les deux onglets proposent les memes reglages de layout. Ils doivent porter
# des identifiants distincts : Shiny ne lie que la premiere occurrence d'un id,
# donc la seconde copie de ces controles etait inerte.
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
      # vis.js attend ici un nombre entre 0 et 1, pas un booleen.
      numericInput(id("phys_avoidoverlap"), "Avoid node overlap:", value = 0, min = 0, max = 1, step = 0.1),
      helpText("0 = nodes may overlap, 1 = maximum repulsion between nodes.")
    )
  )
}

# Applique au reseau les reglages de layout de l'onglet prefixe par p.
apply_layout <- function(net, input, p) {
  g <- function(x) input[[paste0(p, x)]]
  if (isTRUE(g("enable_hierarchical"))) {
    net %>%
      visHierarchicalLayout(
        direction            = g("hier_direction"),
        levelSeparation      = g("hier_levelsep"),
        nodeSpacing          = g("hier_nodespacing"),
        treeSpacing          = g("hier_treespacing"),
        blockShifting        = g("hier_blockshift"),
        edgeMinimization     = g("hier_edgemin"),
        parentCentralization = g("hier_parentcent"),
        sortMethod           = g("hier_sort")
      ) %>%
      visPhysics(enabled = FALSE)
  } else if (isTRUE(g("enable_physics"))) {
    net %>%
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
    net %>% visPhysics(enabled = FALSE)
  }
}


# ------------------------------------------------------------------------------------------------
                                            # UI #
# ------------------------------------------------------------------------------------------------
ui <- page_navbar(
  title = "REWIND",
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
      edges_sub <- edges %>%
        filter(from_type == input$select_graph | to_type == input$select_graph)
      
      obj_in_sub <- unique(c(edges_sub$from_name, edges_sub$to_name))
      nodes_sub <- nodes %>% filter(label %in% obj_in_sub)
    }
    
    nodes_sub <- set_node_positions(nodes_sub)
    
    nodes_df <- nodes_sub %>%
      mutate(
        id = id,
        label = label,
        group = type,
        color = fillcolor,
        title = label,
        x = x,
        y = y,
        shape = if_else(type == "lag", "box", "ellipse")
      ) %>% select(id, label, group, color, title, x, y, shape)
    
    edges_df <- edges_sub %>%
      rename(from = from, to = to) %>%
      select(from, to)
    
    list(nodes = nodes_df, edges = edges_df)
  })
  
  output$graph <- renderVisNetwork({
    data <- graph_reactive()
    
    net <- visNetwork(data$nodes, data$edges, height = h, width = w) %>%
      visNodes(fixed = FALSE,
               font = list(size = 20, face = "arial")) %>%
      visEdges(arrows = "to") %>%
      visOptions(
        highlightNearest = TRUE,
        nodesIdSelection = TRUE
      ) %>%
      visInteraction(
        navigationButtons = TRUE,
        zoomView = TRUE,
        dragView = TRUE
      ) 
          
    net <- apply_layout(net, input, "m_")
      
      
      net <- net %>% visEvents(
        selectNode = "function(params) {
          if(params.nodes.length > 0){
            Shiny.setInputValue('clicked_node', params.nodes[0], {priority: 'event'});
          }
        }"
      )
  })
  
  output$module_title <- renderText({
    data <- graph_reactive()
    mod <- input$select_graph
    n_lag <- sum(data$nodes$group == "lag")
    n_var <- ifelse(mod == "main",
                    nrow(data$nodes) - n_lag,
                    sum(data$nodes$group == mod))
    paste0("Module: ", mod, " (", n_var, " objects) ")
  })
  
  output$legend <- renderUI({
    data <- graph_reactive()
    nodes_df <- data$nodes
    groups <- unique(nodes_df$group)
    
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
        parents <- edges %>% filter(to %in% ids_up) %>% pull(from)
        ids_up <- setdiff(parents, visited)
        visited <- c(visited, ids_up)
        ids <- c(ids, ids_up)
      }
    }
    
    if (down > 0) {
      ids_down <- current_id
      for (i in 1:down) {
        children <- edges %>% filter(from %in% ids_down) %>% pull(to)
        ids_down <- setdiff(children, visited)
        visited <- c(visited, ids_down)
        ids <- c(ids, ids_down)
      }
    }
    
    ids <- unique(ids)
    
    nodes_sub <- nodes %>% filter(id %in% ids) %>% mutate(shape = if_else(label == current_label, "star", if_else(type == "lag", "box", "ellipse")))
    edges_sub <- edges %>% filter(from %in% ids & to %in% ids)
    
    if (nrow(nodes_sub) == 0) return(NULL)
    
    nodes_sub <- set_focus_positions(nodes_sub, edges_sub, focus_id = current_id, up = up, down = down)
    
    nodes_df <- nodes_sub %>%
      mutate(
        id = id,
        label = label,
        group = type,
        color = fillcolor,
        title = label,
        #x = x,
        #y = y,
        shape = shape
      ) %>% select(id, label, group, color, title, x, y, shape)
    
    edges_df <- edges_sub %>%
      rename(from = from, to = to) %>%
      select(from, to)
    
    list(nodes = nodes_df, edges = edges_df)
  })
  
    output$focus_graph <- renderVisNetwork({
      data <- focus_graph_reactive()
      req(!is.null(data))
      
      net <- visNetwork(data$nodes, data$edges, height = h, width = w) %>%
        visNodes(fixed = FALSE,
                 font = list(size = 20, face = "arial")) %>%
        visEdges(arrows = "to") %>%
        visOptions(
          highlightNearest = TRUE,
          nodesIdSelection = TRUE
        ) %>%
        visInteraction(
          navigationButtons = TRUE,
          zoomView = FALSE
        )
      
              net <- apply_layout(net, input, "f_")
    
      net %>%
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
    types <- unique(nodes_df$group)
    
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
    paste0("Focus on: ", input$focus_var,
           " (Up: ", input$focus_up,
           ", Down: ", input$focus_down, ")")
  })
  
  # Clicks on main graph nodes
    observeEvent(input$clicked_node, {
      data <- graph_reactive()
      node_id <- input$clicked_node
      desc <- data$nodes$description[data$nodes$id == node_id]
      
      if (length(desc) == 0 || is.na(desc)) desc <- "(No description available)"
      
      showModal(modalDialog(
        title = paste("Node:", data$nodes$label[data$nodes$id == node_id]),
        desc,
        easyClose = TRUE
      ))
    })
      
  # Clicks on focus graph nodes
    observeEvent(input$clicked_focus_node, {
      data <- focus_graph_reactive()
      node_id <- input$clicked_focus_node
      desc <- data$nodes$description[data$nodes$id == node_id]
      
      if (length(desc) == 0 || is.na(desc)) desc <- "(No description available)"
      
      showModal(modalDialog(
        title = paste("Node:", data$nodes$label[data$nodes$id == node_id]),
        desc,
        easyClose = TRUE
      ))
    })
  # Hierarchique et physique s'excluent : cocher l'un decoche l'autre, par onglet.
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