///|
fn tree_reply(command : String, body : Json) -> @dap.DapResponse raise {
  guard @dap.classify_message({
      "type": "response",
      "seq": 1,
      "request_seq": 1,
      "command": command,
      "success": true,
      "body": body,
    })
    is @dap.Response(response) else {
    fail("response")
  }
  response
}

///|
async test "tree descriptions do not recursively expand a self-referential struct" {
  let requested : Array[Int] = []
  let inspector = VariableInspector::new(
    (command, args) => {
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
        "variables" => {
          let reference = json_int_field(args, "variablesReference").unwrap()
          requested.push(reference)
          match reference {
            100 =>
              {
                "variables": [
                  {
                    "name": "node",
                    "value": "0x1",
                    "type": "example/Node &",
                    "variablesReference": 101,
                  },
                ],
              }
            101 =>
              {
                "variables": [
                  {
                    "name": "next",
                    "value": "0x1",
                    "type": "example/Node &",
                    "variablesReference": 101,
                  },
                ],
              }
            _ => fail(args.stringify())
          }
        }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    {},
  )
  let nodes = inspector.tree_locals(10)
  assert_eq(requested, [100, 101])
  assert_eq(nodes.length(), 1)
  assert_eq(nodes[0].named_children, 1)
  assert_eq(nodes[0].evaluate_name(), Some("node"))
  let children = inspector.tree_children(10, nodes[0], start=0, count=100)
  assert_eq(children.length(), 1)
  assert_eq(children[0].name, "next")
  assert_eq(children[0].named_children, 1)
  assert_eq(children[0].evaluate_name(), Some("node.next"))
  let grandchildren = inspector.tree_children(
    10,
    children[0],
    start=0,
    count=100,
  )
  assert_eq(grandchildren.length(), 1)
  assert_eq(grandchildren[0].name, "next")
  assert_eq(requested, [100, 101, 100, 101, 100, 101])
  let path = @debugger.VariablePath::parse("node.next.next").unwrap()
  let evaluated = inspector.tree_evaluate(10, path)
  assert_eq(evaluated.evaluate_name(), Some("node.next.next"))
  assert_eq(evaluated.named_children, 1)
  assert_eq(requested, [100, 101, 100, 101, 100, 101, 100, 101])
  let expanded = inspector.tree_children(10, evaluated, start=0, count=100)
  assert_eq(expanded[0].evaluate_name(), Some("node.next.next.next"))
  for text in ["missing", "node.missing", "node[0]"] {
    let failed = try {
      inspector.tree_evaluate(10, @debugger.VariablePath::parse(text).unwrap())
      |> ignore
      false
    } catch {
      VariableEvaluationError(_) => true
      error => raise error
    }
    assert_true(failed, msg=text)
  }
}

///|
async test "scalar array listing reads headers only and an expansion reads one bounded payload" {
  let reads : Array[(Int, Int)] = []
  let inspector = VariableInspector::new(
    (command, args) => {
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
        "variables" =>
          match json_int_field(args, "variablesReference") {
            Some(100) =>
              {
                "variables": [
                  {
                    "name": "arr",
                    "value": "0x1000",
                    "type": "FixedArray[Int]",
                    "variablesReference": 101,
                  },
                ],
              }
            Some(101) =>
              {
                "variables": [
                  {
                    "name": "body",
                    "value": "0x1000",
                    "type": "int *",
                    "variablesReference": 0,
                  },
                ],
              }
            _ => fail(args.stringify())
          }
        "readMemory" => {
          let offset = json_int_field(args, "offset").unwrap()
          let count = json_int_field(args, "count").unwrap()
          reads.push((offset, count))
          match (offset, count) {
            (-8, 8) => { "data": "AAAAAAMAAAA=" }
            (4, 8) => { "data": "AgAAAAMAAAA=" }
            _ => fail(args.stringify())
          }
        }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let nodes = inspector.tree_locals(10)
  assert_eq(nodes[0].indexed_children, 3)
  assert_eq(nodes[0].evaluate_name(), Some("arr"))
  assert_eq(reads, [(-8, 8)])
  let page = inspector.tree_children(10, nodes[0], start=1, count=2)
  assert_eq(page.map(node => (node.name, node.value)), [
    ("[1]", "2"),
    ("[2]", "3"),
  ])
  assert_eq(reads, [(-8, 8), (-8, 8), (4, 8)])
  assert_eq(page[0].evaluate_name(), Some("arr[1]"))
  let before = reads.length()
  let failed = try {
    inspector.tree_children(10, nodes[0], start=0, count=101) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(reads.length(), before)
}

///|
async test "tree locals keep unavailable entries and failed layouts do not hide other locals" {
  let inspector = VariableInspector::new(
    (command, _) => {
      tree_reply(
        command,
        if command == "scopes" {
          { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
        } else {
          {
            "variables": [
              {
                "name": "good",
                "value": "3",
                "type": "Int",
                "variablesReference": 0,
              },
              {
                "name": "gone",
                "value": "<variable not available>",
                "type": "Int",
                "variablesReference": 0,
              },
              {
                "name": "broken",
                "value": "0x1000",
                "type": "FixedArray[Int]",
                "variablesReference": 101,
              },
            ],
          }
        },
      )
    },
    () => Some(1),
    {},
  )
  let nodes = inspector.tree_locals(10)
  assert_eq(nodes.length(), 3)
  assert_eq(nodes[0].value, "3")
  assert_eq(nodes[1].value, "<unavailable: <variable not available>>")
  assert_true(nodes[2].value.contains("FixedArray has no body field"))
  assert_eq(nodes[2].indexed_children, 0)
}

///|
priv struct TreeTestState {
  mut frame : Int
  mut epoch : Int
}

///|
async test "tree read errors preserve memory and availability reasons without poisoning the stop" {
  let inspector = VariableInspector::new(
    (command, args) => {
      if command == "readMemory" {
        guard @dap.classify_message({
            "type": "response",
            "seq": 1,
            "request_seq": 1,
            "command": command,
            "success": false,
            "message": "unmapped address",
          })
          is @dap.Response(response) else {
          fail("response")
        }
        return response
      }
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
        "variables" =>
          match json_int_field(args, "variablesReference") {
            Some(100) =>
              {
                "variables": [
                  {
                    "name": "arr",
                    "type": "FixedArray[Int]",
                    "value": "0x1000",
                    "variablesReference": 101,
                  },
                  {
                    "name": "gone",
                    "type": "Int",
                    "value": "<error: register is unavailable>",
                    "variablesReference": 0,
                  },
                  {
                    "name": "good",
                    "type": "Int",
                    "value": "42",
                    "variablesReference": 0,
                  },
                ],
              }
            Some(101) =>
              {
                "variables": [
                  {
                    "name": "body",
                    "type": "int *",
                    "value": "0x1000",
                    "variablesReference": 0,
                  },
                ],
              }
            _ => fail(args.stringify())
          }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let nodes = inspector.tree_locals(10)
  assert_eq(nodes.map(node => node.value), [
    "<Memory read failed for 'arr': unmapped address>", "<unavailable: <error: register is unavailable>>",
    "42",
  ])
  for
    (path, reason) in [
      ("gone", "lldb-dap reported <error: register is unavailable>"),
      (
        "missing", "Cannot distinguish an out-of-scope variable from missing debug information.",
      ),
    ] {
    let message = try {
      inspector.tree_evaluate(10, @debugger.VariablePath::root(path)) |> ignore
      fail("expected a failed path")
    } catch {
      VariableEvaluationError(message) => message
      error => raise error
    }
    assert_true(message.contains(reason), msg=message)
  }
  assert_eq(
    inspector.tree_evaluate(10, @debugger.VariablePath::root("good")).value,
    "42",
  )
}

///|
async test "tree operations reestablish the frame and discard stale replies" {
  let state = TreeTestState::{ frame: 0, epoch: 1, }
  let inspector = VariableInspector::new(
    (command, args) => {
      let body : Json = if command == "scopes" {
        state.frame = json_int_field(args, "frameId").unwrap()
        { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
      } else {
        if state.frame == 30 {
          state.epoch += 1
        }
        {
          "variables": [
            {
              "name": "value",
              "value": state.frame.to_string(),
              "type": "Int",
              "variablesReference": 0,
            },
          ],
        }
      }
      tree_reply(command, body)
    },
    () => Some(state.epoch),
    {},
  )
  assert_eq(inspector.tree_locals(10)[0].value, "10")
  assert_eq(inspector.tree_locals(20)[0].value, "20")
  assert_eq(inspector.tree_locals(10)[0].value, "10")
  let path = @debugger.VariablePath::root("value")
  assert_eq(inspector.tree_evaluate(20, path).value, "20")
  assert_eq(inspector.tree_evaluate(10, path).value, "10")
  assert_true(
    try {
      inspector.tree_evaluate(30, path) |> ignore
      false
    } catch {
      _ => true
    },
  )
}
