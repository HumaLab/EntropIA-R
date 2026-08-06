test_that("package loads with expected metadata", {
  info <- utils::packageDescription("entropiaR")
  expect_equal(info$Package, "entropiaR")
  expect_true(grepl("MIT", info$License, fixed = TRUE))
})
