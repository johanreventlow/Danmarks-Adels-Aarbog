local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R"))
})

event_df <- function(id=c(1,2), key=c("a","b"), status=c("interessant","kandidat"),
                     narrative_id=rep(10,length(id)), category=rep("embede",length(id)),
                     dmin=rep("1580-01-01",length(id)), dmax=rep("1580-12-31",length(id))) {
  data.frame(id=id,narrative_id=narrative_id,noegle=key,feed_status=status,
             kategori=category,date_min=dmin,date_max=dmax,klausul=paste("old",key),
             stringsAsFactors=FALSE)
}
new_df <- function(key=c("a","c"), narrative_id=rep(10,length(key)),
                   category=rep("embede",length(key)), dmin=rep("1580-01-01",length(key)),
                   dmax=rep("1580-12-31",length(key))) {
  data.frame(narrative_id=narrative_id,noegle=key,kategori=category,
             date_min=dmin,date_max=dmax,klausul=paste("new",key),stringsAsFactors=FALSE)
}

test_that("nøglematch updater med stabilt id uden statusfelt og ny nøgle inserter", {
  p <- plan_merge(event_df(), new_df())
  expect_equal(p$updates$id, 1)
  expect_false("feed_status" %in% names(p$updates))
  expect_equal(p$inserts$noegle, "c")
  expect_equal(p$inserts$feed_status, "kandidat")
})

test_that("forældreløs kandidat slettes", {
  old <- event_df(id=2,key="b",status="kandidat")
  p <- plan_merge(old, new_df(key="c",category="rejse",dmin="1600-01-01",dmax="1600-12-31"))
  expect_equal(p$deletes$id, 2)
  expect_equal(0, nrow(p$mistede))
})

test_that("entydigt sekundærmatch overfører markering", {
  old <- event_df(id=1,key="gammel",status="skjult")
  p <- plan_merge(old, new_df(key="ny"))
  expect_equal("skjult", p$inserts$feed_status)
  expect_equal(1, nrow(p$overfoerte))
  expect_equal(0, nrow(p$mistede))
})

test_that("nul eller flere sekundærtræf logger mistet markering", {
  old <- event_df(id=1,key="gammel",status="interessant")
  none <- plan_merge(old, new_df(key="ny",category="rejse"))
  many <- plan_merge(old, new_df(key=c("x","y")))
  expect_equal(1, nrow(none$mistede))
  expect_equal(1, nrow(many$mistede))
  expect_true(all(many$inserts$feed_status == "kandidat"))
})

test_that("narrativer uden for input er urørte", {
  old <- event_df(id=c(1,2),key=c("a","z"),status=c("kandidat","skjult"),narrative_id=c(10,99))
  p <- plan_merge(old, new_df(key="a",narrative_id=10))
  expect_equal(2, p$untouched$id)
  expect_false(2 %in% p$deletes$id)
})

test_that("spanberegning bruger næste forekomst og fejler lukket", {
  text <- "I 1580 rejste han. I 1580 rejste han."
  clause <- "I 1580 rejste han."
  a <- genberegn_span(text, clause)
  b <- genberegn_span(text, clause, a$brugte_offsets)
  missing <- genberegn_span(text, "opfundet", b$brugte_offsets)
  expect_equal(c(0L, nchar(clause) + 1L), c(a$start,b$start))
  expect_true(is.na(missing$start))
})

test_that("rygrad matcher entydig dato eller normaliseret date_raw", {
  facts <- data.frame(id=c(7,8),date_min=c("1580-01-01",NA),date_max=c("1580-12-31",NA),
                      date_raw=c("1580","  CA.   1600 "),stringsAsFactors=FALSE)
  rels <- data.frame(id=9,date_min="1700-01-01",date_max="1700-12-31",date_raw="1700")
  expect_equal(7, match_rygrad(list(date_min="1580-01-01",date_max="1580-12-31",date_raw=NA),facts,rels)$fact_id)
  expect_equal(8, match_rygrad(list(date_min=NA,date_max=NA,date_raw="ca. 1600"),facts,rels)$fact_id)
  expect_equal(9, match_rygrad(list(date_min="1700-01-01",date_max="1700-12-31",date_raw=NA),facts,rels)$relation_id)
  miss <- match_rygrad(list(date_min=NA,date_max=NA,date_raw=NA),facts,rels)
  expect_true(is.na(miss$fact_id) && is.na(miss$relation_id))
})

test_that("NULL-datoer matcher aldrig hinanden", {
  facts <- data.frame(id=7,date_min=NA_character_,date_max=NA_character_,date_raw=NA_character_)
  got <- match_rygrad(list(date_min=NA,date_max=NA,date_raw=NA),facts,data.frame())
  expect_true(is.na(got$fact_id))
})
