const std = @import("std");

const vec = @import("vec.zig");
const Vec3 = vec.Vec3;

const Ray = @import("Ray.zig");

const aspect_ratio = 16.0 / 9.0;
const img_width = 400;
const img_height = blk: {
    const fwidth: comptime_float = @as(comptime_float, img_width);
    const h: comptime_int = @intFromFloat(fwidth / aspect_ratio);
    break :blk if (h < 1) 1 else h;
};

const focal_length = 1.0;
const viewport_height = 2.0;
const viewport_width = blk: {
    const fwidth: comptime_float = @as(comptime_float, img_width);
    const fheight: comptime_float = @as(comptime_float, img_height);
    break :blk viewport_height * (fwidth + 0.0) / fheight;
};
const camera_center: Vec3 = vec.zero;

const viewport_u: Vec3 = .{ viewport_width, 0, 0 };
const viewport_v: Vec3 = .{ 0, -viewport_height, 0 };

const pixel_delta_u = viewport_u / @as(Vec3, @splat(img_width));
const pixel_delta_v = viewport_v / @as(Vec3, @splat(img_height));

const viewport_upper_left = camera_center - Vec3{ 0, 0, focal_length } - viewport_u / @as(Vec3, @splat(2)) - viewport_v / @as(Vec3, @splat(2));
const pixel00_loc = viewport_upper_left + @as(Vec3, @splat(0.5)) * (pixel_delta_u + pixel_delta_v);

pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    var stdout_buf = std.io.bufferedWriter(stdout_file.writer());
    const stdout = stdout_buf.writer();

    var pr_buf: [1024]u8 = undefined;
    const progress = std.Progress.start(.{
        .draw_buffer = &pr_buf,
        .estimated_total_items = img_height * img_width,
        .root_name = "drawing",
    });
    defer progress.end();

    try stdout.print("P3\n{d} {d}\n255\n", .{ img_width, img_height });

    // const fwidth: f32 = @floatFromInt(img_width);
    // const fheight: f32 = @floatFromInt(img_height);
    for (0..img_height) |y| {
        // const fy: f64 = @floatFromInt(y);
        const yvec: Vec3 = @splat(@floatFromInt(y));
        for (0..img_width) |x| {
            // const fx: f64 = @floatFromInt(x);
            const xvec: Vec3 = @splat(@floatFromInt(x));

            const pixel_center = pixel00_loc + (xvec * pixel_delta_u) + (yvec * pixel_delta_v);
            const ray_dir = pixel_center - camera_center;
            const r: Ray = .init(camera_center, ray_dir);

            const pixel_color = rayColor(&r);
            try stdout.print("{}\n", .{vec.fmtColor(pixel_color)});
        }
    }

    try stdout_buf.flush();
}

fn hitSphere(center: Vec3, radius: f64, r: *const Ray) bool {
    const oc = center - r.orig;
    const a = vec.dot(r.dir, r.dir);
    const b = -2.0 * vec.dot(r.dir, oc);
    const c = vec.dot(oc, oc) - radius * radius;
    const discriminant = b * b - 4 * a * c;
    return discriminant >= 0;
}

fn rayColor(r: *const Ray) Vec3 {
    if (hitSphere(.{ 0, 0, -1 }, 0.5, r)) {
        return .{ 1, 0, 0 };
    }

    const unit_direction = vec.normalized(r.dir);
    const a = 0.5 * (unit_direction[1] + 1.0);
    return @as(Vec3, @splat(1.0 - a)) + Vec3{ a * 0.5, a * 0.7, a };
}
