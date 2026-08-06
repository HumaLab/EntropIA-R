# Package-level defaults, installed once at load time. Only options that are
# not already set by the user are touched, so interactive overrides survive
# re-loads.

.onLoad <- function(libname, pkgname) {
  op <- options()
  entropiar_defaults <- list(
    # Schema compatibility policy: "warn" | "error" | "allow". Consumed by the
    # compatibility layer (Task 6); defaults to the tolerant warn posture.
    entropiaR.schema_policy = "warn",
    # v2 write guard: all write ops error until this is set to FALSE.
    # Reserved for the v2 read-write release; not yet consumed in v1.
    entropiaR.write_dry_run = TRUE
  )
  toset <- !(names(entropiar_defaults) %in% names(op))
  if (any(toset)) {
    options(entropiar_defaults[toset])
  }
  invisible()
}
