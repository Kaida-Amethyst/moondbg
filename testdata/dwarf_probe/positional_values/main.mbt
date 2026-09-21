///|
struct Point {
  x : Int
  y : Int
}

///|
enum Choice {
  Empty
  Item(Int, Point)
}

///|
struct Values {
  pair : (Int, String)
  nested : ((Int, Point), Array[(Int, String)])
  result : Result[Point, String]
  choice : Choice
  empty : Choice
  numbers : (Int, Array[Int])
  mut changing : Result[Point, String]
}

///|
#inline(never)
fn inspect_values(values : Values) -> Unit {
  let pair = values.pair
  let result = values.result
  let items = values.nested.1
  let marker = pair.0 // POSITIONAL_READY
  println(marker)
  println(pair.1)
  match result {
    Ok(point) => println(point.x)
    Err(text) => println(text)
  }
  println(values.nested.0.1.y)
  println(items[0].1)
  println(values.numbers.1[1])
  match values.choice {
    Empty => println("Empty")
    Item(value, point) => println(value + point.x)
  }
  values.changing = Err("changed🙂")
  println(values.empty is Empty)
  println(values.changing is Err(_)) // POSITIONAL_CHANGED
}

///|
fn main {
  inspect_values({
    pair: (42, "tuple🙂"),
    nested: ((7, { x: 10, y: 20, }), [(11, "array item")]),
    result: Ok({ x: 3, y: 4, }),
    choice: Item(9, { x: 30, y: 40, }),
    empty: Empty,
    numbers: (0, [21, 22]),
    changing: Ok({ x: 5, y: 6, }),
  })
}
