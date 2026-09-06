# Deploying the graph viewer

Cheat sheet for `app/graph/`, published at
<https://rporcherot.shinyapps.io/minigreen/>.

This file lives in `app/` and not in `app/graph/` on purpose: **everything inside
`app/graph/` is uploaded to shinyapps.io.** rsconnect ignores `rsconnect/`,
`renv/`, `.git` and a short list of others, but not a stray `.md`. The bundle is
currently two files and should stay that way:

```bash
Rscript -e 'cat(rsconnect:::bundleFiles("app/graph"), sep = "\n")'
# app.R
# graph_obj.RData
```

Run everything below **from the project root**, so that renv is active.

## The usual case: redeploy

If you only edited `app/graph/app.R`:

```bash
Rscript -e 'rsconnect::deployApp("app/graph", forceUpdate = TRUE)'
```

No account, no app name, no id. They come from
`app/graph/rsconnect/shinyapps.io/rporcherot/minigreen.dcf`, which rsconnect
wrote on the first deployment and rewrites on every one after. That file is what
makes this an *update* of app `17834341` rather than a second application, so it
is committed to git — do not delete it.

`forceUpdate = TRUE` only matters in a non-interactive `Rscript`: it skips the
confirmation prompt rsconnect would otherwise be unable to ask.

## If you changed the model

`graph_obj.RData` is not rebuilt by the deployment. It is the product of an
actual run of the model, so it goes stale the moment `src/` changes:

```bash
Rscript tool/build-graph.r
Rscript -e 'rsconnect::deployApp("app/graph", forceUpdate = TRUE)'
```

`build-graph.r` runs the model for one period and prints what it found — node
and edge counts, equations captured, modules. Read that line before deploying:
if the counts moved in a way you did not expect, the graph is telling you
something about the model.

Note that it also rewrites `output/model_only.RData` and `output/modelDT.RData`,
because `run_model.r` saves those whenever it is run as a script. Both are
gitignored; nothing depends on them here.

## Before pushing, if you want to be sure

This resolves the whole dependency list and writes the manifest **without
uploading anything**. It is the cheapest way to catch a missing package:

```bash
Rscript -e 'rsconnect::writeManifest("app/graph")' && rm app/graph/manifest.json
```

It should report the same package count as the last successful deployment
(47 at the time of writing) and no error.

## Checking what happened

```bash
Rscript -e 'print(rsconnect::deployments("app/graph")[, c("name", "account", "appId", "url")])'
```

If the app deploys but errors in the browser, the R session's own output is on
the server, not in your console:

```bash
Rscript -e 'rsconnect::showLogs("app/graph", entries = 100)'
```

## First time on a new machine, or after renaming the account

The token is stored per account name under
`~/Library/Preferences/org.R-project.R/R/rsconnect/accounts/shinyapps.io/`.
Renaming the account on shinyapps.io does **not** update it, and editing the
`.dcf` by hand does not help — rsconnect looks the account up by name to find
the token.

1. shinyapps.io → avatar → **Tokens** → *Show* → *Copy to clipboard*
2. Paste the line it gives you into an R console at the project root:
   `rsconnect::setAccountInfo(name = "...", token = "...", secret = "...")`
3. If an old name is still registered:
   `rsconnect::removeAccount("<old>"); rsconnect::forgetDeployment("app/graph", force = TRUE)`
4. Redeploy naming the target explicitly, so it updates rather than duplicates:
   `rsconnect::deployApp("app/graph", account = "<new>", appId = 17834341, appName = "minigreen", appTitle = "miniGREEN")`

## Facts

| | |
|---|---|
| account | `rporcherot` |
| app name | `minigreen` |
| app id | `17834341` |
| URL | <https://rporcherot.shinyapps.io/minigreen/> |
| bundle | `app.R`, `graph_obj.RData` |
| deployment record | `app/graph/rsconnect/shinyapps.io/rporcherot/minigreen.dcf` (committed) |

Running it locally instead:

```bash
Rscript -e 'shiny::runApp("app/graph", port = 7788)'
```
