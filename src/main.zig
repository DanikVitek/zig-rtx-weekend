const std = @import("std");
const vec3 = @import("vec3.zig");
const Vec3 = vec3.Vec3;

pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    var stdout_buf = std.io.bufferedWriter(stdout_file.writer());
    const stdout = stdout_buf.writer();

    const height = 256;
    const width = 256;

    var pr_buf: [1024]u8 = undefined;
    const progress = std.Progress.start(.{
        .draw_buffer = &pr_buf,
        .estimated_total_items = height * width,
        .root_name = "drawing",
    });
    defer progress.end();

    try stdout.print("P3\n{d} {d}\n255\n", .{ width, height });

    const fwidth: f32 = @floatFromInt(width);
    const fheight: f32 = @floatFromInt(height);
    for (0..height) |y| {
        const fy: f32 = @floatFromInt(y);
        for (0..width) |x| {
            const fx: f32 = @floatFromInt(x);

            const color: Vec3 = .{
                fx / (fwidth - 1),
                fy / (fheight - 1),
                0,
            };

            try stdout.print("{}\n", .{vec3.fmtColor(color)});
        }
    }

    try stdout_buf.flush();
}
