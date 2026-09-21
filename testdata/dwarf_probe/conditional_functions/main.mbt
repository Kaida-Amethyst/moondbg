///|
#inline(never)
fn probe(i : Int) -> Int {
  let result = i + 1
  result
}

///|
#inline(never)
fn[T] identity(value : T) -> T {
  let result = value
  result
}

///|
fn main {
  for i in 0..<10 {
    println(probe(i))
  }
  println(identity(1))
  println(identity(7))
  println(identity(7UL))
  println(identity(1.5))
}
