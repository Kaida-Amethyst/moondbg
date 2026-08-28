///|
struct Point {
  x : Double
  y : Double
}

struct Line {
  start : Point
  end : Point
}

///|
fn distance(p1 : Point, p2 : Point) -> Double {
  let dx = p2.x - p1.x
  let dy = p2.y - p1.y
  (dx * dx + dy * dy).sqrt()
}

fn is_parallel(line1 : Line, line2 : Line) -> Bool {
  let dx1 = line1.end.x - line1.start.x
  let dy1 = line1.end.y - line1.start.y
  let dx2 = line2.end.x - line2.start.x
  let dy2 = line2.end.y - line2.start.y
  (dx1 * dy2) == (dy1 * dx2)
}

///|
fn main {
  let p1 = Point::{ x: 1, y: 2, }
  let p2 = Point::{ x: 4, y: 6, }
  let dist_sq = distance(p1, p2)
  println("Distance squared between p1 and p2: \{dist_sq}")

  let p3 = Point::{ x: 0, y: 0, }
  let p4 = Point::{ x: 2, y: 2, }
  let line1 = Line::{ start: p1, end: p2, }
  let line2 = Line::{ start: p3, end: p4, }
  let parallel = is_parallel(line1, line2)
  println("Are line1 and line2 parallel? \{parallel}")
}
