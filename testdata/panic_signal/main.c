// Protocol/lifecycle probe, not a replacement MoonBit runtime. Some installed
// runtimes use exit(1), so exercise the abort() branch independently of them.
#include <stdlib.h>

__attribute__((noinline, noreturn)) void moonbit_panic(void) {
  abort();
}

int main(void) {
  moonbit_panic();
}
