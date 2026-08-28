#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <util.h>
#else
#include <pty.h>
#endif

#include "moonbit.h"

extern char **environ;

enum moondbg_test_pty_status {
  MOONDBG_TEST_PTY_OK = 0,
  MOONDBG_TEST_PTY_SPAWN_FAILED = 1,
  MOONDBG_TEST_PTY_TIMED_OUT = 2,
};

struct moondbg_test_pty_process {
  pid_t child_pid;
  pid_t adapter_pid;
  int master_fd;
  int32_t status;
  unsigned char pending[65536];
  size_t pending_length;
  char adapter_pid_path[PATH_MAX];
};

static int64_t moondbg_test_now_ms(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return -1;
  }
  return (int64_t)now.tv_sec * 1000 + (int64_t)now.tv_nsec / 1000000;
}

static char *moondbg_test_copy_string(moonbit_bytes_t value) {
  const int32_t length = Moonbit_array_length(value);
  char *copy = malloc((size_t)length + 1);
  if (copy == NULL) {
    abort();
  }
  if (length != 0) {
    memcpy(copy, value, (size_t)length);
  }
  copy[length] = '\0';
  return copy;
}

static int moondbg_test_executable_path(char *path, size_t capacity) {
#if defined(__APPLE__)
  uint32_t size = (uint32_t)capacity;
  return _NSGetExecutablePath(path, &size);
#else
  const ssize_t length = readlink("/proc/self/exe", path, capacity - 1);
  if (length < 0 || (size_t)length >= capacity - 1) {
    return -1;
  }
  path[length] = '\0';
  return 0;
#endif
}

static void moondbg_test_pause(void) {
  const struct timespec delay = {.tv_sec = 0, .tv_nsec = 10000000};
  (void)nanosleep(&delay, NULL);
}

static void moondbg_test_adapter_role(void) __attribute__((constructor));
static void moondbg_test_debug_wrapper_role(void)
    __attribute__((constructor));

static void moondbg_test_debug_wrapper_role(void) {
  const char *moon = getenv("MOONDBG_PTY_DEBUG_MOON");
  const char *working_directory = getenv("MOONDBG_PTY_DEBUG_CWD");
  if (moon == NULL || working_directory == NULL || !isatty(STDIN_FILENO)) {
    return;
  }
  if (setsid() < 0 || ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0 ||
      tcsetpgrp(STDIN_FILENO, getpgrp()) < 0) {
    _exit(127);
  }
  execl(
      moon,
      moon,
      "-C",
      working_directory,
      "debug",
      "main",
      (char *)NULL);
  _exit(127);
}

static void moondbg_test_adapter_role(void) {
  const char *fixture = getenv("MOONDBG_PTY_FIXTURE");
  const char *pid_path = getenv("MOONDBG_PTY_ADAPTER_PID_FILE");
  if (fixture == NULL || strcmp(fixture, "1") != 0 || pid_path == NULL ||
      isatty(STDIN_FILENO)) {
    return;
  }
  const int fd = open(pid_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd >= 0) {
    char text[32];
    const int length = snprintf(text, sizeof(text), "%ld\n", (long)getpid());
    if (length > 0 && (size_t)length < sizeof(text)) {
      (void)write(fd, text, (size_t)length);
    }
    close(fd);
  }
  for (;;) {
    pause();
  }
}

static void moondbg_test_reap(struct moondbg_test_pty_process *process) {
  if (process->child_pid > 0) {
    (void)kill(process->child_pid, SIGKILL);
    while (waitpid(process->child_pid, NULL, 0) < 0 && errno == EINTR) {
    }
    process->child_pid = -1;
  }
  if (process->adapter_pid > 0 && kill(process->adapter_pid, 0) == 0) {
    (void)kill(process->adapter_pid, SIGKILL);
  }
  if (process->master_fd >= 0) {
    close(process->master_fd);
    process->master_fd = -1;
  }
  if (process->adapter_pid_path[0] != '\0') {
    (void)unlink(process->adapter_pid_path);
    process->adapter_pid_path[0] = '\0';
  }
}

static void moondbg_test_finalize(void *payload) {
  moondbg_test_reap(payload);
}

static struct moondbg_test_pty_process *moondbg_test_new_process(void) {
  struct moondbg_test_pty_process *process = moonbit_make_external_object(
      moondbg_test_finalize,
      (uint32_t)sizeof(struct moondbg_test_pty_process));
  process->child_pid = -1;
  process->adapter_pid = -1;
  process->master_fd = -1;
  process->status = MOONDBG_TEST_PTY_SPAWN_FAILED;
  process->pending_length = 0;
  process->adapter_pid_path[0] = '\0';
  return process;
}

void *moondbg_test_pty_spawn_self(moonbit_bytes_t filter) {
  struct moondbg_test_pty_process *process = moondbg_test_new_process();
  char executable[PATH_MAX];
  if (moondbg_test_executable_path(executable, sizeof(executable)) != 0) {
    return process;
  }
  char pid_template[] = "/tmp/moondbg-adapter-pid-XXXXXX";
  const int pid_fd = mkstemp(pid_template);
  if (pid_fd < 0) {
    return process;
  }
  close(pid_fd);
  (void)snprintf(
      process->adapter_pid_path,
      sizeof(process->adapter_pid_path),
      "%s",
      pid_template);
  char *filter_z = moondbg_test_copy_string(filter);
  int master_fd = -1;
  int slave_fd = -1;
  if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) != 0) {
    free(filter_z);
    return process;
  }
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) {
    close(slave_fd);
    close(master_fd);
    free(filter_z);
    return process;
  }
  int spawn_error = 0;
  spawn_error |= posix_spawn_file_actions_addclose(&actions, master_fd);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDIN_FILENO);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDOUT_FILENO);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDERR_FILENO);
  if (slave_fd > STDERR_FILENO) {
    spawn_error |= posix_spawn_file_actions_addclose(&actions, slave_fd);
  }
  size_t environment_count = 0;
  while (environ[environment_count] != NULL) {
    environment_count++;
  }
  char **environment = malloc((environment_count + 4) * sizeof(*environment));
  if (environment == NULL) {
    abort();
  }
  size_t copied = 0;
  for (size_t index = 0; index < environment_count; index++) {
    if (strncmp(
            environ[index],
            "MOONDBG_PTY_FIXTURE=",
            sizeof("MOONDBG_PTY_FIXTURE=") - 1) != 0 &&
        strncmp(
            environ[index],
            "MOONDBG_LLDB_DAP=",
            sizeof("MOONDBG_LLDB_DAP=") - 1) != 0 &&
        strncmp(
            environ[index],
            "MOONDBG_PTY_ADAPTER_PID_FILE=",
            sizeof("MOONDBG_PTY_ADAPTER_PID_FILE=") - 1) != 0) {
      environment[copied++] = environ[index];
    }
  }
  const size_t adapter_length = strlen(executable) + 18;
  const size_t pid_path_length = strlen(pid_template) + 30;
  char *fixture_entry = malloc(23);
  char *adapter_entry = malloc(adapter_length);
  char *pid_path_entry = malloc(pid_path_length);
  if (fixture_entry == NULL || adapter_entry == NULL || pid_path_entry == NULL) {
    abort();
  }
  (void)snprintf(fixture_entry, 23, "MOONDBG_PTY_FIXTURE=1");
  (void)snprintf(
      adapter_entry,
      adapter_length,
      "MOONDBG_LLDB_DAP=%s",
      executable);
  (void)snprintf(
      pid_path_entry,
      pid_path_length,
      "MOONDBG_PTY_ADAPTER_PID_FILE=%s",
      pid_template);
  environment[copied] = fixture_entry;
  environment[copied + 1] = adapter_entry;
  environment[copied + 2] = pid_path_entry;
  environment[copied + 3] = NULL;
  char *const arguments[] = {executable, filter_z, NULL};
  pid_t child = -1;
  if (spawn_error == 0) {
    spawn_error = posix_spawn(
        &child, executable, &actions, NULL, arguments, environment);
  }
  (void)posix_spawn_file_actions_destroy(&actions);
  close(slave_fd);
  free(fixture_entry);
  free(adapter_entry);
  free(pid_path_entry);
  free(environment);
  free(filter_z);
  if (spawn_error != 0 || child < 0) {
    close(master_fd);
    return process;
  }
  process->child_pid = child;
  process->master_fd = master_fd;
  process->status = MOONDBG_TEST_PTY_OK;
  return process;
}

int32_t moondbg_test_pty_fixture_prepare(void) {
  if (getenv("MOONDBG_PTY_FIXTURE") == NULL || !isatty(STDIN_FILENO) ||
      setsid() < 0 || ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0 ||
      tcsetpgrp(STDIN_FILENO, getpgrp()) < 0) {
    return 0;
  }
  return 1;
}

void *moondbg_test_pty_spawn_debug(
    moonbit_bytes_t executable_value,
    moonbit_bytes_t working_directory_value) {
  struct moondbg_test_pty_process *process = moondbg_test_new_process();
  char *executable = moondbg_test_copy_string(executable_value);
  char *working_directory = moondbg_test_copy_string(working_directory_value);
  char wrapper[PATH_MAX];
  if (moondbg_test_executable_path(wrapper, sizeof(wrapper)) != 0) {
    free(executable);
    free(working_directory);
    return process;
  }
  int master_fd = -1;
  int slave_fd = -1;
  if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) != 0) {
    free(executable);
    free(working_directory);
    return process;
  }
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) {
    close(slave_fd);
    close(master_fd);
    free(executable);
    free(working_directory);
    return process;
  }
  int spawn_error = 0;
  spawn_error |= posix_spawn_file_actions_addclose(&actions, master_fd);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDIN_FILENO);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDOUT_FILENO);
  spawn_error |=
      posix_spawn_file_actions_adddup2(&actions, slave_fd, STDERR_FILENO);
  if (slave_fd > STDERR_FILENO) {
    spawn_error |= posix_spawn_file_actions_addclose(&actions, slave_fd);
  }
  size_t environment_count = 0;
  while (environ[environment_count] != NULL) {
    environment_count++;
  }
  char **environment = malloc((environment_count + 3) * sizeof(*environment));
  if (environment == NULL) {
    abort();
  }
  size_t copied = 0;
  for (size_t index = 0; index < environment_count; index++) {
    if (strncmp(
            environ[index],
            "MOONDBG_PTY_DEBUG_MOON=",
            sizeof("MOONDBG_PTY_DEBUG_MOON=") - 1) != 0 &&
        strncmp(
            environ[index],
            "MOONDBG_PTY_DEBUG_CWD=",
            sizeof("MOONDBG_PTY_DEBUG_CWD=") - 1) != 0) {
      environment[copied++] = environ[index];
    }
  }
  const char *moon_prefix = "MOONDBG_PTY_DEBUG_MOON=";
  const char *cwd_prefix = "MOONDBG_PTY_DEBUG_CWD=";
  const size_t moon_entry_length = strlen(moon_prefix) + strlen(executable) + 1;
  const size_t cwd_entry_length =
      strlen(cwd_prefix) + strlen(working_directory) + 1;
  char *moon_entry = malloc(moon_entry_length);
  char *cwd_entry = malloc(cwd_entry_length);
  if (moon_entry == NULL || cwd_entry == NULL) {
    abort();
  }
  (void)snprintf(
      moon_entry,
      moon_entry_length,
      "%s%s",
      moon_prefix,
      executable);
  (void)snprintf(
      cwd_entry,
      cwd_entry_length,
      "%s%s",
      cwd_prefix,
      working_directory);
  environment[copied] = moon_entry;
  environment[copied + 1] = cwd_entry;
  environment[copied + 2] = NULL;
  char *const arguments[] = {wrapper, NULL};
  pid_t child = -1;
  if (spawn_error == 0) {
    spawn_error =
        posix_spawn(&child, wrapper, &actions, NULL, arguments, environment);
  }
  (void)posix_spawn_file_actions_destroy(&actions);
  close(slave_fd);
  free(moon_entry);
  free(cwd_entry);
  free(environment);
  free(executable);
  free(working_directory);
  if (spawn_error != 0 || child < 0) {
    close(master_fd);
    return process;
  }
  process->child_pid = child;
  process->master_fd = master_fd;
  process->status = MOONDBG_TEST_PTY_OK;
  return process;
}

static int moondbg_test_wait_fd(int fd, short events, int64_t deadline) {
  for (;;) {
    const int64_t now = moondbg_test_now_ms();
    if (now < 0 || now >= deadline) {
      errno = ETIMEDOUT;
      return -1;
    }
    struct pollfd descriptor = {.fd = fd, .events = events, .revents = 0};
    const int64_t remaining = deadline - now;
    const int timeout = remaining > INT_MAX ? INT_MAX : (int)remaining;
    const int result = poll(&descriptor, 1, timeout);
    if (result > 0) {
      if ((descriptor.revents & events) != 0) {
        return 0;
      }
      errno = EIO;
      return -1;
    }
    if (result == 0) {
      continue;
    }
    if (errno != EINTR) {
      return -1;
    }
  }
}

int32_t moondbg_test_pty_write(
    struct moondbg_test_pty_process *process,
    moonbit_bytes_t bytes,
    int32_t timeout_ms) {
  const int32_t length = Moonbit_array_length(bytes);
  const int64_t now = moondbg_test_now_ms();
  if (process->master_fd < 0 || length < 0 || timeout_ms <= 0 || now < 0) {
    return 0;
  }
  const int64_t deadline = now + timeout_ms;
  int32_t offset = 0;
  while (offset < length) {
    if (moondbg_test_wait_fd(process->master_fd, POLLOUT, deadline) != 0) {
      return 0;
    }
    const ssize_t count = write(
        process->master_fd,
        bytes + offset,
        (size_t)(length - offset));
    if (count > 0) {
      offset += (int32_t)count;
    } else if (count < 0 && errno == EINTR) {
      continue;
    } else {
      return 0;
    }
  }
  return 1;
}

static ssize_t moondbg_test_find(
    const unsigned char *haystack,
    size_t haystack_length,
    const unsigned char *needle,
    size_t needle_length) {
  if (needle_length == 0 || needle_length > haystack_length) {
    return -1;
  }
  for (size_t index = 0; index + needle_length <= haystack_length; index++) {
    if (memcmp(haystack + index, needle, needle_length) == 0) {
      return (ssize_t)index;
    }
  }
  return -1;
}

int32_t moondbg_test_pty_expect(
    struct moondbg_test_pty_process *process,
    moonbit_bytes_t expected,
    int32_t timeout_ms) {
  const int32_t expected_length = Moonbit_array_length(expected);
  const int64_t now = moondbg_test_now_ms();
  if (process->master_fd < 0 || expected_length <= 0 || timeout_ms <= 0 ||
      now < 0) {
    return 0;
  }
  const int64_t deadline = now + timeout_ms;
  for (;;) {
    const ssize_t found = moondbg_test_find(
        process->pending,
        process->pending_length,
        expected,
        (size_t)expected_length);
    if (found >= 0) {
      const size_t consumed = (size_t)found + (size_t)expected_length;
      process->pending_length -= consumed;
      memmove(
          process->pending,
          process->pending + consumed,
          process->pending_length);
      return 1;
    }
    if (process->pending_length == sizeof(process->pending)) {
      process->pending_length = 0;
    }
    if (moondbg_test_wait_fd(process->master_fd, POLLIN, deadline) != 0) {
      return 0;
    }
    const ssize_t count = read(
        process->master_fd,
        process->pending + process->pending_length,
        sizeof(process->pending) - process->pending_length);
    if (count > 0) {
      process->pending_length += (size_t)count;
    } else if (count < 0 && errno == EINTR) {
      continue;
    } else {
      return 0;
    }
  }
}

static pid_t moondbg_test_read_adapter_pid(
    struct moondbg_test_pty_process *process) {
  if (process->adapter_pid > 0) {
    return process->adapter_pid;
  }
  const int fd = open(process->adapter_pid_path, O_RDONLY);
  if (fd < 0) {
    return -1;
  }
  char text[32] = {0};
  const ssize_t length = read(fd, text, sizeof(text) - 1);
  close(fd);
  if (length <= 0) {
    return -1;
  }
  char *end = NULL;
  errno = 0;
  const long pid = strtol(text, &end, 10);
  if (errno != 0 || end == text || pid <= 0 || pid > INT_MAX) {
    return -1;
  }
  process->adapter_pid = (pid_t)pid;
  return process->adapter_pid;
}

int32_t moondbg_test_pty_adapter_started(
    struct moondbg_test_pty_process *process,
    int32_t timeout_ms) {
  const int64_t now = moondbg_test_now_ms();
  if (now < 0 || timeout_ms <= 0 || process->adapter_pid_path[0] == '\0') {
    return 0;
  }
  const int64_t deadline = now + timeout_ms;
  while (moondbg_test_now_ms() < deadline) {
    const pid_t pid = moondbg_test_read_adapter_pid(process);
    if (pid > 0 && kill(pid, 0) == 0) {
      return 1;
    }
    moondbg_test_pause();
  }
  return 0;
}

int32_t moondbg_test_pty_adapter_stopped(
    struct moondbg_test_pty_process *process,
    int32_t timeout_ms) {
  const pid_t pid = moondbg_test_read_adapter_pid(process);
  const int64_t now = moondbg_test_now_ms();
  if (pid <= 0 || now < 0 || timeout_ms <= 0) {
    return 0;
  }
  const int64_t deadline = now + timeout_ms;
  while (moondbg_test_now_ms() < deadline) {
    if (kill(pid, 0) != 0 && errno == ESRCH) {
      return 1;
    }
    moondbg_test_pause();
  }
  return 0;
}

int32_t moondbg_test_pty_wait(
    struct moondbg_test_pty_process *process,
    int32_t timeout_ms) {
  const int64_t now = moondbg_test_now_ms();
  if (process->child_pid <= 0 || now < 0 || timeout_ms <= 0) {
    return 0;
  }
  const int64_t deadline = now + timeout_ms;
  for (;;) {
    int status = 0;
    const pid_t result = waitpid(process->child_pid, &status, WNOHANG);
    if (result == process->child_pid) {
      process->child_pid = -1;
      if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return 1;
      }
      process->status = WIFEXITED(status)
          ? 100 + WEXITSTATUS(status)
          : 200 + WTERMSIG(status);
      return 0;
    }
    if (result < 0 && errno != EINTR) {
      return 0;
    }
    if (moondbg_test_now_ms() >= deadline) {
      process->status = MOONDBG_TEST_PTY_TIMED_OUT;
      return 0;
    }
    if (process->master_fd >= 0) {
      struct pollfd output = {
          .fd = process->master_fd,
          .events = POLLIN,
          .revents = 0,
      };
      if (poll(&output, 1, 0) > 0 && (output.revents & POLLIN) != 0) {
        unsigned char discarded[256];
        (void)read(process->master_fd, discarded, sizeof(discarded));
      }
    }
    moondbg_test_pause();
  }
}

int32_t moondbg_test_pty_status(
    const struct moondbg_test_pty_process *process) {
  return process->status;
}

void moondbg_test_pty_close(struct moondbg_test_pty_process *process) {
  moondbg_test_reap(process);
}
