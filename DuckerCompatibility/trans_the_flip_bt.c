#include <bt/bt_service/bt.h>
#include "bt_paste_serial_proxy.h"
#include "bt_paste_tx_retry.h"

static FuriHalBleProfileBase* bt_paste_start_profile(
    Bt* bt,
    const FuriHalBleProfileTemplate* profile,
    FuriHalBleProfileParams params) {
    furi_check(profile == ble_profile_serial);
    FuriHalBleProfileBase* proxy = bt_profile_start(bt, &bt_paste_serial_template, params);
    return proxy ? bt_paste_proxy_inner(proxy) : NULL;
}

// The firmware sees a distinct profile and does not attach its RPC receiver.
// Ducker still uses the original SDK serial instance and unchanged wire protocol.
#define bt_profile_start bt_paste_start_profile
#define ble_profile_serial_tx bt_paste_serial_tx_retry
#include "upstream_bt.inc"
#undef ble_profile_serial_tx
#undef bt_profile_start
