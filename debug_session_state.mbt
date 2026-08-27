///|
pub enum DebugSessionState {
  Ready
  Preparing
  Configuring
  Running
  Stopped
  Exited
  Failed
} derive(Debug, Eq)

///|
pub extend DebugSessionState with @debug.Debug::{to_repr}

///|
pub extend DebugSessionState with Eq::{equal, not_equal}

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
priv struct DebugSessionMachine {
  mut state : DebugSessionState
  mut execution_epoch : Int
  mut stop_epoch : Int
  mut stop_context : StopEpochContext?
  mut failure_message : String?
}

///|
fn DebugSessionMachine::new() -> DebugSessionMachine {
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
fn DebugSessionMachine::begin_execution(
  self : DebugSessionMachine,
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
fn DebugSessionMachine::mark_running(
  self : DebugSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Preparing || self.state is Configuring else {
    raise InvalidSessionTransition(state=self.state, action="mark running")
  }
  self.stop_context = None
  self.state = Running
}

///|
fn stopped_thread_id(event : DapEvent) -> Int? {
  match event.body {
    { "threadId": Number(thread_id, ..), .. } => Some(thread_id.to_int())
    _ => None
  }
}

///|
fn DebugSessionMachine::accept_event(
  self : DebugSessionMachine,
  event : DapEvent,
) -> Unit raise DapSessionError {
  match event.name {
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
fn DebugSessionMachine::mark_resumed(
  self : DebugSessionMachine,
) -> Unit raise DapSessionError {
  guard self.state is Stopped else {
    raise InvalidSessionTransition(state=self.state, action="resume")
  }
  self.stop_context = None
  self.state = Running
}

///|
fn DebugSessionMachine::select_thread(
  self : DebugSessionMachine,
  thread_id : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select thread")
  }
  context.thread_id = Some(thread_id)
}

///|
#warnings("-unused_value")
fn DebugSessionMachine::select_frame(
  self : DebugSessionMachine,
  frame_id : Int,
) -> Unit raise DapSessionError {
  guard self.state is Stopped && self.stop_context is Some(context) else {
    raise InvalidSessionTransition(state=self.state, action="select frame")
  }
  context.frame_id = Some(frame_id)
}

///|
#warnings("-unused_value")
fn DebugSessionMachine::remember_variable_reference(
  self : DebugSessionMachine,
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
fn DebugSessionMachine::has_current_frame(
  self : DebugSessionMachine,
  frame_id : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.frame_id == Some(frame_id)
}

///|
#warnings("-unused_value")
fn DebugSessionMachine::has_current_variable_reference(
  self : DebugSessionMachine,
  reference : Int,
) -> Bool {
  self.stop_context is Some(context) &&
  context.epoch == self.stop_epoch &&
  context.variable_references.get(reference) == Some(true)
}

///|
#warnings("-unused_value")
fn DebugSessionMachine::selected_thread_id(self : DebugSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.thread_id
    _ => None
  }
}

///|
#warnings("-unused_value")
fn DebugSessionMachine::selected_frame_id(self : DebugSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => context.frame_id
    _ => None
  }
}

///|
fn DebugSessionMachine::current_stop_epoch(self : DebugSessionMachine) -> Int? {
  match self.stop_context {
    Some(context) if context.epoch == self.stop_epoch => Some(context.epoch)
    _ => None
  }
}

///|
fn DebugSessionMachine::finish(self : DebugSessionMachine) -> Unit {
  self.stop_context = None
  if !(self.state is Failed) {
    self.state = Exited
  }
}

///|
fn DebugSessionMachine::fail(
  self : DebugSessionMachine,
  message : String,
) -> Unit {
  self.stop_context = None
  self.failure_message = Some(message)
  self.state = Failed
}
