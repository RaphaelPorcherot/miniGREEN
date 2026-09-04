env <- new.env()

message(paste("✅ ", module_name, "loaded."))

log_block(paste0("", module_name))

script_path <- here("notebooks", "r-nb", "B-modules", paste0(module_name,".r"))
script_lines <- readLines(script_path)
start_line <- grep("# BEGIN Fonctions", script_lines)
end_line <- grep("# END Fonctions", script_lines)

code_lines <- script_lines[(start_line + 1):(end_line - 1)]
temp_file <- tempfile()
writeLines(code_lines, temp_file)
source(temp_file, local = env)

functions_in_env <- ls(envir = env)
functions_in_env <- functions_in_env[
    sapply(
        functions_in_env, function(x) is.function(
            get(x, envir= env)
        )
        )
]

# Assign to global env
functions_in_env <<- functions_in_env


# Separate the functions containing "POLICY" in their name
policy_functions <- functions_in_env[grepl("POL", functions_in_env)]

# Log des fonctions "POLICY"
log_message("📜 Policy Functions:")
log_message(paste(policy_functions, collapse = "\n"))
log_message("\n")

# Log des autres fonctions
other_functions <- setdiff(functions_in_env, policy_functions)
log_message("🔧 Other Functions:")
log_message(paste(other_functions, collapse = "\n"))
log_message("\n")


unlink(temp_file)
rm(env)

                                            