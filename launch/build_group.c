// Keep each build in a private POSIX session. Never signal the debugger's own
// process group. Called by the private worker before it spawns moon.
#ifndef _WIN32
#include <unistd.h>
#include <signal.h>

int moondbg_build_group_start(void) {
  return setsid() < 0 ? -1 : 0;
}

void moondbg_build_group_cancel(int pid) {
  if (pid <= 1) return;
  kill(pid, SIGSTOP);
  // Kill both: before setsid there is no group yet, and the worker must not
  // survive to start moon after a cancellation racing with process startup.
  kill(-pid, SIGKILL);
  kill(pid, SIGKILL);
}
#else
int moondbg_build_group_start(void) { return -1; }
void moondbg_build_group_cancel(int pid) { (void)pid; }
#endif
