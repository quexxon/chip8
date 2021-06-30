const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;
const is_test = @import("builtin").is_test;

extern fn random() u8;

fn randomByte() u8 {
    if (is_test) {
        var buffer = [1]u8{0};
        std.os.getrandom(&buffer) catch return 0;
        return buffer[0];
    } else {
        return random();
    }
}

const Chip8 = struct {
    pc: u16,
    i: u16,
    delay_timer: u8,
    sound_timer: u8,
    sp: u4,
    stack: [16]u16,
    registers: [16]u8,
    ram: [4096]u8,
    display: [32]u64, // 64 x 32
    keys: u16,

    pub fn init() Chip8 {
        return Chip8{
            .pc = 0x200,
            .i = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .sp = 0,
            .stack = [1]u16{0} ** 16,
            .registers = [1]u8{0} ** 16,
            .ram = [_]u8{
                // Font sprites
                0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
                0x20, 0x60, 0x20, 0x20, 0x70, // 1
                0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
                0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
                0x90, 0x90, 0xF0, 0x10, 0x10, // 4
                0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
                0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
                0xF0, 0x10, 0x20, 0x40, 0x40, // 7
                0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
                0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
                0xF0, 0x90, 0xF0, 0x90, 0x90, // A
                0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
                0xF0, 0x80, 0x80, 0x80, 0xF0, // C
                0xE0, 0x90, 0x90, 0x90, 0xE0, // D
                0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
                0xF0, 0x80, 0xF0, 0x80, 0x80, // F
            } ++ [1]u8{0} ** (4096 - 16 * 5),
            .display = [1]u64{0} ** 32,
            .keys = 0,
        };
    }

    pub fn runInstruction(self: *Chip8, instruction: u16) void {
        self.pc += 2;

        var vx = &self.registers[(instruction & 0xF00) >> 8];
        var vy = &self.registers[(instruction & 0xF0) >> 4];

        switch (instruction & 0xF000) {
            0x0000 => switch (instruction) {
                0x00E0 => mem.set(u64, self.display[0..self.display.len], 0),
                0x00EE => if (self.sp > 0) {
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                },
                else => {},
            },
            0x1000 => self.pc = instruction & 0xFFF,
            0x2000 => {
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = instruction & 0xFFF;
            },
            0x3000 => if (vx.* == (instruction & 0xFF)) {
                self.pc += 2;
            },
            0x4000 => if (vx.* != (instruction & 0xFF)) {
                self.pc += 2;
            },
            0x5000 => if (vx.* == vy.*) {
                self.pc += 2;
            },
            0x6000 => vx.* = @intCast(u8, instruction & 0xFF),
            0x7000 => _ = @addWithOverflow(u8, vx.*, @intCast(u8, instruction & 0xFF), vx),
            0x8000 => switch (instruction & 0xF) {
                0x0 => vx.* = vy.*,
                0x1 => vx.* |= vy.*,
                0x2 => vx.* &= vy.*,
                0x3 => vx.* ^= vy.*,
                0x4 => {
                    const carry = @addWithOverflow(u8, vx.*, vy.*, vx);
                    self.registers[0xF] = @boolToInt(carry);
                },
                0x5 => {
                    const borrow = @subWithOverflow(u8, vx.*, vy.*, vx);
                    self.registers[0xF] = if (borrow) 0 else 1;
                },
                0x6 => {
                    self.registers[0xF] = vy.* & 0b1;
                    vx.* = vy.* >> 1;
                },
                0x7 => {
                    const borrow = @subWithOverflow(u8, vy.*, vx.*, vx);
                    self.registers[0xF] = if (borrow) 0 else 1;
                },
                0xE => {
                    self.registers[0xF] = (vy.* & 0b1000_0000) >> 7;
                    vx.* = vy.* << 1;
                },
                else => {},
            },
            0x9000 => if (vx.* != vy.*) {
                self.pc += 2;
            },
            0xA000 => self.i = instruction & 0xFFF,
            0xB000 => self.pc = (instruction & 0xFFF) + self.registers[0],
            0xC000 => vx.* = randomByte() & @intCast(u8, instruction & 0xFF),
            0xD000 => {
                const x = vx.* % 64;
                const y = vy.* % 32;
                const rows = @intCast(u4, instruction & 0xF);
                const offset: i32 = 64 - @as(i32, x) - 8;
                var i: u4 = 0;
                var start_addr = self.i;
                var vf = &self.registers[0xF];
                vf.* = 0;
                while (i <= rows) : (i += 1) {
                    var row = &self.display[y + i];
                    const val = if (offset < 0)
                        @intCast(u64, self.ram[start_addr + i]) >> @intCast(u6, -offset)
                    else
                        @intCast(u64, self.ram[start_addr + i]) << @intCast(u6, offset);

                    if (vf.* == 0) {
                        vf.* = @boolToInt((row.* ^ val) & val != val);
                    }
                    row.* ^= val;
                    if (y + i == 31 or i == 15) break;
                }
            },
            0xE000 => switch (instruction & 0xFF) {
                0x9E => if (self.keys & (@as(u16, 1) << @intCast(u4, instruction & 0xF00)) > 0) {
                    self.pc += 2;
                },
                0xA1 => if (self.keys & (@as(u16, 1) << @intCast(u4, instruction & 0xF00)) == 0) {
                    self.pc += 2;
                },
                else => {},
            },
            0xF000 => switch (instruction & 0xFF) {
                0x07 => vx.* = self.delay_timer,
                0x0A => {
                    self.pc -= 2;
                    var i: u4 = 0;
                    while (i < 16) : (i += 1) {
                        if (self.keys & (@as(u16, 1) << i) > 0) {
                            vx.* = i;
                            self.pc += 2;
                            break;
                        }
                        if (i == 15) break;
                    }
                },
                0x15 => self.delay_timer = vx.*,
                0x18 => self.sound_timer = vx.*,
                0x1E => _ = @addWithOverflow(u16, self.i, vx.*, &self.i),
                0x29 => self.i = 5 * vx.*,
                0x33 => {
                    self.ram[self.i] = vx.* / 100;
                    self.ram[self.i + 1] = (vx.* / 10) % 10;
                    self.ram[self.i + 2] = (vx.* % 100) % 10;
                },
                0x55 => {
                    const n = ((instruction & 0xF00) >> 8) + 1;
                    mem.copy(u8, self.ram[self.i .. self.i + n], self.registers[0..n]);
                    self.i += n;
                },
                0x65 => {
                    const n = ((instruction & 0xF00) >> 8) + 1;
                    mem.copy(u8, self.registers[0..n], self.ram[self.i .. self.i + n]);
                    self.i += n;
                },
                else => {},
            },
            else => {},
        }
    }
};

test "0x00E0 - Clear Display" {
    var chip8 = Chip8.init();
    chip8.display[0] = std.math.maxInt(u64);
    try expect(chip8.display[0] == std.math.maxInt(u64));
    chip8.runInstruction(0x00E0);
    try expect(chip8.display[0] == 0);
}

test "0x00EE - Return from subroutine" {
    var chip8 = Chip8.init();

    chip8.runInstruction(0x00EE);
    try expect(chip8.pc == 0x202);
    try expect(chip8.sp == 0);

    chip8.sp = 1;
    chip8.stack[0] = 0x300;
    chip8.runInstruction(0x00EE);
    try expect(chip8.pc == 0x300);
    try expect(chip8.sp == 0);
}

test "0x1NNN - Jump to NNN" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x1500);
    try expect(chip8.pc == 0x500);
}

test "0x2NNN - Call subroutine at NNN" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x2500);
    try expect(chip8.pc == 0x500);
    try expect(chip8.stack[0] == 0x202);
    try expect(chip8.sp == 1);
}

test "0x3XNN - Skip next instruction if VX == NN" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x3105);
    try expect(chip8.pc == 0x202);

    chip8.registers[1] = 5;
    chip8.runInstruction(0x3105);
    try expect(chip8.pc == 0x206);
}

test "0x4XNN - Skip next instruction if VX != NN" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x4200);
    try expect(chip8.pc == 0x202);

    chip8.registers[2] = 5;
    chip8.runInstruction(0x4200);
    try expect(chip8.pc == 0x206);
}

test "0x5XY0 - Skip next instruction if VX == VY" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x5010);
    try expect(chip8.pc == 0x204);
    chip8.registers[2] = 1;
    chip8.runInstruction(0x5020);
    try expect(chip8.pc == 0x206);
}

test "0x6XNN - Store NN in VX" {
    var chip8 = Chip8.init();
    var pc_start = chip8.pc;
    var val: u8 = 0xAB;
    for (chip8.registers) |_, i| {
        try expect(chip8.registers[i] == 0);
        chip8.runInstruction(0x6000 + @intCast(u16, i * 0x100) + val);
        try expect(chip8.registers[i] == val);
        try expect(chip8.pc == pc_start + (i + 1) * 2);
        val += 1;
    }
}

test "0x7XVV - Add NN to VX (w/o carry)" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x70FF);
    try expect(chip8.registers[0] == 0xFF);
    try expect(chip8.pc == 0x202);
    chip8.runInstruction(0x7001);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.pc == 0x204);
    chip8.registers[1] = 0x10;
    chip8.runInstruction(0x7110);
    try expect(chip8.registers[1] == 0x20);
    try expect(chip8.pc == 0x206);
    chip8.runInstruction(0x7200);
    try expect(chip8.registers[2] == 0);
    try expect(chip8.pc == 0x208);
}

test "0x8XY0 - Store the value of VY in VX" {
    var chip8 = Chip8.init();
    chip8.registers[1] = 0xFF;
    chip8.runInstruction(0x8010);
    try expect(chip8.registers[0] == 0xFF);
    try expect(chip8.registers[1] == 0xFF);
    try expect(chip8.pc == 0x202);
    chip8.runInstruction(0x8120);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.registers[2] == 0);
    try expect(chip8.pc == 0x204);
}

test "0x8XY1 - Set VX to VX | VY" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x8011);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 0xF0;
    chip8.registers[3] = 0x0F;
    chip8.runInstruction(0x8231);
    try expect(chip8.registers[2] == 0xFF);
    try expect(chip8.registers[3] == 0x0F);
    try expect(chip8.pc == 0x204);
}

test "0x8XY2 - Set VX to VX & VY" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x8012);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 0b1111_1100;
    chip8.registers[3] = 0b0011_1111;
    chip8.runInstruction(0x8232);
    try expect(chip8.registers[2] == 0b0011_1100);
    try expect(chip8.registers[3] == 0b0011_1111);
    try expect(chip8.pc == 0x204);
}

test "0x8XY3 - Set VX to VX ^ VY" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x8013);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 0b1100;
    chip8.registers[3] = 0b0110;
    chip8.runInstruction(0x8233);
    try expect(chip8.registers[2] == 0b1010);
    try expect(chip8.registers[3] == 0b0110);
    try expect(chip8.pc == 0x204);
}

test "0x8XY4 - Add VY to VX (w/ carry in VF)" {
    var chip8 = Chip8.init();
    chip8.registers[0] = 2;
    chip8.registers[1] = 3;
    chip8.runInstruction(0x8014);
    try expect(chip8.registers[0] == 5);
    try expect(chip8.registers[1] == 3);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 0xFF;
    chip8.registers[3] = 2;
    chip8.runInstruction(0x8234);
    try expect(chip8.registers[2] == 1);
    try expect(chip8.registers[3] == 2);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x204);
}

test "0x8XY5 - Subtract VY from VX (w/ borrow in VF)" {
    var chip8 = Chip8.init();
    chip8.registers[0] = 5;
    chip8.registers[1] = 3;
    chip8.runInstruction(0x8015);
    try expect(chip8.registers[0] == 2);
    try expect(chip8.registers[1] == 3);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 0;
    chip8.registers[3] = 1;
    chip8.runInstruction(0x8235);
    try expect(chip8.registers[2] == 0xFF);
    try expect(chip8.registers[3] == 1);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x204);
}

test "0x8XY6 - VX = VY >> 1; VF = LSB prior to shift" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x8016);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[3] = 0xF;
    chip8.runInstruction(0x8236);
    try expect(chip8.registers[2] == 0b111);
    try expect(chip8.registers[3] == 0xF);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x204);
}

test "0x8XY7 - VX = VY - VX (w/ borrow in VF)" {
    var chip8 = Chip8.init();
    chip8.registers[0] = 3;
    chip8.registers[1] = 5;
    chip8.runInstruction(0x8017);
    try expect(chip8.registers[0] == 2);
    try expect(chip8.registers[1] == 5);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 1;
    chip8.registers[3] = 0;
    chip8.runInstruction(0x8237);
    try expect(chip8.registers[2] == 0xFF);
    try expect(chip8.registers[3] == 0);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x204);
}

test "0x8XYE - VX = VY << 1; VF = MSB prior to shift" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x801E);
    try expect(chip8.registers[0] == 0);
    try expect(chip8.registers[1] == 0);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[3] = 0xF0;
    chip8.runInstruction(0x823E);
    try expect(chip8.registers[2] == 0b1110_0000);
    try expect(chip8.registers[3] == 0xF0);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x204);
}

test "0x9XY0 - Skip next instruction if VX != VY" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0x9010);
    try expect(chip8.pc == 0x202);
    chip8.registers[2] = 1;
    chip8.runInstruction(0x9020);
    try expect(chip8.pc == 0x206);
}

test "0xANNN - Store NNN in I" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xA000);
    try expect(chip8.i == 0);
    try expect(chip8.pc == 0x202);
    chip8.runInstruction(0xAFFF);
    try expect(chip8.i == 0xFFF);
    try expect(chip8.pc == 0x204);
}

test "0xBNNN - Jump to NNN + V0" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xB500);
    try expect(chip8.pc == 0x500);
    chip8.registers[0] = 0x23;
    chip8.runInstruction(0xB100);
    try expect(chip8.pc == 0x123);
}

test "0xCXNN - VX = randomByte() & NN" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xC003);
    var val = chip8.registers[0];
    try expect(val >= 0 and val <= 3);
    try expect(chip8.pc == 0x202);
    chip8.runInstruction(0xC1FF);
    val = chip8.registers[1];
    try expect(val >= 0 and val <= 0xFF);
    try expect(chip8.pc == 0x204);
}

test "0xDXYN - Draw N+1 bytes of sprite data starting at I to (VX,VY)" {
    var chip8 = Chip8.init();
    var i: u16 = 0;
    while (i < 16) : (i += 1) {
        chip8.ram[0x300 + i] = 0xFF;
    }
    chip8.i = 0x300;
    chip8.runInstruction(0xD010);
    try expect(chip8.display[0] == 0xFF00_0000_0000_0000);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[0] = 4;
    chip8.runInstruction(0xD010);
    try expect(chip8.display[0] == 0xF0F0_0000_0000_0000);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x204);
    chip8.registers[0] = 63;
    chip8.registers[1] = 31;
    chip8.runInstruction(0xD01F);
    try expect(chip8.display[0] == 0xF0F0_0000_0000_0000);
    try expect(chip8.display[31] == 0x0000_0000_0000_0001);
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x206);
    chip8.registers[0] = 56;
    chip8.registers[1] = 1;
    chip8.runInstruction(0xD01F);
    var row: u5 = 1;
    while (row <= 16) : (row += 1) {
        try expect(chip8.display[row] == 0xFF);
    }
    try expect(chip8.registers[0xF] == 0);
    try expect(chip8.pc == 0x208);
    chip8.registers[0] = 60;
    chip8.registers[1] = 1;
    chip8.runInstruction(0xD010);
    try expect(chip8.display[1] == 0xF0);
    try expect(chip8.registers[0xF] == 1);
    try expect(chip8.pc == 0x20A);
}

test "0xEX9E - Skip next instruction if key X is pressed" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xE09E);
    try expect(chip8.pc == 0x202);
    chip8.keys |= 1;
    chip8.runInstruction(0xE09E);
    try expect(chip8.pc == 0x206);
}

test "0xEXA1 - Skip next instruction if key X is not pressed" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xE0A1);
    try expect(chip8.pc == 0x204);
    chip8.keys |= 1;
    chip8.runInstruction(0xE0A1);
    try expect(chip8.pc == 0x206);
}

test "0xFX07 - Store current value of delay timer in VX" {
    var chip8 = Chip8.init();
    const start_addr = chip8.pc;
    for (chip8.registers) |*reg, i| {
        chip8.delay_timer = randomByte();
        chip8.runInstruction(0xF007 + @intCast(u16, 0x100 * i));
        try expect(reg.* == chip8.delay_timer);
        try expect(chip8.pc == start_addr + ((i + 1) * 2));
    }
}

test "0xFX0A - Await a keypress and store the value in VX" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xF00A);
    try expect(chip8.pc == 0x200);
    chip8.keys |= 0b1100;
    chip8.runInstruction(0xF00A);
    try expect(chip8.registers[0] == 2);
    try expect(chip8.pc == 0x202);
}

test "0xFX15 - Set the delay timer to the value of VX" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xF015);
    try expect(chip8.delay_timer == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[1] = 0xFF;
    chip8.runInstruction(0xF115);
    try expect(chip8.delay_timer == 0xFF);
    try expect(chip8.pc == 0x204);
}

test "0xFX18 - Set the sound timer to the value of VX" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xF018);
    try expect(chip8.sound_timer == 0);
    try expect(chip8.pc == 0x202);
    chip8.registers[1] = 0xFF;
    chip8.runInstruction(0xF118);
    try expect(chip8.sound_timer == 0xFF);
    try expect(chip8.pc == 0x204);
}

test "0xFX1E - I += VX (w/o carry)" {
    var chip8 = Chip8.init();
    chip8.runInstruction(0xF01E);
    try expect(chip8.i == 0);
    try expect(chip8.pc == 0x202);
    chip8.i = 0xF0;
    chip8.registers[1] = 0xF;
    chip8.runInstruction(0xF11E);
    try expect(chip8.i == 0xFF);
    try expect(chip8.pc == 0x204);
    chip8.i = 0xFFFF;
    chip8.registers[1] = 1;
    chip8.runInstruction(0xF11E);
    try expect(chip8.i == 0);
    try expect(chip8.pc == 0x206);
}

test "0xFX29 - Set I to the address of the sprite for char X" {
    var chip8 = Chip8.init();
    var char: u8 = 0;
    const start_addr = chip8.pc;
    while (char < 16) : (char += 1) {
        chip8.registers[char] = char;
        chip8.runInstruction(0xF029 + 0x100 * @as(u16, char));
        try expect(chip8.i == 5 * char);
        try expect(chip8.pc == start_addr + ((char + 1) * 2));
        if (char == 15) break;
    }
}

test "0xFX33 - Store the BCD representation of VX at I, I+1, and I+2" {
    var chip8 = Chip8.init();
    chip8.registers[0] = 123;
    chip8.i = 0x300;
    chip8.runInstruction(0xF033);
    try expect(chip8.ram[0x300] == 1);
    try expect(chip8.ram[0x301] == 2);
    try expect(chip8.ram[0x302] == 3);
    try expect(chip8.pc == 0x202);
}

test "0xFX55 - Store [V0, VX] in memory starting at I (incrementing I)" {
    var chip8 = Chip8.init();
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    for (data) |val, i| {
        chip8.registers[i] = val;
    }
    const start_addr = 0x300;
    chip8.i = start_addr;
    chip8.runInstruction(0xF455);
    const mem_range = chip8.ram[start_addr .. start_addr + 5];
    try expect(mem.eql(u8, mem_range, data[0..5]));
    try expect(mem.eql(u8, mem_range, chip8.registers[0..5]));
    try expect(chip8.i == start_addr + 5);
    try expect(chip8.pc == 0x202);
}

test "0xFX65 - Fill [V0, VX] from memory starting at I (incrementing I)" {
    var chip8 = Chip8.init();
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const start_addr = 0x300;
    for (data) |val, i| {
        chip8.ram[start_addr + i] = val;
    }
    chip8.i = start_addr;
    chip8.runInstruction(0xF465);
    const reg_range = chip8.registers[0..5];
    const mem_range = chip8.ram[start_addr .. start_addr + 5];
    try expect(mem.eql(u8, reg_range, data[0..5]));
    try expect(mem.eql(u8, reg_range, mem_range));
    try expect(chip8.i == start_addr + 5);
    try expect(chip8.pc == 0x202);
}
