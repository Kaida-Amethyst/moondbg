
struct Point {
  x: Double
  y: Double
} derive(Debug)

extend Point with Debug::{to_repr}

fn sum_of_points(points: Array[Point]) -> Point {
  let mut x = 0.0
  let mut y = 0.0
  for point in points {
    x += point.x
    y += point.y
  }
  {x, y}
}

fn main {
  let arr: Array[Point] = [
    {x: 1.0, y: 2.0},
    {x: 3.0, y: 4.0},
    {x: 5.0, y: 6.0}
  ]
  let sum_arr = sum_of_points(arr)

  println("Sum of points: \{sum_arr.to_repr()}")
}
