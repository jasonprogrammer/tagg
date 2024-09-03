import cx.{type Context}
import gleam/dict.{type Dict}
import section.{type Section}
import tagg_error.{type TaggError}

/// This stores Text/Tag sections with contextual values that are used to help
/// render the final HTML.
pub type Sections =
  Result(List(Section), TaggError)

/// Dict of <component name> -> <function that performs custom logic for the
/// component>. The names are used to find each custom element when scanning
/// the HTML. Once the Tag or Text sections are all found, the list of sections
/// will be iterated over, and each component's custom function will be used
/// to produce any Tag/Text sections in its place in the HTML. For example, a
/// <for> tag will be replaced by repeating its child sections.
pub type TagConfig =
  Dict(String, fn(Tagg, Section, Context) -> Sections)

/// Configuration for the templating engine.
/// The base_dir_path is used to resolve paths (e.g. "/employees/employee.html")
/// that appear in the template. The TagConfig is used to help find custom tags
/// and replace them with custom sections in the HTML.
pub type Tagg {
  Tagg(base_dir_path: String, tag_config: TagConfig)
}
