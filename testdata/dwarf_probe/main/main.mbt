///|
fn inspect_value(input : Int) -> Int {
  let answer = input + 1
  println(answer) // MOONDBG_BREAKPOINT
  let combined = answer + input
  combined
}

///|
fn main {
  let seed = 41
  let observed = inspect_value(seed)
  println(observed)
}
