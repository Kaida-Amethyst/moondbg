///|
fn increment(value : Int) -> Int {
  let result = value + 1
  result
}

///|
fn main {
  let first = 10
  let second = first + 2
  let result = increment(second)
  println(result)
}
