// A deliberately slow fake moon used only by the opt-in process-tree test.
#include <stdio.h>
#include <unistd.h>

int main(void) {
  int child = fork();
  if (child < 0) return 1;
  if (child == 0) {
    for (;;) pause();
  }
  printf("build-cancel-ready %d %d %d %d\n", (int)getppid(),
         (int)getpid(), child, (int)getpgrp());
  fflush(stdout);
  for (;;) pause();
}
