///|
test "mangle top-level function golden symbols" {
  inspect(
    @name_mangle.mangle_top_level_function_base(
      "Kaida-Amethyst/moondbg-dwarf-probe/main", "sum",
    ),
    content="_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe4main3sum",
  )
  inspect(
    @name_mangle.mangle_top_level_function_base(
      "moonbitlang/core/builtin", "println",
    ),
    content="_M0FPB7println",
  )
  inspect(
    @name_mangle.mangle_top_level_function_base(
      "moonbitlang/core/abort", "abort",
    ),
    content="_M0FPC15abort5abort",
  )
  inspect(
    @name_mangle.mangle_top_level_function_base("", "count"),
    content="_M0FP05count",
  )
}

///|
test "demangle ordinary and escaped top-level symbols" {
  debug_inspect(
    @name_mangle.demangle_top_level_function(
      "_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe4main3sum",
    ),
    content=(
      #|{
      #|  package_name: "Kaida-Amethyst/moondbg-dwarf-probe/main",
      #|  function_name: "sum",
      #|  type_arguments: [],
      #|  error_type_argument: None,
      #|}
    ),
  )
  debug_inspect(
    @name_mangle.demangle_top_level_function("_M0FPB20int__to__string__hex"),
    content=(
      #|{
      #|  package_name: "moonbitlang/core/builtin",
      #|  function_name: "int_to_string_hex",
      #|  type_arguments: [],
      #|  error_type_argument: None,
      #|}
    ),
  )
}

///|
test "demangle compiler generic golden symbols" {
  debug_inspect(
    @name_mangle.demangle_top_level_function("_M0FPB7printlnGiE"),
    content=(
      #|{
      #|  package_name: "moonbitlang/core/builtin",
      #|  function_name: "println",
      #|  type_arguments: ["Int"],
      #|  error_type_argument: None,
      #|}
    ),
  )
  debug_inspect(
    @name_mangle.demangle_top_level_function("_M0FPC15abort5abortGuE"),
    content=(
      #|{
      #|  package_name: "moonbitlang/core/abort",
      #|  function_name: "abort",
      #|  type_arguments: ["Unit"],
      #|  error_type_argument: None,
      #|}
    ),
  )
  debug_inspect(
    @name_mangle.demangle_top_level_function(
      "_M0FP14demo3mapGARPB5ArrayGiEEHWisEs",
    ),
    content=(
      #|{
      #|  package_name: "demo",
      #|  function_name: "map",
      #|  type_arguments: ["FixedArray[@moonbitlang/core/builtin.Array[Int]]"],
      #|  error_type_argument: Some("(Int, String) -> String"),
      #|}
    ),
  )
}

///|
test "demangle rejects malformed or unsupported symbols" {
  let invalid = [
    "not_mangled", "_M1FP14demo3foo", "_M0MP14demo3Foo3foo", "_M0FP14demo3fooG",
    "_M0FP14demo3fooGE", "_M0FP14demo3fooC12", "_M0FP14demo4_zz_",
  ]
  for symbol in invalid {
    let rejected = try {
      @name_mangle.demangle_top_level_function(symbol) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
