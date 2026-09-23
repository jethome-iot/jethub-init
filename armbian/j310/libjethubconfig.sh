#!/bin/bash
# shellcheck disable=SC2034

UXM_MODE_APP=0
UXM_MODE_BOOTLOADER=1
UXM_LINK_DIR=${UXM_LINK_DIR:-/dev/jethub}

reset_uxm() {
    local slot="${1}"
    echo "${0}: Reset UXM${slot} module ..."
    wait_line "UXM${slot}_RESET" || return 1
    gset "UXM${slot}_MODE=${UXM_MODE_APP}" || return 1
    gpulse "UXM${slot}_RESET"
}

reset_uxm_bootloader() {
    local slot="${1}"
    echo "${0}: Reset UXM${slot} module into its bootloader ..."
    wait_line "UXM${slot}_RESET" || return 1
    gset "UXM${slot}_MODE=${UXM_MODE_BOOTLOADER}" || return 1
    gpulse "UXM${slot}_RESET"
    sleep 1
    gset "UXM${slot}_MODE=${UXM_MODE_APP}"
}

wait_uxm_links() {
    for _ in $(seq 1 100); do
        systemctl is-active --quiet systemd-udev-trigger.service && break
        sleep 0.1
    done
    udevadm settle --timeout=10 || echo "${0}: *** Warning: udev queue did not settle"
}

reset_zigbee() {
    local link slot found=0 rc=0
    echo "${0}: Reset Zigbee UXM modules ..."
    wait_uxm_links
    for link in "${UXM_LINK_DIR}"/slot*/ttyZigbee; do
        [ -e "${link}" ] || continue
        slot=${link#"${UXM_LINK_DIR}"/slot}
        slot=${slot%%/*}
        found=1
        reset_uxm "${slot}" || rc=1
    done
    [ "${found}" -eq 1 ] || echo "${0}: No Zigbee UXM module found"
    return "${rc}"
}

ADDITIONALFUNC="reset_zigbee"
