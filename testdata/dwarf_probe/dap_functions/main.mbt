///|
fn foo(value : Int) -> Int {
  let result = value + 1 // MOONDBG_FUNCTION_FOO
  result
}

///|
fn[T] identity(value : T) -> T {
  let result = value // MOONDBG_FUNCTION_IDENTITY
  result
}

///|
fn main {
  let first = foo(10) // MOONDBG_FUNCTION_MAIN
  let imported = @util.foo(first)
  let integer = identity(imported)
  let double = identity(1.5)
  println("first: \{integer}, \{double}") // MOONDBG_FUNCTION_CHECKPOINT
  let second = foo(20)
  let imported = @util.foo(second)
  let integer = identity(imported)
  let double = identity(2.5)
  println("second: \{integer}, \{double}")
}
