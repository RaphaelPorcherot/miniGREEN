:g
« l «coste sraffiano» utilizado por Bródy y Morishima no contabiliza, pues, el gasto efectivo de trabajo social necesario para reproducir una mercancía. » ([Ramos, 2003, p. 242](zotero://select/library/items/Q8BUIY2K)) ([pdf](zotero://open-pdf/library/items/PUI8HLKZ?page=12&annotation=UNB9YW9C))

« Ciertamente, Sraffa no pretende formalizar el cálculo de valor de Marx pero es, de hecho, su método el que adoptan dichos autores. » ([Ramos, 2003, p. 242](zotero://select/library/items/Q8BUIY2K)) ([pdf](zotero://open-pdf/library/items/PUI8HLKZ?page=12&annotation=CYF6NS29))

« El modelo «tras la cosecha» puede concebirse como una variante de la «subasta walrasiana», también un proceso imaginario cuyo resultado son unos «valores de cambio» que mantendrían un estado de equilibrio. » ([Ramos, 2003, p. 242](zotero://select/library/items/Q8BUIY2K)) ([pdf](zotero://open-pdf/library/items/PUI8HLKZ?page=12&annotation=9L2KXJB5))

—> POUR EUROGREEN REVOIR LE MODELE DE PRIX !!

:g
« Para Marx, por el contrario, la causación es cronológica: el valor está determinado por una serie de eventos –el gasto de trabajo social– que ocurren sucesivamente en el tiempo » ([Ramos, 2003, p. 245](zotero://select/library/items/Q8BUIY2K)) ([pdf](zotero://open-pdf/library/items/PUI8HLKZ?page=15&annotation=BCKFCCFU)) En fait c'est ca qu'il faut introduire dans le modèle de Pascal une fois qu'on autorise la modification dans le temps des conditions de la production

Pour m4w

M4W :

– Four main differences:
◦ Calibration: steady state achieved through equation inversion instead of an interative search algorithm.

Il faut reprendre les cours sur SFC dans le EPOG course : pour comprendre enfin les concpets de base

AUSSI le travail de DUGGAN SUR R 

ENfin AUGIER

« Software packages for system dynamics support dimensional checking, so adding in units at an early stage can improve the model building process. » ([Duggan, 2016, p. 14](zotero://select/library/items/KQ5I4QI9)) ([pdf](zotero://open-pdf/library/items/ZJ5WPSXT?page=31&annotation=LUCW8HZT))

• The package deSolve contains numerical integration functions, in particular, the function ode(). • The package FME provides support for sensitivity analysis (latin hypercube sampling), and for model calibration, as illustrated through the examples in Chap. 7. • The package RUnit provides a valuable testing framework for system dynamics models, as shown through the examples in Chap. 6. • The package ggplot2 provides an excellent way to visualize behavior over time, and generate high-quality charts that can enhance the model building process. • The data frame stores simulation results and provides the key structure for analysis, as it is used by plotting functions. • The matrix and associated operations supports vectorized models such as the SIR disaggregate model developed in Chap. 5. • The function cor() calculates the correlation coefficient for two variables, and this function is required for as part of the statistical screening process. • The function approxfun() supports the implementation of lookup tables in system dynamics models—see the example in Chap. 3. • The function sapply() can be used to process all elements of a data structure, and return a vector as a result. This is used in Chap. 7, as part of the statistical screening process.

Télécharger tout le dossier Nextcloud epog

Créer dépôt github https://ericmarcon.github.io/travailleR/chap-shiny.html / https://ericmarcon.github.io/travailleR/chap-git.html

https://www.dt.mef.gov.it/export/sites/sitodt/modules/documenti_it/eventi/eventi/Slides-GEMMES.pdf

Sensitivity analysis https://github.com/antoinegodin/OpenMORDM?tab=readme-ov-file

ROBUST DECISION https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5327551 


* Il faut au contraire expliciter à l'initialisation qu'on utilise pour             F_expDispIncPerCap_dsg et pour R_p_i en fait : 1 Ca veut dire qu'on introduit pas dans la boucle de la période 1 ces éléments et on le fait clairement ressortir.

* IN GOV : # SH_unempBenefWage :fixed and rather high | SH_unempCov fixed

# Revision

* Il faudra faire un gros passage une fois le modèle temriné pour améliorer chaque fonction et ce, avant d'écrire la documentation.
 
* lobstr -> pkg pour  myfun <- make_fun() lobstr::obj_tree(myfun) Ca permettra de check ce qu'il y a dans mes objets qui sont les fonctions

* a un moment il faudra nettoyer le renv pour essayer de comprendre pourquoi c'est si lourd.

* it could be nice to have a "history" column to store previous formula.

* testthat est un package R qui te permet d’écrire des tests automatisés pour ton code — un peu comme un filet de sécurité : si un jour quelque chose casse, tu le sauras immédiatement.s

* it will be necessary to rework the DEM module in order to reduce the size of parameters. R_morality_csg in fact is only cohort dependant, it makes no sense to have a full 3D array

* main loop : every function is recalculated in main loop when the loop needs to recharge. We need an exist() logic at some point

* Pour les scénarios rajouter une colonne dans la database

* M4W : à voir si jamais ca peut pas permettre d'aller plus vite https://jthomasmock.github.io/arrow-dplyr/#/we-can-benchmark

* Sensitivity analysis https://github.com/antoinegodin/OpenMORDM?tab=readme-ov-file

* Code profiling

## Logging with package(logger)

* mettre des choses en cache
* Rcpp
* install.packages("arrayhelpers") library(arrayhelpers) POUR result <- sum_over(F_labour_isg, dims = 2)  # somme sur la dimension Skill

## Conceptual stuff

* add the Geoergescu Rogen distinction between flux and flows and between stock and fond ? See Rammelt The Spiraling Economy for more details

## Lvl and lag 

* there was a maximal confusion with lag and lvl : we wont respect what the code is doing but what was instead apparent in the technical documentation fo feasible. This might generate ne resutls
for instance, lambda evolves depending on both realCapitalStock_lvl (preivous period or beginning-of-period capital stock) and realCapitalStock_lag2 (penultimate period). 
lambda diffusion is the mean of the effect of newly installed capital and already installed capital.
Most probably :

* newly insllated capital was meant to be realCapitalStock (end-of-period, after in K i)

* old capital was meant to be realCapitalStock_lvl (begin-of-period)

Instead, we applied what the code was doing : le tout est décalé d'un an vers le passé. Ce n'est complètement absurde.
But it breaks the likely desired link between current investment and current technological evolution : its recent investment that causes the "new" part of the evolution of lambda. 
Though in the end it is not necessarily incohrent : after all, you need some time for the impact of your investment decisions to bear their fruit under the form of technogocial advancmeents 

```{python}
# To keep only the last five rows of d

#setwd('/Users/macraph2/Nextcloud/_Own/Pro/Travaux/2024/1_M4W/0_M4W-git/MUST4WATER/notebooks/r-nb/C-modules')

# @STEP 4 : Write down the equations and run the model

# head(d)

# # Fonction pour ajouter une nouvelle période
# add_period <- function(d, period, modules, variables) {
#   for (module in modules) {
#     for (variable in variables) {
#       value <- runif(1)  # Exemple de valeur, remplacer par ton calcul
#       d <- rbind(d, data.table(Module = module, 
#                                Period = period, 
#                                Variable = variable, 
#                                Value = value))
#     }
#   }
  
#   # Si plus de 5 périodes, sauvegarder et garder les 5 dernières
#   if (nrow(d) > (5 * length(modules) * length(variables))) {
#     # Sauvegarder les anciennes périodes dans un fichier .fst
#     write.fst(d[1:(nrow(d) - 5 * length(modules) * length(variables))], 
#               path = "old_periods.fst", append = TRUE)
    
#     # Garder seulement les 5 dernières périodes
#     d <- d[(nrow(d) - 5 * length(modules) * length(variables) + 1):nrow(d), ]
#   }
  
#   return(d)
# }


# # Simuler l'ajout de données pour 200 périodes
# for (i in 0:199) {
#   d <- add_period(d, i, modules, variables)
# }

# # Affichage de la data.table finale
# head(d)

# Dans boucle a considérer car j'ai mis un garde fou mais ca pourrait buguer

# idx <- To("DEM", t)
# if (!is.na(idx)) {
#     set(d, i = idx, j = c("Name", "Value"), value = list("F_death_csg", temp))
# } else {
#     warning("No available row found for DEM at time ", t)
# }
```

```{python}
#@CODE TO OPTIMISE D and RECONSTITUTE IT IN THE END FOR ANALYSIS PURPOSES

## Autres idées d'optimisation /
#e. Parallélisation et traitement par lots
#Mise à jour conditionnell

##Les gains en mémoire sont évidents avec les fichiers .rds, car tu libères de l'espace mémoire en conservant une version "compressée" de tes données. Mais en termes de temps de calcul, cela dépend du nombre de périodes et de la fréquence des lectures/écritures :
## il pourrait être préférable de conserver tout dans une data.table en mémoire et d'explorer d'autres optimisations comme l'indexation ou l'utilisation de fichiers .fst (qui sont plus rapides que .rds pour les lectures et écritures).


 #  # Si plus de 5 périodes, on sauvegarde la plus ancienne et on la retire de la data.table
 #  if (nrow(dt) > 5) {
 #    # Sauvegarde de la première période dans un fichier .rds
 #    saveRDS(dt[1, .(Period, Population)], file = paste0("period_", dt[1, Period], ".rds"))
    
 #    # Retirer la plus ancienne période de la data.table
 #    dt <- dt[-1, ]
#  #  }

  
# # Dossier où les fichiers .rds sont stockés
# folder_path <- "chemin/vers/le/dossier/des/rds"

# # Lister tous les fichiers .rds dans le dossier
# rds_files <- list.files(path = folder_path, pattern = "\\.rds$", full.names = TRUE)

# # Créer une liste pour stocker les data.tables
# loaded_data <- list()

# # Charger chaque fichier .rds et ajouter les résultats dans la liste
# for (file in rds_files) {
#   # Lire le fichier .rds
#   data <- readRDS(file)
  
#   # Vérifier que les données sont bien un data.table (ou un data.frame) avant de les ajouter
#   if (is.data.table(data) || is.data.frame(data)) {
#     loaded_data[[file]] <- data  # Ajouter à la liste
#   } else {
#     warning(paste("Le fichier", file, "n'est pas un data.table ou un data.frame"))
#   }
# }

# # Combiner toutes les data.tables en une seule
# dfinal <- rbindlist(loaded_data, use.names = TRUE, fill = TRUE)
```

