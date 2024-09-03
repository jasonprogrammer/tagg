/// Helps assemble output HTML for a custom <for> tag that looks like this:
/// <for items="people" item="person" index="i">
///  <for items="person.Nicknames" item="nickname" index="j">
///    <div>@i @j @nickname</div>
///  </for>
/// </for>
///
/// To process this:
///
/// 1. Get "people" from the context.
/// 2. For loop over "people":
///
/// <for items="people" item="person" index="i">
///   <for items="person.Nicknames" item="nickname" index="j">
///     <div>@i @j @nickname</div>
///   </for>
/// </for>
///
/// 3. Get "person" from the context.
///
/// Put the first "person" in the context.
/// Put an "i" of 0 in the context.
/// <for items="person.Nicknames" item="nickname" index="j">
///   <div>@i @j @nickname</div>
/// </for>
///
/// Recurse until no "for" items remain.
///
/// Put the first "nickname" in the context.
/// Put "j" of 0 in the context.
/// <div>@i @j @nickname</div>
///
///
/// Put the second "person" in the context.
/// Put an "i" of 1 in the context.
/// <for items="person.Nicknames" item="nickname" index="j">
///   <div>@i @j @nickname</div>
/// </for>
///
/// 4. For loop over "person.Nicknames".
/// 5. Get "nickname" from the context.
/// 6. Write "i" and "j" to the output.
import cx.{type Context}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import section.{type Section}
import tagg_error.{type TaggError}
import tagg_config.{type Sections, type Tagg}

type ForTag {
  ForTag(items: List(Context), item_key: String, index_key: String)
}

fn get_for_tag(
  tag_name: String,
  attrs: Dict(String, String),
  context: Context,
) -> Result(ForTag, TaggError) {
  let for_attrs = {
    use items_key <- result.try(dict.get(attrs, "items"))
    use item_key <- result.try(dict.get(attrs, "item"))
    use index_key <- result.try(dict.get(attrs, "index"))
    Ok(#(items_key, item_key, index_key))
  }

  case for_attrs {
    Ok(#(items_key, item_key, index_key)) -> {
      case cx.get_list(context, items_key) {
        Ok(items) -> Ok(ForTag(items, item_key, index_key))
        Error(_) ->
          Error(tagg_error.ContextValueNotFoundError(
            "Error getting context for tag: " <> tag_name,
          ))
      }
    }
    Error(_) ->
      Error(tagg_error.TagAttributeParsingError(
        "Error parsing tag: " <> tag_name,
      ))
  }
}

fn get_for_looped_children_with_contexts(
  context: Context,
  item_key: String,
  index_key: String,
  items: List(Context),
  index: Int,
  // we need to reverse these children because we'll be repeating them;
  // to repeat them, we'll be prepending to a list and will need to
  // reverse that resulting list to get an ordered list of children
  children_to_repeat_reversed: List(Section),
  acc: List(Section),
) -> List(Section) {
  case list.first(items) {
    Ok(item) -> {
      let item_context =
        cx.add(context, item_key, item)
        |> cx.add_int(index_key, index)

      get_for_looped_children_with_contexts(
        context,
        item_key,
        index_key,
        list.drop(items, 1),
        index + 1,
        children_to_repeat_reversed,
        list.fold(children_to_repeat_reversed, acc, fn(acc1, child_section) {
          case child_section {
            section.Text(value, start, ..) -> [
              section.Text(value, start, item_context),
              ..acc1
            ]
            section.Tag(name, attrs, children, start, ..) -> [
              section.Tag(name, attrs, children, start, item_context),
              ..acc1
            ]
          }
        }),
      )
    }
    Error(_) -> {
      list.reverse(acc)
    }
  }
}

pub fn create_sections(
  _tagg: Tagg,
  doc_section: Section,
  context: Context,
) -> Sections {
  case doc_section {
    section.Tag(name, attrs, children, ..) -> {
      case get_for_tag(name, attrs, context) {
        Ok(for_tag) ->
          Ok(
            list.reverse(
              get_for_looped_children_with_contexts(
                context,
                for_tag.item_key,
                for_tag.index_key,
                for_tag.items,
                1,
                list.reverse(children),
                [],
              ),
            ),
          )
        Error(_) -> Ok(list.new())
      }
    }
    _ -> Ok([])
  }
}
