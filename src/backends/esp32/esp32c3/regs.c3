module embedded::backends::esp32::esp32c3::regs @feat(MCU_ESP32C3);

// ESP32-C3 register addresses and fields used by the backend. Not part of
// the public API. Addresses and fields follow the ESP32-C3 Technical
// Reference Manual and ESP-IDF v5.3 (components/soc/esp32c3/include/soc/
// *_reg.h, gpio_sig_map.h, interrupts.h and rom/rtc.h).
//
// Conventions: single-bit fields are masks already shifted into place.
// Multi-bit fields have a *_SHIFT and, where the code reads them back, a
// *_MASK that is also shifted into place. Registers of a peripheral that has
// several instances (UART, LEDC channels, timer groups) are offsets from the
// instance base; all others are absolute addresses.

// ---------------------------------------------------------------------------
// SYSTEM: clock gating, peripheral reset, CPU clock source (system_reg.h)
// ---------------------------------------------------------------------------

const uint SYSTEM_BASE = 0x600C_0000;
const uint SYSTEM_PERIP_CLK_EN0 = SYSTEM_BASE + 0x010;
const uint SYSTEM_PERIP_RST_EN0 = SYSTEM_BASE + 0x018;
const uint SYSTEM_SYSCLK_CONF   = SYSTEM_BASE + 0x058;

// Bits shared by SYSTEM_PERIP_CLK_EN0 and SYSTEM_PERIP_RST_EN0.
const uint PERIP_UART0      = 1u << 2;
const uint PERIP_UART1      = 1u << 5;
const uint PERIP_SPI2       = 1u << 6;
const uint PERIP_I2C_EXT0   = 1u << 7;
const uint PERIP_LEDC       = 1u << 11;
const uint PERIP_UART_MEM   = 1u << 24;
const uint PERIP_APB_SARADC = 1u << 28;
const uint PERIP_SYSTIMER   = 1u << 29;

// SYSTEM_SYSCLK_CONF
const uint SYSTEM_PRE_DIV_CNT_MASK = 0x3FF;      // CPU clock divider - 1
const uint SYSTEM_SOC_CLK_SEL_SHIFT = 10;
const uint SYSTEM_SOC_CLK_SEL_MASK = 0x3u << 10;
const uint SYSTEM_SOC_CLK_SEL_XTAL = 0;
const uint SYSTEM_SOC_CLK_SEL_PLL = 1;            // 2 = RC_FAST

// ---------------------------------------------------------------------------
// SYSTIMER (systimer_reg.h)
// ---------------------------------------------------------------------------

const uint SYSTIMER_BASE = 0x6002_3000;
const uint SYSTIMER_CONF           = SYSTIMER_BASE + 0x000;
const uint SYSTIMER_UNIT0_OP       = SYSTIMER_BASE + 0x004;
const uint SYSTIMER_UNIT0_VALUE_HI = SYSTIMER_BASE + 0x040;
const uint SYSTIMER_UNIT0_VALUE_LO = SYSTIMER_BASE + 0x044;

// SYSTIMER_CONF
const uint SYSTIMER_CONF_CLK_EN = 1u << 31;
const uint SYSTIMER_CONF_UNIT0_WORK_EN = 1u << 30;
const uint SYSTIMER_CONF_UNIT0_CORE0_STALL_EN = 1u << 28;
// SYSTIMER_UNIT0_OP
const uint SYSTIMER_UNIT0_UPDATE = 1u << 30;
const uint SYSTIMER_UNIT0_VALUE_VALID = 1u << 29;
// SYSTIMER_UNIT0_VALUE_HI: the counter is 52 bits wide.
const uint SYSTIMER_UNIT0_VALUE_HI_MASK = 0x000F_FFFF;

// ---------------------------------------------------------------------------
// GPIO and GPIO matrix (gpio_reg.h, gpio_sig_map.h)
// ---------------------------------------------------------------------------

const uint GPIO_BASE = 0x6000_4000;
const uint GPIO_OUT         = GPIO_BASE + 0x004;
const uint GPIO_OUT_W1TS    = GPIO_BASE + 0x008;
const uint GPIO_OUT_W1TC    = GPIO_BASE + 0x00C;
const uint GPIO_ENABLE_W1TS = GPIO_BASE + 0x024;
const uint GPIO_ENABLE_W1TC = GPIO_BASE + 0x028;
const uint GPIO_IN          = GPIO_BASE + 0x03C;
const uint GPIO_STATUS      = GPIO_BASE + 0x044;  // one interrupt pending bit per pin
const uint GPIO_STATUS_W1TC = GPIO_BASE + 0x04C;
// Arrays of 32-bit registers: GPIO_PINn per pin, FUNCn_IN_SEL_CFG per
// peripheral input signal, FUNCn_OUT_SEL_CFG per pin.
const uint GPIO_PIN0 = GPIO_BASE + 0x074;
const uint GPIO_FUNC0_IN_SEL_CFG = GPIO_BASE + 0x154;
const uint GPIO_FUNC0_OUT_SEL_CFG = GPIO_BASE + 0x554;

// GPIO_PINn
const uint GPIO_PIN_PAD_DRIVER = 1u << 2;         // open drain
const uint GPIO_PIN_INT_TYPE_SHIFT = 7;
const uint GPIO_PIN_INT_TYPE_MASK = 0x7u << 7;
const uint GPIO_PIN_INT_ENA_CPU = 1u << 13;
const uint GPIO_PIN_INT_ENA_MASK = 0x1Fu << 13;
// GPIO_PINn INT_TYPE values.
const uint GPIO_INT_TYPE_RISING     = 1;
const uint GPIO_INT_TYPE_FALLING    = 2;
const uint GPIO_INT_TYPE_ANY_EDGE   = 3;
const uint GPIO_INT_TYPE_LOW_LEVEL  = 4;
const uint GPIO_INT_TYPE_HIGH_LEVEL = 5;

// GPIO_FUNCn_IN_SEL_CFG: the low bits select the pin.
const uint GPIO_FUNC_IN_SEL_ROUTE = 1u << 6;      // take the signal from the matrix
// GPIO_FUNCn_OUT_SEL_CFG: the low bits select the signal.
const uint GPIO_FUNC_OUT_OEN_SEL = 1u << 9;       // output enable from GPIO_ENABLE
const uint GPIO_OUT_SIGNAL_SIMPLE = 0x80;         // plain GPIO_OUT bit

// Peripheral signal indices for the GPIO matrix. Where an output and an
// input signal share an index, one constant serves both.
const uint SIG_U0 = 6;               // U0TXD_OUT / U0RXD_IN
const uint SIG_U1 = 9;               // U1TXD_OUT / U1RXD_IN
const uint SIG_LEDC_LS_OUT0 = 45;    // LEDC_LS_SIG_OUT0..5 follow
const uint SIG_I2CEXT0_SCL = 53;     // I2CEXT0_SCL_IN / _OUT
const uint SIG_I2CEXT0_SDA = 54;     // I2CEXT0_SDA_IN / _OUT
const uint SIG_FSPICLK = 63;         // FSPICLK_OUT
const uint SIG_FSPIQ = 64;           // FSPIQ_IN (MISO)
const uint SIG_FSPID = 65;           // FSPID_OUT (MOSI)

// ---------------------------------------------------------------------------
// IO MUX (io_mux_reg.h): one register per pad, GPIO0 first.
// ---------------------------------------------------------------------------

const uint IO_MUX_BASE = 0x6000_9000;
const uint IO_MUX_GPIO0 = IO_MUX_BASE + 0x004;

// IO_MUX_GPIOn layout. The MCU_* bits apply in light sleep, the FUN_* bits
// when awake.
//   0 MCU_OE   1 SLP_SEL   2 MCU_WPD   3 MCU_WPU   4 MCU_IE
//   7 FUN_WPD (pull-down)  8 FUN_WPU (pull-up)  9 FUN_IE (input enable)
//   11:10 FUN_DRV  drive strength: 0 ~5 mA, 1 ~10 mA, 2 ~20 mA, 3 ~40 mA
//   14:12 MCU_SEL  pad function; 1 is GPIO / GPIO matrix
//   15 FILTER_EN
// (Plain constants rather than a bitstruct: c3c 0.8.6 does not accept a
// bitstruct-to-uint cast as a constant in another module's const.)
const uint IO_MUX_FUN_WPD = 1u << 7;
const uint IO_MUX_FUN_WPU = 1u << 8;
const uint IO_MUX_FUN_IE  = 1u << 9;
const uint IO_MUX_FUN_DRV_SHIFT = 10;
const uint IO_MUX_FUN_DRV_DEFAULT = 2u << 10;     // ~20 mA
const uint IO_MUX_MCU_SEL_SHIFT = 12;
const uint IO_MUX_MCU_SEL_GPIO = 1u << 12;

// ---------------------------------------------------------------------------
// UART0/UART1 (uart_reg.h): offsets from UARTn_BASE.
// ---------------------------------------------------------------------------

const uint UART0_BASE = 0x6000_0000;
const uint UART1_BASE = 0x6001_0000;
const uint UART_FIFO       = 0x00;
const uint UART_INT_RAW    = 0x04;
const uint UART_INT_CLR    = 0x10;
const uint UART_CLKDIV     = 0x14;
const uint UART_STATUS     = 0x1C;
const uint UART_CONF0      = 0x20;
const uint UART_CONF1      = 0x24;
const uint UART_FSM_STATUS = 0x6C;
const uint UART_CLK_CONF   = 0x78;

// UART_INT_RAW / UART_INT_CLR
const uint UART_INT_PARITY_ERR = 1u << 2;
const uint UART_INT_FRM_ERR    = 1u << 3;
const uint UART_INT_RXFIFO_OVF = 1u << 4;
// UART_CLKDIV: 12.4 fixed-point divider, integer part low, fraction at 23:20.
const uint UART_CLKDIV_INT_MASK = 0xFFF;
const uint UART_CLKDIV_FRAG_SHIFT = 20;
const uint UART_CLKDIV_FRAG_MASK = 0xFu << 20;
// UART_STATUS
const uint UART_STATUS_RXFIFO_CNT_MASK = 0x3FF;
const uint UART_STATUS_TXFIFO_CNT_SHIFT = 16;
const uint UART_STATUS_TXFIFO_CNT_MASK = 0x3FFu << 16;
// UART_CONF0
const uint UART_CONF0_PARITY_ODD = 1u << 0;
const uint UART_CONF0_PARITY_EN = 1u << 1;
const uint UART_CONF0_BIT_NUM_SHIFT = 2;          // data bits - 5
const uint UART_CONF0_STOP_BIT_NUM_SHIFT = 4;     // 1: one, 3: two stop bits
const uint UART_CONF0_RXFIFO_RST = 1u << 17;
const uint UART_CONF0_TXFIFO_RST = 1u << 18;
const uint UART_CONF0_MEM_CLK_EN = 1u << 28;
// UART_FSM_STATUS
const uint UART_FSM_ST_UTX_OUT_MASK = 0xF0;
// UART_CLK_CONF
const uint UART_CLK_CONF_SCLK_DIV_NUM_SHIFT = 12;
const uint UART_CLK_CONF_SCLK_DIV_NUM_MASK = 0xFFu << 12;
const uint UART_CLK_CONF_SCLK_SEL_XTAL = 3u << 20;
const uint UART_CLK_CONF_SCLK_EN = 1u << 22;
const uint UART_CLK_CONF_RST_CORE = 1u << 23;
const uint UART_CLK_CONF_TX_SCLK_EN = 1u << 24;
const uint UART_CLK_CONF_RX_SCLK_EN = 1u << 25;

// ---------------------------------------------------------------------------
// USB-Serial-JTAG (usb_serial_jtag_reg.h): a 64-byte FIFO in each direction
// behind one data register.
// ---------------------------------------------------------------------------

const uint USJ_BASE = 0x6004_3000;
const uint USJ_EP1      = USJ_BASE + 0x00;
const uint USJ_EP1_CONF = USJ_BASE + 0x04;

// USJ_EP1_CONF
const uint USJ_WR_DONE = 1u << 0;
const uint USJ_IN_EP_DATA_FREE = 1u << 1;
const uint USJ_OUT_EP_DATA_AVAIL = 1u << 2;

// ---------------------------------------------------------------------------
// I2C0 (i2c_reg.h). The ESP32-C3 has one I2C controller.
// ---------------------------------------------------------------------------

const uint I2C0_BASE = 0x6001_3000;
const uint I2C_SCL_LOW_PERIOD   = I2C0_BASE + 0x00;
const uint I2C_CTR              = I2C0_BASE + 0x04;
const uint I2C_TO               = I2C0_BASE + 0x0C;
const uint I2C_FIFO_CONF        = I2C0_BASE + 0x18;
const uint I2C_DATA             = I2C0_BASE + 0x1C;
const uint I2C_INT_RAW          = I2C0_BASE + 0x20;
const uint I2C_INT_CLR          = I2C0_BASE + 0x24;
const uint I2C_SDA_HOLD         = I2C0_BASE + 0x30;
const uint I2C_SDA_SAMPLE       = I2C0_BASE + 0x34;
const uint I2C_SCL_HIGH_PERIOD  = I2C0_BASE + 0x38;
const uint I2C_SCL_START_HOLD   = I2C0_BASE + 0x40;
const uint I2C_SCL_RSTART_SETUP = I2C0_BASE + 0x44;
const uint I2C_SCL_STOP_HOLD    = I2C0_BASE + 0x48;
const uint I2C_SCL_STOP_SETUP   = I2C0_BASE + 0x4C;
const uint I2C_FILTER_CFG       = I2C0_BASE + 0x50;
const uint I2C_CLK_CONF         = I2C0_BASE + 0x54;
const uint I2C_COMD0            = I2C0_BASE + 0x58;   // COMD0..7 follow

// I2C_SCL_LOW_PERIOD
const uint I2C_SCL_LOW_PERIOD_MASK = 0x1FF;
// I2C_CTR
const uint I2C_CTR_SDA_FORCE_OUT = 1u << 0;
const uint I2C_CTR_SCL_FORCE_OUT = 1u << 1;
const uint I2C_CTR_MS_MODE     = 1u << 4;
const uint I2C_CTR_TRANS_START = 1u << 5;
const uint I2C_CTR_CLK_EN      = 1u << 8;
const uint I2C_CTR_FSM_RST     = 1u << 10;
const uint I2C_CTR_CONF_UPGATE = 1u << 11;
// I2C_TO: the timeout is 2^value source clocks.
const uint I2C_TO_VALUE_MASK = 0x1F;
const uint I2C_TO_ENABLE = 1u << 5;
// I2C_FIFO_CONF
const uint I2C_FIFO_RX_RST = 1u << 12;
const uint I2C_FIFO_TX_RST = 1u << 13;
// I2C_INT_RAW / I2C_INT_CLR
const uint I2C_INT_END_DETECT     = 1u << 3;
const uint I2C_INT_ARB_LOST       = 1u << 5;
const uint I2C_INT_TRANS_COMPLETE = 1u << 7;
const uint I2C_INT_TIME_OUT       = 1u << 8;
const uint I2C_INT_NACK           = 1u << 10;
// I2C_SCL_HIGH_PERIOD
const uint I2C_SCL_HIGH_PERIOD_MASK = 0x1FF;
const uint I2C_SCL_WAIT_HIGH_PERIOD_SHIFT = 9;
const uint I2C_SCL_WAIT_HIGH_PERIOD_MASK = 0x7Fu << 9;
// I2C_FILTER_CFG: thresholds in source clocks.
const uint I2C_FILTER_SCL_THRES_SHIFT = 0;
const uint I2C_FILTER_SDA_THRES_SHIFT = 4;
const uint I2C_FILTER_SCL_EN = 1u << 8;
const uint I2C_FILTER_SDA_EN = 1u << 9;
// I2C_CLK_CONF
const uint I2C_CLK_CONF_SCLK_DIV_NUM_MASK = 0xFF; // divider - 1; source XTAL (SCLK_SEL 0)
const uint I2C_CLK_CONF_SCLK_ACTIVE = 1u << 21;

// I2C_COMDn command word: op_code[13:11] ack_val[10] ack_exp[9] ack_en[8]
// byte_num[7:0].
const uint I2C_CMD_OP_SHIFT = 11;
const uint I2C_CMD_ACK_VAL_NACK = 1u << 10;
const uint I2C_CMD_ACK_EN = 1u << 8;
const uint I2C_OP_WRITE  = 1;
const uint I2C_OP_STOP   = 2;
const uint I2C_OP_READ   = 3;
const uint I2C_OP_END    = 4;
const uint I2C_OP_RSTART = 6;

// ---------------------------------------------------------------------------
// GP-SPI2 (spi_reg.h)
// ---------------------------------------------------------------------------

const uint SPI2_BASE = 0x6002_4000;
const uint SPI_CMD         = SPI2_BASE + 0x00;
const uint SPI_CTRL        = SPI2_BASE + 0x08;
const uint SPI_CLOCK       = SPI2_BASE + 0x0C;
const uint SPI_USER        = SPI2_BASE + 0x10;
const uint SPI_USER1       = SPI2_BASE + 0x14;
const uint SPI_USER2       = SPI2_BASE + 0x18;
const uint SPI_MS_DLEN     = SPI2_BASE + 0x1C;
const uint SPI_MISC        = SPI2_BASE + 0x20;
const uint SPI_DMA_CONF    = SPI2_BASE + 0x30;
const uint SPI_DMA_INT_CLR = SPI2_BASE + 0x38;
const uint SPI_DMA_INT_RAW = SPI2_BASE + 0x3C;
const uint SPI_W0          = SPI2_BASE + 0x98;    // W0..W15 data buffer
const uint SPI_SLAVE       = SPI2_BASE + 0xE0;
const uint SPI_CLK_GATE    = SPI2_BASE + 0xE8;

// SPI_CMD
const uint SPI_CMD_UPDATE = 1u << 23;
const uint SPI_CMD_USR = 1u << 24;
// SPI_CTRL
const uint SPI_CTRL_RD_BIT_ORDER = 1u << 25;
const uint SPI_CTRL_WR_BIT_ORDER = 1u << 26;
// SPI_CLOCK: f = f_src / ((CLKDIV_PRE + 1) * (CLKCNT_N + 1)), CLKCNT_H the
// high phase and CLKCNT_L = CLKCNT_N.
const uint SPI_CLOCK_CLKCNT_L_SHIFT = 0;
const uint SPI_CLOCK_CLKCNT_H_SHIFT = 6;
const uint SPI_CLOCK_CLKCNT_N_SHIFT = 12;
const uint SPI_CLOCK_CLKDIV_PRE_SHIFT = 18;
const uint SPI_CLOCK_EQU_SYSCLK = 1u << 31;
// SPI_USER
const uint SPI_USER_DOUTDIN = 1u << 0;
const uint SPI_USER_CK_OUT_EDGE = 1u << 9;
const uint SPI_USER_USR_MOSI = 1u << 27;
const uint SPI_USER_USR_MISO = 1u << 28;
// SPI_MISC: CK_IDLE_EDGE is CPOL; CS0_DIS..CS5_DIS are bits 5:0.
const uint SPI_MISC_CS_ALL_DISABLED = 0x3F;
const uint SPI_MISC_CK_IDLE_EDGE = 1u << 29;
// SPI_DMA_INT_RAW / SPI_DMA_INT_CLR
const uint SPI_INT_TRANS_DONE = 1u << 12;
// SPI_CLK_GATE: MST_CLK_SEL (bit 2) clear selects XTAL.
const uint SPI_CLK_GATE_CLK_EN = 1u << 0;
const uint SPI_CLK_GATE_MST_CLK_ACTIVE = 1u << 1;

// ---------------------------------------------------------------------------
// LEDC (ledc_reg.h): low-speed channels and timers.
// ---------------------------------------------------------------------------

const uint LEDC_BASE = 0x6001_9000;
// Channel n registers: LEDC_BASE + n * LEDC_CH_STRIDE + offset.
const uint LEDC_CH_STRIDE = 0x14;
const uint LEDC_CH_CONF0  = 0x00;
const uint LEDC_CH_HPOINT = 0x04;
const uint LEDC_CH_DUTY   = 0x08;
const uint LEDC_CH_CONF1  = 0x0C;
// Timer n configuration: LEDC_TIMER0_CONF + n * LEDC_TIMER_STRIDE.
const uint LEDC_TIMER0_CONF = LEDC_BASE + 0xA0;
const uint LEDC_TIMER_STRIDE = 0x08;
const uint LEDC_CONF = LEDC_BASE + 0xD0;

// LEDC_CHn_CONF0: the low bits select the timer.
const uint LEDC_CH_SIG_OUT_EN = 1u << 2;
const uint LEDC_CH_PARA_UP = 1u << 4;
// LEDC_CHn_DUTY: fixed point with 4 fraction bits.
const uint LEDC_CH_DUTY_FRAC_BITS = 4;
// LEDC_CHn_CONF1
const uint LEDC_CH_DUTY_CYCLE_SHIFT = 10;
const uint LEDC_CH_DUTY_NUM_SHIFT = 20;
const uint LEDC_CH_DUTY_INC = 1u << 30;
const uint LEDC_CH_DUTY_START = 1u << 31;
// LEDC_TIMERn_CONF: DUTY_RES in bits 3:0, CLK_DIV 10.8 fixed point above it.
const uint LEDC_TIMER_DUTY_RES_MASK = 0xF;
const uint LEDC_TIMER_CLK_DIV_SHIFT = 4;
const uint LEDC_TIMER_CLK_DIV_MAX = (1u << 18) - 1;
const uint LEDC_TIMER_RST = 1u << 23;
const uint LEDC_TIMER_PARA_UP = 1u << 25;
// LEDC_CONF
const uint LEDC_CONF_APB_CLK_SEL_XTAL = 3;
const uint LEDC_CONF_CLK_EN = 1u << 31;

// ---------------------------------------------------------------------------
// APB SAR ADC (apb_saradc_reg.h)
// ---------------------------------------------------------------------------

const uint SARADC_BASE = 0x6004_0000;
const uint SARADC_CTRL           = SARADC_BASE + 0x000;
const uint SARADC_ONETIME_SAMPLE = SARADC_BASE + 0x020;
const uint SARADC_1_DATA_STATUS  = SARADC_BASE + 0x02C;
const uint SARADC_INT_RAW        = SARADC_BASE + 0x044;
const uint SARADC_INT_CLR        = SARADC_BASE + 0x04C;
const uint SARADC_CLKM_CONF      = SARADC_BASE + 0x054;

// SARADC_CTRL
const uint SARADC_CTRL_SAR_CLK_GATED = 1u << 6;
const uint SARADC_CTRL_SAR_CLK_DIV_SHIFT = 7;
const uint SARADC_CTRL_SAR_CLK_DIV_MASK = 0xFFu << 7;
const uint SARADC_CTRL_XPD_SAR_FORCE_MASK = 3u << 27;
const uint SARADC_CTRL_XPD_SAR_FORCE_ON = 3u << 27;
// SARADC_ONETIME_SAMPLE
const uint SARADC_ONETIME_ATTEN_SHIFT = 23;
const uint SARADC_ONETIME_CHANNEL_SHIFT = 25;
const uint SARADC_ONETIME_START = 1u << 29;
const uint SARADC_ONETIME_ADC1 = 1u << 31;
// SARADC_1_DATA_STATUS: the 12-bit result is in the low bits.
const uint SARADC_1_DATA_MASK = 0xFFF;
// SARADC_INT_RAW / SARADC_INT_CLR
const uint SARADC_INT_ADC1_DONE = 1u << 31;
// SARADC_CLKM_CONF: f = f_src / (DIV_NUM + DIV_B / DIV_A).
const uint SARADC_CLKM_DIV_NUM_SHIFT = 0;
const uint SARADC_CLKM_DIV_A_SHIFT = 14;
const uint SARADC_CLKM_CLK_EN = 1u << 20;
const uint SARADC_CLKM_CLK_SEL_SHIFT = 21;
const uint SARADC_CLKM_CLK_SEL_APB = 2;

// ---------------------------------------------------------------------------
// Timer groups: main system watchdogs MWDT0/1 (timer_group_reg.h). Offsets
// from TIMGn_BASE.
// ---------------------------------------------------------------------------

const uint TIMG0_BASE = 0x6001_F000;
const uint TIMG1_BASE = 0x6002_0000;
const uint TIMG_WDTCONFIG0  = 0x0048;
const uint TIMG_WDTCONFIG1  = 0x004C;
const uint TIMG_WDTCONFIG2  = 0x0050;   // stage 0 timeout in ticks
const uint TIMG_WDTFEED     = 0x0060;
const uint TIMG_WDTWPROTECT = 0x0064;

// TIMG_WDTCONFIG0. CONFIG0..2 are only latched when CONF_UPDATE_EN is written.
const uint TIMG_WDT_SYS_RESET_LENGTH_SHIFT = 15;
const uint TIMG_WDT_CPU_RESET_LENGTH_SHIFT = 18;
const uint TIMG_WDT_USE_XTAL = 1u << 21;
const uint TIMG_WDT_CONF_UPDATE_EN = 1u << 22;
const uint TIMG_WDT_STG0_SHIFT = 29;
const uint TIMG_WDT_EN = 1u << 31;
// Stage actions and reset pulse lengths.
const uint TIMG_WDT_STG_RESET_SYSTEM = 3;
const uint TIMG_WDT_RESET_LENGTH_3_2_US = 7;
// TIMG_WDTCONFIG1
const uint TIMG_WDT_DIVCNT_RST = 1u << 0;
const uint TIMG_WDT_CLK_PRESCALE_SHIFT = 16;
// TIMG_WDTWPROTECT: every MWDT register, including the feed register, is
// write-protected unless this key is written here.
const uint TIMG_WDT_WKEY = 0x50D8_3AA1;

// ---------------------------------------------------------------------------
// RTC_CNTL: reset cause, RTC watchdog, super watchdog, analog power
// (rtc_cntl_reg.h)
// ---------------------------------------------------------------------------

const uint RTC_CNTL_BASE = 0x6000_8000;
const uint RTC_CNTL_RESET_STATE  = RTC_CNTL_BASE + 0x038;
const uint RTC_CNTL_WDTCONFIG0   = RTC_CNTL_BASE + 0x090;
const uint RTC_CNTL_WDTWPROTECT  = RTC_CNTL_BASE + 0x0A8;
const uint RTC_CNTL_SWD_CONF     = RTC_CNTL_BASE + 0x0AC;
const uint RTC_CNTL_SWD_WPROTECT = RTC_CNTL_BASE + 0x0B0;
const uint RTC_CNTL_SENSOR_CTRL  = RTC_CNTL_BASE + 0x11C;

// RTC_CNTL_RESET_STATE: reset cause of CPU0 in the low bits.
const uint RTC_CNTL_RESET_CAUSE_MASK = 0x3F;
// RTC_CNTL_WDTWPROTECT
const uint RTC_CNTL_WDT_WKEY = 0x50D8_3AA1;
// RTC_CNTL_SWD_CONF / RTC_CNTL_SWD_WPROTECT
const uint RTC_CNTL_SWD_AUTO_FEED_EN = 1u << 31;
const uint RTC_CNTL_SWD_WKEY = 0x8F1D_312A;
// RTC_CNTL_SENSOR_CTRL: FORCE_XPD_SAR powers the SAR ADC's analog part.
const uint RTC_CNTL_FORCE_XPD_SAR_ON = 3u << 30;

// Watchdog reset causes (RESET_REASON in rom/rtc.h).
const uint RESET_TG0WDT_SYS = 7;
const uint RESET_TG1WDT_SYS = 8;
const uint RESET_RTCWDT_SYS = 9;
const uint RESET_TG0WDT_CPU = 11;
const uint RESET_RTCWDT_CPU = 13;
const uint RESET_RTCWDT_RTC = 16;
const uint RESET_TG1WDT_CPU = 17;
const uint RESET_SUPER_WDT  = 18;

// ---------------------------------------------------------------------------
// Interrupt matrix, INTERRUPT_CORE0 (interrupt_core0_reg.h)
// ---------------------------------------------------------------------------

const uint INTC_BASE = 0x600C_2000;
// One map register per peripheral source, from INTC_BASE, holding the CPU
// interrupt line the source is routed to (0: not routed).
const uint INTC_SOURCE_MAP0 = INTC_BASE;
const uint INTC_MAP_LINE_MASK = 0x1F;
const uint INTC_CPU_INT_ENABLE = INTC_BASE + 0x104;  // one bit per line
const uint INTC_CPU_INT_TYPE   = INTC_BASE + 0x108;  // 0 level, 1 edge
const uint INTC_CPU_INT_CLEAR  = INTC_BASE + 0x10C;
const uint INTC_CPU_INT_PRI_0  = INTC_BASE + 0x114;  // one register per line
const uint INTC_CPU_INT_THRESH = INTC_BASE + 0x194;

// ---------------------------------------------------------------------------
// RISC-V CSR fields
// ---------------------------------------------------------------------------

const uint MSTATUS_MIE = 1u << 3;
const uint MCAUSE_INTERRUPT = 1u << 31;
const uint MCAUSE_LINE_MASK = 0x1F;  // CPU line of an interrupt (32 lines)
