///|
struct Point {
  x : Int
  y : Int
}

///|
struct Values {
  text : String
  bytes : Bytes
  empty_text : String
  empty_bytes : Bytes
  long_text : String
  long_bytes : Bytes
  result : Result[Point, String]
}

///|
#inline(never)
fn inspect_values(values : Values) -> Unit {
  let marker = values.text
  println(marker)
  println(values.bytes.length() + values.empty_bytes.length())
  println(values.empty_text.length() + values.long_text.length())
  println(values.long_bytes.length())
  match values.result {
    Ok(point) => println(point.x + point.y)
    Err(message) => println(message)
  }
}

///|
fn main {
  inspect_values({
    text: "你好🙂\nA\u0000B",
    bytes: b"A\x00\xff",
    empty_text: "",
    empty_bytes: b"",
    long_text: "a".repeat(127) + "🙂" + "b".repeat(150) + "尾",
    long_bytes: Bytes::make(150, 0xff),
    result: Err("错误\nmessage"),
  })
}
