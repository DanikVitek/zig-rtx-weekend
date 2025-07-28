const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Progress = std.Progress;
const Random = std.Random;

const Vec3 = @import("Vec3.zig");
const Vec2 = @import("Vec2.zig");
const Ray = @import("Ray.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Hit = objects.Hit;

/// Ratio of image width over height
pub const aspect_ratio = 16.0 / 9.0;
/// Rendered image width in pixel count
pub const img_width = 1920;

/// Count of random samples for each pixel
pub const samples_per_pixel = 1000;
/// Maximum number of ray bounces into scene
pub const max_recursion = 50;

/// Vertical view angle (field of view)
pub const v_fov = 20.0; // 90.0;

/// Point camera is looking from
pub const look_from: Vec3 = .init(.{ 13, 2, 3 }); //.zero;
/// Point camera is looking at
pub const look_at: Vec3 = .zero;

/// Camera-relative "up" direction
pub const v_up: Vec3 = .y_axis;

/// Variation angle of rays through each pixel
pub const defocus_angle = 0.6; //0.0;
/// Distance from camera lookfrom point to plane of perfect focus
pub const focus_dist = 10.0; //10.0;

/// Rendered image height
const img_height = blk: {
    const fwidth: comptime_float = @floatFromInt(img_width);
    const h: comptime_int = @intFromFloat(fwidth / aspect_ratio);
    break :blk if (h < 1) 1 else h;
};

const camera_center: Vec3 = look_from;

const viewport_height = blk: {
    const theta: comptime_float = std.math.degreesToRadians(v_fov);
    const h: comptime_float = std.math.tan(theta / 2.0);
    break :blk 2 * h * focus_dist;
};
const viewport_width = blk: {
    const fwidth: comptime_float = @floatFromInt(img_width);
    const fheight: comptime_float = @floatFromInt(img_height);
    break :blk viewport_height * (fwidth + 0.0) / fheight;
};

/// Camera frame basis X axis
const u: Vec3 = v_up.cross(w).normalized();
/// Camera frame basis Y axis
const v: Vec3 = w.cross(u);
/// Camera frame basis Z axis
const w: Vec3 = look_from.sub(look_at).normalized();

const defocus_radius = focus_dist * std.math.tan(std.math.degreesToRadians(defocus_angle / 2.0));
/// Defocus disk horizontal radius
const defocus_disk_u: Vec3 = u.mulScalar(defocus_radius);
/// Defocus disk vertical radius
const defocus_disk_v: Vec3 = v.mulScalar(defocus_radius);

/// Vector across viewport horizontal edge
const viewport_u = u.mulScalar(viewport_width);
/// Vector down viewport vertical edge
const viewport_v = v.neg().mulScalar(viewport_height);

/// Offset to pixel to the right
const pixel_delta_u: Vec3 = viewport_u.divScalar(img_width);
/// Offset to pixel below
const pixel_delta_v: Vec3 = viewport_v.divScalar(img_height);

/// Location of pixel (0, 0)
const pixel00_loc: Vec3 = blk: {
    const viewport_upper_left: Vec3 = camera_center
        .sub(w.mulScalar(focus_dist))
        .sub(viewport_u.divScalar(2))
        .sub(viewport_v.divScalar(2));
    break :blk pixel_delta_u.add(pixel_delta_v).mulScalar(0.5).add(viewport_upper_left);
};

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
        .root_name = "rendering",
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

    try stdout.print("P6\n{d} {d}\n255\n", .{ img_width, img_height });
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
    const pixel_sample: Vec3 = .mulScalarAdd(
        y + offset.y(),
        pixel_delta_v,
        .mulScalarAdd(
            x + offset.x(),
            pixel_delta_u,
            pixel00_loc,
        ),
    );

    const ray_origin = if (defocus_angle <= 0) camera_center else defocusDiskScample(rand);
    const ray_dir: Vec3 = pixel_sample.sub(ray_origin);

    return .init(ray_origin, ray_dir);
}

fn sampleSquare(rand: Random) Vec2 {
    return .init(.{
        rand.float(f64) - 0.5,
        rand.float(f64) - 0.5,
    });
}

fn defocusDiskScample(rand: Random) Vec3 {
    const p: Vec2 = .randomInUnitDisk(rand);
    return .mulScalarAdd(
        p.x(),
        defocus_disk_u,
        .mulScalarAdd(
            p.y(),
            defocus_disk_v,
            camera_center,
        ),
    );
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
    for (objs) |obj| {
        if (obj.hit(ray, .{ .min = 0.001, .max = closest_so_far })) |h| {
            hit = h;
            closest_so_far = hit.?.t;
        }
    }
    return hit;
}
