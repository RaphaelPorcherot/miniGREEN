# Voir app/graph/.Rprofile : meme mecanique, un niveau plus haut.
local({
  root <- normalizePath("..", mustWork = FALSE)
  if (file.exists(file.path(root, "renv", "activate.R"))) {
    owd <- setwd(root)
    on.exit(setwd(owd), add = TRUE)
    source("renv/activate.R")
  }
})
