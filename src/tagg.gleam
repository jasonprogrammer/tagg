import cx.{type Context}
import filepath
import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import grapheme_util
import pre_section
import section.{type Section}
import simplifile
import tagg_config.{type Sections, type TagConfig, type Tagg}
import tagg_error.{type TaggError}
import tags/component_tag
import tags/for_loop_component
import tags/include_tag
import tags/if_tag
import tags/unless_tag

/// Gets the custom tags that this library includes by default, along with
/// their corresponding transformation functions (the functions that allow the
/// tags to have custom behavior, change the output, etc.).
fn get_default_tag_config() -> TagConfig {
  dict.from_list([
    #("component", component_tag.create_sections),
    #("for", for_loop_component.create_sections),
    #("include", include_tag.create_sections),
    #("if", if_tag.create_sections),
    #("unless", unless_tag.create_sections),

    // this tag is deprecated in favor of "unless"
    #("ifn", unless_tag.create_sections),
  ])
}

/// Gets the next template variable name (e.g. @person.address.street) in the
/// HTML string.
fn get_var_name(s: String) -> #(String, String) {
  grapheme_util.get_chars_matching_func(
    s,
    "",
    grapheme_util.is_alphanumeric_or_dash_or_underscore_or_period,
  )
}

/// Find template variables (e.g. @employee.first_name) in the HTML string and
/// replace them with the values in the context, if they exist. If they don't
/// exist, then leave the variable intact in the output HTML.
pub fn replace_text_vars(s: String, context: Context, acc: String) -> String {
  case s {
    "@" <> rest -> {
      let #(var_name, rest1) = get_var_name(rest)
      case string.is_empty(var_name) {
        True -> replace_text_vars(rest1, context, "@" <> acc)
        False -> {
          case cx.get_string(context, var_name) {
            Ok(value) -> replace_text_vars(rest1, context, acc <> value)
            Error(_) ->
              replace_text_vars(rest1, context, acc <> "@" <> var_name)
          }
        }
      }
    }
    _ -> {
      case string.pop_grapheme(s) {
        Ok(#(grapheme, rest)) ->
          replace_text_vars(rest, context, acc <> grapheme)
        Error(_) -> acc
      }
    }
  }
}

/// Recursive function to get the output HTML, given a list of Tag/Text
/// sections.
pub fn get_html_rec(
  sections: List(Section),
  tagg: Tagg,
  acc: String,
) -> Result(String, TaggError) {
  case list.first(sections) {
    Ok(doc_section) -> {
      case doc_section {
        section.Text(value, _start, context) -> {
          get_html_rec(
            list.drop(sections, 1),
            tagg,
            acc <> replace_text_vars(value, context, ""),
          )
        }
        section.Tag(name, _attrs, _children, _start, context) -> {
          case dict.get(tagg.tag_config, name) {
            Ok(tag_fn) -> {
              // call the tag's transformation function, to generate any
              // additional sections with context (e.g. in the case of a "for"
              // loop tag that will generate additional child sections with new
              // contexts)
              case tag_fn(tagg, doc_section, context) {
                Ok(new_sections) -> {
                  // Debug printing:
                  // io.println_error("")
                  // io.println_error("New sections for tag: " <> name)
                  // list.each(new_sections, test_print_section)

                  get_html_rec(
                    list.fold(
                      new_sections,
                      list.drop(sections, 1),
                      list.prepend,
                    ),
                    tagg,
                    acc,
                  )
                }
                Error(err) -> Error(err)
              }
            }
            // this error should never happen, since every tag in the tag config
            // should have a corresponding function
            Error(_) -> Error(tagg_error.TagConfigMissingError)
          }
        }
      }
    }
    Error(_) -> Ok(acc)
  }
}

// This method is used occasionally for debugging.
// fn test_print_section(doc_section: Section, indent_level: Int) {
//   let indent = string.repeat("  ", indent_level)
//   let indent2 = string.repeat("  ", indent_level + 1)
//   let indent3 = string.repeat("  ", indent_level + 2)
//
//   io.println_error("")
//   io.println_error(indent <> "Section: ")
//
//   case doc_section {
//     section.Text(value, start, context) -> {
//       io.println_error(indent2 <> "Text: ")
//       io.println_error(indent3 <> "  Start: " <> string.inspect(start))
//       io.println_error(indent3 <> "  Value: " <> value)
//       io.println_error(indent3 <> "  Context: " <> string.inspect(context))
//     }
//     section.Tag(name, attrs, children, start, context) -> {
//       io.println_error(indent2 <> "Tag: " <> name)
//       io.println_error(indent3 <> "  Start: " <> string.inspect(start))
//       io.println_error(indent3 <> "  Attrs: " <> string.inspect(attrs))
//       io.println_error(indent3 <> "  Context: " <> string.inspect(context))
//       io.println_error(indent3 <> "  Children: ")
//       list.each(children, fn(child) {
//         test_print_section(child, indent_level + 3)
//       })
//     }
//   }
// }

/// Transforms a list of Tag/Text sections into an HTML string.
pub fn get_html(
  children: List(Section),
  context: Context,
  tagg: Tagg,
) -> Result(String, TaggError) {
  // Debug printing:
  // list.each(children, fn(child) { test_print_section(child, 0) })

  case
    get_html_rec(
      list.map(children, fn(child) {
        case child {
          section.Text(value, start, ..) -> section.Text(value, start, context)
          section.Tag(name, attrs, children, start, ..) ->
            section.Tag(name, attrs, children, start, context)
        }
      }),
      tagg,
      "",
    )
  {
    Ok(html) -> Ok(html)
    Error(err) -> Error(err)
  }
}

/// This is a pass-through function that can serve as a component's
/// transformation function. This can be used if you want to have a custom
/// component (tag name) that does not have any custom logic.
pub fn default_component_func(
  _tagg: Tagg,
  doc_section: Section,
  context: Context,
) -> Sections {
  case doc_section {
    // a Text node should never be encountered since this function is called to
    // translate a Tag into HTML
    section.Text(text, start, ..) -> Ok([section.Text(text, start, context)])
    section.Tag(_name, _attrs, children, ..) ->
      Ok(
        list.map(children, fn(child) {
          case child {
            section.Text(value, start, ..) ->
              section.Text(value, start, context)
            section.Tag(name, attrs, children, start, ..) ->
              section.Tag(name, attrs, children, start, context)
          }
        }),
      )
  }
}

// This is helpful for debugging:
// fn test_print_section(doc_section: Section) {
//   io.println_error("")
//   io.println_error("Section: ")
//   io.println_error("  " <> string.inspect(doc_section))
// }

/// Renders a template file to an HTML string, using the provided context. The
/// context is a data structure that allows the consumer to pass in dynamic
/// values (e.g. a list of employee records from a database) to populate the
/// template.
pub fn render(
  tagg: Tagg,
  filepath: String,
  context: Context,
) -> Result(String, TaggError) {
  case simplifile.read(filepath.join(tagg.base_dir_path, filepath)) {
    Ok(html_content) -> {
      let tag_config = dict.merge(get_default_tag_config(), tagg.tag_config)
      case
        pre_section.get_raw_sections(
          html_content,
          set.from_list(dict.keys(tag_config)),
        )
      {
        Ok(raw_sections) -> {
          raw_sections
          |> section.get_sections()
          |> get_html(context, tagg_config.Tagg(..tagg, tag_config: tag_config))
        }
        Error(err) -> Error(err)
      }
    }
    Error(err) -> {
      Error(tagg_error.TemplateFileNotFoundError(
        simplifile.describe_error(err) <> "; path: " <> filepath,
      ))
    }
  }
}
