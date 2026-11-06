module embedded::pwm;

import embedded::gpio;
import embedded::irq;
import embedded::backends::esp32::esp32c3::soc;

// LEDC in low-speed mode (the only mode on the ESP32-C3): 6 channels, each
// driven by one of 4 timers, clocked from the 40 MHz crystal.
const uint LEDC_BASE = 0x6001_9000;
const uint LEDC_CH_STRIDE = 0x14;
const uint LEDC_CH_CONF0  = 0x00;
const uint LEDC_CH_HPOINT = 0x04;
const uint LEDC_CH_DUTY   = 0x08;
const uint LEDC_CH_CONF1  = 0x0C;
const uint LEDC_TIMER0_CONF = LEDC_BASE + 0xA0;
const uint LEDC_TIMER_STRIDE = 0x08;
const uint LEDC_CONF = LEDC_BASE + 0xD0;

// CHn_CONF0
const uint CH_PARA_UP = 1u << 4;
const uint CH_SIG_OUT_EN = 1u << 2;
// CHn_CONF1: start a duty update of one step of one cycle.
const uint CH_DUTY_START = 1u << 31;
const uint CH_DUTY_INC = 1u << 30;
const uint CH_DUTY_NUM_1 = 1u << 20;
const uint CH_DUTY_CYCLE_1 = 1u << 10;
// TIMERn_CONF
const uint TIMER_PARA_UP = 1u << 25;
const uint TIMER_RST = 1u << 23;
const uint TIMER_CLK_DIV_SHIFT = 4;
// LEDC_CONF
const uint CONF_CLK_EN = 1u << 31;
const uint CONF_CLK_SEL_XTAL = 3;

const uint CHANNEL_COUNT = 6;
const uint TIMER_COUNT = 4;
const uint MAX_RESOLUTION = 14;
const uint MAX_CLK_DIV = (1u << 18) - 1; // 10.8 fixed point
const uint DEFAULT_HZ = 1000;
const uint SIGNAL_LS_OUT0 = 45;          // LEDC_LS_SIG_OUT0_IDX
const char NO_PIN = 0xFF;

struct Channel {
    char index;
}

char[CHANNEL_COUNT] channel_pin @local;
char[CHANNEL_COUNT] channel_timer @local;
uint[CHANNEL_COUNT] channel_permille @local;
uint[TIMER_COUNT] timer_hz @local;      // 0 = free
char[TIMER_COUNT] timer_resolution @local;
char[TIMER_COUNT] timer_users @local;
bool ledc_ready @local = false;

fn bool supports(gpio::Pin pin) => gpio::is_valid(pin);

fn uint ch_reg(char index, uint offset) @local => LEDC_BASE + (uint)index * LEDC_CH_STRIDE + offset;
fn uint timer_reg(char timer) @local => LEDC_TIMER0_CONF + (uint)timer * LEDC_TIMER_STRIDE;

fn void init() @local {
    soc::enable_peripheral(soc::PERIP_LEDC);
    soc::write(LEDC_CONF, CONF_CLK_EN | CONF_CLK_SEL_XTAL);
    for (uint i = 0; i < CHANNEL_COUNT; i++) channel_pin[i] = NO_PIN;
    ledc_ready = true;
}

// Duty resolution for `hz`: as many bits as the 40 MHz clock allows, at most
// 14, with a divider of at least 1.
fn uint resolution_for(uint hz) @local {
    uint ratio = soc::XTAL_HZ / hz;
    uint bits = 0;
    while (bits < MAX_RESOLUTION && (2u << bits) <= ratio) bits++;
    return bits;
}

// Programs `timer` for `hz`; returns the effective frequency.
fn uint? program_timer(char timer, uint hz) @local {
    if (hz == 0 || hz > soc::XTAL_HZ / 2) return UNSUPPORTED_FREQUENCY~;
    uint bits = resolution_for(hz);
    ulong div = ((ulong)soc::XTAL_HZ << 8) / ((ulong)hz << bits);
    if (div < 256 || div > MAX_CLK_DIV) return UNSUPPORTED_FREQUENCY~;

    uint conf = ((uint)div << TIMER_CLK_DIV_SHIFT) | bits;
    soc::write(timer_reg(timer), conf | TIMER_RST);
    soc::write(timer_reg(timer), conf | TIMER_PARA_UP);
    timer_hz[timer] = hz;
    timer_resolution[timer] = (char)bits;
    return (uint)(((ulong)soc::XTAL_HZ << 8) / (div << bits));
}

// Finds a timer already running at `hz`, or a free one.
fn char? acquire_timer(uint hz) @local {
    for (char t = 0; t < TIMER_COUNT; t++) {
        if (timer_users[t] != 0 && timer_hz[t] == hz) {
            timer_users[t]++;
            return t;
        }
    }
    for (char t = 0; t < TIMER_COUNT; t++) {
        if (timer_users[t] == 0) {
            program_timer(t, hz)!;
            timer_users[t] = 1;
            return t;
        }
    }
    return NO_FREE_CHANNEL~;
}

fn void release_timer(char timer) @local {
    if (timer_users[timer] > 0) timer_users[timer]--;
}

fn void attach_timer(char index, char timer) @local {
    channel_timer[index] = timer;
    soc::write(ch_reg(index, LEDC_CH_CONF0), (uint)timer | CH_SIG_OUT_EN | CH_PARA_UP);
}

fn Channel? open(gpio::Pin pin, Config config = {}) {
    if (!supports(pin)) return PIN_NOT_PWM_CAPABLE~;
    irq::State state = irq::save_and_disable();
    defer irq::restore(state);
    if (!ledc_ready) init();

    char index = NO_PIN;
    for (char i = 0; i < CHANNEL_COUNT; i++) {
        if (channel_pin[i] == NO_PIN) {
            index = i;
            break;
        }
    }
    if (index == NO_PIN) return NO_FREE_CHANNEL~;

    uint hz = config.frequency_hz == 0 ? DEFAULT_HZ : config.frequency_hz;
    char timer = acquire_timer(hz)!;
    channel_pin[index] = (char)pin;
    soc::write(ch_reg(index, LEDC_CH_HPOINT), 0);
    attach_timer(index, timer);
    Channel channel = { index };
    channel.set_duty(config.duty_permille);
    soc::route_output(pin, SIGNAL_LS_OUT0 + index);
    return channel;
}

fn void Channel.set_duty(self, uint permille) {
    if (permille > MAX_DUTY) permille = MAX_DUTY;
    channel_permille[self.index] = permille;
    uint bits = timer_resolution[channel_timer[self.index]];
    // The duty register is fixed point with 4 fraction bits; the integer part
    // may equal 2^bits for a steady high level.
    uint duty = (permille << bits) / MAX_DUTY;
    soc::write(ch_reg(self.index, LEDC_CH_DUTY), duty << 4);
    soc::write(ch_reg(self.index, LEDC_CH_CONF1), CH_DUTY_START | CH_DUTY_INC | CH_DUTY_NUM_1 | CH_DUTY_CYCLE_1);
    soc::set_bits(ch_reg(self.index, LEDC_CH_CONF0), CH_PARA_UP);
}

fn uint Channel.frequency(self) {
    char timer = channel_timer[self.index];
    uint conf = soc::read(timer_reg(timer));
    ulong div = (ulong)((conf >> TIMER_CLK_DIV_SHIFT) & MAX_CLK_DIV);
    if (div == 0) return 0;
    return (uint)(((ulong)soc::XTAL_HZ << 8) / (div << (conf & 0xF)));
}

// Moves the channel to a timer running at `hz` (reprogramming its own timer
// when no other channel uses it), so other channels keep their frequency.
fn uint? Channel.set_frequency(self, uint hz) {
    irq::State state = irq::save_and_disable();
    defer irq::restore(state);
    char old = channel_timer[self.index];
    if (timer_users[old] == 1) {
        program_timer(old, hz)!;
    } else {
        char timer = acquire_timer(hz)!;
        release_timer(old);
        attach_timer(self.index, timer);
    }
    self.set_duty(channel_permille[self.index]);
    return self.frequency();
}

fn void Channel.close(self) {
    irq::State state = irq::save_and_disable();
    defer irq::restore(state);
    soc::write(ch_reg(self.index, LEDC_CH_CONF0), CH_PARA_UP); // output off, idle low
    release_timer(channel_timer[self.index]);
    soc::release_pin((gpio::Pin)channel_pin[self.index]);
    channel_pin[self.index] = NO_PIN;
}
