import cx.{type Context}
import filepath
import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import gleeunit
import gleeunit/should
import tagg
import tagg_config.{type TagConfig}
import logging
import pre_section.{type RawTag}
import simplifile
import section

pub fn main() {
  gleeunit.main()
}

// this helps us reference mock raw tags, for comparison to the ones from the
// parser output, to verify that we're parsing tags correctly
type RawTag2 {
  RawTag2(
    table1_start: RawTag,
    table1_end: RawTag,
    table1_self_closing: RawTag,
    for_outer: RawTag,
    for_inner: RawTag,
    for_inner_end: RawTag,
    for_outer_end: RawTag,
  )
}

/// Compare the "raw tags" (any custom tags we're looking for) against what
/// we're expecting to find
fn get_raw_tags_for_compare() -> RawTag2 {
  RawTag2(
    pre_section.RawTag("table1", 187, 209, False, False, "items=\"people\""),
    pre_section.RawTag("table1", 210, 218, True, False, ""),
    pre_section.RawTag("table1", 224, 248, False, True, "items=\"people\" "),
    pre_section.RawTag(
      "for",
      315,
      358,
      False,
      False,
      "items=\"people\" item=\"person\" index=\"i\"",
    ),
    pre_section.RawTag(
      "for",
      366,
      421,
      False,
      False,
      "items=\"person.Nicknames\" item=\"nickname\" index=\"j\"",
    ),
    pre_section.RawTag("for", 464, 469, True, False, ""),
    pre_section.RawTag("for", 475, 480, True, False, ""),
  )
}

/// Test that we can find:
///   - A custom tag (one whose name is in the tag_config list)
///   - A text section (anything other than a custom tag)
/// The "raw tags" parsing just identifies the start and end of sections in the
/// document, and is a precursor to parsing the tags completely (e.g.
/// identifying attribute name-value pairs).
pub fn pre_section_test() {
  let filepath = "test/page1.html"

  case simplifile.read(filepath) {
    Ok(html_content) -> {
      let assert Ok(raw_sections) =
        pre_section.get_raw_sections(
          html_content,
          set.from_list(["for", "table1"]),
        )

      let tags2 = get_raw_tags_for_compare()
      let expected_sections = [
        pre_section.RawTextSection(
          string.slice(html_content, 0, tags2.table1_start.start),
          0,
          tags2.table1_start.start - 1,
        ),
        pre_section.RawTagSection(tags2.table1_start),
        pre_section.RawTagSection(tags2.table1_end),
        pre_section.RawTextSection("\n    ", 219, 223),
        pre_section.RawTagSection(tags2.table1_self_closing),
        pre_section.RawTextSection(
          "\n    <div class=\"@settings.className\">@company_address1</div>\n    ",
          249,
          314,
        ),
        pre_section.RawTagSection(tags2.for_outer),
        pre_section.RawTextSection("\n      ", 359, 365),
        pre_section.RawTagSection(tags2.for_inner),
        pre_section.RawTextSection(
          "\n        <div>@i @j @nickname</div>\n      ",
          422,
          463,
        ),
        pre_section.RawTagSection(tags2.for_inner_end),
        pre_section.RawTextSection("\n    ", 470, 474),
        pre_section.RawTagSection(tags2.for_outer_end),
        pre_section.RawTextSection("\n  </body>\n</html>\n", 481, 499),
      ]

      should.equal(raw_sections, expected_sections)

      case list.drop(raw_sections, 1) |> list.first() {
        Ok(doc_section) -> {
          case doc_section {
            pre_section.RawTagSection(tag) -> {
              string.slice(html_content, tag.start, tag.end - tag.start + 1)
              |> should.equal("<table1 items=\"people\">")
            }
            _ -> {
              should.fail()
            }
          }
        }
        Error(Nil) -> {
          should.fail()
        }
      }
    }
    Error(err) -> {
      logging.log(logging.Error, simplifile.describe_error(err))
    }
  }
}

/// Test that we can parse the tags (e.g. the name-value attributes) and return
/// a list of custom tags or text sections.
pub fn section_parser_test() {
  let filepath = "test/page1.html"
  let tags2 = get_raw_tags_for_compare()

  let inner_for_tag_pair =
    section.Tag(
      "for",
      dict.from_list([
        #("index", "j"),
        #("item", "nickname"),
        #("items", "person.Nicknames"),
      ]),
      [section.Text("\n        <div>@i @j @nickname</div>\n      ", 422, cx.dict())],
      tags2.for_inner.start,
      cx.dict(),
    )

  case simplifile.read(filepath) {
    Ok(html_content) -> {
      let assert Ok(raw_sections) =
        pre_section.get_raw_sections(
          html_content,
          set.from_list(["for", "table1"]),
        )

      let sections =
        raw_sections
        |> section.get_sections()

      let expected_sections = [
        section.Text(
          string.slice(html_content, 0, tags2.table1_start.start),
          0,
          cx.dict(),
        ),
        section.Tag(
          "table1",
          dict.from_list([#("items", "people")]),
          [],
          tags2.table1_start.start,
          cx.dict(),
        ),
        section.Text("\n    ", 219, cx.dict()),
        section.Tag(
          "table1",
          dict.from_list([#("items", "people")]),
          [],
          tags2.table1_self_closing.start,
          cx.dict(),
        ),
        section.Text(
          "\n    <div class=\"@settings.className\">@company_address1</div>\n    ",
          249,
          cx.dict(),
        ),
        section.Tag(
          "for",
          dict.from_list([
            #("index", "i"),
            #("item", "person"),
            #("items", "people"),
          ]),
          [inner_for_tag_pair, section.Text("\n    ", 470, cx.dict())],
          tags2.for_outer.start,
          cx.dict(),
        ),
        section.Text("\n  </body>\n</html>\n", 481, cx.dict()),
      ]

      sections
      |> should.equal(expected_sections)
      Nil
    }
    Error(_) -> {
      // logging.log(logging.Error, simplifile.describe_error(err))
      should.fail()
    }
  }
}

/// Test parsing tag attributes (name-value pairs).
pub fn get_multiple_attrs_test() {
  section.get_attrs(
    "items=\"people\" item=person index='i' quotes1='\"' quotes2=\"'\" bool_attr bool-dash-attr",
  )
  |> should.equal(
    dict.from_list([
      #("items", "people"),
      #("item", "person"),
      #("index", "i"),
      #("quotes1", "\""),
      #("quotes2", "'"),
      #("bool_attr", ""),
      #("bool-dash-attr", ""),
    ]),
  )
}

/// Test that the templating engine can process a document containing a for
/// loop and some variables in the document.
pub fn page1_for_loop_and_variables_test() {
  let file_prefix = "page1"

  let tag_config =
    dict.from_list([#("table1", tagg.default_component_func)])

  let context =
    cx.dict()
    |> cx.add("settings", cx.add_string(cx.dict(), "className", "myClass"))
    |> cx.add_string("company_address1", "123 Main St")
    |> cx.add_list("people", [
      cx.add_strings(cx.dict(), "Nicknames", ["Jane", "Jill"]),
    ])

  html_compare(file_prefix, tag_config, context, False)
}

/// Test that the templating engine can process a document containing a
/// <component> that includes and parses another document.
pub fn page2_component_containing_for_loop_test() {
  let file_prefix = "page2"

  let context =
    cx.dict()
    |> cx.add("settings", cx.add_string(cx.dict(), "className", "myClass"))
    |> cx.add_string("company_address1", "123 Main St")
    |> cx.add_list("events", [
      cx.dict()
        |> cx.add_string("name", "Muse Concert")
        |> cx.add_string("location", "Los Angeles, CA")
    ])

  html_compare(file_prefix, dict.new(), context, False)
}

/// Test that the templating engine can process a document containing a
/// <include> tag that includes another document (without parsing the other
/// document).
pub fn page3_include_component_test() {
  let file_prefix = "page3"
  html_compare(file_prefix, dict.new(), cx.dict(), False)
}

/// This helps write the "expected" files that are used for regression
/// testing. This is intended to be manually set locally, when we need to
/// generate new files.
fn html_compare(
  file_prefix: String,
  tag_config: TagConfig,
  context: Context,
  should_write_output_files: Bool,
) {
  case simplifile.current_directory() {
    Ok(current_dir_path) -> {
      let test_dir_name = "test"
      let test_dir_path = filepath.join(current_dir_path, test_dir_name)
      let input_path = file_prefix <> ".html"
      let expected_path =
        filepath.join(test_dir_path, file_prefix <> "-expected.html")
      let output_path =
        filepath.join(test_dir_path, file_prefix <> "-output.html")
      let tagg = tagg_config.Tagg(test_dir_path, tag_config)

      case tagg.render(tagg, input_path, context) {
        Ok(output_html) -> {
          case should_write_output_files {
            True -> {
              case simplifile.write(output_path, output_html) {
                Ok(_) -> {
                  Nil
                }
                Error(err) -> {
                  logging.log(
                    logging.Error,
                    "Error writing file: " <> simplifile.describe_error(err),
                  )
                  Nil
                }
              }
            }
            False -> Nil
          }

          case simplifile.read(expected_path) {
            Ok(expected_html) -> {
              output_html
              |> should.equal(expected_html)
              Nil
            }
            Error(err) -> {
              logging.log(
                logging.Error,
                "Error reading file: " <> simplifile.describe_error(err),
              )
              Nil
            }
          }
        }
        Error(err) -> {
          logging.log(logging.Error, string.inspect(err))
          should.fail()
        }
      }
    }
    Error(err) -> {
      logging.log(logging.Error, simplifile.describe_error(err))
      should.fail()
    }
  }
}
