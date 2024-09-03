import gleam/list
import gleam/set.{type Set}
import gleam/string
import grapheme_util
import tagg_error.{type TaggError}

/// This represents the start/end of a custom tag. For example, this may be
/// used to identify where a <for> opening tag or </for> closing tag exists in
/// the HTML. At this stage, we're not intending to identify opening/closing tag
/// pairs or to parse the attributes inside the tags; we're just trying to
/// identify where the custom opening or closing tags are in the document.
pub type RawTag {
  RawTag(
    name: String,
    start: Int,
    end: Int,
    is_closing_tag: Bool,
    is_self_closing_tag: Bool,
    attrs_text: String,
  )
}

/// Once we've identified where the custom opening/closing tags exist in the
/// document, we'll separate the document into "sections"; a section will either
/// be a custom tag that we'll transform into HTML, or a fragment of text that
/// does not contain any custom tags. It's called a "raw" section because we've
/// only done minimal parsing so far, and are going to parse each "RawSection"
/// to create a "Section" with more specific attributes.
pub type RawSection {
  RawTextSection(text: String, start: Int, end: Int)
  RawTagSection(tag: RawTag)
}

/// Gets the attributes text inside an HTML tag, once the tag name has been
/// identified. For example, if we're parsing the following HTML:
/// ```html
/// <for items="people" item="person" index="i">
/// ```
/// This function will return the following:
/// ```
/// items="people" item="person" index="i"
/// ```
fn get_attrs_text(s: String) -> #(String, String) {
  grapheme_util.get_chars_matching_func(s, "", grapheme_util.is_not_gt)
}

/// Recursively parses a string to get a list of custom HTML tags (e.g. <for>)
/// in the document.
fn get_tags_rec(
  s: String,
  i: Int,
  custom_tag_names: Set(String),
  acc: List(RawTag),
) -> Result(List(RawTag), TaggError) {
  case s {
    "<!" <> rest -> get_tags_rec(rest, i + 2, custom_tag_names, acc)
    "</" <> rest -> {
      // the start of the '<' grapheme
      let start = i

      let i = i + 2
      let #(tag_name, rest, num_graphemes) =
        grapheme_util.get_name_ignore_ws(rest)
      let i = i + num_graphemes
      case set.contains(custom_tag_names, tag_name) {
        True -> {
          // this is a closing tag for a custom tag, we need to parse it and
          // store it
          case rest {
            ">" <> rest ->
              get_tags_rec(rest, i + 1, custom_tag_names, [
                RawTag(tag_name, start, i, True, False, ""),
                ..acc
              ])
            _ -> Error(tagg_error.TagNotClosedError("Closing tag not closed for tag: " <> tag_name))
          }
        }
        False -> {
          // this is not a custom tag, there's no reason to further parse it
          get_tags_rec(rest, i, custom_tag_names, acc)
        }
      }
    }
    "<" <> rest -> {
      // the start of the '<' grapheme
      let start = i

      let i = i + 1
      let #(tag_name, rest, num_graphemes) =
        grapheme_util.get_name_ignore_ws(rest)
      let i = i + num_graphemes

      case set.contains(custom_tag_names, tag_name) {
        True -> {
          // this is a custom tag, we need to parse it
          let #(attrs_text, rest) = get_attrs_text(rest)
          let i = i + string.length(attrs_text)

          case rest {
            ">" <> rest -> {
              case string.ends_with(attrs_text, "/") {
                True ->
                  get_tags_rec(rest, i + 1, custom_tag_names, [
                    RawTag(
                      tag_name,
                      start,
                      i,
                      False,
                      True,
                      string.drop_right(attrs_text, 1),
                    ),
                    ..acc
                  ])
                False ->
                  get_tags_rec(rest, i + 1, custom_tag_names, [
                    RawTag(tag_name, start, i, False, False, attrs_text),
                    ..acc
                  ])
              }
            }
            _ -> Error(tagg_error.TagNotClosedError("Closing tag not closed for tag: " <> tag_name))
          }
        }
        False -> {
          // this is not a custom tag, there's no reason to further parse it
          get_tags_rec(rest, i, custom_tag_names, acc)
        }
      }
    }
    _ -> {
      case string.pop_grapheme(s) {
        Ok(#(_grapheme, rest)) ->
          get_tags_rec(rest, i + 1, custom_tag_names, acc)
        Error(_) -> Ok(acc)
      }
    }
  }
}

/// Parses a string to get a list of custom HTML tags (e.g. <for>) in the
/// document.
fn get_tags(s: String, custom_tag_names: Set(String)) -> Result(List(RawTag), TaggError) {
  case get_tags_rec(s, 0, custom_tag_names, []) {
    Ok(tags) -> Ok(list.reverse(tags))
    Error(err) -> Error(err)
  }
}

// Note that "s" stores the _unprocessed_ strings (this string gets smaller as
// we process tags, in an attempt to be more efficient with our string
// operations). The "i", however, represents our current position with
// reference to the _original_ HTML string (this is because the 'start' and
// 'end' in the 'RawTag' type are relative to the original HTML string).
fn get_raw_sections_rec(
  tags: List(RawTag),
  s: String,
  i: Int,
  acc: List(RawSection),
) -> List(RawSection) {
  case list.first(tags) {
    Ok(tag) -> {
      case i < tag.start {
        True -> {
          // we need to process a text section and a tag that follows
          let text_len = tag.start - i
          let tag_len = tag.end - tag.start + 1
          get_raw_sections_rec(
            list.drop(tags, 1),
            string.drop_left(s, text_len + tag_len),
            tag.end + 1,
            [
              RawTagSection(tag),
              RawTextSection(string.slice(s, 0, text_len), i, tag.start - 1),
              ..acc
            ],
          )
        }
        False ->
          // we need to process only a tag
          get_raw_sections_rec(
            list.drop(tags, 1),
            string.drop_left(s, tag.end - tag.start + 1),
            tag.end + 1,
            [RawTagSection(tag), ..acc],
          )
      }
    }
    Error(_) -> {
      case string.is_empty(s) {
        True -> acc
        False -> [RawTextSection(s, i, i + string.length(s) - 1), ..acc]
      }
    }
  }
}

/// Divide the HTML document into Text or Tag sections. Identifying each
/// "section" comes after we've identified where the custom tags exist in the
/// document.
///
/// A Text section is HTML that doesn't contain any custom tags (but may contain
/// variables, e.g. @person.first_name).
///
/// A Tag section is HTML inside a custom tag (e.g. inside a <for> tag).
///
/// We do not parse every HTML tag inside the document for performance and
/// memory usage reasons.
pub fn get_raw_sections(
  s: String,
  custom_tag_names: Set(String),
) -> Result(List(RawSection), TaggError) {
  case get_tags(s, custom_tag_names) {
    Ok(tags) -> Ok(list.reverse(tags |> get_raw_sections_rec(s, 0, [])))
    Error(err) -> Error(err)
  }
}
