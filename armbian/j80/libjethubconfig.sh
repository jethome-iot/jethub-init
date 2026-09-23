#!/bin/bash
# shellcheck disable=SC2034

configure_leds() {
    echo "${0}: Configure LEDs ..."
    # The DT does not name the LED line
    gset -c gpiochip1 73=0
}

reset_zigbee() {
    echo "${0}: Reset Zigbee module ..."
    wait_line ZigBeeRESET || return 1
    gset ZigBeeBOOT=1
    gpulse ZigBeeRESET
}

reset_zwave() {
    echo "${0}: Reset Z-Wave module ..."
    # Optional SUSPEND pin: gset -c gpiochip1 90=1
    gset -c gpiochip1 89=1
    sleep 1
    gset -c gpiochip1 89=0
}

eth_leds() {
    echo "${0}: Configure Ethernet leds ..."
    /usr/sbin/jethub_set-eth_leds
}

ADDITIONALFUNC="configure_leds eth_leds reset_zigbee"

