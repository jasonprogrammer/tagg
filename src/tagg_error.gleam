/// Errors that can occur while using the templating engine.
pub type TaggError {
  TagAttributeParsingError(error: String)
  ContextValueNotFoundError(error: String)
  TemplateFileNotFoundError(error: String)
  TagConfigMissingError
  TagNotClosedError(error: String)
}
