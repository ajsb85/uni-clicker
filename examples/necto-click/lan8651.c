#include <inttypes.h>
#include <stdbool.h>

#include "board.h"
#include "drv_digital_in.h"
#include "drv_digital_out.h"
#include "drv_spi_master.h"
#include "log.h"

enum {
    OA_IDVER = 0x00000, OA_RESET = 0x00003, OA_CONFIG0 = 0x00004, OA_STATUS0 = 0x00008,
    LAN8651_DEVID = 0xa0094, WRITE_HEADER = 1u << 29, PROTE = 1u << 5, RESETC = 1u << 6,
};

/* Kept at a stable symbol so the board can be checked through SWD without a UART cable. */
volatile struct {
    uint32_t result;
    uint32_t idver;
    uint32_t devid;
    uint32_t initial_status;
    uint32_t initial_irq;
    uint32_t protected_id;
    uint32_t cleared_status;
    uint32_t cleared_irq;
    uint32_t footer;
    uint32_t acknowledged_irq;
    uint32_t reset_status;
} lan8651_result;

static spi_master_t spi;
static log_t logger;
static bool protected_mode;

static void put_word(uint8_t *buffer, uint32_t word)
{
    for (int i = 3; i >= 0; --i) {
        buffer[i] = (uint8_t)word;
        word >>= 8;
    }
}

static uint32_t get_word(const uint8_t *buffer)
{
    return ((uint32_t)buffer[0] << 24) | ((uint32_t)buffer[1] << 16) |
           ((uint32_t)buffer[2] << 8) | buffer[3];
}

static err_t spi_exchange(uint8_t *tx, uint8_t *rx, size_t size)
{
    spi_master_select_device(GPIO_PA4);
    err_t status = spi_master_transfer(&spi, tx, rx, size);
    spi_master_deselect_device(GPIO_PA4);
    return status;
}

static bool read_status_footer(volatile uint32_t *result)
{
    uint8_t tx[68] = {0}, rx[68] = {0}; // Four-byte header and default 64-byte payload.
    put_word(tx, 0xa0000001u); // DNC, NORX, no valid transmit data, odd parity.
    if (spi_exchange(tx, rx, sizeof(tx)) != SPI_MASTER_SUCCESS) {
        return false;
    }
    *result = get_word(rx + 64);
    return __builtin_parity(*result) && !(*result & 0xc0200000u); // EXST, HDRB, DV clear.
}

static bool control(uint32_t address, uint32_t *value, bool write)
{
    uint8_t tx[16] = {0}, rx[16] = {0};
    uint32_t header = (address << 8) | (write ? WRITE_HEADER : 0);
    header |= (uint32_t)!__builtin_parity(header);
    put_word(tx, header);
    if (write) {
        put_word(tx + 4, *value);
        if (protected_mode) {
            put_word(tx + 8, ~*value);
        }
    }

    err_t status = spi_exchange(tx, rx, protected_mode ? 16 : 12);
    uint32_t response = get_word(rx + 8);
    if (status != SPI_MASTER_SUCCESS || get_word(rx + 4) != header ||
        (protected_mode && get_word(rx + 12) != ~response)) {
        return false;
    }
    if (write) {
        return response == *value;
    }
    *value = response;
    return true;
}

static bool write_register(uint32_t address, uint32_t value)
{
    return control(address, &value, true);
}

static bool read_register(uint32_t address, volatile uint32_t *result)
{
    uint32_t value;
    if (!control(address, &value, false)) {
        return false;
    }
    *result = value;
    return true;
}

static unsigned probe(void)
{
    spi_master_config_t config;
    digital_out_t cs, reset;
    digital_in_t irq;

    digital_out_init(&cs, GPIO_PA4);
    digital_out_high(&cs);
    digital_out_init(&reset, GPIO_PE11);
    digital_out_high(&reset);
    digital_in_init(&irq, GPIO_PD3);

    spi_master_configure_default(&config);
    config.sck = GPIO_PA5;
    config.miso = GPIO_PA6;
    config.mosi = GPIO_PB5;
    config.speed = 1000000;
    if (spi_master_open(&spi, &config) == SPI_MASTER_ERROR) {
        return 1;
    }

    digital_out_low(&reset);
    Delay_ms(2);
    digital_out_high(&reset);
    Delay_ms(25);

    lan8651_result.initial_irq = digital_in_read(&irq);
    if (!read_register(OA_IDVER, &lan8651_result.idver) || lan8651_result.idver != 0x11 ||
        !read_register(LAN8651_DEVID, &lan8651_result.devid) ||
        (lan8651_result.devid >> 4) != 0x8651) {
        return 2;
    }
    if (!read_register(OA_STATUS0, &lan8651_result.initial_status) ||
        !(lan8651_result.initial_status & RESETC) || lan8651_result.initial_irq != 0) {
        return 3;
    }

    uint32_t settings;
    if (!control(OA_CONFIG0, &settings, false) || !write_register(OA_CONFIG0, settings | PROTE)) {
        return 4;
    }
    protected_mode = true;
    if (!read_register(LAN8651_DEVID, &lan8651_result.protected_id) ||
        lan8651_result.protected_id != lan8651_result.devid) {
        return 5;
    }
    if (!write_register(OA_STATUS0, RESETC) ||
        !read_register(OA_STATUS0, &lan8651_result.cleared_status) ||
        (lan8651_result.cleared_status & RESETC)) {
        return 6;
    }
    lan8651_result.cleared_irq = digital_in_read(&irq);
    if (!read_status_footer(&lan8651_result.footer)) {
        return 9;
    }
    lan8651_result.acknowledged_irq = digital_in_read(&irq);
    if (lan8651_result.cleared_irq != 0 || lan8651_result.acknowledged_irq != 1) {
        return 10;
    }
    if (!write_register(OA_RESET, 1)) {
        return 7;
    }
    protected_mode = false;
    Delay_ms(25);
    if (!read_register(OA_STATUS0, &lan8651_result.reset_status) ||
        !(lan8651_result.reset_status & RESETC)) {
        return 8;
    }
    return 0;
}

int main(void)
{
    log_cfg_t config;
    LOG_MAP_USB_UART(config);
    log_init(&logger, &config);
    unsigned error = probe();
    log_printf(&logger, "LAN8651 OA=%08" PRIX32 " ID=%08" PRIX32 " protected=%08" PRIX32 "\r\n",
               lan8651_result.idver, lan8651_result.devid, lan8651_result.protected_id);
    log_printf(&logger, "LAN8651 RESET=%08" PRIX32 "/%08" PRIX32 "/%08" PRIX32 " IRQ=%" PRIu32 "/%" PRIu32 "/%" PRIu32 "\r\n",
               lan8651_result.initial_status, lan8651_result.cleared_status,
               lan8651_result.reset_status, lan8651_result.initial_irq, lan8651_result.cleared_irq,
               lan8651_result.acknowledged_irq);
    log_printf(&logger, "LAN8651 FOOTER=%08" PRIX32 "\r\n", lan8651_result.footer);
    if (error) {
        log_printf(&logger, "LAN8651 FAIL %u\r\n", error);
    } else {
        log_printf(&logger, "LAN8651 PASS\r\n");
    }
    lan8651_result.result = error ? 0xBAD00000u + error : 0x86510000u;
    for (;;) {
        /* Keep the debug bus accessible for the SWD result readback. */
        __asm__ volatile ("nop");
    }
}
