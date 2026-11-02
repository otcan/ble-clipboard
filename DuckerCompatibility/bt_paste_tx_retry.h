#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifndef BT_PASTE_TX_HOST_TEST
#include <furi.h>
#include <profiles/serial_profile.h>
#endif

static bool bt_paste_serial_tx_retry(
    FuriHalBleProfileBase* profile, uint8_t* data, uint16_t size) {
    // Only retry a rejected status indication, never a received job or HID action.
    for(unsigned attempt = 0; attempt < 32; attempt++) {
        if(ble_profile_serial_tx(profile, data, size)) return true;
        if(attempt + 1 < 32) furi_delay_ms(10);
    }
    return false;
}
