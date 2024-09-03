# Tagg

[![Package Version](https://img.shields.io/hexpm/v/tagg)](https://hex.pm/packages/tagg)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/tagg/)

Tagg is an HTML templating engine written in [Gleam](https://gleam.run/) that
uses XML/HTML tag syntax to render HTML.

Goals of the project include:
  - Familiar HTML tag syntax that editors can already highlight and format
  - Write custom, reusable components (e.g. the `<component />` tag)
  - Include scripts (e.g. the `<include />` tag)
  - Use Gleam code alonside templates, to customize rendering

**Note**: This library is still being written!

## Tags

Here is a usage summary of the supported tags:

### Component

Create a file containing a reusable component. The context set on the parent
file will be passed to this component.

```html
<component path="/path/to/component.html" />
```

This can also be written with a closing tag:

```html
<component path="/path/to/component.html"></component>
```

### Include

Includes content (verbatim) from another file (the contents will not be parsed).

```html
<script>
  <include path="/path/to/script.js" />
</script>
```

This can also be written with a closing tag:

```html
<script>
  <include path="/path/to/script.js"></include>
</script>

### For

Render a list of items.

```html
<for items="people" item="person" index="i">
  <li>@person.name</li>
</for>
```

### If

Render an item if a condition is true.

```html
<if name="is_admin">
  <h2>Users</h2>
</if>
```

### Ifn

Render an item if a condition is false.

```html
<ifn name="is_dark_mode">
  <div>This is bright.</div>
</ifn>
```

## Example

See the [example Wisp app](https://github.com/jasonprogrammer/tagg_wisp_example) that uses Tagg.

### router.gleam

```gleam
fn events_page(req: Request, web_context: Context) -> Response {
  // The home page can only be accessed via GET requests, so this middleware is
  // used to return a 405: Method Not Allowed response for all other methods.
  use <- wisp.require_method(req, Get)

  let context =
    cx.dict()
    |> cx.add_list("events", [
      cx.dict()
        |> cx.add_string("name", "Muse Concert")
        |> cx.add_string("location", "Los Angeles, CA"),
      cx.dict()
        |> cx.add_string("name", "The Killers")
        |> cx.add_string("location", "Las Vegas, NV"),
    ])

  case tagg.render(web_context.tagg, "events.html", context) {
    Ok(html) -> {
      wisp.ok()
      |> wisp.html_body(string_builder.from_string(html))
    }
    Error(err) -> {
      io.debug(err)
      wisp.internal_server_error()
    }
  }
}
```

### events.html

```html
<!doctype html>
<html lang="en-US">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width" />
    <title>Events</title>
  </head>
  <body>
    <component path="/events-component.html"/>
  </body>
</html>
```

### events-component.html

```html
<h2>Events</h2>

<table border="1">
  <for items="events" item="event" index="i">
    <tr>
      <td>@event.name</td>
      <td>@event.location</td>
    </tr>
  </for>
</table>
```

### Output

The output HTML (whitespace is preserved) is:

```html
<!doctype html>
<html lang="en-US">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width" />
    <title>Events</title>
  </head>
  <body>
    <h2>Events</h2>

<table border="1">
  
    <tr>
      <td>Muse Concert</td>
      <td>Los Angeles, CA</td>
    </tr>
  
    <tr>
      <td>The Killers</td>
      <td>Las Vegas, NV</td>
    </tr>
  
</table>

  </body>
</html>
```

The page looks like this:

![screenshot of HTML output](./docs/images/tagg-example-html-output.png)


## Installing

```sh
gleam add tagg
```

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
