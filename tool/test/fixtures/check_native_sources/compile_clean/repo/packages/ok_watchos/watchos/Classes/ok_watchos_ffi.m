#import <Foundation/Foundation.h>

__attribute__((deprecated("a newer call replaces it"))) static int ok_watchos_old_value(void) {
  return 1;
}

int ok_watchos_value(void) { return ok_watchos_old_value(); }
