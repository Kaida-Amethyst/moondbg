///|
priv enum DapSessionState {
  Ready
  Preparing
  Configuring
  Running
  Stopped
  Exited
  Failed
} derive(Debug)

///|
priv struct StopEpochContext {
  epoch : Int
  mut thread_id : Int?
  mut frame_id : Int?
  mut frame_index : Int?
  variable_references : Map[Int, Bool]
}

///|
// Failure details remain private to the adapter and are retained for state
// diagnostics and whitebox lifecycle tests.
#warnings("-unused_field")
priv struct DapSessionMachine {
  mut state : DapSessionState
  mut execution_epoch : Int
  mut stop_epoch : Int
  mut stop_context : StopEpochContext?
  mut failure_message : String?
}

///|
fn DapSessionMachine::new() -> DapSessionMachine {
  {
    state: Ready,
    execution_epoch: 0,
    stop_epoch: 0,
    stop_context: None,
    failure_message: None,
  }
}

///|
#warnings("-unused_value")
fn DapSessionMachine::begin_execution(
  self : DapSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Ready else {
    raise InvalidSessionTransition(state=self.state, action="begin execution")
  }
  self.execution_epoch += 1
  self.stop_context = None
  self.failure_message = None
  self.state = Preparing
}

///|
#warnings("-unused_value")
fn DapSessionMachine::mark_running(
  self : DapSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Preparing || self.state is Configuring else {
    raise InvalidSessionTransition(state=self.state, action="mark running")
  }
  self.stop_context = None
  self.state = Running
}

///|
fn stopped_thread_id(event : @dap.DapEvent) -> Int? {
  match event.body() {
    { "threadId": Number(thread_id, ..), .. } => Some(thread_id.to_int())
    _ => None
  }
}

///|
fn DapSessionMachine::accept_event(
  self : DapSessionMachine,
  event : @dap.DapEvent,
) -> Unit raise DapSessionError {
  match event.name() {
    "initialized" =>
      match self.state {
        Preparing => self.state = Configuring
        Configuring => ()
        state =>
          raise InvalidSessionTransition(state~, action="accept initialized")
      }
    "stopped" =>
      match self.state {
        Preparing | Configuring | Running => {
          self.stop_epoch += 1
          self.stop_context = Some({
            epoch: self.stop_epoch,
            thread_id: stopped_thread_id(event),
            frame_id: None,
            frame_index: None,
            variable_references: {},
          })
          self.state = Stopped
        }
        Stopped => ()
        state => raise InvalidSessionTransition(state~, action="accept stopped")
      }
    "exited" | "terminated" =>
      if !(self.state is Exited || self.state is Failed) {
        self.stop_context = None
        self.state = Exited
      }
    _ => ()
  }
}

///|
#warnings("-unused_value")
fn DapSessionMachine::mark_resumed(
  self : DapSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Stopped else {
    raise InvalidSessionTransition(state=self.state, action="resume")
  }
  self.stop_context = None
  self.state = Running
}

///|
fn DapSessionMachine::select_thread(
  self : DapSessionMachine,
  thread_id : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select thread")
  }
  context.thread_id = Some(thread_id)
}

///|
#warnings("-unused_value")
fn DapSessionMachine::select_frame(
  self : DapSessionMachine,
  frame_id : Int,
  physical_index? : Int = 0,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select frame")
  }
  context.frame_id = Some(frame_id)
  context.frame_index = Some(physical_index)
}

///|
#warnings("-unused_value")
fn DapSessionMachine::remember_variable_reference(
  self : DapSessionMachine,
  reference : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(
      state=self.state,
      action="remember variable reference",
    )
  }
  context.variable_references.set(reference, true)
}

///|
#warnings("-unused_value")
fn DapSessionMachine::has_current_frame(
  self : DapSessionMachine,
  frame_id : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.frame_id == Some(frame_id)
}

///|
#warnings("-unused_value")
fn DapSessionMachine::has_current_variable_reference(
  self : DapSessionMachine,
  reference : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.variable_references.get(reference) == Some(true)
}

///|
#warnings("-unused_value")
fn DapSessionMachine::selected_thread_id(self : DapSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.thread_id
    _ => None
  }
}

///|
#warnings("-unused_value")
fn DapSessionMachine::selected_frame_id(self : DapSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.frame_id
    _ => None
  }
}

///|
fn DapSessionMachine::selected_frame_index(self : DapSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.frame_index
    _ => None
  }
}

///|
fn DapSessionMachine::current_stop_epoch(self : DapSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => Some(context.epoch)
    _ => None
  }
}

///|
fn DapSessionMachine::finish(self : DapSessionMachine) -> Unit {
  self.stop_context = None
  if !(self.state is Failed) {
    self.state = Exited
  }
}

///|
fn DapSessionMachine::fail(self : DapSessionMachine, message : String) -> Unit {
  self.stop_context = None
  self.failure_message = Some(message)
  self.state = Failed
}
