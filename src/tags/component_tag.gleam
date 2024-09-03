import cx.{type Context}
import filepath
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set
import pre_section
import section.{type Section}
import simplifile
import tagg_config.{type Sections, type Tagg}
import tagg_error.{type TaggError}

type ComponentTag {
  ComponentTag(path: String)
}

/// get the attributes of the <component> tag, with error handling in case
/// attributes don't exist
fn get_component_tag(
  tag_name: String,
  attrs: Dict(String, String),
  _context: Context,
) -> Result(ComponentTag, TaggError) {
  let component_attrs = {
    use path <- result.try(dict.get(attrs, "path"))
    Ok(#(path))
  }

  case component_attrs {
    Ok(#(path)) -> Ok(ComponentTag(path))
    Error(_) ->
      Error(tagg_error.TagAttributeParsingError(
        "Error parsing tag: " <> tag_name,
      ))
  }
}

pub fn create_sections(
  tagg: Tagg,
  doc_section: Section,
  context: Context,
) -> Sections {
  case doc_section {
    section.Tag(name, attrs, _children, _start, ..) -> {
      case get_component_tag(name, attrs, context) {
        Ok(component_tag) -> {
          let template_path =
            filepath.join(tagg.base_dir_path, component_tag.path)
          case simplifile.read(template_path) {
            Ok(html_content) -> {
              case
                pre_section.get_raw_sections(
                  html_content,
                  set.from_list(dict.keys(tagg.tag_config)),
                )
              {
                Ok(raw_sections) ->
                  // this list needs reversal because we'll be prepending these
                  // elements later on
                  Ok(list.reverse(
                    raw_sections
                    |> section.get_sections()
                    |> list.map(fn(doc_section1) {
                      case doc_section1 {
                        section.Text(value, start, ..) ->
                          section.Text(value, start, context)
                        section.Tag(name, attrs, children, start, ..) ->
                          section.Tag(name, attrs, children, start, context)
                      }
                    }),
                  ))
                Error(err) -> Error(err)
              }
            }
            Error(err) ->
              Error(tagg_error.TemplateFileNotFoundError(
                simplifile.describe_error(err)
                <> "; path: "
                <> component_tag.path,
              ))
          }
        }
        Error(_) -> Ok(list.new())
      }
    }
    _ -> Ok([])
  }
}
