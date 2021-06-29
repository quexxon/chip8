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
                    self.registers[0xF] = vy.* & 0b1;
                    vx.* = vy.* << 1;
                },
                else => {},
            },
            0x9000 => if (vx.* != vy.*) {
                self.pc += 2;
            },
            0xA000 => self.i = instruction & 0xFFF,
            0xB000 => self.i = (instruction & 0xFFF) + self.registers[0],
            0xC000 => vx.* = randomByte() & @intCast(u8, instruction & 0xFF),
            0xD000 => {
                const x = vx.*;
                const y = vy.*;
                const rows = @intCast(u4, instruction & 0xF);
                const offset = @intCast(u6, 64 - x - 8);
                var i: u4 = 0;
                var start_addr = self.i;
                var vf = &self.registers[0xF];
                vf.* = 0;
                while (i < rows) : (i += 1) {
                    var row = &self.display[y + i];
                    const val = if (offset < 0)
                        @intCast(u64, self.ram[start_addr + i]) >> offset
                    else
                        @intCast(u64, self.ram[start_addr + i]) << offset;

                    if (vf.* == 0) {
                        vf.* = @boolToInt(row.* ^ val > 0);
                    }
                    row.* ^= val;
                    if (i == 15) break;
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
                0x1E => self.i += vx.*,
                0x29 => self.i = 5 * vx.*,
                0x33 => {
                    self.ram[self.i] = vx.* / 100;
                    self.ram[self.i + 1] = (vx.* / 10) % 10;
                    self.ram[self.i + 2] = (vx.* % 100) % 10;
                },
                0x55 => {
                    const n = (instruction & 0xF00) + 1;
                    mem.copy(u8, self.ram[self.i..n], self.registers[0..n]);
                    self.i += n;
                },
                0x65 => {
                    const n = (instruction & 0xF00) + 1;
                    mem.copy(u8, self.registers[0..n], self.ram[self.i..n]);
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
