import cx.{type Context}
import gleam/dict.{type Dict}
import gleam/result
import section.{type Section}
import tagg_config.{type Sections, type Tagg}
import tagg_error.{type TaggError}

/// This adds the <if> tag, which is used to conditionally render sections.
///
/// Usage:
///
/// <if name="is_admin">
///   <h2>Admin items</h2>
/// </if>

pub type IfTag {
  IfTag(name: String)
}

/// get the attributes of the <component> tag, with error handling in case
/// attributes don't exist
pub fn get_if_tag(
  tag_name: String,
  attrs: Dict(String, String),
  _context: Context,
) -> Result(IfTag, TaggError) {
  let component_attrs = {
    use bool_name <- result.try(dict.get(attrs, "name"))
    Ok(#(bool_name))
  }

  case component_attrs {
    Ok(#(bool_name)) -> Ok(IfTag(bool_name))
    Error(_) ->
      Error(tagg_error.TagAttributeParsingError(
        "Error parsing tag: " <> tag_name,
      ))
  }
}

pub fn create_sections(
  _tagg: Tagg,
  doc_section: Section,
  context: Context,
) -> Sections {
  case doc_section {
    section.Tag(name, attrs, children, _start, ..) -> {
      case get_if_tag(name, attrs, context) {
        Ok(if_tag) -> {
          case cx.get_bool(context, if_tag.name) {
            Ok(value) -> {
              case value {
                True -> Ok(children)
                False -> Ok([])
              }
            }
            Error(_) ->
              Error(tagg_error.ContextValueNotFoundError(
                "Unable to find key in context: " <> name
              ))
          }
        }
        Error(err) -> Error(err)
      }
    }
    _ -> Ok([])
  }
}


