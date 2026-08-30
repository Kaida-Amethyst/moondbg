///|
fn sum(arr : Array[Double]) -> Double {
  let mut total = 0.0
  let mut i = 0
  while i < arr.length() {
    total += arr[i]
    i += 1
  } nobreak {
    total
  }
}

///|
fn main {
  let arr : Array[Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let result = sum(arr)
  println("The sum of the array is: \{result}")

  let arr : Array[Double] = [ for i in 1..<=100 => i.to_double() ]
  let result = sum(arr)
  println("The sum of the array is: \{result}")
}
