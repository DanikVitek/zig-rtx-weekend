const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Progress = std.Progress;
const Random = std.Random;

const Vec3 = @import("Vec3.zig");
const Ray = @import("Ray.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Hit = objects.Hit;

pub const aspect_ratio = 16.0 / 9.0;
pub const img_width = 1080;
pub const samples_per_pixel = 100;

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

pub fn render(world: anytype, allocator: Allocator, rand: Random) !void {
    const stdout_file = std.io.getStdOut();
    var stdout_buf = std.io.bufferedWriter(stdout_file.writer());
    const stdout = stdout_buf.writer();

    const image = try allocator.alloc(Color, img_width * img_height);
    defer allocator.free(image);

    const grid = try factorizeParallelizm();
    if (builtin.mode == .Debug) {
        std.debug.print("grid:\n  w: {d}\n  h: {d}\n", .{ grid.width, grid.height });
    }

    var pr_buf: [1024]u8 = undefined;
    const progress = Progress.start(.{
        .draw_buffer = &pr_buf,
        .estimated_total_items = grid.height * grid.width,
        .root_name = "drawing",
    });

    defer progress.end();
    var threads: std.ArrayListUnmanaged(Thread) = try .initCapacity(
        allocator,
        std.math.mulWide(Sqrt(usize), grid.height, grid.width),
    );
    defer threads.deinit(allocator);

    for (0..grid.height) |i| {
        for (0..grid.width) |j| {
            const kernel_x = j * (img_width / grid.width);
            const kernel_y = i * (img_height / grid.height);
            const kernel_width = @min(kernel_x + (img_width / grid.width), img_width) - kernel_x;
            const kernel_height = @min(kernel_y + (img_height / grid.height), img_height) - kernel_y;
            const thread = try Thread.spawn(
                .{ .allocator = allocator },
                kernel,
                .{
                    kernel_x,
                    kernel_y,
                    kernel_width,
                    kernel_height,
                    world,
                    image,
                    progress,
                    rand,
                },
            );
            threads.appendAssumeCapacity(thread);
        }
    }

    for (threads.items) |thread| {
        thread.join();
    }

    try stdout.print("P3\n{d} {d}\n255\n", .{ img_width, img_height });
    for (image) |pixel| {
        try stdout.print("{}", .{pixel});
        progress.completeOne();
    }

    try stdout_buf.flush();
}

fn factorizeParallelizm() !struct { width: Sqrt(usize), height: Sqrt(usize) } {
    const parallelizm: usize = try Thread.getCpuCount();

    const width: Sqrt(usize) = std.math.sqrt(parallelizm);
    const height: Sqrt(usize) = @intCast(try std.math.divExact(usize, parallelizm, width));

    return .{ .width = @max(width, height), .height = @min(width, height) };
}

fn Sqrt(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => |info| std.meta.Int(.unsigned, (info.bits + 1) / 2),
        else => T,
    };
}

fn kernel(
    kx: usize,
    ky: usize,
    kw: usize,
    kh: usize,
    world: anytype,
    image: []Color,
    progress: std.Progress.Node,
    rand: Random,
) void {
    const fmt = "kernel({d}, {d})";
    var name_buf: [std.fmt.count(fmt, .{std.math.maxInt(usize)} ** 2)]u8 = undefined;
    const name: []const u8 = std.fmt.bufPrint(&name_buf, fmt, .{ kx, ky }) catch unreachable;

    const kprogress = progress.start(name, kw * kh * samples_per_pixel);
    defer kprogress.end();

    for (kx..kx + kw) |x| {
        for (ky..ky + kh) |y| {
            var pixel: Color = .black;
            for (0..samples_per_pixel) |_| {
                const ray: Ray = getRay(
                    rand,
                    @floatFromInt(x),
                    @floatFromInt(y),
                );
                pixel.v += rayColor(ray, rand, world, 0).v;

                kprogress.completeOne();
            }
            pixel.v /= @splat(samples_per_pixel);
            image[y * img_width + x] = pixel;
        }
    }
}

fn getRay(rand: Random, x: f64, y: f64) Ray {
    const offset = sampleSquare(rand);
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

fn sampleSquare(rand: Random) [2]f64 {
    const u = rand.float(f64);
    const v = rand.float(f64);
    return .{ u - 0.5, v - 0.5 };
}

fn rayColor(
    ray: Ray,
    rand: Random,
    world: anytype,
    depth: std.math.IntFittingRange(0, max_recursion + 1),
) Color {
    if (depth > max_recursion) return .black;

    if (hitWorld(world, ray)) |hit| {
        return if (hit.material.scatter(rand, ray, hit)) |scatter|
            scatter.attenuation.mul(rayColor(scatter.scattered_ray, rand, world, depth + 1))
        else
            .black;
    }

    const unit_direction = ray.dir.normalized();
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
