fn sum(arr: FixedArray[Int]) -> Int {
  let mut total = 0
  for i in arr {
    total += i
  }
  total
}



///|
fn main {
  let arr: FixedArray[Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let result = sum(arr)
  println(result)
}
