#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

typedef struct { unsigned unused; } FuriHalBleProfileBase;
static FuriHalBleProfileBase expected;
static unsigned failures, calls, elapsed;
static uint8_t message[] = "OK\n";
static bool ble_profile_serial_tx(FuriHalBleProfileBase* profile, uint8_t* data, uint16_t size) {
    assert(profile == &expected && data == message && size == 3);
    return calls++ >= failures;
}
static void furi_delay_ms(uint32_t ms) { elapsed += ms; }
#define BT_PASTE_TX_HOST_TEST
#include "../../DuckerCompatibility/bt_paste_tx_retry.h"

int main(void) {
    assert(bt_paste_serial_tx_retry(&expected, message, 3));
    assert(calls == 1 && elapsed == 0);
    calls = elapsed = 0;
    failures = 3;
    assert(bt_paste_serial_tx_retry(&expected, message, 3));
    assert(calls == 4 && elapsed == 30);
    calls = elapsed = 0;
    failures = 1000;
    assert(!bt_paste_serial_tx_retry(&expected, message, 3));
    assert(calls == 32 && elapsed == 310);
    puts("Status-only backpressure retry and bounded failure checks passed");
}
