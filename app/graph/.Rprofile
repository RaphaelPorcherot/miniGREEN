# Ce dossier est une sous-application du projet : quand on demarre R ici
# (RStudio, `R` dans un terminal), renv doit etre active depuis la racine.
# `source()` a besoin d'y etre reellement, d'ou le setwd temporaire.
# on.exit() garantit le retour meme si activate.R echoue : sinon R finit de
# demarrer dans le mauvais dossier et load("graph_obj.RData") ne trouve rien.
# Le garde-fou file.exists() rend ce fichier inerte sur shinyapps.io.
local({
  root <- normalizePath(file.path("..", ".."), mustWork = FALSE)
  if (file.exists(file.path(root, "renv", "activate.R"))) {
    owd <- setwd(root)
    on.exit(setwd(owd), add = TRUE)
    source("renv/activate.R")
  }
})
