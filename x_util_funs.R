




# this script contains general utility functions





paste0_NA_to_zerolength <- function(..., collapse = NULL) {
  arg_list <- lapply(list(...), function(elem) {
    elem[is.na(elem)] <- ""
    elem
  })
  arg_list <- c(arg_list, collapse)
  do.call(paste, arg_list)
}





normalise_text <- function(x) {
  x <- gsub("\\n|\\r", " ", x)
  x <- gsub("[: ]{1,}", " ", x)
  x <- gsub("\\.{2,}", " ", x)
  x <- gsub("\\_+", " ", x)
  x <- gsub("\\-{2,}", " ", x)
  x <- gsub("(?<=[0-9])(?=[a-zåäöA-ZÅÄÖ])", " ", x, perl = TRUE)
  roman_numerals <- toupper(c(
    "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"
  ))
  roman_numeral_res <- paste0(
    " ", roman_numerals, " "
  )
  for (i in seq_along(roman_numerals)) {
    x <- gsub(roman_numeral_res[i], paste0(" ", i, " "), x)
  }
  x <- gsub("\\s+", " ", x)
  x <- tolower(x)
  x
}





#' Like setdiff, but retains duplicate entries (a set has no duplicates, a group
#' may have)
groupdiff <- function(x, y) {
  requireNamespace("data.table")
  stopifnot(
    identical(class(x), class(y))
  )
  
  match_fun <- `%in%`
  if (is.character(x)) {
    match_fun <- data.table::`%chin%`
  }
  
  keep <- rep(TRUE, length(x))
  for (i in seq_along(y)) {
    mark_for_drop <- match_fun(x, y[i]) & keep
    mark_for_drop <- mark_for_drop & !duplicated(mark_for_drop)
    if (sum(mark_for_drop) == 1L) {
      keep[mark_for_drop] <- FALSE
    }
  }
  
  x[keep]
}
local({
  stopifnot(
    identical(groupdiff(1:3, 1:3), integer(0L)),
    identical(groupdiff(1:3, c(1:3, 3L)), integer(0L)),
    identical(groupdiff(c(1:3, 3L), 1:3), 3L),
    identical(groupdiff(c(1:3, 3L, 3L), 1:3), c(3L, 3L))
  )
})





bootstrap <- function(
  x,
  statistics_fun = function(x, i) {
    mean(x[i])
  },
  statistics_id_dt = data.table::data.table(statistic = "mean"),
  n_bootstrap_samples = 1e3L,
  n_threads = 4L,
  verbose = TRUE
) {
  requireNamespace("boot")
  requireNamespace("data.table")
  
  if (verbose) {
    message("* bootstrap: bootstrapping...")
    t <- proc.time()
  }
  b <- boot::boot(
    data = x,
    statistic = statistics_fun,
    R = n_bootstrap_samples,
    sim = "ordinary",
    stype = "i",
    ncpus = n_threads
  )
  
  ci <- lapply(seq_along(b[["t0"]]), function(i) {
    utils::tail(as.vector(
      boot::boot.ci(boot.out = b, index = i, type = "perc")[["percent"]]
    ), 2L)
  })
  
  ci[] <- lapply(ci, function(elem) {
    if (is.null(elem)) {
      rep(1.0, 2)
    } else {
      elem
    }
  })
  
  ci <- do.call(what = rbind, args = ci)
  ci <- cbind(b[["t0"]], 
              as.vector(apply(b[["t"]], 2L, mean)), 
              as.vector(apply(b[["t"]], 2L, median)),
              ci)
  rownames(ci) <- names(b[["t0"]])
  colnames(ci) <- c("grand_estimate", "mean", "median", "lo", "hi")
  
  ci <- data.table::as.data.table(ci)
  ci <- cbind(statistics_id_dt, ci)
  
  if (verbose) {
    message("* bootstrap: done; ", data.table::timetaken(t))
    t <- proc.time()
  }
  
  ci
}






# data format funs -------------------------------------------------------------
# in the standard format, each row has, at a minimum, the value for c alone.
# there are no rows with value for "a" or "b" alone, even though in the texts
# they occasionally appear separately from others values 
# (e.g. structured format such as "most common gleason ..... 4", 
# "second most common gleason ..... 5"). it has (at a minimum) columns
# - text_id: identifies note-fields (not fields within notes) or just the notes
#   where the fields have been pasted together
# - text: contains the text
# - a: integer (a + b = c)
# - b: integer (a + b = c)
# - c: integer (a + b = c)
#
# in the typed format we have separate rows for even components of the
# gleason score, e.g.
# "most common gleason 4 ... second most common gleason 5"  
# recorded as a = 4 on one row and b = 5 on another row.
#


check_match_types <- function(match_types) {
  stopifnot(
    inherits(match_types, c("character", "factor")),
    match_types %in% c("a", "b", "c", "a + b", "a + b = c", "kw_all_a", NA_character_)
  )
}

check_gleason_a_values <- check_gleason_b_values <- function(values) {
  stopifnot(
    is.integer(values),
    values %in% c(2:5, NA_integer_)
  )
}

check_gleason_c_values <- function(values) {
  stopifnot(
    is.integer(values),
    values %in% c(4:10, NA_integer_)
  )
}

check_gleason_abc_values <- function(a, b, c) {
  check_gleason_a_values(a)
  check_gleason_b_values(b)
  check_gleason_c_values(c)
  stopifnot(
    length(a) == length(b),
    length(c) == length(a)
  )
  
  has_abc <- !is.na(a + b + c)
  n_has_abc <- sum(has_abc)
  n_correct_abc <- sum((a + b)[has_abc] == c[has_abc])
  if (n_correct_abc < n_has_abc) {
    warning("of ", n_has_abc, " observations with a, b, and c defined, in ",
            n_has_abc - n_correct_abc, " observations a + b != c")
  }
  invisible(NULL)
}

infer_match_type <- function(a, b, c) {
  check_gleason_abc_values(a, b, c)
  
  type <- rep(NA_character_, length(a))
  has_a <- !is.na(a)
  has_b <- !is.na(b)
  has_c <- !is.na(c)
  type[has_a & has_b & has_c] <- "a + b = c"
  type[has_a & has_b & !has_c] <- "a + b"
  type[has_a & !has_b & !has_c] <- "a"
  type[!has_a & has_b & !has_c] <- "b"
  type[!has_a & !has_b & has_c] <- "c"
  
  # type <- factor(type, levels = c("a + b = c", "a + b", "a", "b", "c"))
  
  return(type)
}

infer_standard_format_match_type <- function(a_src, b_src, c_src) {
  stopifnot(
    is.character(a_src),
    is.character(b_src),
    is.character(c_src),
    length(a_src) == length(b_src),
    length(b_src) == length(c_src)
  )
  sum_re <- "\\d\\s*\\+\\s*\\d"
  is_addition_with_sum <- grepl(sum_re, c_src)
  is_addition_without_sum <- grepl(sum_re, a_src) & !is_addition_with_sum
  is_gleasonless <- is.na(a_src) & is.na(b_src) & is.na(c_src)
  
  type <- rep(NA_character_, length(a_src))
  type[is_addition_without_sum] <- "a + b"
  type[is_addition_with_sum] <- "a + b = c"
  type[is_gleasonless] <- "gleasonless"
  type
}

infer_typed_format_match_type <- function(a_src, b_src, c_src) {
  type <- infer_standard_format_match_type(a_src, b_src, c_src)
  type[!is.na(a_src) & is.na(b_src) & is.na(c_src)] <- "a"
  type[is.na(a_src) & !is.na(b_src) & is.na(c_src)] <- "b"
  type[is.na(a_src) & is.na(b_src) & !is.na(c_src)] <- "c"
  type
}

standard_format_dt_to_typed_format_dt <- function(dt) {
  requireNamespace("data.table")
  stopifnot(
    data.table::is.data.table(dt),
    c("text_id", "text", "a", "b", "c", "a_src","b_src","c_src") %in% names(dt)
  )
  
  dt <- data.table::copy(dt)
  dt[, "match_type" := infer_standard_format_match_type(a_src, b_src, c_src)]
  dt[match_type == "a + b", "src" := a_src]
  dt[match_type == "a + b = c", "src" := c_src]
  dt[match_type == "gleasonless", "src" := NA_character_]
  
  dt[, ".__tmp_order" := 1:.N]
  
  keywordy <- dt[is.na(match_type), ]
  keywordy <- data.table::rbindlist(lapply(c("a", "b", "c"), function(letter) {
    is_letter <- !is.na(keywordy[[letter]])
    letter_dt <- keywordy[is_letter, ]
    letter_dt[, "src" := .SD, .SDcols = paste0(letter, "_src")]
    letter_dt[, (setdiff(c("a", "b", "c"), letter)) := NA_integer_]
    letter_dt[, "match_type" := letter]
    letter_dt[]
  }))
  
  match_typed_dt <- rbind(
    dt[!is.na(match_type), ],
    keywordy,
    use.names = TRUE
  )
  data.table::setkeyv(match_typed_dt, c("text_id", ".__tmp_order"))
  match_typed_dt[, ".__tmp_order" := NULL]
  match_typed_dt[, c("a_src", "b_src", "c_src") := NULL]
  match_typed_dt[]
}


determine_element_sets <- function(dt, n_max_each = 5L) {
  requireNamespace("data.table")
  stopifnot(
    data.table::is.data.table(dt),
    c("a", "b", "c") %in% names(dt),
    !c("grp", "grp_type", "type") %in% names(dt)
  )
  
  allowed_sets <- list(
    c("c", "a", "b"),
    c("c", "b", "a"),
    c("a", "b", "c"),
    c("b", "a", "c"),
    c("a", "b"),
    "a",
    "b",
    "c"
  )
  
  lapply(c("a", "b", "c"), function(elem_nm) {
    is_na <- is.na(dt[[elem_nm]])
    dt[!is_na, "type" := ..elem_nm]
    NULL
  })
  
  n <- nrow(dt)
  dt[, "grp" := NA_integer_]
  max_grp <- 0L
  while (anyNA(dt[["grp"]])) {
    wh_first <- which(is.na(dt[["grp"]]))[1L]
    for (i in seq_along(allowed_sets)) {
      break_search <- FALSE
      for (n_each in 1:n_max_each) {
        candidate <- rep(allowed_sets[[i]], each = n_each)
        r <- wh_first:min(n, wh_first + length(candidate) - 1L)
        if (identical(dt[["type"]][r], candidate)) {
          dt[
            i = r, 
            j = c("grp", "grp_type") := list(
              max_grp + 1L, paste0(candidate, collapse = "")
            )
            ]
          max_grp <- max_grp + 1L
          
          break_search <- TRUE
          break()
        }
      }
      if (break_search) {
        break()
      }
    }
  }
  
  return(dt[])
}


typed_format_dt_to_standard_format_dt <- function(dt) {
  stopifnot(
    data.table::is.data.table(dt),
    c("text_id", "obs_id", "text", "match_type", "a", "b", "c") %in% names(dt),
    is.integer(dt[["obs_id"]]),
    !duplicated(dt[["obs_id"]])
  )
  check_match_types(dt[["match_type"]])
  check_gleason_abc_values(a = dt[["a"]], b = dt[["b"]], c = dt[["c"]])
  
  dt <- data.table::copy(dt)
  data.table::setkeyv(dt, c("text_id", "obs_id"))
  
  is_single_elem_match <- dt[["match_type"]] %in% c("a", "b", "c")
  elem_dt <- dt[is_single_elem_match, ]
  if (nrow(elem_dt) > 0L) {
    # sequential observations have diff(obs_id) == 1L, non-seq. have > 1L;
    # latter cases are first in their set of sequential observations
    wh_first_in_seq_set <- union(1L, elem_dt[, which(c(1L, diff(obs_id)) > 1L)])
    wh_last_in_seq_set <- union(wh_first_in_seq_set[-1L] - 1L, nrow(elem_dt))
    elem_dt[, ".__processing_grp" := NA_integer_]
    invisible(lapply(seq_along(wh_first_in_seq_set), function(i) {
      elem_dt[
        i = wh_first_in_seq_set[i]:wh_last_in_seq_set[i], 
        j = ".__processing_grp" := i
        ]
      NULL
    }))
    elem_dt[, ".__processing_grp" := .GRP, by = c("text_id", ".__processing_grp")]
    elem_dt <- elem_dt[
      j = determine_element_sets(dt = data.table::as.data.table(.SD), n_max_each = 6L),
      by = ".__processing_grp"
      ]
    elem_dt[, ".__processing_grp" := .GRP, by = c("grp", ".__processing_grp")]
    
    elem_dt <- lapply(unique(elem_dt[[".__processing_grp"]]), function(grp) {
      ..__grp <- grp
      sub_dt <- elem_dt[.__processing_grp == ..__grp, ]
      sub_dt[
        j = {
          a <- a[!is.na(a)]
          b <- b[!is.na(b)]
          c <- c[!is.na(c)]
          n <- max(length(a), length(b), length(c))
          if (length(a) == 0L) {
            a <- rep(NA_integer_, n)
          }
          if (length(b) == 0L) {
            b <- rep(NA_integer_, n)
          }
          if (length(c) == 0L) {
            c <- rep(NA_integer_, n)
          }
          sd <- .SD[1:n, ]
          cbind(sd, a = a, b = b, c = c)
        }, .SDcols = setdiff(names(dt), c("a", "b", "c"))
        ]
    })
    elem_dt <- data.table::rbindlist(elem_dt)
  }
  
  out <- rbind(elem_dt, dt[!is_single_elem_match, ],
               use.names = TRUE, fill = TRUE)
  out[, "match_type" := NULL]
  data.table::setkeyv(out, c("text_id", "obs_id"))
  out[] 
}








