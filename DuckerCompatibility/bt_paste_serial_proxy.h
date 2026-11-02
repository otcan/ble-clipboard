#pragma once
#include <stddef.h>
#include <stdlib.h>
#ifndef BT_PASTE_PROFILE_HOST_TEST
#include <furi.h>
#include <furi_ble/profile_interface.h>
#include <profiles/serial_profile.h>
#endif

typedef struct {
    FuriHalBleProfileBase base;
    FuriHalBleProfileBase* serial;
} BtPasteSerialProxy;

static const FuriHalBleProfileTemplate bt_paste_serial_template;

static FuriHalBleProfileBase* bt_paste_proxy_start(FuriHalBleProfileParams params) {
    BtPasteSerialProxy* proxy = malloc(sizeof(*proxy));
    if(!proxy) return NULL;
    proxy->serial = ble_profile_serial->start(params);
    if(!proxy->serial) {
        free(proxy);
        return NULL;
    }
    proxy->base.config = &bt_paste_serial_template;
    return &proxy->base;
}

static void bt_paste_proxy_stop(FuriHalBleProfileBase* base) {
    furi_check(base && base->config == &bt_paste_serial_template);
    BtPasteSerialProxy* proxy = (BtPasteSerialProxy*)base;
    ble_profile_serial->stop(proxy->serial);
    // SDK 1.5.1 serial_stop releases services but not its malloc-allocated profile.
    free(proxy->serial);
    free(proxy);
}

static void bt_paste_proxy_gap_config(GapConfig* config, FuriHalBleProfileParams params) {
    // Preserve the SDK's device identity, bonding and pairing configuration.
    ble_profile_serial->get_gap_config(config, params);
}

static const FuriHalBleProfileTemplate bt_paste_serial_template = {
    .start = bt_paste_proxy_start,
    .stop = bt_paste_proxy_stop,
    .get_gap_config = bt_paste_proxy_gap_config,
};

static FuriHalBleProfileBase* bt_paste_proxy_inner(FuriHalBleProfileBase* base) {
    furi_check(base && base->config == &bt_paste_serial_template);
    return ((BtPasteSerialProxy*)base)->serial;
}
