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
  variable_references : Map[Int, Bool]
}

///|
// P4 and P5 consume the epochs and recorded failure through structured results.
#warnings("-unused_field")
priv struct LegacyDapSessionMachine {
  mut state : DapSessionState
  mut execution_epoch : Int
  mut stop_epoch : Int
  mut stop_context : StopEpochContext?
  mut failure_message : String?
}

///|
fn LegacyDapSessionMachine::new() -> LegacyDapSessionMachine {
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
fn LegacyDapSessionMachine::begin_execution(
  self : LegacyDapSessionMachine,
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
fn LegacyDapSessionMachine::mark_running(
  self : LegacyDapSessionMachine,
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
fn LegacyDapSessionMachine::accept_event(
  self : LegacyDapSessionMachine,
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
fn LegacyDapSessionMachine::mark_resumed(
  self : LegacyDapSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Stopped else {
    raise InvalidSessionTransition(state=self.state, action="resume")
  }
  self.stop_context = None
  self.state = Running
}

///|
fn LegacyDapSessionMachine::select_thread(
  self : LegacyDapSessionMachine,
  thread_id : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select thread")
  }
  context.thread_id = Some(thread_id)
}

///|
#warnings("-unused_value")
fn LegacyDapSessionMachine::select_frame(
  self : LegacyDapSessionMachine,
  frame_id : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select frame")
  }
  context.frame_id = Some(frame_id)
}

///|
#warnings("-unused_value")
fn LegacyDapSessionMachine::remember_variable_reference(
  self : LegacyDapSessionMachine,
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
fn LegacyDapSessionMachine::has_current_frame(
  self : LegacyDapSessionMachine,
  frame_id : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.frame_id == Some(frame_id)
}

///|
#warnings("-unused_value")
fn LegacyDapSessionMachine::has_current_variable_reference(
  self : LegacyDapSessionMachine,
  reference : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.variable_references.get(reference) == Some(true)
}

///|
#warnings("-unused_value")
fn LegacyDapSessionMachine::selected_thread_id(
  self : LegacyDapSessionMachine,
) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.thread_id
    _ => None
  }
}

///|
#warnings("-unused_value")
fn LegacyDapSessionMachine::selected_frame_id(
  self : LegacyDapSessionMachine,
) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.frame_id
    _ => None
  }
}

///|
fn LegacyDapSessionMachine::current_stop_epoch(
  self : LegacyDapSessionMachine,
) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => Some(context.epoch)
    _ => None
  }
}

///|
fn LegacyDapSessionMachine::finish(self : LegacyDapSessionMachine) -> Unit {
  self.stop_context = None
  if !(self.state is Failed) {
    self.state = Exited
  }
}

///|
fn LegacyDapSessionMachine::fail(
  self : LegacyDapSessionMachine,
  message : String,
) -> Unit {
  self.stop_context = None
  self.failure_message = Some(message)
  self.state = Failed
}
