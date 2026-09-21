///|
fn access(values : Array[Int], index : Int) -> Int {
  values[index]
}

///|
fn main {
  let values = [10, 20, 30]
  let index = values.length()
  println(access(values, index))
}
