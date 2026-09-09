#include <stdio.h>
#include <unistd.h>

int main(void) {
  puts("dap-running-ready");
  fflush(stdout);
  for (;;) sleep(1);
}
