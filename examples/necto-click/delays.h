#ifndef UNI_CLICKER_NECTO_DELAYS_H
#define UNI_CLICKER_NECTO_DELAYS_H

void Delay_ms(unsigned milliseconds);
void Delay_us(unsigned microseconds);
#define Delay_1us() Delay_us(1)
#define Delay_1ms() Delay_ms(1)
#define Delay_100ms() Delay_ms(100)
#define Delay_1sec() Delay_ms(1000)

#endif
