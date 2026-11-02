#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

typedef void* FuriHalBleProfileParams;
typedef struct { unsigned pairing; } GapConfig;
typedef struct FuriHalBleProfileTemplate FuriHalBleProfileTemplate;
typedef struct { const FuriHalBleProfileTemplate* config; } FuriHalBleProfileBase;
struct FuriHalBleProfileTemplate {
    FuriHalBleProfileBase* (*start)(FuriHalBleProfileParams);
    void (*stop)(FuriHalBleProfileBase*);
    void (*get_gap_config)(GapConfig*, FuriHalBleProfileParams);
};
static const FuriHalBleProfileTemplate original;
static const FuriHalBleProfileTemplate* const ble_profile_serial = &original;
static unsigned starts, stops;
static bool fail_inner;
static int parameter;
static FuriHalBleProfileBase* original_start(FuriHalBleProfileParams params) {
    assert(params == &parameter);
    if(fail_inner) return NULL;
    FuriHalBleProfileBase* inner = malloc(sizeof(*inner));
    assert(inner);
    inner->config = &original;
    starts++;
    return inner;
}
static void original_stop(FuriHalBleProfileBase* profile) {
    assert(profile->config == &original);
    stops++;
}
static void original_gap(GapConfig* config, FuriHalBleProfileParams params) {
    assert(params == &parameter);
    config->pairing = 42;
}
static const FuriHalBleProfileTemplate original = {
    .start = original_start, .stop = original_stop, .get_gap_config = original_gap,
};
#define furi_check assert
#define BT_PASTE_PROFILE_HOST_TEST
#include "../../DuckerCompatibility/bt_paste_serial_proxy.h"

int main(void) {
    for(unsigned i = 0; i < 100; i++) {
        FuriHalBleProfileBase* proxy = bt_paste_serial_template.start(&parameter);
        assert(proxy && proxy->config != ble_profile_serial);
        FuriHalBleProfileBase* inner = bt_paste_proxy_inner(proxy);
        assert(inner && inner->config == ble_profile_serial);
        GapConfig gap = {0};
        bt_paste_serial_template.get_gap_config(&gap, &parameter);
        assert(gap.pairing == 42);
        bt_paste_serial_template.stop(proxy);
    }
    assert(starts == 100 && stops == 100);
    fail_inner = true;
    assert(bt_paste_serial_template.start(&parameter) == NULL);
    assert(starts == 100 && stops == 100);
    puts("Isolated profile identity / GAP forwarding / repeated cleanup checks passed");
}
