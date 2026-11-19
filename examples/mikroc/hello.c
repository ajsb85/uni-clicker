#define REG32(address) (*(volatile unsigned long *)(address))
#define SYST_CSR REG32(0xE000E010UL)
#define SYST_RVR REG32(0xE000E014UL)
#define SYST_CVR REG32(0xE000E018UL)

volatile unsigned long uni_heartbeat;
volatile unsigned long uni_tx_bytes;

static const char banner[] = "Hello, UNI Clicker from mikroC!\r\n";

static void wait_ms(unsigned long milliseconds)
{
    SYST_CVR = 0;
    while (milliseconds-- != 0) {
        while ((SYST_CSR & (1UL << 16)) == 0) {}
    }
}

static void write_banner(void)
{
    unsigned long i;
    for (i = 0; i < sizeof(banner) - 1; ++i) {
        while ((USART6_ISR & (1UL << 7)) == 0) {}
        USART6_TDR = banner[i];
    }
    while ((USART6_ISR & (1UL << 6)) == 0) {}
    uni_tx_bytes += sizeof(banner) - 1;
}

void main()
{
    unsigned long edges = 0;

    RCC_AHB1ENR |= (1UL << 2) | (1UL << 3);
    RCC_APB2ENR |= 1UL << 5;
    (void)RCC_AHB1ENR;
    (void)RCC_APB2ENR;

    GPIOD_BSRR = 1UL << 23;
    GPIOD_MODER = (GPIOD_MODER & ~(3UL << 14)) | (1UL << 14);

    GPIOC_AFRL = (GPIOC_AFRL & ~(0xffUL << 24)) | (0x88UL << 24);
    GPIOC_MODER = (GPIOC_MODER & ~(0x0fUL << 12)) | (0x0aUL << 12);
    USART6_BRR = 139;
    USART6_CR1 = 0x0d;

    SYST_RVR = 16000 - 1;
    SYST_CSR = 5;
    write_banner();

    while (1) {
        wait_ms(500);
        ++edges;
        GPIOD_BSRR = (edges & 1) ? (1UL << 7) : (1UL << 23);
        uni_heartbeat = edges;
        if ((edges & 1) == 0) write_banner();
    }
}
