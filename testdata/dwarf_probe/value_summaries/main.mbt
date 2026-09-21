///|
struct Point {
  x : Int
  y : Int
}

///|
struct Envelope {
  point : Point
}

///|
enum View {
  Item(Point)
  Nested(Envelope)
  Many(Int, Int, Int, Int, Int, Point)
  Text(String, Point)
  Points(Array[Point])
}

///|
#inline(never)
fn consume(view : View) -> Unit {
  match view {
    Item(point) => println(point.x + point.y)
    Nested(envelope) => println(envelope.point.x)
    Many(a, b, c, d, e, point) => println(a + b + c + d + e + point.x)
    Text(text, point) => {
      println(text.length())
      println(point.x)
    }
    Points(points) => println(points[0].x)
  }
}

///|
#inline(never)
fn inspect_values(
  item : View,
  nested : View,
  many : View,
  text : View,
  points : View,
) -> Unit {
  let marker = 1 // SUMMARY_READY
  println(marker)
  consume(item)
  consume(nested)
  consume(many)
  consume(text)
  consume(points)
}

///|
fn main {
  inspect_values(
    Item({ x: 1, y: 2, }),
    Nested({ point: { x: 3, y: 4, }, }),
    Many(1, 2, 3, 4, 5, { x: 6, y: 7, }),
    Text("🙂".repeat(200), { x: 8, y: 9, }),
    Points([{ x: 10, y: 11, }, { x: 12, y: 13, }]),
  )
}
