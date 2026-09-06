///|
fn ordinary(value : Int) -> Int {
  let adjusted = value + 1 // MOONDBG_BREAKPOINT_ORDINARY
  adjusted
}

///|
fn[T] identity(value : T) -> T {
  let result = value // MOONDBG_BREAKPOINT_GENERIC
  result
}

///|
fn main {
  let first = ordinary(10) // MOONDBG_BREAKPOINT_FIRST
  let first_int = identity(first)
  let first_double = identity(1.5)
  println("first: \{first_int}, \{first_double}") // MOONDBG_BREAKPOINT_CHECKPOINT
  let second = ordinary(20)
  let second_int = identity(second)
  let second_double = identity(2.5)
  println("second: \{second_int}, \{second_double}")
  let third = ordinary(30)
  let third_int = identity(third)
  let third_double = identity(3.5)
  println("third: \{third_int}, \{third_double}")
}
