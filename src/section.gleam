import cx.{type Context}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import grapheme_util
import logging
import pre_section.{type RawSection, type RawTag}

/// A "section" found in the document, that is either:
///   - A custom tag (e.g. <component path="/mycomponent.html"/> to process
///   - A section of text that doesn't contain any custom tags. It might have
///     variables (e.g. @person.first_name) for us to replace though.
pub type Section {
  Text(value: String, start: Int, context: Context)
  Tag(
    name: String,
    attrs: Dict(String, String),
    children: List(Section),
    start: Int,
    context: Context,
  )
}

/// Recursive function to parse attributes in an HTML tag
fn get_attrs_rec(s: String, acc: Dict(String, String)) -> Dict(String, String) {
  let #(attr_name, s1, _) = grapheme_util.get_name_ignore_ws(s)
  case attr_name {
    "" -> acc
    _ -> {
      case s1 {
        "=" <> s2 -> {
          let #(_, s3) = grapheme_util.get_whitespace(s2)
          case s3 {
            "\"" <> s4 -> {
              let #(attr_value, s5) =
                grapheme_util.get_chars_matching_func(
                  s4,
                  "",
                  grapheme_util.is_not_double_quote,
                )

              case s5 {
                "\"" <> rest ->
                  get_attrs_rec(rest, acc |> dict.insert(attr_name, attr_value))
                _ -> {
                  logging.log(
                    logging.Error,
                    "Expected end double quote for attribute name: "
                      <> attr_name,
                  )
                  acc
                }
              }
            }
            "'" <> s4 -> {
              let #(attr_value, s5) =
                grapheme_util.get_chars_matching_func(
                  s4,
                  "",
                  grapheme_util.is_not_single_quote,
                )

              case s5 {
                "'" <> rest ->
                  get_attrs_rec(rest, acc |> dict.insert(attr_name, attr_value))
                _ -> {
                  logging.log(
                    logging.Error,
                    "Expected end single quote for attribute name: "
                      <> attr_name,
                  )
                  acc
                }
              }
            }
            _ -> {
              let #(attr_value, rest) =
                grapheme_util.get_chars_matching_func(s3, "", grapheme_util.is_not_whitespace)
              get_attrs_rec(rest, acc |> dict.insert(attr_name, attr_value))
            }
          }
        }
        // This is a boolean attribute (no value)
        _ -> get_attrs_rec(s1, acc |> dict.insert(attr_name, ""))
      }
    }
  }
}

/// Get the attributes as key-value pairs, from a custom tag. For example, if
/// we're parsing this:
/// ```
/// 'items="people" item="person" index="i"'
/// ```
/// Then this function should return a dict with these key -> value pairs:
///    items -> people
///    item -> person
///    index -> i
///
/// Any leading and trailing whitespace in the text will be removed.
pub fn get_attrs(s: String) -> Dict(String, String) {
  get_attrs_rec(s, dict.new())
}

fn get_children(
  child_dict: Dict(Int, List(Section)),
  start: Int,
) -> List(Section) {
  case dict.get(child_dict, start) {
    Ok(children) -> list.sort(children, sort_sections)
    Error(_) -> []
  }
}

// store that a section is a child of its parent tag
fn insert_section_into_child_dict(
  tag_stack: List(RawTag),
  doc_section: Section,
  child_dict: Dict(Int, List(Section)),
) -> Dict(Int, List(Section)) {
  case list.first(tag_stack) {
    Ok(parent_tag) -> {
      case dict.get(child_dict, parent_tag.start) {
        Ok(children) ->
          dict.insert(child_dict, parent_tag.start, [doc_section, ..children])
        Error(_) -> dict.new() |> dict.insert(parent_tag.start, [doc_section])
      }
    }
    Error(_) -> child_dict
  }
}

pub fn get_sections_rec(
  sections: List(RawSection),
  tag_stack: List(RawTag),
  acc: List(Section),
  child_dict: Dict(Int, List(Section)),
) -> List(Section) {
  case list.first(sections) {
    Ok(doc_section) -> {
      case doc_section {
        pre_section.RawTextSection(text, start, _end) -> {
          let text_tag = Text(text, start, cx.dict())

          // if there's no parent node, then we want to return it as a
          // top-level Section
          let acc = case list.first(tag_stack) {
            Ok(_parent) -> acc
            Error(_) -> [text_tag, ..acc]
          }

          get_sections_rec(
            list.drop(sections, 1),
            tag_stack,
            acc,
            insert_section_into_child_dict(tag_stack, text_tag, child_dict),
          )
        }
        pre_section.RawTagSection(tag) -> {
          case tag.is_closing_tag {
            True -> {
              case list.first(tag_stack) {
                Ok(opening_tag) -> {
                  let section_tag =
                    Tag(
                      tag.name,
                      get_attrs(opening_tag.attrs_text),
                      // when we reach a closing tag, we know all of its children
                      get_children(child_dict, opening_tag.start),
                      opening_tag.start,
                      cx.dict(),
                    )

                  // if there's no parent node, then we want to return it as a
                  // top-level Section
                  let acc = case list.drop(tag_stack, 1) |> list.first {
                    Ok(_parent) -> acc
                    Error(_) -> [section_tag, ..acc]
                  }

                  get_sections_rec(
                    list.drop(sections, 1),
                    // pop the opening tag from the stack, so that we can pair it
                    // with the closing tag we just found
                    list.drop(tag_stack, 1),
                    acc,
                    // this tag pair needs to be marked as a child of its parent
                    insert_section_into_child_dict(
                      list.drop(tag_stack, 1),
                      section_tag,
                      child_dict,
                    ),
                  )
                }
                Error(_) -> list.sort(acc, sort_sections)
              }
            }
            False -> {
              case tag.is_self_closing_tag {
                True -> {
                  let section_tag =
                    Tag(tag.name, get_attrs(tag.attrs_text), [], tag.start, cx.dict())

                  // if there's no parent node, then we want to return it as a
                  // top-level Section
                  let acc = case list.first(tag_stack) {
                    Ok(_parent) -> acc
                    Error(_) -> [section_tag, ..acc]
                  }

                  get_sections_rec(
                    list.drop(sections, 1),
                    tag_stack,
                    acc,
                    // this tag pair needs to be marked as a child of its parent
                    insert_section_into_child_dict(
                      tag_stack,
                      section_tag,
                      child_dict,
                    ),
                  )
                }
                False -> {
                  get_sections_rec(
                    list.drop(sections, 1),
                    [tag, ..tag_stack],
                    acc,
                    child_dict,
                  )
                }
              }
            }
          }
        }
      }
    }
    Error(_) -> list.sort(acc, sort_sections)
  }
}

fn sort_sections(section1: Section, section2: Section) -> order.Order {
  // order the tag pairs by start tag index, so that we get a list of HTML
  // tag pairs in the order in which they appear in the HTML
  case section1 {
    Tag(_, _, _, start1, _) -> {
      case section2 {
        Tag(_, _, _, start2, _) -> int.compare(start1, start2)
        Text(_, start2, _) -> int.compare(start1, start2)
      }
    }
    Text(_, start1, _) -> {
      case section2 {
        Tag(_, _, _, start2, _) -> int.compare(start1, start2)
        Text(_, start2, _) -> int.compare(start1, start2)
      }
    }
  }
}

pub fn get_sections(raw_sections: List(RawSection)) -> List(Section) {
  list.sort(get_sections_rec(raw_sections, [], [], dict.new()), sort_sections)
  // sort all tag pairs by opening tag index
  // list.sort(sections, sort_sections)
}
