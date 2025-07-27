const std = @import("std");

const Vec3 = @import("Vec3.zig");
const Ray = @import("Ray.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Hit = objects.Hit;

pub const aspect_ratio = 16.0 / 9.0;
pub const img_width = 600;
pub const samples_per_pixel = 30;

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
const camera_center: Vec3 = .zero;

const viewport_u: Vec3 = .init(.{ viewport_width, 0, 0 });
const viewport_v: Vec3 = .init(.{ 0, -viewport_height, 0 });

const pixel_delta_u: Vec3 = .init(viewport_u.v / Vec3.splat(img_width).v);
const pixel_delta_v: Vec3 = .init(viewport_v.v / Vec3.splat(img_height).v);

const viewport_upper_left: Vec3 = .init(
    camera_center.v - Vec3.Repr{ 0, 0, focal_length } - viewport_u.v / Vec3.splat(2).v - viewport_v.v / Vec3.splat(2).v,
);
const pixel00_loc: Vec3 = .init(
    viewport_upper_left.v + Vec3.splat(0.5).v * (pixel_delta_u.v + pixel_delta_v.v),
);

const max_recursion = 50;

threadlocal var rand_state = std.Random.DefaultPrng.init(42);

pub fn render(world: anytype) !void {
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

    for (0..img_height) |y| {
        for (0..img_width) |x| {
            var pixel: Color = .black;
            for (0..samples_per_pixel) |_| {
                const ray: Ray = getRay(
                    @floatFromInt(x),
                    @floatFromInt(y),
                );
                pixel.v += rayColor(ray, world, 0).v;
            }
            pixel.v /= @splat(samples_per_pixel);

            try stdout.print("{}", .{pixel});

            progress.completeOne();
        }
    }

    try stdout_buf.flush();
}

fn getRay(x: f64, y: f64) Ray {
    const offset = sampleSquare();
    const pixel_sample: Vec3 = .mulAdd(
        .splat(y + offset[1]),
        pixel_delta_v,
        .mulAdd(
            .splat(x + offset[0]),
            pixel_delta_u,
            pixel00_loc,
        ),
    );

    const ray_origin = camera_center;
    const ray_dir: Vec3 = pixel_sample.sub(ray_origin);

    return .init(ray_origin, ray_dir);
}

fn sampleSquare() [2]f64 {
    const rand = rand_state.random();
    const u = rand.float(f64);
    const v = rand.float(f64);
    return .{ u - 0.5, v - 0.5 };
}

fn rayColor(
    r: Ray,
    world: anytype,
    depth: std.math.IntFittingRange(0, max_recursion + 1),
) Color {
    if (depth > max_recursion) return .black;

    if (hitWorld(world, r)) |hit| {
        const rand = rand_state.random();
        return if (hit.material.scatter(rand, r, hit)) |scatter|
            scatter.attenuation.mul(rayColor(scatter.scattered, world, depth + 1))
        else
            .black;
    }

    const unit_direction = r.dir.normalized();
    const a: f64 = 0.5 * (unit_direction.y() + 1.0);
    const wat: Color = .init(.{ 0.5, 0.7, 1 });
    return .mulScalarAdd(a, wat, .splat(1.0 - a));
}

fn hitWorld(objs: anytype, ray: Ray) ?Hit {
    var hit: ?Hit = null;
    var closest_so_far = std.math.inf(f64);
    inline for (objs) |obj| {
        if (obj.hit(ray, .{ .min = 0.001, .max = closest_so_far })) |h| {
            hit = h;
            closest_so_far = hit.?.t;
        }
    }
    return hit;
}
