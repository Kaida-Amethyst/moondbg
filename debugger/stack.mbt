///|
/// Rejects malformed backend-independent stack values at their construction
/// boundary, before navigation can depend on physical ordering.
pub(all) suberror StackSnapshotError {
  InvalidLogicalThreadIndex(Int)
  InvalidPhysicalFrameIndex(Int)
  InvalidStackWindow(start~ : Int, count~ : Int)
  InvalidLoadedFrameRange(start~ : Int, count~ : Int)
  LoadedFrameCountMismatch(expected~ : Int, actual~ : Int)
  UnexpectedPhysicalFrameIndex(expected~ : Int, actual~ : Int)
  CompleteStackStartsAfterZero(Int)
  StackExtensionThreadMismatch(expected~ : Int, actual~ : Int)
  StackExtensionMustStartAtZero(Int)
  StackExtensionWentBackwards(previous~ : Int, next~ : Int)
  StackExtensionChangedFrame(Int)
  StackExtensionMadeNoProgress(Int)
} derive(Debug, Eq)

///|
pub extend StackSnapshotError with @debug.Debug::{to_repr}

///|
pub extend StackSnapshotError with Eq::{equal, not_equal}

///|
/// A zero-based logical thread selection inside the current stable stop.
/// Backend-specific thread identifiers never appear in this value.
pub struct ThreadSelection {
  priv index : Int
} derive(Debug, Eq)

///|
pub extend ThreadSelection with @debug.Debug::{to_repr}

///|
pub extend ThreadSelection with Eq::{equal, not_equal}

///|
pub fn ThreadSelection::initial() -> ThreadSelection {
  { index: 0, }
}

///|
pub fn ThreadSelection::at(
  index : Int,
) -> ThreadSelection raise StackSnapshotError {
  guard index >= 0 else { raise InvalidLogicalThreadIndex(index) }
  { index, }
}

///|
pub fn ThreadSelection::index(self : ThreadSelection) -> Int {
  self.index
}

///|
/// A zero-based physical frame selection inside the selected thread.
///
/// Hidden runtime/native frames keep their physical positions, so visible
/// frame numbers may contain gaps. Backend-specific stack-frame identifiers
/// never appear in this value.
pub struct FrameSelection {
  priv index : Int
} derive(Debug, Eq)

///|
pub extend FrameSelection with @debug.Debug::{to_repr}

///|
pub extend FrameSelection with Eq::{equal, not_equal}

///|
pub fn FrameSelection::index(self : FrameSelection) -> Int {
  self.index
}

///|
fn FrameSelection::at(index : Int) -> FrameSelection {
  { index, }
}

///|
/// Application-level classification used by default stack filtering.
///
/// `UnknownFrame` deliberately preserves uncertainty when an adapter does not
/// provide enough information to distinguish runtime and native frames.
pub(all) enum FrameKind {
  MoonBitUserFrame
  MoonBitRuntimeFrame
  NativeFrame
  UnknownFrame
} derive(Debug, Eq)

///|
pub extend FrameKind with @debug.Debug::{to_repr}

///|
pub extend FrameKind with Eq::{equal, not_equal}

///|
fn FrameKind::is_visible_by_default(self : FrameKind) -> Bool {
  self is MoonBitUserFrame
}

///|
/// A backend-independent frame description at one physical stack depth.
pub struct StackFrameSnapshot {
  priv physical_index : Int
  priv raw_name : String
  priv display_name : String
  priv linkage_name : String?
  priv source_path : String?
  priv line : Int?
  priv column : Int?
  priv kind : FrameKind
} derive(Debug, Eq)

///|
pub extend StackFrameSnapshot with @debug.Debug::{to_repr}

///|
pub extend StackFrameSnapshot with Eq::{equal, not_equal}

///|
pub fn StackFrameSnapshot::new(
  physical_index : Int,
  raw_name : String,
  display_name : String,
  linkage_name : String?,
  source_path : String?,
  line : Int?,
  column : Int?,
  kind : FrameKind,
) -> StackFrameSnapshot raise StackSnapshotError {
  guard physical_index >= 0 else {
    raise InvalidPhysicalFrameIndex(physical_index)
  }
  {
    physical_index,
    raw_name,
    display_name,
    linkage_name,
    source_path,
    line,
    column,
    kind,
  }
}

///|
pub fn StackFrameSnapshot::physical_index(self : StackFrameSnapshot) -> Int {
  self.physical_index
}

///|
pub fn StackFrameSnapshot::raw_name(self : StackFrameSnapshot) -> String {
  self.raw_name
}

///|
pub fn StackFrameSnapshot::display_name(self : StackFrameSnapshot) -> String {
  self.display_name
}

///|
pub fn StackFrameSnapshot::linkage_name(self : StackFrameSnapshot) -> String? {
  self.linkage_name
}

///|
pub fn StackFrameSnapshot::source_path(self : StackFrameSnapshot) -> String? {
  self.source_path
}

///|
pub fn StackFrameSnapshot::line(self : StackFrameSnapshot) -> Int? {
  self.line
}

///|
pub fn StackFrameSnapshot::column(self : StackFrameSnapshot) -> Int? {
  self.column
}

///|
pub fn StackFrameSnapshot::kind(self : StackFrameSnapshot) -> FrameKind {
  self.kind
}

///|
/// A requested physical stack range. It is independent of DAP pagination and
/// can be satisfied from a backend cache.
pub struct StackWindow {
  priv start : Int
  priv count : Int
} derive(Debug, Eq)

///|
pub extend StackWindow with @debug.Debug::{to_repr}

///|
pub extend StackWindow with Eq::{equal, not_equal}

///|
pub fn StackWindow::new(
  start : Int,
  count : Int,
) -> StackWindow raise StackSnapshotError {
  guard start >= 0 && count > 0 else {
    raise InvalidStackWindow(start~, count~)
  }
  { start, count, }
}

///|
pub fn StackWindow::initial() -> StackWindow {
  { start: 0, count: 20, }
}

///|
pub fn StackWindow::start(self : StackWindow) -> Int {
  self.start
}

///|
pub fn StackWindow::count(self : StackWindow) -> Int {
  self.count
}

///|
/// Result of moving through frames visible under the default filter.
pub enum FrameNavigationResult {
  FrameAvailable(FrameSelection)
  MoreFramesRequired(start_frame~ : Int)
  VisibleFrameBoundary
} derive(Debug, Eq)

///|
pub extend FrameNavigationResult with @debug.Debug::{to_repr}

///|
pub extend FrameNavigationResult with Eq::{equal, not_equal}

///|
/// A possibly partial stack snapshot for one logical thread.
///
/// The loaded range is `[loaded_start, loaded_start + loaded_count)`. A
/// `total_frames_hint` is advisory only: adapters may report an unstable total.
/// `complete` is the backend's positive assertion that no physical frame lies
/// outside the loaded range.
pub struct StackSnapshot {
  priv thread : ThreadSelection
  priv frames : Array[StackFrameSnapshot]
  priv loaded_start : Int
  priv loaded_count : Int
  priv total_frames_hint : Int?
  priv complete : Bool
} derive(Debug, Eq)

///|
pub extend StackSnapshot with @debug.Debug::{to_repr}

///|
pub extend StackSnapshot with Eq::{equal, not_equal}

///|
pub fn StackSnapshot::new(
  thread : ThreadSelection,
  frames : Array[StackFrameSnapshot],
  loaded_start : Int,
  loaded_count : Int,
  total_frames_hint : Int?,
  complete : Bool,
) -> StackSnapshot raise StackSnapshotError {
  guard loaded_start >= 0 && loaded_count >= 0 else {
    raise InvalidLoadedFrameRange(start=loaded_start, count=loaded_count)
  }
  guard frames.length() == loaded_count else {
    raise LoadedFrameCountMismatch(
      expected=loaded_count,
      actual=frames.length(),
    )
  }
  for offset, frame in frames {
    let expected = loaded_start + offset
    guard frame.physical_index() == expected else {
      raise UnexpectedPhysicalFrameIndex(
        expected~,
        actual=frame.physical_index(),
      )
    }
  }
  guard !complete || loaded_start == 0 else {
    raise CompleteStackStartsAfterZero(loaded_start)
  }
  {
    thread,
    frames: frames.copy(),
    loaded_start,
    loaded_count,
    total_frames_hint,
    complete,
  }
}

///|
pub fn StackSnapshot::thread(self : StackSnapshot) -> ThreadSelection {
  self.thread
}

///|
pub fn StackSnapshot::frames(
  self : StackSnapshot,
) -> ReadOnlyArray[StackFrameSnapshot] {
  ReadOnlyArray::from_array(self.frames)
}

///|
pub fn StackSnapshot::loaded_start(self : StackSnapshot) -> Int {
  self.loaded_start
}

///|
pub fn StackSnapshot::loaded_count(self : StackSnapshot) -> Int {
  self.loaded_count
}

///|
pub fn StackSnapshot::loaded_end(self : StackSnapshot) -> Int {
  self.loaded_start + self.loaded_count
}

///|
pub fn StackSnapshot::total_frames_hint(self : StackSnapshot) -> Int? {
  self.total_frames_hint
}

///|
pub fn StackSnapshot::is_complete(self : StackSnapshot) -> Bool {
  self.complete
}

///|
/// Validates a cumulative prefix returned after requesting a later window.
/// Existing physical frames are immutable, and an incomplete extension must
/// add at least one frame.
pub fn StackSnapshot::validate_extension(
  self : StackSnapshot,
  next : StackSnapshot,
) -> Unit raise StackSnapshotError {
  guard next.thread() == self.thread() else {
    raise StackExtensionThreadMismatch(
      expected=self.thread().index(),
      actual=next.thread().index(),
    )
  }
  guard next.loaded_start() == 0 else {
    raise StackExtensionMustStartAtZero(next.loaded_start())
  }
  guard next.loaded_count() >= self.loaded_count() else {
    raise StackExtensionWentBackwards(
      previous=self.loaded_count(),
      next=next.loaded_count(),
    )
  }
  for physical_index in 0..<self.loaded_count() {
    guard self.frame(physical_index) == next.frame(physical_index) else {
      raise StackExtensionChangedFrame(physical_index)
    }
  }
  guard next.loaded_count() > self.loaded_count() || next.is_complete() else {
    raise StackExtensionMadeNoProgress(self.loaded_count())
  }
}

///|
pub fn StackSnapshot::is_loaded(
  self : StackSnapshot,
  physical_index : Int,
) -> Bool {
  physical_index >= self.loaded_start && physical_index < self.loaded_end()
}

///|
pub fn StackSnapshot::frame(
  self : StackSnapshot,
  physical_index : Int,
) -> StackFrameSnapshot? {
  for frame in self.frames {
    if frame.physical_index() == physical_index {
      return Some(frame)
    }
  }
  None
}

///|
pub fn StackSnapshot::visible_frames(
  self : StackSnapshot,
) -> Array[StackFrameSnapshot] {
  self.frames.filter(frame => frame.kind().is_visible_by_default())
}

///|
/// Chooses the nearest loaded MoonBit user frame, retaining its physical
/// index. A partial stack with no user frame remains unselected so its caller
/// can load the next window. Only a complete non-empty stack falls back to its
/// first frame for diagnostics.
pub fn StackSnapshot::default_selection(
  self : StackSnapshot,
) -> FrameSelection? {
  for frame in self.frames {
    if frame.kind().is_visible_by_default() {
      return Some(FrameSelection::at(frame.physical_index()))
    }
  }
  guard self.complete else { return None }
  guard self.frames.length() > 0 else { return None }
  Some(FrameSelection::at(self.frames[0].physical_index()))
}

///|
pub fn StackSnapshot::selection(
  self : StackSnapshot,
  physical_index : Int,
) -> FrameSelection? {
  self.frame(physical_index).map(_ => FrameSelection::at(physical_index))
}

///|
pub fn StackSnapshot::visible_caller(
  self : StackSnapshot,
  selection : FrameSelection,
) -> FrameNavigationResult {
  for frame in self.frames {
    if frame.physical_index() > selection.index() &&
      frame.kind().is_visible_by_default() {
      return FrameAvailable(FrameSelection::at(frame.physical_index()))
    }
  }
  if self.complete {
    VisibleFrameBoundary
  } else {
    MoreFramesRequired(start_frame=self.loaded_end())
  }
}

///|
pub fn StackSnapshot::visible_callee(
  self : StackSnapshot,
  selection : FrameSelection,
) -> FrameNavigationResult {
  let mut candidate : FrameSelection? = None
  for frame in self.frames {
    if frame.physical_index() >= selection.index() {
      break
    }
    if frame.kind().is_visible_by_default() {
      candidate = Some(FrameSelection::at(frame.physical_index()))
    }
  }
  match candidate {
    Some(frame) => FrameAvailable(frame)
    None if self.loaded_start > 0 => MoreFramesRequired(start_frame=0)
    None => VisibleFrameBoundary
  }
}

///|
pub struct StopSnapshot {
  priv reason : String
  priv function_name : String
  priv source_path : String?
  priv line : Int?
  priv column : Int?
  priv notice : String?
}

///|
/// Creates an application-level stopped-location snapshot.
pub fn StopSnapshot::new(
  reason : String,
  function_name : String,
  source_path : String?,
  line : Int?,
  column : Int?,
  notice? : String? = None,
) -> StopSnapshot {
  { reason, function_name, source_path, line, column, notice, }
}

///|
pub fn StopSnapshot::notice(self : StopSnapshot) -> String? {
  self.notice
}

///|
pub fn StopSnapshot::reason(self : StopSnapshot) -> String {
  self.reason
}

///|
pub fn StopSnapshot::function_name(self : StopSnapshot) -> String {
  self.function_name
}

///|
pub fn StopSnapshot::source_path(self : StopSnapshot) -> String? {
  self.source_path
}

///|
pub fn StopSnapshot::line(self : StopSnapshot) -> Int? {
  self.line
}

///|
pub fn StopSnapshot::column(self : StopSnapshot) -> Int? {
  self.column
}

///|
pub enum RunOutcome {
  Stopped(StopSnapshot)
  Exited(Int?)
}

///|
pub fn RunOutcome::stopped(snapshot : StopSnapshot) -> RunOutcome {
  Stopped(snapshot)
}

///|
pub fn RunOutcome::exited(exit_code : Int?) -> RunOutcome {
  Exited(exit_code)
}
