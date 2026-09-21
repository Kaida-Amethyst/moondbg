///|
struct Point {
  x : Int
  y : Int
}

///|
struct Values {
  integer : Int?
  negative : Int?
  unsigned : UInt?
  absent : Int?
  point : Point?
  no_point : Point?
  nested : Int??
  inner_none : Int??
  outer_none : Int??
  nested_point : Point??
  flag : Bool?
  no_flag : Bool?
  double : Double?
  text : String?
  items : FixedArray[Int?]
  mut changing : Point?
}

///|
#inline(never)
fn inspect_values(values : Values, argument : Int?) -> Unit {
  let local : Int? = Some(23)
  let mut changing_int : Int? = Some(12)
  let mut changing_point : Point? = Some({ x: 30, y: 40 })
  println(123) // OPTION_READY
  println(changing_int)
  println(changing_point is Some(_))
  println(argument)
  println(local)
  println(values.integer)
  println(values.negative)
  println(values.unsigned)
  println(values.absent)
  println(values.point is Some(_))
  println(values.no_point is None)
  println(values.nested)
  println(values.inner_none)
  println(values.outer_none)
  println(values.nested_point is Some(Some(_)))
  println(values.flag)
  println(values.no_flag)
  println(values.double)
  println(values.text)
  println(values.items)
  values.changing = None
  changing_int = None
  changing_point = None
  println(456) // OPTION_CHANGED
  println(changing_int)
  println(changing_point is None)
  println(values.changing is None)
}

///|
fn main {
  inspect_values({
    integer: Some(7),
    negative: Some(-2147483648),
    unsigned: Some(4294967295U),
    absent: None,
    point: Some({ x: 3, y: 4 }),
    no_point: None,
    nested: Some(Some(9)),
    inner_none: Some(None),
    outer_none: None,
    nested_point: Some(Some({ x: 10, y: 20 })),
    flag: Some(true),
    no_flag: None,
    double: Some(1.5),
    text: Some("option🙂"),
    items: [Some(11), None],
    changing: Some({ x: 5, y: 6 }),
  }, Some(42))
}
