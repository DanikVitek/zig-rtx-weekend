const std = @import("std");

pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    var stdout_buf = std.io.bufferedWriter(stdout_file.writer());
    const stdout = stdout_buf.writer();

    const height = 256;
    const width = 256;

    try stdout.print("P3\n{d} {d}\n255\n", .{ width, height });

    for (0..height) |y| {
        const fy: f32 = @floatFromInt(y);
        for (0..width) |x| {
            const fx: f32 = @floatFromInt(x);

            const r: u8 = @intFromFloat(@trunc(255.99 * (fy / (height - 1.0))));
            const g: u8 = @intFromFloat(@trunc(255.99 * (fx / (width - 1.0))));
            const b: u8 = 0;

            try stdout.print("{d: >3} {d: >3} {d: >3}\n", .{ r, g, b });
        }
    }

    try stdout_buf.flush();
}
