import gleam/string

// From: https://github.com/hayleigh-dot-dev/nibble/blob/main/src/nibble/predicates.gleam
// MIT licensed: https://github.com/hayleigh-dot-dev/nibble?tab=MIT-1-ov-file#readme
// Author: Hayleigh Thompson
pub fn is_lower_ascii(grapheme: String) -> Bool {
  case grapheme {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" -> True
    "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" -> True
    "w" | "x" | "y" | "z" -> True
    _ -> False
  }
}

// From: https://github.com/hayleigh-dot-dev/nibble/blob/main/src/nibble/predicates.gleam
// MIT licensed: https://github.com/hayleigh-dot-dev/nibble?tab=MIT-1-ov-file#readme
// Author: Hayleigh Thompson
pub fn is_upper_ascii(grapheme: String) -> Bool {
  case grapheme {
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" -> True
    "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" -> True
    "W" | "X" | "Y" | "Z" -> True
    _ -> False
  }
}

// From: https://github.com/hayleigh-dot-dev/nibble/blob/main/src/nibble/predicates.gleam
// MIT licensed: https://github.com/hayleigh-dot-dev/nibble?tab=MIT-1-ov-file#readme
// Author: Hayleigh Thompson
pub fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

// From: https://github.com/hayleigh-dot-dev/nibble/blob/main/src/nibble/predicates.gleam
// MIT licensed: https://github.com/hayleigh-dot-dev/nibble?tab=MIT-1-ov-file#readme
// Author: Hayleigh Thompson
pub fn is_whitespace(grapheme: String) -> Bool {
  case grapheme {
    " " | "\t" | "\r" | "\n" -> True
    _ -> False
  }
}

pub fn is_alphanumeric(grapheme: String) -> Bool {
  case
    is_lower_ascii(grapheme) || is_upper_ascii(grapheme) || is_digit(grapheme)
  {
    True -> True
    _ -> False
  }
}

pub fn is_alphanumeric_or_dash_or_underscore(grapheme: String) -> Bool {
  case is_alphanumeric(grapheme) || grapheme == "_" || grapheme == "-" {
    True -> True
    _ -> False
  }
}

pub fn is_alphanumeric_or_dash_or_underscore_or_period(grapheme: String) -> Bool {
  case is_alphanumeric_or_dash_or_underscore(grapheme) || grapheme == "." {
    True -> True
    _ -> False
  }
}

pub fn get_chars_matching_func(
  s: String,
  acc: String,
  match_func: fn(String) -> Bool,
) -> #(String, String) {
  case string.pop_grapheme(s) {
    Ok(#(grapheme, rest)) -> {
      case match_func(grapheme) {
        True -> get_chars_matching_func(rest, acc <> grapheme, match_func)
        False -> #(acc, s)
      }
    }
    Error(_) -> #(acc, s)
  }
}

pub fn get_whitespace(s: String) -> #(String, String) {
  get_chars_matching_func(s, "", is_whitespace)
}

// Get the (alphanumeric) name of an HTML tag or attribute name, and ignore any
// whitespace around the name.
pub fn get_name_ignore_ws(s: String) -> #(String, String, Int) {
  let i = 0
  let #(whitespace_chars, rest) = get_whitespace(s)
  let i = i + string.length(whitespace_chars)

  let #(name_graphemes, rest) =
    get_chars_matching_func(rest, "", is_alphanumeric_or_dash_or_underscore)
  let i = i + string.length(name_graphemes)

  let #(whitespace_chars, rest) = get_whitespace(rest)
  let i = i + string.length(whitespace_chars)

  #(name_graphemes, rest, i)
}

pub fn is_not_double_quote(grapheme: String) -> Bool {
  case grapheme {
    "\"" -> False
    _ -> True
  }
}

pub fn is_not_single_quote(grapheme: String) -> Bool {
  case grapheme {
    "'" -> False
    _ -> True
  }
}

pub fn is_not_whitespace(grapheme: String) -> Bool {
  case is_whitespace(grapheme) {
    True -> False
    _ -> True
  }
}

pub fn is_not_gt(grapheme: String) -> Bool {
  case grapheme {
    ">" -> False
    _ -> True
  }
}
