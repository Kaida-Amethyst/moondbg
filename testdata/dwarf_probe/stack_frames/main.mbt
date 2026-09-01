///|
fn main {
  let main_seed = 7
  let main_values : Array[Int] = [11, 13, 17]
  let stack_result = @stack_support.enter_stack(main_seed, main_values)
  let main_after_call = stack_result + main_seed
  println("stack fixture result: \{main_after_call}")
}
