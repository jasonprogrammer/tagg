import cx.{type Context}
import filepath
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import section.{type Section}
import simplifile
import tagg_error.{type TaggError}
import tagg_config.{type Sections, type Tagg}

type IncludeTag {
  IncludeTag(path: String)
}

/// get the attributes of the <include> tag, with error handling in case
/// attributes don't exist
fn get_include_tag(
  tag_name: String,
  attrs: Dict(String, String),
  _context: Context,
) -> Result(IncludeTag, TaggError) {
  let include_attrs = {
    use path <- result.try(dict.get(attrs, "path"))
    Ok(#(path))
  }

  case include_attrs {
    Ok(#(path)) -> Ok(IncludeTag(path))
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
    section.Tag(name, attrs, _children, start, ..) -> {
      case get_include_tag(name, attrs, context) {
        Ok(include_tag) -> {
          let template_path =
            filepath.join(tagg.base_dir_path, include_tag.path)
          case simplifile.read(template_path) {
            Ok(html_content) ->
              // we just want to include the contents of the template file; we
              // don't parse it or do anything with it
              Ok([section.Text(html_content, start, cx.dict())])
            Error(err) ->
              Error(tagg_error.TemplateFileNotFoundError(
                simplifile.describe_error(err)
                <> "; path: "
                <> include_tag.path,
              ))
          }
        }
        Error(_) -> Ok(list.new())
      }
    }
    _ -> Ok([])
  }
}
