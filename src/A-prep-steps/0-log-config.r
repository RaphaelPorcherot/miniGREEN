log_path <- DIR_LOG

dir.create(log_path, showWarnings = FALSE)

# BEGIN

log_file <- file.path(log_path, paste0("model_log_", Sys.Date(), ".log"))

log_message <- function(msg) {
  cat(msg, "\n", file = log_file, append = TRUE)
}

log_block <- function(title, module_name = "") {
  sep <- paste(rep("─", 60), collapse = "")
  log_message(paste0(
    "\n", sep,
    "\n📦 Module : ", title, ifelse(module_name != "", paste(" - ", module_name), ""),
    "\n⏰ ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    "\n", sep
  ))
}

parent_wd <- dirname(getwd())

log_message(paste0(
  "\n",
  "═══════════════════════════════════════════════════════════\n",
  "📅 New session : ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n",
  "📁 Working Dir      : ", parent_wd, "\n",
  "═══════════════════════════════════════════════════════════\n"
))


# END

# Créer un nouvel environnement local pour les dimensions
env <- new.env()

message("✅ Logging initialised")


# Lire le contenu du fichier et extraire les lignes entre les balises BEGIN et END

script_lines <- readLines(path_prep("0-log-config.r"))
start_line <- grep("# BEGIN", script_lines)
end_line <- grep("# END", script_lines)

# Extraire le code entre ces lignes
code_lines <- script_lines[(start_line + 1):(end_line - 1)]
temp_file <- tempfile()
# Écrire ce code dans un fichier temporaire
writeLines(code_lines, temp_file)

# Sourcer le fichier temporaire dans l'environnement local
source(temp_file, local = env)

# Liste des objets dans l'environnement local
objects_in_env <- ls(envir = env)
objects_in_env <- sort(objects_in_env)

# Définir les éléments à conserver
toKeep0 <<- objects_in_env

# Nettoyer le fichier temporaire et l'environnement
unlink(temp_file)
rm(env)

toKeep <- c(toKeep, toKeep0)

# ------- AVEC LOGGER

#library(logger)
#
## 📄 Fichier de log
#log_path <- here::DIR_LOG
#dir.create(log_path, showWarnings = FALSE, recursive = TRUE)
#log_file <- file.path(log_path, paste0("model_log_", Sys.Date(), ".log"))
#
## ⚙️ Configure le logger
#log_appender(appender_tee(log_file)) # Console + fichier
#log_layout(layout_glue_colors)
#
#log_info("🔧 Logger initialisé")
#log_info("📁 Working dir: {here::here()}")


## 

# ============================================================
# log_utils.R — Logging module pour projets R
# Auteur : Toi 🔥
# Description : Utilitaire de logs simple et portable
# ============================================================

#' Initialise le système de logging
#' @param log_dir Chemin vers le dossier de log (chemin absolu ou relatif)
#' @param prefix Nom de base du fichier de log
#' @return NULL (définit les fonctions log_* dans l’environnement global)
#init_logger <- function(log_dir = "logs", prefix = "log") {
#  # Crée le dossier s'il n'existe pas
#  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
#
#  # Définit le chemin du fichier log
#  log_file <<- file.path(log_dir, paste0(prefix, "_", Sys.Date(), ".log"))
#
#  # Fonction interne d'écriture
#  .write_log <- function(level, msg) {
#    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
#    line <- paste0("[", level, "] ", timestamp, " | ", msg)
#    cat(line, "\n", file = log_file, append = TRUE)
#  }
#
#  # Fonctions publiques
#  log_info  <<- function(msg) .write_log("INFO", msg)
#  log_warn  <<- function(msg) .write_log("WARN", msg)
#  log_error <<- function(msg) .write_log("ERROR", msg)
#
#  log_block <<- function(title, module = "") {
#    sep <- paste(rep("─", 60), collapse = "")
#    block_msg <- paste0("\n", sep,
#                        "\n📦 Module : ", title,
#                        ifelse(module != "", paste(" - ", module), ""),
#                        "\n⏰ ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
#                        "\n", sep)
#    log_info(block_msg)
#  }
#
#  # Log de démarrage
#  log_info("═══════════════════════════════════════════════════════════")
#  log_info("📅 New session")
#  log_info(paste("📁 Working Dir:", getwd()))
#  log_info("═══════════════════════════════════════════════════════════")
#
#  message("✅ Logger initialisé → ", normalizePath(log_file))
#}
#
#
#2. Dans ton notebook ou script R :
#
#source(here::here("R", "log_utils.R"))
#init_logger(log_dir = here::DIR_LOG, prefix = "model_log")
#
#log_info("🚀 Script lancé")
#log_block("Prétraitement", "step_1_cleaning")
#log_warn("Colonne 'age' contient des NA")
#log_error("Impossible de charger le fichier input.csv")
#
#
#🧼 Bonus : Nettoyage auto + portable
#
#Pas besoin de setwd() : here::here() s'occupe de tout. Tu peux même ajouter des options comme :
#
#init_logger(log_dir = here::here("logs"), prefix = "REWIND")
#
#Et ça génère automatiquement :
#
#logs/REWIND_2025-04-25.log
#
#
### V2 PRO
#
#Parfait, on passe en **mode pro** 🧑‍💻🔥  
#Voici **`log_utils.R` V2** : plus modulaire, configurable, filtrable, et avec **logging dans un fichier + console**, comme les vrais outils de prod.
#
#---
#
### 🧱 Ce que fait cette version :
#
#✅ Logging dans fichier **et** console  
#✅ Niveaux de logs filtrables (`INFO`, `WARN`, `ERROR`)  
#✅ Chemins propres avec `here`  
#✅ Facile à plugger dans n’importe quel projet  
#✅ Aucun `setwd()` requis  
#✅ Tu peux **désactiver** les logs en console (ou tout court)
#
#---
#
### 📦 `R/log_utils.R`
#
#```r
## ============================================================
## log_utils.R — Logger Pro v2
## Description : Logging avancé pour projets R
## Auteur : Toi 🔥
## ============================================================
#
##' Initialise le logger avec options avancées
##'
##' @param log_dir Dossier pour stocker les fichiers log (par défaut "logs")
##' @param prefix Nom de base du fichier de log (ex: "run", "model", etc.)
##' @param level Niveau minimal de log ("INFO", "WARN", "ERROR")
##' @param log_to_console TRUE pour afficher aussi dans la console
##'
##' @return NULL (définit des fonctions log_* globalement)
#init_logger <- function(log_dir = "logs",
#                        prefix = "log",
#                        level = "INFO",
#                        log_to_console = TRUE) {
#  
#  # Liste des niveaux autorisés (ordre d’importance)
#  levels <- c("INFO", "WARN", "ERROR")
#  level <- toupper(level)
#  if (!(level %in% levels)) stop("Niveau de log invalide : ", level)
#
#  # Stocke le niveau global pour filtrage
#  log_level_threshold <<- match(level, levels)
#
#  # Crée le dossier log
#  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
#
#  # Fichier log
#  log_file <<- file.path(log_dir, paste0(prefix, "_", Sys.Date(), ".log"))
#
#  # Fonction d’écriture centralisée
#  .write_log <- function(level, msg) {
#    current_level <- match(level, levels)
#    if (current_level < log_level_threshold) return(invisible(NULL))
#
#    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
#    line <- paste0("[", level, "] ", timestamp, " | ", msg)
#
#    # Ecrit dans le fichier
#    cat(line, "\n", file = log_file, append = TRUE)
#
#    # Optionnellement, écrit dans la console
#    if (isTRUE(log_to_console)) cat(line, "\n")
#  }
#
#  # Fonctions publiques
#  log_info  <<- function(msg) .write_log("INFO", msg)
#  log_warn  <<- function(msg) .write_log("WARN", msg)
#  log_error <<- function(msg) .write_log("ERROR", msg)
#
#  # Bloc visuel
#  log_block <<- function(title, module = "") {
#    sep <- paste(rep("─", 60), collapse = "")
#    block_msg <- paste0("\n", sep,
#                        "\n📦 Module : ", title,
#                        ifelse(module != "", paste(" - ", module), ""),
#                        "\n⏰ ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
#                        "\n", sep)
#    log_info(block_msg)
#  }
#
#  # Log d'initialisation
#  log_info("═══════════════════════════════════════════════════════════")
#  log_info(paste("📅 Session initialisée le :", format(Sys.time())))
#  log_info(paste("📁 Working Dir :", getwd()))
#  log_info(paste("📄 Log file :", normalizePath(log_file)))
#  log_info("═══════════════════════════════════════════════════════════")
#
#  message("✅ Logger initialisé (level = ", level, ") → ", normalizePath(log_file))
#}
#```
#
#---
#
### 🧪 Exemple d’utilisation dans ton notebook
#
#```r
#library(here)
#
#source(here::here("R", "log_utils.R"))
#init_logger(
#  log_dir = here::DIR_LOG,
#  prefix = "REWIND",
#  level = "INFO",             # ou "WARN", "ERROR"
#  log_to_console = TRUE       # ou FALSE si tu veux silence radio
#)
#
#log_block("Chargement des données")
#log_info("Lecture du fichier input.csv")
#log_warn("Colonne 'age' contient 15% de NA")
#log_error("Impossible de joindre la table des paramètres")
#
#source(here::path_prep("0-dataPrep.r"))
#log_info("Module de prétraitement terminé ✅")
#```
#
#---
#
### 🧠 Résumé des features
#
#| Fonction      | Ce qu’elle fait |
#|---------------|------------------|
#| `init_logger()` | Configure tout (dossier, nom, niveau, console) |
#| `log_info()`     | Message d'information |
#| `log_warn()`     | Avertissement |
#| `log_error()`    | Message d’erreur |
#| `log_block()`    | Bloc lisible pour marquer les étapes |
#| `log_to_console = FALSE` | Pour loguer uniquement dans un fichier |
#| `level = "WARN"`         | Filtrer les messages moins importants |
#
#---
#
#Tu veux que je te fasse un **template de projet R** avec ce logger intégré + `here` + `renv` pour gérer les dépendances ?
