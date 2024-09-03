import tags/if_tag
import cx.{type Context}
import section.{type Section}
import tagg_config.{type Sections, type Tagg}
import tagg_error

/// This adds the <ifn> tag, which is used to conditionally render sections. It
/// does the opposite of the <if> tag; the 'n' stands for 'not'.
///
/// Usage:
///
/// <ifn name="is_admin">
///   <h2>Non-admin items</h2>
/// </ifn>

pub fn create_sections(
  _tagg: Tagg,
  doc_section: Section,
  context: Context,
) -> Sections {
  case doc_section {
    section.Tag(name, attrs, children, _start, ..) -> {
      case if_tag.get_if_tag(name, attrs, context) {
        Ok(if_tag) -> {
          case cx.get_bool(context, if_tag.name) {
            Ok(value) -> {
              case value {
                True -> Ok([])
                False -> Ok(children)
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
