///|
struct Point {
  x : Int
  y : Int
}

///|
enum List {
  Empty
  Cons(Int, List)
}

///|
fn inspect_values(
  point : Point,
  values : Array[Double],
  fixed : FixedArray[Int],
  points : Array[Point],
  list : List,
) -> Unit {
  let marker = point.x
  values[0] = 42.0
  println(marker)
  println(values[0])
  println(fixed.length() + points.length())
  match list {
    Empty => println("Empty")
    Cons(value, _) => println(value)
  }
}

///|
fn main {
  let caller_only = 700
  let point = Point::{ x: 35, y: 4 }
  let values : Array[Double] = [1.5, 2.5, 3.5]
  let fixed : FixedArray[Int] = [for i in 1..<=1000 => i]
  let points : Array[Point] = [point, { x: 5, y: 6 }]
  let list = Cons(3, Cons(2, Cons(1, Empty)))
  inspect_values(point, values, fixed, points, list)
  println(caller_only)
}
