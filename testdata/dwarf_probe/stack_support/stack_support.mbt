///|
priv struct TracePayload {
  payload_code : Int
  payload_values : Array[Int]
}

///|
priv struct GenericEnvelope[T] {
  envelope_value : T
  envelope_code : Int
}

///|
fn[T] generic_leaf(
  generic_value : T,
  leaf_code : Int,
  leaf_payload : TracePayload,
) -> Int {
  let generic_envelope = GenericEnvelope::{
    envelope_value: generic_value,
    envelope_code: leaf_code,
  }
  generic_envelope.envelope_value |> ignore
  let leaf_values = [
    generic_envelope.envelope_code,
    leaf_payload.payload_code,
    leaf_payload.payload_values.length(),
  ]
  let leaf_adjustment = leaf_values[2]
  generic_envelope.envelope_code + leaf_payload.payload_code + leaf_adjustment // MOONDBG_STACK_LEAF_BREAKPOINT
}

///|
fn recursive_frame(
  recursion_depth : Int,
  running_value : Int,
  recursion_payload : TracePayload,
) -> Int {
  let depth_marker = running_value + recursion_depth * 10
  let recursion_values = [recursion_depth, depth_marker]
  if recursion_depth == 0 {
    generic_leaf(recursion_values[1], depth_marker, recursion_payload)
  } else {
    let child_result = recursive_frame(
      recursion_depth - 1,
      depth_marker,
      recursion_payload,
    )
    let unwind_value = child_result + recursion_depth
    unwind_value
  }
}

///|
fn ordinary_frame(ordinary_seed : Int, ordinary_payload : TracePayload) -> Int {
  let shadowed_value = ordinary_seed + 30
  let nested_result = {
    let shadowed_value = shadowed_value + 300
    recursive_frame(3, shadowed_value, ordinary_payload)
  }
  let after_recursive = nested_result + shadowed_value
  after_recursive
}

///|
pub fn enter_stack(cross_seed : Int, incoming_values : Array[Int]) -> Int {
  let cross_total = cross_seed + incoming_values.length()
  let cross_payload = TracePayload::{
    payload_code: 200 + cross_total,
    payload_values: incoming_values,
  }
  let cross_result = ordinary_frame(cross_total, cross_payload)
  let cross_after_call = cross_result + cross_total
  cross_after_call
}
