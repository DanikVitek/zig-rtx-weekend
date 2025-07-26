const std = @import("std");

const vec = @import("vec.zig");
const Vec3 = vec.Vec3;

const Ray = @import("Ray.zig");

const objects = @import("objects.zig");
const Sphere = objects.Sphere;
const Hit = objects.Hit;

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

const pixel_delta_u = viewport_u / vec.splat(img_width);
const pixel_delta_v = viewport_v / vec.splat(img_height);

const viewport_upper_left = camera_center - Vec3{ 0, 0, focal_length } - viewport_u / vec.splat(2) - viewport_v / vec.splat(2);
const pixel00_loc = viewport_upper_left + vec.splat(0.5) * (pixel_delta_u + pixel_delta_v);

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

    const world = .{
        Sphere.init(.{ 0, 0, -1 }, 0.5),
        Sphere.init(.{ 0, -100.5, -1 }, 100),
    };

    for (0..img_height) |y| {
        const yvec: Vec3 = @splat(@floatFromInt(y));
        for (0..img_width) |x| {
            const xvec: Vec3 = @splat(@floatFromInt(x));

            const pixel_center = pixel00_loc + (xvec * pixel_delta_u) + (yvec * pixel_delta_v);
            const ray_dir = pixel_center - camera_center;
            const r: Ray = .init(camera_center, ray_dir);

            const pixel_color = rayColor(r, world);
            try stdout.print("{}\n", .{vec.fmtColor(pixel_color)});
        }
    }

    try stdout_buf.flush();
}

fn rayColor(r: Ray, world: anytype) Vec3 {
    if (hitEverything(world, r)) |hit| {
        return vec.splat(0.5) * (hit.norm + vec.splat(1));
    }

    const unit_direction = vec.normalized(r.dir);
    const a: f64 = 0.5 * (unit_direction[1] + 1.0);
    const wat: Vec3 = .{ 0.5, 0.7, 1 };
    return @mulAdd(Vec3, @splat(a), wat, @splat(1.0 - a));
}

fn hitEverything(objs: anytype, ray: Ray) ?Hit {
    var hit: ?Hit = null;
    var closest_so_far = std.math.inf(f64);
    inline for (objs) |obj| {
        if (obj.hit(ray, 0, closest_so_far)) |h| {
            hit = h;
            closest_so_far = hit.?.t;
        }
    }
    return hit;
}
