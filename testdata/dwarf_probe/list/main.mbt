
enum List {
  Empty
  Cons(Int, List)
}

fn List::new() -> List {
  Empty
}

fn List::push(self: Self, value : Int) -> List {
  Cons(value, self)
}

fn List::length(self: Self) -> Int {
  match self {
    Empty => 0
    Cons(_, tail) => 1 + tail.length()
  }
}

fn List::head(self: Self) -> Int {
  match self {
    Empty => -1
    Cons(head, _) => head
  }
}

fn main {
  let list = List::new()
  let list = list.push(1)
  let list = list.push(2)
  let list = list.push(3)
  let len = list.length()
  println("Length of the list: \{len}")

  let fst = list.head()
  println("Head of the list: \{fst}")
}
