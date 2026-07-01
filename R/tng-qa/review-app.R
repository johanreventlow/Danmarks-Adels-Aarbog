#!/usr/bin/env Rscript
# Interaktiv reviewer til data/tng-review-queue.csv.
# Kør fra repo-roden: Rscript -e "shiny::runApp('R/tng-qa/review-app.R')"
#
# Skriver beslutninger direkte tilbage til samme CSV-skema som
# merge_review_decisions() (R/tng-qa/05-review.R) forventer ved næste
# pipeline-kørsel — ingen ny mekanisme, bare et pænere sted at redigere
# samme fil. Kør R/tng-qa/run-pipeline.R mindst én gang først.

suppressPackageStartupMessages({ library(shiny); library(DT) })

# shiny::runApp() på en enkelt-fil-app sætter working directory til filens
# egen mappe for hele app'ens levetid — derfor er stier her relative til
# R/tng-qa/, IKKE repo-roden (til forskel fra run-pipeline.R/run-tests.R).
source("05c-review-logic.R")

rq_csv <- file.path("..", "..", "data", "tng-review-queue.csv")

ui <- fluidPage(
  titlePanel("TNG-QA — gennemgå usikre kandidater"),
  fluidRow(column(12, textOutput("fremgang"))),
  fluidRow(column(12, DTOutput("tabel"))),
  hr(),
  fluidRow(
    column(7, h4("Valgt kandidat"), uiOutput("valgt_info")),
    column(5,
      selectInput("afgoerelse", "Afgørelse:",
                 choices = c("(ingen endnu)" = "", "Bekræft" = "bekræft",
                            "Afvis" = "afvis", "Andet TNG-id" = "ny-id")),
      conditionalPanel("input.afgoerelse == 'ny-id'",
                       textInput("ny_tng_id", "Nyt TNG-id (fx I1234):")),
      actionButton("gem", "Gem beslutning", class = "btn-primary")
    )
  )
)

server <- function(input, output, session) {
  rq <- reactiveVal(load_review_queue(rq_csv))

  vis_kolonner <- c("vores_label", "vores_navn", "vores_foedt", "vores_doed",
                    "tng_navn", "tng_foedt", "tng_doed", "score",
                    "familie_status", "familie_stoette_antal", "afgoerelse")

  output$tabel <- renderDT({
    datatable(rq()[, vis_kolonner], selection = "single", rownames = FALSE,
             options = list(pageLength = 20)) |>
      formatStyle("familie_status", backgroundColor = styleEqual(
        c("bekraeftet", "modstridende", "ingen_auto_nabo"),
        c("#d4edda", "#f8d7da", "#f0f0f0")))
  })

  valgt_raekke <- reactive({
    idx <- input$tabel_rows_selected
    if (is.null(idx) || !length(idx)) return(NULL)
    rq()[idx, ]
  })

  output$valgt_info <- renderUI({
    r <- valgt_raekke()
    if (is.null(r)) return(tags$p("Vælg en række i tabellen for at se detaljer."))
    tagList(
      tags$p(tags$b(sprintf("%s (%s) ↔ %s", r$vores_label, r$vores_navn, r$tng_navn))),
      tags$p(sprintf("Score: %.2f | Familie-status: %s (%d støtte)",
                     r$score, r$familie_status, r$familie_stoette_antal)),
      if (nzchar(r$familie_detalje)) tags$p(tags$em(r$familie_detalje)) else NULL
    )
  })

  observeEvent(valgt_raekke(), {
    r <- valgt_raekke()
    if (!is.null(r)) {
      updateSelectInput(session, "afgoerelse", selected = if (nzchar(r$afgoerelse)) r$afgoerelse else "")
      updateTextInput(session, "ny_tng_id", value = r$ny_tng_id)
    }
  })

  output$fremgang <- renderText({
    p <- review_progress(rq())
    sprintf("%d af %d kandidater besluttet (%d tilbage)", p$besluttet, p$total, p$resterende)
  })

  observeEvent(input$gem, {
    r <- valgt_raekke()
    if (is.null(r)) { showNotification("Vælg en række først.", type = "warning"); return() }
    ny <- tryCatch(
      set_decision(rq(), r$person_id, r$tng_id, input$afgoerelse, input$ny_tng_id),
      error = function(e) { showNotification(conditionMessage(e), type = "error"); NULL }
    )
    if (!is.null(ny)) {
      rq(ny)
      write_review_queue(ny, rq_csv)
      showNotification("Gemt.", type = "message")
    }
  })
}

shinyApp(ui, server)
