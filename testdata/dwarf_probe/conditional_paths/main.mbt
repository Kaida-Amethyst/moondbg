///|
struct Point {
  x : Int
}

///|
struct Line {
  start : Point
  end : Point
}

///|
struct Scene {
  point : Point
  line : Line
  arr : Array[Int]
  fixed : FixedArray[Int]
  points : Array[Point]
}

///|
#inline(never)
fn probe(scene : Scene, i : Int) -> Unit {
  let limit = 7
  let ready = i == 7
  let flag = true
  let unsigned = i.reinterpret_as_uint()
  let signed = -9007199254740992L - i.to_int64()
  let wide = 9007199254740992UL + i.to_uint64()
  let max64 = 18446744073709551615UL
  let ratio = 1.5
  let marker = scene.point.x
  println(
    "\{marker} \{scene.arr[0]} \{scene.fixed[0]} \{scene.points[0].x} \{scene.line.start.x} \{scene.line.end.x} \{limit} \{ready} \{flag} \{unsigned} \{signed} \{wide} \{max64} \{ratio}",
  )
}

///|
fn main {
  for i in 0..<10 {
    let point = Point::{ x: i, }
    let line = Line::{ start: point, end: Point::{ x: i + 1, }, }
    let arr : Array[Int] = [i, 10]
    let fixed : FixedArray[Int] = [i, 10]
    let points : Array[Point] = [point]
    probe(Scene::{ point, line, arr, fixed, points, }, i)
  }
}
