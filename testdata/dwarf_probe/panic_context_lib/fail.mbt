///|
pub fn fail(value : Int) -> Int {
  if value > 0 {
    @abort.abort("panic context example")
  }
  value
}
