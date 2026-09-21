///|
fn fail(value : Int) -> Int {
  if value > 0 {
    panic()
  }
  value
}

///|
fn main {
  let value = 42
  println(fail(value))
}
