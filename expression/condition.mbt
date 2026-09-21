///|
pub(all) suberror ConditionError {
  ConditionError(String)
} derive(Debug)

///|
pub extend ConditionError with @debug.Debug::{to_repr}

///|
priv enum ConditionNode {
  Compare(ScalarComparison)
  And(ConditionNode, ConditionNode)
  Or(ConditionNode, ConditionNode)
  Not(ConditionNode)
} derive(Eq, Debug)

///|
pub struct Condition {
  text : String
  priv node : ConditionNode
} derive(Eq, Debug)

///|
pub extend Condition with Eq::{equal, not_equal}

///|
pub extend Condition with @debug.Debug::{to_repr}

///|
priv struct ConditionParser {
  mut rest : StringView
  mut nodes : Int
}

///|
fn ConditionParser::consume(self : ConditionParser, token : StringView) -> Bool {
  self.rest = self.rest.trim_start()
  guard self.rest.strip_prefix(token) is Some(rest) else { return false }
  self.rest = rest
  true
}

///|
fn ConditionParser::count_node(
  self : ConditionParser,
) -> Unit raise ConditionError {
  self.nodes += 1
  guard self.nodes <= 256 else {
    raise ConditionError("Condition has too many operations")
  }
}

///|
fn ConditionParser::parse_or(
  self : ConditionParser,
  depth : Int,
) -> ConditionNode raise ConditionError {
  let mut node = self.parse_and(depth)
  while self.consume("||") {
    self.count_node()
    node = Or(node, self.parse_and(depth))
  }
  node
}

///|
fn ConditionParser::parse_and(
  self : ConditionParser,
  depth : Int,
) -> ConditionNode raise ConditionError {
  let mut node = self.parse_unary(depth)
  while self.consume("&&") {
    self.count_node()
    node = And(node, self.parse_unary(depth))
  }
  node
}

///|
fn ConditionParser::parse_unary(
  self : ConditionParser,
  depth : Int,
) -> ConditionNode raise ConditionError {
  guard depth <= 64 else {
    raise ConditionError("Condition is nested too deeply")
  }
  if self.consume("!") {
    guard self.rest.trim_start() is ['(' | '!', ..] else {
      raise ConditionError("Use !(condition) to negate a condition")
    }
    self.count_node()
    return Not(self.parse_unary(depth + 1))
  }
  if self.consume("(") {
    let node = self.parse_or(depth + 1)
    guard self.consume(")") else {
      raise ConditionError("Expected ')' in condition")
    }
    return node
  }
  self.rest = self.rest.trim_start()
  let end = for index, ch in self.rest.iter2() {
    if ch is ('&' | '|' | '(' | ')') {
      break index
    }
  } nobreak {
    self.rest.length()
  }
  let comparison = ScalarComparison::parse(self.rest[:end])
  self.rest = self.rest[end:]
  self.count_node()
  Compare(comparison)
}

///|
fn ConditionNode::display(self : ConditionNode, parent : Int) -> String {
  let (precedence, text) = match self {
    Compare(value) => (4, value.text)
    Not(value) => (3, "!(\{value.display(0)})")
    And(left, right) => (2, "\{left.display(2)} && \{right.display(2)}")
    Or(left, right) => (1, "\{left.display(1)} || \{right.display(1)}")
  }
  if precedence < parent {
    "(\{text})"
  } else {
    text
  }
}

///|
pub fn Condition::parse(input : StringView) -> Condition raise ConditionError {
  guard input.length() <= 8192 else {
    raise ConditionError("Condition is too long")
  }
  let parser = ConditionParser::{ rest: input, nodes: 0, }
  let node = parser.parse_or(0)
  guard parser.rest.trim().is_empty() else {
    raise ConditionError("Unexpected condition suffix: \{parser.rest}")
  }
  { node, text: node.display(0), }
}

///|
/// Resolve lazily: skipped branches perform no variable reads and raise no
/// runtime type/availability errors. Parsing still validates the whole input.
pub async fn Condition::evaluate(
  self : Condition,
  read : async (VariablePath) -> ScalarValue,
) -> Bool {
  self.node.evaluate(read)
}

///|
async fn ConditionNode::evaluate(
  self : ConditionNode,
  read : async (VariablePath) -> ScalarValue,
) -> Bool {
  match self {
    Compare(comparison) => {
      let left = read(comparison.left)
      let right = match comparison.right {
        PathOperand(path) => read(path)
        _ =>
          match comparison.literal_value(left) {
            Some(value) => value
            None => raise ConditionError("Missing condition operand")
          }
      }
      comparison.evaluate(left, right)
    }
    And(left, right) => {
      guard left.evaluate(read) else { return false }
      right.evaluate(read)
    }
    Or(left, right) => {
      if left.evaluate(read) {
        return true
      }
      right.evaluate(read)
    }
    Not(value) => !value.evaluate(read)
  }
}
