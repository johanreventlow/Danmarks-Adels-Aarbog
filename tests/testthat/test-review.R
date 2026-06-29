test_that("merge_review_decisions applies confirm/reject/new-id idempotently", {
  cw <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"),
                   score = c(0.8,0.75,0.72), tier = c("review","review","review"),
                   stringsAsFactors = FALSE)
  dec <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"),
                    afgoerelse = c("bekræft","afvis","ny-id"), ny_tng_id = c(NA,NA,"I99"),
                    stringsAsFactors = FALSE)
  out1 <- merge_review_decisions(cw, dec)
  expect_equal(out1$tier[out1$person_id==1L], "accepted")
  expect_equal(out1$tier[out1$person_id==2L], "afvist")
  expect_equal(out1$tng_id[out1$person_id==3L], "I99")
  expect_equal(out1$tier[out1$person_id==3L], "accepted")
  out2 <- merge_review_decisions(out1, dec)  # idempotent
  expect_equal(out1[order(out1$person_id),], out2[order(out2$person_id),])
})
