// Game Center over a C ABI, for Dart FFI.
//
// watchOS has no method channels, so FFI is the only plugin model there. The
// same shim serves iOS: GameKit's leaderboard API is identical on both, and a
// single implementation means the game cannot drift between platforms.
//
// Everything here is poll-based rather than callback-based. GameKit answers on
// its own queues, and calling back into Dart from an arbitrary thread needs
// NativeCallable plus a live isolate; a state word the game reads on the frame
// it already runs is both simpler and impossible to get wrong at shutdown.
#ifndef GAMES_SERVICES_WATCHOS_FFI_H_
#define GAMES_SERVICES_WATCHOS_FFI_H_

#include <stdint.h>

// Every symbol is `used` + default-visibility. FFI exports have no
// compile-time caller, so without `used` the compiler is free to drop them
// even though the CLI -force_loads the archive, and without default
// visibility they never reach the dynamic symbol table that
// DynamicLibrary.process() / dlsym reads.
#define GAMES_SERVICES_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

#if defined(__cplusplus)
extern "C" {
#endif

// State values shared by every async operation below.
//   0 idle (never started)   1 pending   2 succeeded   3 failed
GAMES_SERVICES_WATCHOS_EXPORT int32_t games_services_watchos_auth_state(void);
GAMES_SERVICES_WATCHOS_EXPORT int32_t games_services_watchos_submit_state(void);
GAMES_SERVICES_WATCHOS_EXPORT int32_t games_services_watchos_entries_state(void);

// Installs the authentication handler. Safe to call more than once; only the
// first call installs. The system shows its own sign-in UI where it wants to.
GAMES_SERVICES_WATCHOS_EXPORT void games_services_watchos_authenticate(void);

// Player's display name once authenticated, else NULL. Caller frees.
GAMES_SERVICES_WATCHOS_EXPORT char* games_services_watchos_player_alias(void);

// Fire-and-forget score submission. Poll games_services_watchos_submit_state.
GAMES_SERVICES_WATCHOS_EXPORT void games_services_watchos_submit(int64_t score, const char* leaderboard_id);

// Loads the global all-time top `count` entries. Poll games_services_watchos_entries_state,
// then read games_services_watchos_entries_json.
GAMES_SERVICES_WATCHOS_EXPORT void games_services_watchos_load_entries(const char* leaderboard_id, int32_t count);

// JSON array of {rank, score, player, is_local}, or NULL until ready. Caller frees.
GAMES_SERVICES_WATCHOS_EXPORT char* games_services_watchos_entries_json(void);

// Most recent error text, or NULL. Caller frees.
GAMES_SERVICES_WATCHOS_EXPORT char* games_services_watchos_last_error(void);

GAMES_SERVICES_WATCHOS_EXPORT void games_services_watchos_free(char* ptr);

#if defined(__cplusplus)
}
#endif
#endif  // GAMES_SERVICES_WATCHOS_FFI_H_
