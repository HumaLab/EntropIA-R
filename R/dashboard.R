# Optional interactive exploration. Metrics live in eda.R, never in the UI.

ent_require_dashboard <- function() {
  for (pkg in c("shiny", "bslib", "ggplot2")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      ent_abort(
        "entropia_error_missing_dependency",
        "The dashboard requires {.pkg {pkg}}. Install it before opening the app."
      )
    }
  }
  invisible(TRUE)
}

ent_dashboard_query <- function(con, selection, text = FALSE) {
  args <- selection[intersect(names(selection), c(
    "collection_ids", "asset_types", "page_assets", "date_var", "date_range"
  ))]
  do.call(ent_study_query, c(list(con = con, text = text), args))
}

# Pagination uses one stable SQL order and transfers only the requested page.
ent_dashboard_page <- function(con, query, page, page_size) {
  page <- max(1L, as.integer(page))
  offset <- (as.double(page) - 1) * page_size
  cols <- c(
    "item_id", "item_title", "collection_id", "collection_name", "asset_id",
    "asset_type", "asset_size", "item_created_at", "asset_created_at"
  )
  query <- dplyr::select(query, dplyr::any_of(cols))
  sql <- as.character(dbplyr::sql_render(query))
  sql <- paste0(
    "SELECT * FROM (", sql, ") AS ent_page ORDER BY item_id, asset_id LIMIT ",
    as.integer(page_size), " OFFSET ", format(offset, scientific = FALSE, trim = TRUE)
  )
  entropia_collect(dplyr::tbl(con, dbplyr::sql(sql)), schema = ent_corpus_contract())
}

ent_dashboard_choices <- function(x, label, key) {
  stats::setNames(x[[key]], paste0(x[[label]], " [", x[[key]], "]"))
}

#' Explore an EntropIA snapshot in a local dashboard
#'
#' Builds an optional Shiny application; it does not start a server, open a
#' browser or open a database connection until a browser session starts.
#' Prepare a self-contained snapshot with [entropia_copy()] first. Each session
#' owns a read-only connection and its reactive results; closing one session
#' never disconnects another. The caller owns the snapshot file and must retain
#' it until the application stops. Live refresh and remote authentication are
#' deliberately not provided by this local application.
#'
#' All panels use the same applied selection. Overview calculations aggregate
#' in SQLite. Detail pagination is server-side. Text is retrieved only on
#' request; the length panel explicitly profiles at most `profile_limit` rows,
#' in stable item/asset order, not a representative random sample. Downloads
#' are bounded by `download_limit` and exclude paths and metadata. Downloaded
#' text is opt-in. Entity filters affect entity statistics, not the item universe.
#'
#' @param path Path to a self-contained SQLite snapshot.
#' @param title Application title.
#' @param page_size Detail rows per page, from 1 to 200.
#' @param download_limit Maximum rows in a dataset download.
#' @param profile_limit Maximum text rows retrieved for an explicit length profile.
#' @return A `shiny.appobj`. Start it with `shiny::runApp(app)`.
#' @export
#' @examples
#' if (interactive() && requireNamespace("shiny", quietly = TRUE) &&
#'   requireNamespace("bslib", quietly = TRUE) &&
#'   requireNamespace("ggplot2", quietly = TRUE)) {
#'   path <- system.file("extdata", "entropia-example.sqlite", package = "entropiaR")
#'   app <- entropia_dashboard(path)
#'   shiny::runApp(app)
#' }
entropia_dashboard <- function(path, title = "EntropIA: explorar el corpus",
                               page_size = 25L, download_limit = 10000L,
                               profile_limit = 1000L) {
  ent_require_dashboard()
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
    !ent_is_sqlite_header(path)) {
    ent_abort("entropia_error_not_sqlite", "{.arg path} must name a readable SQLite snapshot.")
  }
  if (!is.character(title) || length(title) != 1L || is.na(title)) {
    ent_abort("entropia_error_invalid_argument", "{.arg title} must be one string.")
  }
  page_size <- ent_validate_chunk_size(page_size)
  download_limit <- ent_validate_chunk_size(download_limit)
  profile_limit <- ent_validate_chunk_size(profile_limit)
  if (page_size > 200L) {
    ent_abort("entropia_error_invalid_argument", "{.arg page_size} must not exceed 200.")
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  wal <- paste0(path, "-wal")
  if (file.exists(wal) && isTRUE(file.info(wal)$size > 0)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "The source has a nonempty WAL. Use {.fn entropia_copy} before opening the dashboard."
    )
  }

  ui <- bslib::page_sidebar(
    title = title,
    sidebar = bslib::sidebar(
      title = "Universo del estudio", width = 300,
      shiny::selectInput("collections", "Colecciones (sin selecci\u00f3n: todas)",
        choices = character(), multiple = TRUE
      ),
      shiny::selectInput("types", "Tipos de asset (sin selecci\u00f3n: todos)",
        choices = character(), multiple = TRUE
      ),
      shiny::checkboxInput("pages", "Incluir p\u00e1ginas de PDF", TRUE),
      shiny::selectInput("date_var", "Fecha del estudio", choices = c(
        "Creaci\u00f3n del item" = "item_created_at",
        "Actualizaci\u00f3n del item" = "item_updated_at",
        "Creaci\u00f3n del asset" = "asset_created_at"
      )),
      shiny::checkboxInput("date_filter", "Limitar intervalo temporal", FALSE),
      shiny::conditionalPanel(
        "input.date_filter",
        shiny::dateRangeInput("dates", "Intervalo inclusivo",
          start = as.Date("1900-01-01"), end = Sys.Date()
        )
      ),
      shiny::selectInput("text_source", "Fuente de texto", choices = c(
        "Autom\u00e1tica: extracci\u00f3n, luego transcripci\u00f3n" = "auto",
        "Extracci\u00f3n" = "extraction", "Transcripci\u00f3n" = "transcription"
      )),
      shiny::selectInput("entity_source", "Fuente de entidades", choices = c("Todas" = "")),
      shiny::selectInput("model", "Modelo de entidades", choices = c("Todos" = "")),
      shiny::checkboxInput("use_confidence", "Filtrar confianza de entidades", FALSE),
      shiny::conditionalPanel(
        "input.use_confidence",
        shiny::sliderInput("confidence", "Confianza m\u00ednima", min = 0, max = 1, value = 0.5)
      ),
      shiny::actionButton("apply", "Aplicar filtros", class = "btn-primary"),
      shiny::tags$p(paste(
        "Las fechas de creaci\u00f3n/importaci\u00f3n no equivalen a la",
        "fecha del documento."
      )),
      shiny::tags$p("Las entidades extra\u00eddas por IA no son hechos verificados.")
    ),
    bslib::navset_card_tab(
      bslib::nav_panel(
        "Resumen",
        shiny::verbatimTextOutput("source_info"),
        shiny::tableOutput("counts"),
        shiny::plotOutput("collections_plot"),
        shiny::tableOutput("collections_table"),
        shiny::tags$h3("Esquema: esperado y observado"),
        shiny::tableOutput("inventory")
      ),
      bslib::nav_panel(
        "Calidad",
        shiny::tags$p("Cada tasa conserva unidad, numerador, denominador y disponibilidad."),
        shiny::plotOutput("quality_plot", height = "500px"),
        shiny::tableOutput("quality_table")
      ),
      bslib::nav_panel(
        "Exploraci\u00f3n",
        shiny::plotOutput("temporal_plot"),
        shiny::plotOutput("entities_plot"),
        shiny::tableOutput("entities_table"),
        shiny::plotOutput("topics_plot"),
        shiny::tableOutput("topics_table"),
        shiny::actionButton("lengths", "Calcular perfil acotado de texto"),
        shiny::textOutput("length_notice"),
        shiny::plotOutput("length_plot"),
        shiny::tableOutput("length_summary")
      ),
      bslib::nav_panel(
        "Detalle",
        shiny::textOutput("page_notice"),
        shiny::actionButton("previous", "P\u00e1gina anterior"),
        shiny::actionButton("next_page", "P\u00e1gina siguiente"),
        shiny::tableOutput("detail"),
        shiny::selectInput("document", "Asset de esta p\u00e1gina", choices = character()),
        shiny::actionButton("show_text", "Mostrar texto seleccionado"),
        shiny::tags$p("El texto se muestra escapado, nunca como HTML ejecutable."),
        shiny::verbatimTextOutput("document_text")
      ),
      bslib::nav_panel(
        "Exportaci\u00f3n",
        shiny::verbatimTextOutput("selection_info"),
        shiny::textOutput("download_notice"),
        shiny::checkboxInput("download_text", "Incluir texto documental en la descarga", FALSE),
        shiny::downloadButton("download_data", "Dataset CSV"),
        shiny::downloadButton("download_recipe", "Procedencia JSON"),
        shiny::downloadButton("download_eda", "Tablas EDA JSON"),
        shiny::downloadButton("download_plot", "Figura temporal PNG"),
        shiny::tags$p(paste(
          "Las descargas omiten rutas y metadata. Revise nombres e IDs",
          "antes de compartir."
        ))
      )
    )
  )

  server <- function(input, output, session) {
    con <- entropia_connect(path, quiet = TRUE)
    session$onSessionEnded(function() {
      try(DBI::dbRollback(con), silent = TRUE)
      entropia_disconnect(con)
    })
    # Transaction pins one read snapshot for all panels in this session.
    DBI::dbBegin(con)
    colls <- dplyr::collect(dplyr::select(entropia_collections(con), "id", "name"))
    shiny::updateSelectInput(session, "collections",
      choices = ent_dashboard_choices(colls, "name", "id")
    )
    types <- dplyr::collect(dplyr::distinct(dplyr::select(entropia_assets(con), "type")))$type
    shiny::updateSelectInput(session, "types", choices = sort(types[!is.na(types)]))
    if (DBI::dbExistsTable(con, "entities")) {
      fields <- DBI::dbListFields(con, "entities")
      for (pair in list(c("source", "entity_source"), c("model_name", "model"))) {
        if (pair[[1]] %in% fields) {
          choices <- dplyr::collect(dplyr::distinct(dplyr::select(
            entropia_entities(con), dplyr::all_of(pair[[1]])
          )))[[1]]
          choices <- sort(choices[!is.na(choices) & nzchar(choices)])
          shiny::updateSelectInput(session, pair[[2]], choices = c("Todos" = "", choices))
        }
      }
    }
    selected <- shiny::eventReactive(input$apply,
      {
        dates <- NULL
        if (isTRUE(input$date_filter)) {
          shiny::req(length(input$dates) == 2L, !anyNA(input$dates))
          dates <- as.POSIXct(input$dates, tz = "UTC")
          dates[[2]] <- dates[[2]] + 86400 - 0.001
        }
        list(
          collection_ids = if (length(input$collections)) input$collections else NULL,
          asset_types = if (length(input$types)) input$types else NULL,
          page_assets = isTRUE(input$pages), date_var = input$date_var,
          date_range = dates, text_source = input$text_source,
          entity_source = if (nzchar(input$entity_source %||% "")) input$entity_source else NULL,
          model_name = if (nzchar(input$model %||% "")) input$model else NULL,
          min_confidence = if (isTRUE(input$use_confidence)) input$confidence else NULL
        )
      },
      ignoreNULL = FALSE
    )
    overview <- shiny::reactive({
      do.call(entropia_overview, c(list(con = con), selected()))
    })
    query <- shiny::reactive(ent_dashboard_query(con, selected()))
    total_rows <- shiny::reactive(dplyr::collect(dplyr::tally(query()))$n[[1]])
    current_page <- shiny::reactiveVal(1L)
    shiny::observeEvent(selected(), current_page(1L))
    shiny::observeEvent(input$previous, current_page(max(1L, current_page() - 1L)))
    shiny::observeEvent(input$next_page, {
      pages <- max(1, ceiling(total_rows() / page_size))
      current_page(min(pages, current_page() + 1L))
    })
    details <- shiny::reactive(ent_dashboard_page(con, query(), current_page(), page_size))
    shiny::observeEvent(details(), {
      rows <- details()
      rows <- rows[!is.na(rows$asset_id), , drop = FALSE]
      shiny::updateSelectInput(session, "document",
        choices = stats::setNames(rows$asset_id, paste(rows$item_title, rows$asset_id,
          sep = " \u2014 "
        ))
      )
    })
    output$source_info <- shiny::renderText(paste0(
      "Esquema: ", entropia_schema_version(con),
      "\nModo: snapshot de solo lectura; conexi\u00f3n aislada por sesi\u00f3n.",
      "\nFecha operativa elegida: ", selected()$date_var
    ))
    output$counts <- shiny::renderTable(overview()$counts)
    output$collections_table <- shiny::renderTable(overview()$collections)
    output$collections_plot <- shiny::renderPlot(entropia_plot_collections(overview()$collections))
    output$inventory <- shiny::renderTable(overview()$inventory)
    output$quality_table <- shiny::renderTable(overview()$quality)
    output$quality_plot <- shiny::renderPlot(entropia_plot_coverage(overview()$quality))
    output$temporal_plot <- shiny::renderPlot(entropia_plot_temporal(overview()$temporal,
      date_var = "date"
    ))
    output$entities_plot <- shiny::renderPlot(entropia_plot_entities(overview()$entities))
    output$entities_table <- shiny::renderTable(overview()$entities)
    output$topics_plot <- shiny::renderPlot(entropia_plot_topics(overview()$topics))
    output$topics_table <- shiny::renderTable(overview()$topics)
    output$page_notice <- shiny::renderText(paste0(
      "P\u00e1gina ", current_page(), " de ", max(1, ceiling(total_rows() / page_size)),
      "; ", total_rows(), " filas del universo (no documentos independientes)."
    ))
    output$detail <- shiny::renderTable(details())
    text_result <- shiny::eventReactive(input$show_text, {
      id <- input$document
      shiny::req(length(id) == 1L, nzchar(id))
      # Verify the selected asset still belongs to the applied universe.
      q <- ent_dashboard_query(con, selected(), text = selected()$text_source)
      q <- dplyr::filter(q, .data$asset_id == !!id)
      rows <- dplyr::collect(utils::head(dplyr::select(q, "text"), 1L))
      if (!nrow(rows) || is.na(rows$text[[1]])) "Sin texto disponible." else rows$text[[1]]
    })
    output$document_text <- shiny::renderText({
      input$apply
      shiny::req(text_result())
      text_result()
    })
    length_result <- shiny::eventReactive(input$lengths, {
      q <- ent_dashboard_query(con, selected(), text = selected()$text_source)
      q <- dplyr::arrange(
        dplyr::select(q, "item_id", "asset_id", "asset_type", "text"),
        .data$item_id, .data$asset_id
      )
      rows <- dplyr::collect(utils::head(q, profile_limit))
      list(data = entropia_document_lengths(rows), selection = selected())
    })
    valid_lengths <- shiny::reactive({
      shiny::req(length_result())
      shiny::validate(shiny::need(
        identical(length_result()$selection, selected()),
        "Los filtros cambiaron: vuelva a calcular el perfil de texto."
      ))
      length_result()$data
    })
    output$length_notice <- shiny::renderText(paste0(
      "Vista acotada: primeras ", min(total_rows(), profile_limit), " de ", total_rows(),
      " filas, ordenadas por item/asset. No es una muestra aleatoria representativa."
    ))
    output$length_plot <- shiny::renderPlot(entropia_plot_distribution(valid_lengths(), "n_words"))
    output$length_summary <- shiny::renderTable(entropia_profile(
      valid_lengths(),
      columns = c("n_chars", "n_words")
    )$numeric)
    output$selection_info <- shiny::renderText(jsonlite::toJSON(
      selected(),
      pretty = TRUE, auto_unbox = TRUE, null = "null", POSIXt = "ISO8601"
    ))
    output$download_notice <- shiny::renderText(paste0(
      total_rows(), " filas seleccionadas; l\u00edmite de descarga: ", download_limit,
      if (total_rows() > download_limit) ". Reduzca el universo antes de descargar." else "."
    ))
    download_dataset <- shiny::reactive({
      shiny::validate(shiny::need(
        total_rows() <= download_limit,
        "Reduzca el universo de descarga."
      ))
      args <- selected()[c(
        "collection_ids", "asset_types", "page_assets", "date_var",
        "date_range"
      )]
      cols <- c(
        "item_id", "item_title", "collection_id", "collection_name", "asset_id",
        "asset_type", "asset_size", "item_created_at", "asset_created_at"
      )
      if (isTRUE(input$download_text)) cols <- c(cols, "text")
      do.call(entropia_analysis_dataset, c(list(
        con = con, name = "dashboard-selection", columns = cols,
        text = if (isTRUE(input$download_text)) selected()$text_source else FALSE
      ), args))
    })
    output$download_data <- shiny::downloadHandler(
      filename = function() "entropia-selection.csv",
      content = function(file) entropia_export(download_dataset(), file, "csv")
    )
    output$download_recipe <- shiny::downloadHandler(
      filename = function() "entropia-provenance.json",
      content = function(file) entropia_write_provenance(download_dataset(), file, redact = TRUE)
    )
    output$download_eda <- shiny::downloadHandler(
      filename = function() "entropia-eda.json",
      content = function(file) {
        result <- overview()
        result$provenance$source_path <- NULL
        jsonlite::write_json(result, file,
          pretty = TRUE, auto_unbox = TRUE,
          null = "null", na = "null", POSIXt = "ISO8601"
        )
      }
    )
    output$download_plot <- shiny::downloadHandler(
      filename = function() "entropia-temporal.png",
      content = function(file) {
        ggplot2::ggsave(
          file, entropia_plot_temporal(overview()$temporal, date_var = "date"),
          device = "png", width = 8, height = 5, dpi = 144
        )
      }
    )
  }
  shiny::shinyApp(ui, server)
}
