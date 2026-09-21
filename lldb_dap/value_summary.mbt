///|
const SUMMARY_DEPTH : Int = 2

///|
const SUMMARY_MEMBERS : Int = 4

///|
const SUMMARY_NODES : Int = 16

///|
const SUMMARY_CHARS : Int = 160

///|
/// One budget per displayed value, shared by all descendants. Character counts
/// are Unicode scalar values, not bytes, UTF-16 units or terminal columns.
priv struct ValueSummaryBudget {
  output : Array[Char]
  mut remaining_chars : Int
  mut remaining_nodes : Int
  visiting : Map[Int, Unit]
}

///|
fn ValueSummaryBudget::new() -> ValueSummaryBudget {
  {
    output: [],
    remaining_chars: SUMMARY_CHARS,
    remaining_nodes: SUMMARY_NODES,
    visiting: Map([]),
  }
}

///|
fn ValueSummaryBudget::write(self : ValueSummaryBudget, text : String) -> Unit {
  // Keep at most 160 characters. Only replace the last one with an omission
  // marker when more text actually follows; an exact fit stays intact.
  for ch in text {
    guard self.remaining_chars > 0 else {
      self.output[SUMMARY_CHARS - 1] = '…'
      break
    }
    self.output.push(
      match ch {
        '\n' | '\r' | '\t' => ' '
        _ => ch
      },
    )
    self.remaining_chars -= 1
  }
}

///|
fn ValueSummaryBudget::text(self : ValueSummaryBudget) -> String {
  String::from_array(self.output[:])
}

///|
async fn VariableInspector::value_summary(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> String {
  let budget = ValueSummaryBudget::new()
  self.append_value_summary(identity, variable, 0, budget)
  self.ensure_variable_identity(identity)
  budget.text()
}

///|
async fn VariableInspector::positional_summary(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  kind : String,
  children : Array[DapVariable],
) -> String {
  let budget = ValueSummaryBudget::new()
  budget.remaining_nodes -= 1
  budget.visiting.set(variable.variables_reference, ())
  self.append_positional_summary(identity, variable, kind, children, 0, budget)
  self.ensure_variable_identity(identity)
  budget.text()
}

///|
async fn VariableInspector::append_positional_summary(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  kind : String,
  children : Array[DapVariable],
  depth : Int,
  budget : ValueSummaryBudget,
) -> Unit {
  if variable.is_tuple_type() {
    budget.write("(")
  } else {
    budget.write(kind)
    guard !children.is_empty() else { return }
    budget.write("(")
  }
  self.append_summary_members(identity, children, false, depth, budget)
  budget.write(")")
}

///|
async fn VariableInspector::append_value_summary(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  depth : Int,
  budget : ValueSummaryBudget,
) -> Unit {
  guard budget.remaining_chars > 0 else {
    budget.write("…")
    return
  }
  guard budget.remaining_nodes > 0 else {
    budget.write("…")
    return
  }
  budget.remaining_nodes -= 1
  if variable.unavailable_reason() is Some(reason) {
    budget.write("<unavailable: \{reason}>")
    return
  }
  let ty = variable.source_type_name().unwrap_or("value")
  // Strings and byte buffers are bounded scalar previews, not another level of
  // structural expansion, even when LLDB gives them an expandable handle.
  let composite = variable.buffer_kind() is None &&
    (
      variable.variables_reference > 0 ||
      variable.is_option_type() ||
      variable.is_tuple_type()
    )
  if composite &&
    (
      depth >= SUMMARY_DEPTH ||
      budget.visiting.contains(variable.variables_reference)
    ) {
    budget.write("\{ty} { … }")
    return
  }
  if variable.variables_reference > 0 {
    budget.visiting.set(variable.variables_reference, ())
  }
  defer budget.visiting.remove(variable.variables_reference)
  try {
    if variable.buffer_kind() is Some(_) {
      let layout = self.buffer_layout(identity, variable)
      let preview = self.buffer_preview(identity, layout, None)
      budget.write(preview.summary())
      return
    }
    // Arrays retain their separate policy: never recursively read their elements
    // just to describe an enclosing struct or enum.
    if self.load_indexed_collection_layout(identity, variable) is Some(layout) {
      budget.write(
        "\{layout.kind.source_name()}[\{layout.element_type.source_name()}] with length = \{layout.total_length}",
      )
      return
    }
    if self.positional_members(identity, variable) is Some((kind, children)) {
      self.append_positional_summary(
        identity, variable, kind, children, depth, budget,
      )
      return
    }
    if variable.is_moonbit_struct_candidate() {
      let children = self.load_variables(identity, variable.variables_reference)
      budget.write("\{ty} { ")
      self.append_summary_members(identity, children, true, depth, budget)
      budget.write(" }")
      return
    }
    budget.write(if composite { "\{ty} { … }" } else { variable.value })
  } catch {
    error => {
      self.ensure_variable_identity(identity)
      guard inspection_failure(variable.name, error) is Some(failure) else {
        raise error
      }
      budget.write("<\{failure.message()}>")
    }
  }
}

///|
async fn VariableInspector::append_summary_members(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  children : Array[DapVariable],
  named : Bool,
  depth : Int,
  budget : ValueSummaryBudget,
) -> Unit {
  for index, child in children {
    guard budget.remaining_chars > 0 else {
      budget.write("…")
      break
    }
    if index > 0 {
      budget.write(", ")
    }
    guard index < SUMMARY_MEMBERS && budget.remaining_nodes > 0 else {
      budget.write("…")
      break
    }
    if named {
      budget.write("\{child.name}: ")
    }
    // Writing the field name may exhaust the character budget. The recursive
    // entry checks it before issuing any more adapter requests.
    self.append_value_summary(identity, child, depth + 1, budget)
  }
}
