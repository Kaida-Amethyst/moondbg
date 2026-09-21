///|
/// One backend-independent step in a variable lookup path.
pub(all) enum VariablePathStep {
  Field(String)
  Position(Int)
  Index(Int)
} derive(Eq, Debug)

///|
pub extend VariablePathStep with Eq::{equal, not_equal}

///|
pub extend VariablePathStep with @debug.Debug::{to_repr}

///|
/// A shared parsed variable lookup path for inspection and conditions.
///
/// Adapter references and expression-evaluator text intentionally do not
/// appear in this value.
pub struct VariablePath {
  priv root : String
  priv steps : Array[VariablePathStep]
  priv range : (Int, Int)?
} derive(Eq, Debug)

///|
pub extend VariablePath with Eq::{equal, not_equal}

///|
pub extend VariablePath with @debug.Debug::{to_repr}

///|
pub fn VariablePath::root(root : String) -> VariablePath {
  { root, steps: [], range: None, }
}

///|
/// Creates a variable path from an ordered sequence of field and index steps.
pub fn VariablePath::new(
  root : String,
  steps : Array[VariablePathStep],
) -> VariablePath {
  { root, steps: steps.copy(), range: None, }
}

///|
pub fn VariablePath::with_range(
  self : VariablePath,
  start : Int,
  end : Int,
) -> VariablePath {
  { ..self, range: Some((start, end)), }
}

///|
pub fn VariablePath::range(self : VariablePath) -> (Int, Int)? {
  self.range
}

///|
pub fn VariablePath::without_range(self : VariablePath) -> VariablePath {
  { ..self, range: None, }
}

///|
pub fn VariablePath::with_fields(
  root : String,
  fields : Array[String],
) -> VariablePath {
  VariablePath::new(root, fields.map(field => Field(field)))
}

///|
pub fn VariablePath::root_name(self : VariablePath) -> String {
  self.root
}

///|
pub fn VariablePath::steps(
  self : VariablePath,
) -> ReadOnlyArray[VariablePathStep] {
  ReadOnlyArray::from_array(self.steps)
}

///|
pub fn VariablePath::display_name(self : VariablePath) -> String {
  let output = StringBuilder(size_hint=self.root.length() + self.steps.length())
  output.write_string(self.root)
  for step in self.steps {
    match step {
      Field(field) => {
        output.write_char('.')
        output.write_string(field)
      }
      Position(index) => output.write_string(".\{index}")
      Index(index) => {
        output.write_char('[')
        output.write_string(index.to_string())
        output.write_char(']')
      }
    }
  }
  if self.range is Some((start, end)) {
    output.write_string("[\{start}:\{end}]")
  }
  output.to_string()
}
