**Two possiblities to access the graphical app:**

* graph shiny app deployed at [https://rewind.shinyapps.io/graph/](https://rewind.shinyapps.io/graph/).

* use jupyter notebook `DirectedGraphs.ipynb` in current folder

**ToDo**:

* integrate graph generation in the shinyApp instead of using preset graphs

* add variables selection and degree of connection remoteness

* add more value box

**HowTo**:

```r
library(shiny)
library(rsconnect)

runApp()
deployApp()
terminateApp() 
```
