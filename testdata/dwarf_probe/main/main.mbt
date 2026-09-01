struct Point {
  x: Double
  y: Double
}

fn Point::new(x: Double, y: Double) -> Point {
  Point::{ x: x, y: y }
}

fn Point::length(self: Self) -> Double {
  (self.x * self.x + self.y * self.y).sqrt()
}

fn main {
  let p = Point::new(3.0, 4.0)
  let len = p.length()
  println("Length of point: \{len}")

  let q = Point::new(6.0, 8.0)
  let len_q = q.length()
  println("Length of point q: \{len_q}")
}
