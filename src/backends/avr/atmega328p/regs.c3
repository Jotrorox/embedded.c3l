module embedded::backends::avr::atmega328p::regs @feat(MCU_ATMEGA328P);

// ATmega328P register map: memory-mapped addresses (I/O address + 0x20, the
// form `lds`/`sts` and pointers use) and bit fields, named as in the
// ATmega328P datasheet (DS40002061). Not part of the public API.
//
// Inline asm uses I/O addresses (`in`/`out`) instead: SPL 0x3D, SPH 0x3E,
// SREG 0x3F.

// --- CPU and power (datasheet 7, 10, 11) ------------------------------------

const uint SREG  = 0x5F;
const uint SPL   = 0x5D;
const uint SPH   = 0x5E;
const uint SMCR  = 0x53;
const uint MCUSR = 0x54;
const uint PRR   = 0x64;

const char SREG_I = 1 << 7;   // global interrupt enable

const char SMCR_SE = 1 << 0;  // sleep enable; SM2:0 = 000 is idle mode

const char MCUSR_WDRF = 1 << 3;

// --- Watchdog (datasheet 10.9) -----------------------------------------------

const uint WDTCSR = 0x60;

const char WDTCSR_WDP3 = 1 << 5;
const char WDTCSR_WDCE = 1 << 4;
const char WDTCSR_WDE  = 1 << 3;
const char WDTCSR_WDP_LOW_MASK = 0x07; // WDP2:0

// --- I/O ports (datasheet 14.4) ----------------------------------------------
// Each port is three consecutive registers: PINx, DDRx, PORTx.

const uint PINB  = 0x23;
const uint DDRB  = 0x24;
const uint PORTB = 0x25;
const uint PINC  = 0x26;
const uint DDRC  = 0x27;
const uint PORTC = 0x28;
const uint PIND  = 0x29;
const uint DDRD  = 0x2A;
const uint PORTD = 0x2B;

const char PORT_FROM_PIN = 2; // PORTx = PINx + 2

// --- External interrupts (datasheet 12.2) ------------------------------------

const uint EIFR  = 0x3C;
const uint EIMSK = 0x3D;
const uint EICRA = 0x69;

// EICRA sense control, two bits per line (ISCn1:ISCn0).
const char ISC_MASK      = 0x03;
const char ISC_LOW_LEVEL = 0;
const char ISC_ANY_EDGE  = 1;
const char ISC_FALLING   = 2;
const char ISC_RISING    = 3;

// --- Timer/counters, shared fields (datasheet 15-18) -------------------------
// TCCRnA output-compare mode bits sit at the same positions on all three
// timers, as do the clock-select bits CSn2:0 in TCCRnB.

const char COM_A1 = 1 << 7;
const char COM_A0 = 1 << 6;
const char COM_B1 = 1 << 5;
const char COM_B0 = 1 << 4;
const char COM_A_MASK = COM_A1 | COM_A0;
const char COM_B_MASK = COM_B1 | COM_B0;
const char CS_MASK = 0x07;

// --- Timer/counter 0 (datasheet 15) ------------------------------------------

const uint TIFR0  = 0x35;
const uint TCCR0A = 0x44;
const uint TCCR0B = 0x45;
const uint TCNT0  = 0x46;
const uint OCR0A  = 0x47;
const uint OCR0B  = 0x48;
const uint TIMSK0 = 0x6E;

const char WGM01 = 1 << 1; // TCCR0A
const char WGM00 = 1 << 0;
const char CS01  = 1 << 1; // TCCR0B
const char CS00  = 1 << 0;
const char TOIE0 = 1 << 0; // TIMSK0
const char TOV0  = 1 << 0; // TIFR0

// --- Timer/counter 1 (datasheet 16) ------------------------------------------
// 16-bit registers: use soc::write16/read16 for the TEMP byte ordering.

const uint TCCR1A = 0x80;
const uint TCCR1B = 0x81;
const uint TCNT1  = 0x84;
const uint ICR1   = 0x86;
const uint OCR1A  = 0x88;
const uint OCR1B  = 0x8A;

const char WGM11 = 1 << 1; // TCCR1A
const char WGM13 = 1 << 4; // TCCR1B
const char WGM12 = 1 << 3;

// --- Timer/counter 2 (datasheet 18) ------------------------------------------

const uint TCCR2A = 0xB0;
const uint TCCR2B = 0xB1;
const uint OCR2A  = 0xB3;
const uint OCR2B  = 0xB4;

const char WGM21 = 1 << 1; // TCCR2A
const char WGM20 = 1 << 0;

// --- SPI (datasheet 19.5) ----------------------------------------------------

const uint SPCR = 0x4C;
const uint SPSR = 0x4D;
const uint SPDR = 0x4E;

const char SPE  = 1 << 6; // SPCR
const char DORD = 1 << 5;
const char MSTR = 1 << 4;
const char CPOL = 1 << 3;
const char CPHA = 1 << 2;
const char SPR_MASK = 0x03; // SPR1:0
const char SPIF  = 1 << 7; // SPSR
const char SPI2X = 1 << 0;

// --- USART0 (datasheet 20.11) ------------------------------------------------

const uint UCSR0A = 0xC0;
const uint UCSR0B = 0xC1;
const uint UCSR0C = 0xC2;
const uint UBRR0L = 0xC4;
const uint UBRR0H = 0xC5;
const uint UDR0   = 0xC6;

const char RXC0  = 1 << 7; // UCSR0A
const char TXC0  = 1 << 6;
const char UDRE0 = 1 << 5;
const char FE0   = 1 << 4;
const char DOR0  = 1 << 3;
const char UPE0  = 1 << 2;
const char U2X0  = 1 << 1;
const char RXEN0 = 1 << 4; // UCSR0B
const char TXEN0 = 1 << 3;
const char UPM01 = 1 << 5; // UCSR0C
const char UPM00 = 1 << 4;
const char USBS0 = 1 << 3;
const char UCSZ0_SHIFT = 1; // UCSZ01:00 in bits 2:1
const char UBRR0H_MASK = 0x0F; // UBRR0 is 12 bits

// --- TWI / I2C (datasheet 22.9) ----------------------------------------------

const uint TWBR = 0xB8;
const uint TWSR = 0xB9;
const uint TWDR = 0xBB;
const uint TWCR = 0xBC;

const char TWINT = 1 << 7; // TWCR
const char TWEA  = 1 << 6;
const char TWSTA = 1 << 5;
const char TWSTO = 1 << 4;
const char TWEN  = 1 << 2;
const char TWPS_MASK = 0x03; // TWSR prescaler bits

// TWSR status codes, master modes (datasheet tables 22-3 and 22-4).
const char TW_STATUS_MASK  = 0xF8;
const char TW_START        = 0x08;
const char TW_REP_START    = 0x10;
const char TW_MT_SLA_ACK   = 0x18;
const char TW_MT_SLA_NACK  = 0x20;
const char TW_MT_DATA_ACK  = 0x28;
const char TW_MT_DATA_NACK = 0x30;
const char TW_ARB_LOST     = 0x38;
const char TW_MR_SLA_ACK   = 0x40;
const char TW_MR_SLA_NACK  = 0x48;
const char TW_MR_DATA_ACK  = 0x50;
const char TW_MR_DATA_NACK = 0x58;

// --- ADC (datasheet 24.9) ----------------------------------------------------

const uint ADCL   = 0x78;
const uint ADCH   = 0x79;
const uint ADCSRA = 0x7A;
const uint ADMUX  = 0x7C;
const uint DIDR0  = 0x7E;

const char REFS1 = 1 << 7; // ADMUX
const char REFS0 = 1 << 6;
const char REFS_MASK = REFS1 | REFS0;
const char ADEN = 1 << 7;  // ADCSRA
const char ADSC = 1 << 6;
const char ADPS2 = 1 << 2;
const char ADPS1 = 1 << 1;
const char ADPS0 = 1 << 0;
